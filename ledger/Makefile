COBC     ?= cobc
COBFLAGS ?= -free -Wall -fstatic-call -I copy
PREFIX   ?= /usr/local
E2E_PORT ?= 8080
E2E_NAME := cobol-demos-ledger-e2e

CORE := src/ledgrun.cbl $(wildcard copy/*.cpy)

.PHONY: build test e2e install clean

build: build/ledger build/ledgerweb

build/ledger: src/ledger.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/ledger.cbl src/ledgrun.cbl

build/ledgerweb: src/ledgerweb.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/ledgerweb.cbl src/ledgrun.cbl

test: build
	./tests/run.sh

# Builds the web image, serves it on E2E_PORT and runs Playwright
# against it. Needs Docker and `npm ci` in e2e/.
e2e:
	docker build -t $(E2E_NAME) .
	docker rm -f $(E2E_NAME) >/dev/null 2>&1 || true
	docker run -d --name $(E2E_NAME) -p $(E2E_PORT):8080 $(E2E_NAME) >/dev/null
	@for _ in $$(seq 1 20); do \
	  curl -sf http://127.0.0.1:$(E2E_PORT)/cgi-bin/ledger >/dev/null && break; sleep 0.5; \
	done
	cd e2e && BASE_URL=http://127.0.0.1:$(E2E_PORT) npx playwright test; \
	  status=$$?; docker rm -f $(E2E_NAME) >/dev/null; exit $$status

install: build/ledger
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/ledger $(DESTDIR)$(PREFIX)/bin/ledger

clean:
	rm -rf build
