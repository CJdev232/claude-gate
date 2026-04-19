import AppKit
import SwiftUI

@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: PermissionStore
    private var config: PolicyConfig
    private let configURL: URL
    private var clickMonitor: Any?

    private static let orangeColor = NSColor(
        red: 230/255, green: 159/255, blue: 0, alpha: 1  // #E69F00
    )

    public init(store: PermissionStore, config: PolicyConfig, configURL: URL) {
        self.store = store; self.config = config; self.configURL = configURL
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        setupPopover()
    }

    private func setupButton() {
        guard let btn = statusItem.button else { return }
        btn.image = NSImage(systemSymbolName: "lock.shield",
                            accessibilityDescription: "claude-gate")
        btn.action = #selector(toggle)
        btn.target = self
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                config: Binding(get: { self.config }, set: { self.config = $0 }),
                onConfigChanged: { [weak self] in self?.persistConfig() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
        popover.contentSize = NSSize(width: 340, height: 420)
    }

    @objc private func toggle() {
        if popover.isShown {
            closePopover()
        } else if let btn = statusItem.button {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in self?.closePopover() }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    public func refreshBadge() {
        guard let btn = statusItem.button else { return }
        let n = store.pendingRequests.count
        if n > 0 {
            btn.attributedTitle = NSAttributedString(
                string: " ◦ \(n)",
                attributes: [
                    .foregroundColor: Self.orangeColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            )
        } else {
            btn.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func persistConfig() {
        try? config.save(to: configURL)
    }
}
