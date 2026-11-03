COBC     ?= cobc
COBFLAGS ?= -free -Wall -fstatic-call -I copy
PREFIX   ?= /usr/local

CORE := src/ledgrun.cbl $(wildcard copy/*.cpy)

.PHONY: build test install clean

build: build/ledger build/ledgerweb

build/ledger: src/ledger.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/ledger.cbl src/ledgrun.cbl

build/ledgerweb: src/ledgerweb.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/ledgerweb.cbl src/ledgrun.cbl

test: build
	./tests/run.sh

install: build/ledger
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/ledger $(DESTDIR)$(PREFIX)/bin/ledger

clean:
	rm -rf build
