import ClaudeGateLib
import AppKit
import Foundation

let args = CommandLine.arguments

// --install
if args.contains("--install") {
    do {
        try Installer.install()
        print("✓ claude-gate installed.")
        print("  Config: ~/.claude-gate/config.json")
        print("  Restart Claude Code to activate hooks.")
    } catch {
        fputs("Install failed: \(error)\n", stderr); exit(1)
    }
    exit(0)
}

// --uninstall
if args.contains("--uninstall") {
    do {
        try Installer.uninstall()
        print("✓ claude-gate uninstalled.")
    } catch {
        fputs("Uninstall failed: \(error)\n", stderr); exit(1)
    }
    exit(0)
}

// subagent-start / subagent-stop — called by command hook, reads JSON stdin, POSTs to server
if let cmd = args.dropFirst().first, cmd == "subagent-start" || cmd == "subagent-stop" {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let path = cmd == "subagent-start" ? "/subagent-start" : "/subagent-stop"
    var req = URLRequest(url: URL(string: "http://127.0.0.1:9191\(path)")!)
    req.httpMethod = "POST"
    req.httpBody = data
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 2.0
    URLSession.shared.dataTask(with: req).resume()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
    exit(0)
}

// GUI mode
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
