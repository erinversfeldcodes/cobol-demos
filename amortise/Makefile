COBC     ?= cobc
COBFLAGS ?= -free -Wall -fstatic-call -I copy
PREFIX   ?= /usr/local

CORE := src/amortcalc.cbl $(wildcard copy/*.cpy)

.PHONY: build test install clean

build: build/amortise build/amortweb

build/amortise: src/amortise.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/amortise.cbl src/amortcalc.cbl

build/amortweb: src/amortweb.cbl $(CORE)
	@mkdir -p build
	$(COBC) -x $(COBFLAGS) -o $@ src/amortweb.cbl src/amortcalc.cbl

test: build
	./tests/run.sh

install: build/amortise
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/amortise $(DESTDIR)$(PREFIX)/bin/amortise

clean:
	rm -rf build
