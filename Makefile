# arc — Workspace toolbox
#
# Install:    make install      (symlinks arc into ~/.local/bin)
# Uninstall:  make uninstall
# Deps:       make check        (reports missing external tools)
# Test:       make test         (syntax + smoke tests)
#
# Everything lives in this folder. Nothing external is required at runtime
# beyond the command-line tools listed in `make check` (or by `arc doctor`).

PREFIX      ?= $(HOME)/.local
BINDIR      ?= $(PREFIX)/bin
SRC         := $(CURDIR)
TARGET      := $(BINDIR)/arc
LIBS        := $(wildcard arc-lib/*.sh)

# External tools arc shells out to. Encoded here so `make check` and the
# README stay in sync.
REQUIRED    := magick ffmpeg ffprobe gpg zip unzip
OPTIONAL    := pngquant exiftool

.PHONY: all install uninstall reinstall check test help

all: help

help:
	@echo "arc — Workspace toolbox"
	@echo
	@echo "  make install     symlink $(TARGET) -> $(SRC)/arc"
	@echo "  make uninstall   remove the symlink"
	@echo "  make reinstall   uninstall then install"
	@echo "  make check       report missing external tools"
	@echo "  make test        syntax-check and smoke-test"
	@echo
	@echo "Keep this folder in place after installing: the symlink points at it."

install:
	@mkdir -p "$(BINDIR)"
	@chmod +x "$(SRC)/arc"
	@ln -sfn "$(SRC)/arc" "$(TARGET)"
	@echo "installed: $(TARGET) -> $(SRC)/arc"
	@command -v arc >/dev/null 2>&1 && echo "arc is on PATH" \
		|| echo "warning: $(BINDIR) is not on PATH"

uninstall:
	@if [ -L "$(TARGET)" ]; then rm -f "$(TARGET)"; echo "removed $(TARGET)"; \
	else echo "nothing to remove at $(TARGET)"; fi

reinstall: uninstall install

check:
	@missing=""; \
	for t in $(REQUIRED); do \
		if command -v "$$t" >/dev/null 2>&1; then printf '  ok       %s\n' "$$t"; \
		else printf '  MISSING  %s\n' "$$t"; missing="$$missing $$t"; fi; \
	done; \
	for t in $(OPTIONAL); do \
		if command -v "$$t" >/dev/null 2>&1; then printf '  ok       %s (optional)\n' "$$t"; \
		else printf '  absent   %s (optional)\n' "$$t"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo; echo "Required tools missing. On Fedora:"; \
		echo "  sudo dnf install $$(printf '%s' "$$missing" | tr ' ' '\n' | grep -v '^$$' | sed 's/^ffprobe$$/ffmpeg/;s/^magick$$/ImageMagick/' | sort -u | tr '\n' ' ')"; \
		exit 1; \
	else echo; echo "all required tools present"; fi

test:
	@set -e; \
	echo "syntax:"; \
	bash -n arc && echo "  ok  arc"; \
	for f in $(LIBS); do bash -n "$$f" && echo "  ok  $$f"; done; \
	echo "smoke:"; \
	./arc --help >/dev/null && echo "  ok  arc --help"; \
	./arc img --help >/dev/null && echo "  ok  arc img --help"; \
	./arc vid --help >/dev/null && echo "  ok  arc vid --help"; \
	./arc seal --help >/dev/null && echo "  ok  arc seal --help"; \
	./arc unseal --help >/dev/null && echo "  ok  arc unseal --help"; \
	if ./arc nosuchgroup >/dev/null 2>&1; then echo "  FAIL bad group exit 0"; exit 1; \
	else echo "  ok  bad group rejected"; fi; \
	echo "all tests passed"
