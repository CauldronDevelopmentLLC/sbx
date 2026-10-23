PREFIX   ?= $(HOME)/.local
CONFIG   ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/sbx
PROGRAMS := sbx sbx-portal sbx-x11

install:
	install -d $(PREFIX)/bin $(CONFIG)
	install -m 755 $(PROGRAMS) $(PREFIX)/bin
	@if [ ! -e $(CONFIG)/global.yml ]; then \
	  install -m 644 global.yml $(CONFIG); \
	elif ! cmp -s global.yml $(CONFIG)/global.yml; then \
	  echo "$(CONFIG)/global.yml differs, see:" \
	    "diff -u $(CONFIG)/global.yml global.yml"; \
	fi

uninstall:
	rm -f $(addprefix $(PREFIX)/bin/,$(PROGRAMS))

check:
	tests/sbx-x11

.PHONY: install uninstall check
