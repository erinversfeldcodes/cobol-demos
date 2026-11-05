# Runs a target in every app. Each app also builds on its own:
#   make -C amortise test
APPS := amortise ledger

# The nixpkgs revision in flake.lock, which every app's Dockerfile must
# also build from.
NIXPKGS_REV = $(shell jq -r .nodes.nixpkgs.locked.rev flake.lock)
NIXPKGS_ARG = ARG NIXPKGS=github:NixOS/nixpkgs/$(NIXPKGS_REV)

.PHONY: build test e2e clean nix-pin check-nix-pin

build test e2e clean:
	@for app in $(APPS); do $(MAKE) -C $$app $@ || exit 1; done

# After `nix flake update`, point the Dockerfiles at the new revision.
nix-pin:
	@for app in $(APPS); do \
	  sed -i.bak 's|^ARG NIXPKGS=.*|$(NIXPKGS_ARG)|' $$app/Dockerfile && rm $$app/Dockerfile.bak; \
	done

check-nix-pin:
	@for app in $(APPS); do \
	  grep -qx '$(NIXPKGS_ARG)' $$app/Dockerfile \
	    || { echo "$$app/Dockerfile doesn't build from nixpkgs $(NIXPKGS_REV); run make nix-pin" >&2; exit 1; }; \
	done
