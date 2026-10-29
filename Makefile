PREFIX   ?= /usr/local
BIN      := $(DESTDIR)$(PREFIX)/bin
LIB      := $(DESTDIR)$(PREFIX)/lib/sbx
BASH     := $(DESTDIR)$(PREFIX)/share/bash-completion/completions
FISH     := $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d
TMPFILES := $(DESTDIR)$(PREFIX)/lib/tmpfiles.d
PROGRAMS := sbx sbx-portal sbx-x11

install: root
	install -d $(BIN) $(LIB) $(BASH) $(FISH) $(TMPFILES)
	install -m 755 $(PROGRAMS) $(BIN)
	cp -R templates images $(LIB)
	chmod -R u+w,go-w,a+rX $(LIB)/templates $(LIB)/images
	install -m 644 completions/sbx.completion $(BASH)/sbx
	install -m 644 completions/sbx.fish $(FISH)/sbx.fish
	install -m 644 sbx.tmpfiles $(TMPFILES)/sbx.conf
	[ -n "$(DESTDIR)" ] || systemd-tmpfiles --create $(TMPFILES)/sbx.conf

uninstall: root
	rm -f $(addprefix $(BIN)/,$(PROGRAMS)) $(BASH)/sbx $(FISH)/sbx.fish \
	  $(TMPFILES)/sbx.conf
	rm -rf $(LIB)

root:
	@[ "$$(id -u)" = 0 ] || { echo 'Run as root, e.g. "sudo make install"' >&2; \
	  exit 1; }

check:
	tests/sbx-x11

.PHONY: install uninstall root check
