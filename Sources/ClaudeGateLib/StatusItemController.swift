import AppKit
import os
import SwiftUI

@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: PermissionStore
    private var config: PolicyConfig
    private let configURL: URL
    private var clickMonitor: Any?
    private var wasAutoOpened = false
    private let modeState: GateModeState
    private var modeMenu: NSMenu?
    private let logger = Logger(subsystem: "com.claude-gate", category: "ui")

    private static let orangeColor = NSColor(
        red: 230/255, green: 159/255, blue: 0, alpha: 1  // #E69F00
    )
    private static let tealColor = NSColor(
        red: 0/255, green: 178/255, blue: 169/255, alpha: 1  // #00B2A9
    )

    public init(store: PermissionStore, config: PolicyConfig, configURL: URL, modeState: GateModeState) {
        self.store = store; self.config = config; self.configURL = configURL; self.modeState = modeState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        setupPopover()
        setupMenu()
    }

    private func setupButton() {
        guard let btn = statusItem.button else { return }
        btn.image = NSImage(systemSymbolName: "lock.shield",
                            accessibilityDescription: "claude-gate")
        btn.action = #selector(handleClick(_:))
        btn.target = self
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            if let menu = modeMenu, let btn = statusItem.button {
                updateMenuCheckmarks()
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.height + 5), in: btn)
            }
        } else {
            togglePopover()
        }
    }

    private func setupPopover() {
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                config: Binding(get: { self.config }, set: { self.config = $0 }),
                onConfigChanged: { [weak self] in self?.persistConfig() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
        popover.contentSize = NSSize(width: 400, height: 420)
    }

    private func setupMenu() {
        let menu = NSMenu()

        let presentItem = NSMenuItem(title: "Present", action: #selector(setPresent), keyEquivalent: "")
        presentItem.target = self
        presentItem.state = .on
        menu.addItem(presentItem)

        let remoteItem = NSMenuItem(title: "Remote", action: #selector(setRemote), keyEquivalent: "")
        remoteItem.target = self
        menu.addItem(remoteItem)

        let awayItem = NSMenuItem(title: "Away", action: #selector(setAway), keyEquivalent: "")
        awayItem.target = self
        menu.addItem(awayItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit claude-gate", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        self.modeMenu = menu
    }

    @objc private func setPresent() { setMode(.present) }
    @objc private func setRemote() { setMode(.remote) }
    @objc private func setAway() { setMode(.away) }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    private func setMode(_ mode: GateMode) {
        modeState.current = mode
        logger.info("Mode changed to: \(mode.rawValue)")
        updateMenuCheckmarks()
        updateIconBadge()
    }

    private func updateMenuCheckmarks() {
        guard let menu = modeMenu else { return }
        for item in menu.items {
            switch item.title {
            case "Present": item.state = modeState.current == .present ? .on : .off
            case "Remote":  item.state = modeState.current == .remote ? .on : .off
            case "Away":    item.state = modeState.current == .away ? .on : .off
            default: break
            }
        }
    }

    private func updateIconBadge() {
        guard let btn = statusItem.button else { return }
        switch modeState.current {
        case .present:
            btn.image = NSImage(systemSymbolName: "lock.shield",
                                accessibilityDescription: "claude-gate")
            btn.attributedTitle = NSAttributedString(string: "")
        case .remote:
            btn.image = NSImage(systemSymbolName: "lock.shield",
                                accessibilityDescription: "claude-gate remote")
            btn.attributedTitle = NSAttributedString(
                string: " R",
                attributes: [.foregroundColor: Self.orangeColor,
                             .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
        case .away:
            btn.image = NSImage(systemSymbolName: "lock.shield",
                                accessibilityDescription: "claude-gate away")
            btn.attributedTitle = NSAttributedString(
                string: " A",
                attributes: [.foregroundColor: Self.tealColor,
                             .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if let btn = statusItem.button {
            wasAutoOpened = false
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in self?.closePopover() }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        wasAutoOpened = false
    }

    public func refreshBadge() {
        guard let btn = statusItem.button else { return }
        if modeState.current == .away {
            return  // away badge handled by updateIconBadge()
        }
        let n = store.pendingRequests.count
        if n > 0 {
            btn.attributedTitle = NSAttributedString(
                string: " ◦ \(n)",
                attributes: [
                    .foregroundColor: Self.orangeColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            )
        } else if modeState.current == .remote {
            updateIconBadge()
        } else {
            btn.attributedTitle = NSAttributedString(string: "")
        }
    }

    public func autoOpenIfNeeded() {
        guard modeState.current != .away,
              !popover.isShown,
              store.pendingRequests.count > 0,
              let btn = statusItem.button else { return }
        wasAutoOpened = true
        logger.info("Auto-opening popover for \(self.store.pendingRequests.count) pending request(s)")
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        popover.contentViewController?.view.window?.level = .floating
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.closePopover() }
    }

    public func autoCloseIfEmpty() {
        guard popover.isShown, wasAutoOpened, store.pendingRequests.isEmpty else { return }
        logger.info("Auto-closing popover (queue empty)")
        closePopover()
    }

    public func updateConfig(_ newConfig: PolicyConfig) {
        config = newConfig
    }

    private func persistConfig() {
        try? config.save(to: configURL)
    }
}
