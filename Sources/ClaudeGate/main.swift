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

// --restart
if args.contains("--restart") {
    // Find and kill existing process
    let find = Process()
    find.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    find.arguments = ["claude-gate"]
    let pipe = Pipe()
    find.standardOutput = pipe
    find.standardError = FileHandle.nullDevice
    try? find.run(); find.waitUntilExit()
    let pids = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .split(separator: "\n")
        .compactMap { Int32($0) }
        .filter { $0 != ProcessInfo.processInfo.processIdentifier } ?? []
    for pid in pids {
        kill(pid, SIGTERM)
    }
    if !pids.isEmpty {
        print("Stopping claude-gate (pid \(pids.map(String.init).joined(separator: ", ")))...")
        // Wait for port to be free (max 5 seconds)
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/config.json")
        let port = (try? PolicyConfig.load(from: configURL))?.server.port ?? 9191
        for _ in 0..<50 {
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
            check.arguments = ["-ti", ":\(port)"]
            check.standardOutput = FileHandle.nullDevice
            check.standardError = FileHandle.nullDevice
            try? check.run(); check.waitUntilExit()
            if check.terminationStatus != 0 { break }  // port free
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    // Start new instance by re-exec without --restart
    let exe = CommandLine.arguments[0]
    let task = Process()
    task.executableURL = URL(fileURLWithPath: exe)
    task.arguments = []
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    print("✓ claude-gate restarted (pid \(task.processIdentifier))")
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
