import Foundation
import Network
import os

public final class HTTPServer {
    private static let maxRequestSize = 1_048_576  // 1MB
    private static let initialReadSize = 65_536     // 64KB — covers most requests in one read

    private var _config: PolicyConfig
    private let configLock = NSLock()
    private let tracker: SubagentTracker
    private let store: PermissionStore
    private var listener: NWListener?
    private let logger = Logger(subsystem: "com.claude-gate", category: "http")

    public init(config: PolicyConfig, tracker: SubagentTracker, store: PermissionStore) {
        self._config = config
        self.tracker = tracker
        self.store = store
    }

    public func updateConfig(_ newConfig: PolicyConfig) {
        configLock.lock(); defer { configLock.unlock() }
        _config = newConfig
    }

    private var config: PolicyConfig {
        configLock.lock(); defer { configLock.unlock() }
        return _config
    }

    public func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params,
                               on: NWEndpoint.Port(integerLiteral: UInt16(config.server.port)))
        self.listener = l

        l.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:           cont.resume()
                case .failed(let e):   cont.resume(throwing: e)
                default:               break
                }
            }
            l.start(queue: .global())
        }
        logger.info("Server started on port \(self.config.server.port)")

        // Persistent crash-recovery handler (replaces the initial continuation-based one)
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                self.logger.error("Listener failed after startup: \(error). Attempting restart.")
                self.listener?.cancel()
                self.listener = nil
                // One restart attempt
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    do {
                        try await self.start()
                        self.logger.info("Listener restarted successfully")
                    } catch {
                        self.logger.error("Listener restart failed: \(error). Giving up — KeepAlive will restart process.")
                    }
                }
            case .cancelled:
                self.logger.info("Listener cancelled")
            default:
                break
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        logger.info("Server stopped")
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global())
        var buffer = Data()

        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: Self.initialReadSize) { [weak self] data, _, isComplete, error in
                guard let self else { conn.cancel(); return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                }
                // Safety: don't accumulate beyond max
                if buffer.count > Self.maxRequestSize {
                    self.reply(conn, json: ["error": "request_too_large"])
                    return
                }
                // Check if we have the full request
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let contentLength = self.parseContentLength(from: buffer) ?? 0
                    let bodyStart = headerEnd.upperBound
                    let bodyReceivedCount = buffer.count - buffer.distance(from: buffer.startIndex, to: bodyStart)

                    if bodyReceivedCount >= contentLength || isComplete {
                        // Full request received
                        Task { await self.processRequest(data: buffer, conn: conn) }
                        return
                    }
                }
                // Not complete yet — keep reading, or give up if connection closed
                if isComplete || error != nil {
                    if buffer.isEmpty {
                        conn.cancel()
                    } else {
                        Task { await self.processRequest(data: buffer, conn: conn) }
                    }
                    return
                }
                readMore()
            }
        }
        readMore()
    }

    /// Extracts Content-Length from raw HTTP header bytes, returns nil if not found.
    private func parseContentLength(from data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let headers = text[..<headerEnd.lowerBound]
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return len
            }
        }
        return nil
    }

    private func processRequest(data: Data, conn: NWConnection) async {
        guard let text = String(data: data, encoding: .utf8),
              let (path, body) = parseHTTP(text) else {
            logger.error("Bad request: could not parse HTTP")
            reply(conn, json: ["error": "bad_request"]); return
        }
        switch path {
        case "/permission":     await handlePermission(body: body, conn: conn)
        case "/subagent-start": await handleSubagentStart(body: body, conn: conn)
        case "/subagent-stop":  await handleSubagentStop(body: body, conn: conn)
        default:
            logger.error("Unknown path: \(path)")
            reply(conn, json: ["error": "not_found"])
        }
    }

    private func handlePermission(body: Data, conn: NWConnection) async {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let toolName  = json["tool_name"]  as? String,
              let sessionID = json["session_id"] as? String else {
            replyPermission(conn, behavior: "deny"); return
        }

        let inputPreview: String
        if let toolInput = json["tool_input"] as? [String: Any] {
            // Check known high-signal keys first; fall back to first string value
            let priorityKeys = ["command", "file_path", "query", "url"]
            inputPreview = priorityKeys.compactMap { toolInput[$0] as? String }.first
                ?? toolInput.values.compactMap { $0 as? String }.first
                ?? ""
        } else {
            inputPreview = ""
        }

        let isSubagent = await tracker.isSubagent(sessionID)
        let pol = config.policy(for: toolName)
        let policyValue = isSubagent ? pol.subagent : pol.parent

        logger.info("Permission request: \(toolName) [\(isSubagent ? "subagent" : "parent")]")

        switch policyValue {
        case .allow:
            replyPermission(conn, behavior: "allow")
            logger.info("Decision for \(toolName): allow (policy)")
        case .deny:
            replyPermission(conn, behavior: "deny")
            logger.info("Decision for \(toolName): deny (policy)")
        case .ask:
            let requestID = UUID()
            // Monitor connection — if it drops, auto-deny
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .cancelled, .failed:
                    Task { @MainActor in
                        self?.store.decide(id: requestID, allow: false)
                    }
                default:
                    break
                }
            }
            let decision = await askUser(
                id: requestID,
                toolName: toolName,
                context: isSubagent ? .subagent : .parent,
                inputPreview: inputPreview,
                timeoutSecs: config.server.timeout,
                timeoutPolicy: pol.timeout
            )
            conn.stateUpdateHandler = nil  // Clean up after decision
            replyPermission(conn, behavior: decision == .allow ? "allow" : "deny")
            logger.info("Decision for \(toolName): \(decision == .allow ? "allow" : "deny") (user)")
        }
    }

    private func askUser(
        id: UUID,
        toolName: String, context: SessionContext,
        inputPreview: String, timeoutSecs: Int, timeoutPolicy: PolicyValue
    ) async -> Decision {
        return await withCheckedContinuation { continuation in
            let req = PendingRequest(
                id: id, toolName: toolName, sessionContext: context,
                inputPreview: inputPreview, timestamp: Date(), continuation: continuation
            )
            Task { @MainActor in
                self.store.add(req)
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSecs) * 1_000_000_000)
                    await MainActor.run {
                        self.store.decideTimeout(id: id, timeoutPolicy: timeoutPolicy)
                    }
                }
            }
        }
    }

    private func handleSubagentStart(body: Data, conn: NWConnection) async {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let id = json["session_id"] as? String { await tracker.add(id) }
        reply(conn, json: ["ok": true])
    }

    private func handleSubagentStop(body: Data, conn: NWConnection) async {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let id = json["session_id"] as? String { await tracker.remove(id) }
        reply(conn, json: ["ok": true])
    }

    // MARK: - HTTP helpers

    /// Claude Code PermissionRequest response format
    private func replyPermission(_ conn: NWConnection, behavior: String) {
        var decision: [String: Any] = ["behavior": behavior]
        if behavior == "deny" {
            decision["message"] = "Denied by claude-gate"
            decision["interrupt"] = false
        }
        let json: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
        reply(conn, json: json)
    }

    private func reply(_ conn: NWConnection, json: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: json),
              let bodyStr = String(data: body, encoding: .utf8) else { return }
        let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" +
                   "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n\(bodyStr)"
        conn.send(content: http.data(using: .utf8)!, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    /// Minimal HTTP parser — returns (path, bodyData) or nil.
    private func parseHTTP(_ text: String) -> (String, Data)? {
        guard let range = text.range(of: "\r\n\r\n") else { return nil }
        let headers = String(text[..<range.lowerBound])
        let bodyStr  = String(text[range.upperBound...])
        guard let firstLine = headers.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let path     = parts[1]
        let bodyData = bodyStr.trimmingCharacters(in: .whitespacesAndNewlines)
                              .data(using: .utf8) ?? Data()
        return (path, bodyData)
    }
}
