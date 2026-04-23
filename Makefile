BINARY     = .build/release/claude-gate
INSTALL_TO = /usr/local/bin/claude-gate

.PHONY: build release install uninstall clean test

build:
	swift build

release:
	swift build -c release

# Usage: sudo make install (both cp and codesign need root)
install: release
	@kill $$(pgrep claude-gate) 2>/dev/null; while lsof -ti :9191 >/dev/null 2>&1; do sleep 0.2; done; true
	cp $(BINARY) $(INSTALL_TO)
	codesign --force --sign - $(INSTALL_TO)
	@echo "Installed to $(INSTALL_TO)"
	@echo "Run: claude-gate --install  (first time only)"
	@echo "Run: claude-gate &          (to start)"

# Usage: sudo make restart (kills, installs, starts)
restart: install
	@claude-gate &
	@sleep 1
	@echo "Restarted"

uninstall:
	-$(INSTALL_TO) --uninstall
	rm -f $(INSTALL_TO)

test: release
	@chmod +x scripts/test-all.sh
	@./scripts/test-all.sh

clean:
	rm -rf .build
