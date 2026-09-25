#!/bin/bash
# Move Docker's data-root from /var/lib/docker to /tmp/docker.
#
# Why: GitHub Codespaces mounts / as a 32G overlay. A full kind cluster with
# several Helm releases easily fills it. /tmp is a separate ext4 volume that
# is typically much larger (30-60 GB depending on the Codespace size).
#
# What this script does:
#   1. Stops Docker so no writes happen during the move.
#   2. Writes /etc/docker/daemon.json pointing data-root at /tmp/docker.
#   3. Copies the existing /var/lib/docker tree to /tmp/docker (preserving
#      permissions and hard links). This keeps cached image layers so the
#      first `make run` doesn't re-pull everything.
#   4. Restarts Docker and verifies the new data-root is active.
#
# Safe to re-run: if /tmp/docker already exists and daemon.json already
# points there, the script exits early. Existing data is never deleted.
#
# Usage:
#   scripts/move-docker-to-tmp.sh
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] move-docker-to-tmp: $*"; }

TARGET=/tmp/docker
DAEMON_JSON=/etc/docker/daemon.json

# ── guard: already done ────────────────────────────────────────────────────────
current_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
if [[ "${current_root}" == "${TARGET}" ]]; then
  log "Docker data-root is already ${TARGET}, nothing to do"
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  log "not Linux, skipping"
  exit 0
fi

if ! sudo -n true 2>/dev/null; then
  echo "ERROR: passwordless sudo required" >&2
  exit 1
fi

# ── stop Docker ───────────────────────────────────────────────────────────────
# In Codespaces, systemctl and service both exit 0 but don't actually stop
# dockerd (no systemd running). Trust the socket state, not the exit code.
log "stopping Docker..."
sudo systemctl stop docker docker.socket 2>/dev/null || true
sudo service docker stop 2>/dev/null || true
# If the socket is still up, dockerd is still running -- kill it directly.
if [[ -S /var/run/docker.sock ]]; then
  sudo pkill -x dockerd 2>/dev/null || true
  for i in $(seq 1 10); do
    [[ ! -S /var/run/docker.sock ]] && break
    sleep 1
  done
fi
log "Docker stopped"

# ── write daemon.json ─────────────────────────────────────────────────────────
# Merge with existing config if present so we don't lose other settings
# (e.g. insecure-registries added by Codespaces).
if [[ -f "${DAEMON_JSON}" ]]; then
  log "merging data-root into existing ${DAEMON_JSON}"
  # Use Python (always present) to merge the JSON key.
  sudo python3 - "${DAEMON_JSON}" "${TARGET}" <<'PY'
import json, sys
path, target = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["data-root"] = target
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
else
  log "creating ${DAEMON_JSON}"
  sudo mkdir -p "$(dirname "${DAEMON_JSON}")"
  echo "{\"data-root\": \"${TARGET}\"}" | sudo tee "${DAEMON_JSON}" > /dev/null
fi

# ── copy data ─────────────────────────────────────────────────────────────────
if [[ -d /var/lib/docker ]] && [[ ! -d "${TARGET}" ]]; then
  log "copying /var/lib/docker → ${TARGET} (this may take a minute)..."
  # -a: archive (preserve permissions, symlinks, timestamps)
  # -H: preserve hard links (overlay layers use them heavily)
  sudo rsync -aH /var/lib/docker/ "${TARGET}/"
  log "copy done"
elif [[ ! -d /var/lib/docker ]]; then
  log "/var/lib/docker does not exist, nothing to copy"
else
  log "${TARGET} already exists, skipping copy (remove it manually to re-sync)"
fi

# ── start Docker ──────────────────────────────────────────────────────────────
log "starting Docker..."
sudo systemctl start docker 2>/dev/null || true
sudo service docker start 2>/dev/null || true
# Same logic as stop: check the socket, not the exit code.
if [[ ! -S /var/run/docker.sock ]]; then
  # Codespaces: launch dockerd directly. daemon.json already has the right
  # data-root so no --data-root flag needed; it reads the file on startup.
  sudo dockerd > /tmp/dockerd.log 2>&1 &
  log "started via direct dockerd (pid $!); logs at /tmp/dockerd.log"
fi
# Wait for the socket to appear (up to 15 s).
for i in $(seq 1 15); do
  [[ -S /var/run/docker.sock ]] && break
  sleep 1
done

# ── verify ────────────────────────────────────────────────────────────────────
new_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
if [[ "${new_root}" == "${TARGET}" ]]; then
  log "success: Docker data-root is now ${TARGET}"
else
  echo "ERROR: expected data-root ${TARGET}, got '${new_root}'" >&2
  echo "Check ${DAEMON_JSON} and 'sudo journalctl -u docker' for details" >&2
  exit 1
fi
