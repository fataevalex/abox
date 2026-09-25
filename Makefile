help:
	@echo "Available targets:"
	@echo "  run        - Bootstrap the full environment (install tools, provision cluster)"
	@echo "  down       - Destroy the cluster and all resources"
	@echo "  push       - Bump patch version, tag, and push to trigger CI"
	@echo "  tools      - Install necessary tools only"
	@echo "  tofu       - Initialize OpenTofu"
	@echo "  apply      - Apply OpenTofu configuration"
	@echo "  move-docker-to-tmp - Move Docker data-root to /tmp (Codespaces disk space)"
	@echo "  fix-docker-acl - Fix /tmp Docker ACL before first make run (Codespaces)"
	@echo "  fix-egress - Repair nested-Docker egress (Codespaces) and verify nodes"
	@echo "  flux-reconcile - Force reconciliation of all Flux sources and kustomizations"
	@echo "  flux-status    - Show current state of all Flux resources"

run:
	@bash scripts/setup.sh

tools:
	@curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
	@curl -sS https://webi.sh/k9s | bash
	@ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); \
	  OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.33.0/kind-$$OS-$$ARCH" && \
	  sudo install -m 0755 /tmp/kind /usr/local/bin/kind && rm -f /tmp/kind

move-docker-to-tmp:
	# Move Docker data-root from /var/lib/docker to /tmp/docker.
	# /tmp is a larger ext4 volume in Codespaces; / fills up quickly with kind.
	# Run once per Codespace, before make run. Safe to re-run (no-ops if done).
	@bash scripts/move-docker-to-tmp.sh

fix-docker-acl:
	# Run this once in a fresh Codespace before make run.
	# /tmp carries a default ACL that strips o+x from unpacked container layers,
	# causing non-root pods to fail at exec (Permission denied on binaries).
	@bash scripts/fix-docker-acl.sh

fix-egress:
	@bash scripts/fix-egress.sh
	@bash scripts/fix-egress.sh verify abox

tofu:
	@cd bootstrap && tofu init

apply:
	@cd bootstrap && tofu apply -auto-approve

down:
	@cd bootstrap && tofu destroy -auto-approve

flux-reconcile:
	@echo "Reconciling RSIP (tag discovery)..."
	@kubectl annotate resourcesetinputprovider releases-image -n flux-system \
	  fluxcd.controlplane.io/reconcileAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
	@echo "Waiting for RSIP → ResourceSet propagation..."
	@sleep 10
	@kubectl annotate resourceset releases -n flux-system \
	  fluxcd.controlplane.io/reconcileAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
	@sleep 5
	@echo "Reconciling Flux sources..."
	@flux reconcile source oci releases -n flux-system
	@echo "Reconciling Flux kustomizations..."
	@flux reconcile kustomization releases-crds -n flux-system
	@flux reconcile kustomization releases -n flux-system
	@echo "Done."

flux-status:
	@echo "=== OCIRepository ==="
	@flux get source oci -n flux-system
	@echo ""
	@echo "=== Kustomizations ==="
	@flux get kustomization -n flux-system
	@echo ""
	@echo "=== HelmReleases ==="
	@flux get helmrelease -A
	@echo ""
	@echo "=== ResourceSetInputProvider ==="
	@kubectl get resourcesetinputprovider -n flux-system

push:
	@git fetch origin --tags --force
	$(eval TAG=$(shell git tag --list 'v*' | sort -V | tail -1 | sed 's/^v//' || echo "0.0.0"))
	$(eval MAJOR=$(shell echo $(TAG) | cut -d. -f1))
	$(eval MINOR=$(shell echo $(TAG) | cut -d. -f2))
	$(eval PATCH=$(shell echo $(TAG) | cut -d. -f3))
	$(eval NEW_TAG=v$(MAJOR).$(MINOR).$(shell echo $$(($(PATCH)+1))))
	@git tag $(NEW_TAG)
	@git push origin $(NEW_TAG)
	@echo "Tagged and pushed $(NEW_TAG)"
