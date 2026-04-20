import Foundation
import Network

public final class HTTPServer {
    private var _config: PolicyConfig
    private let configLock = NSLock()
    private let tracker: SubagentTracker
    private let store: PermissionStore
    private var listener: NWListener?

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
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { conn.cancel(); return }
            Task { await self.processRequest(data: data, conn: conn) }
        }
    }

    private func processRequest(data: Data, conn: NWConnection) async {
        guard let text = String(data: data, encoding: .utf8),
              let (path, body) = parseHTTP(text) else {
            reply(conn, json: ["error": "bad_request"]); return
        }
        switch path {
        case "/permission":     await handlePermission(body: body, conn: conn)
        case "/subagent-start": await handleSubagentStart(body: body, conn: conn)
        case "/subagent-stop":  await handleSubagentStop(body: body, conn: conn)
        default:                reply(conn, json: ["error": "not_found"])
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

        switch policyValue {
        case .allow:
            replyPermission(conn, behavior: "allow")
        case .deny:
            replyPermission(conn, behavior: "deny")
        case .ask:
            let decision = await askUser(
                toolName: toolName,
                context: isSubagent ? .subagent : .parent,
                inputPreview: inputPreview,
                timeoutSecs: config.server.timeout,
                timeoutPolicy: pol.timeout
            )
            replyPermission(conn, behavior: decision == .allow ? "allow" : "deny")
        }
    }

    private func askUser(
        toolName: String, context: SessionContext,
        inputPreview: String, timeoutSecs: Int, timeoutPolicy: PolicyValue
    ) async -> Decision {
        let id = UUID()
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
