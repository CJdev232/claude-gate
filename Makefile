BINARY     = .build/release/claude-gate
INSTALL_TO = /usr/local/bin/claude-gate

.PHONY: build release install uninstall clean

build:
	swift build

release:
	swift build -c release

install: release
	cp $(BINARY) $(INSTALL_TO)
	@echo "Installed to $(INSTALL_TO)"
	@echo "Run: claude-gate --install"

uninstall:
	-$(INSTALL_TO) --uninstall
	rm -f $(INSTALL_TO)

clean:
	rm -rf .build
