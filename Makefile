# Runs a target in every app. Each app also builds on its own:
#   make -C amortise test
APPS := amortise ledger

.PHONY: build test e2e clean

build test e2e clean:
	@for app in $(APPS); do $(MAKE) -C $$app $@ || exit 1; done
