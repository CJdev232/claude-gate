import Foundation

public enum PolicyValue: String, Codable, CaseIterable, Equatable {
    case allow, ask, deny
}

public struct ToolPolicy: Codable, Equatable {
    public var parent: PolicyValue
    public var subagent: PolicyValue
    public var timeout: PolicyValue
    public var awayWorkspace: PolicyValue
    public var awayOutside: PolicyValue

    enum CodingKeys: String, CodingKey {
        case parent, subagent, timeout
        case awayWorkspace = "away_workspace"
        case awayOutside = "away_outside"
    }

    public init(parent: PolicyValue, subagent: PolicyValue, timeout: PolicyValue,
                awayWorkspace: PolicyValue = .deny, awayOutside: PolicyValue = .deny) {
        self.parent = parent
        self.subagent = subagent
        self.timeout = timeout
        self.awayWorkspace = awayWorkspace
        self.awayOutside = awayOutside
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parent = try c.decode(PolicyValue.self, forKey: .parent)
        subagent = try c.decode(PolicyValue.self, forKey: .subagent)
        timeout = try c.decode(PolicyValue.self, forKey: .timeout)
        awayWorkspace = try c.decodeIfPresent(PolicyValue.self, forKey: .awayWorkspace) ?? timeout
        awayOutside = try c.decodeIfPresent(PolicyValue.self, forKey: .awayOutside) ?? .deny
    }
}

public struct ServerConfig: Codable, Equatable {
    public var port: Int
    public var timeout: Int
    public var remoteTimeout: Int

    enum CodingKeys: String, CodingKey {
        case port, timeout
        case remoteTimeout = "remote_timeout"
    }

    public init(port: Int = 9191, timeout: Int = 30, remoteTimeout: Int = 300) {
        self.port = port; self.timeout = timeout; self.remoteTimeout = remoteTimeout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 9191
        timeout = try c.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
        remoteTimeout = try c.decodeIfPresent(Int.self, forKey: .remoteTimeout) ?? 300
    }
}

public struct PolicyConfig: Codable {
    public var server: ServerConfig
    public var policies: [String: ToolPolicy]
    public var workspaces: [String]

    enum CodingKeys: String, CodingKey {
        case server, policies, workspaces
    }

    public init(server: ServerConfig, policies: [String: ToolPolicy], workspaces: [String] = []) {
        self.server = server; self.policies = policies; self.workspaces = workspaces
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decodeIfPresent(ServerConfig.self, forKey: .server) ?? ServerConfig()
        policies = try c.decodeIfPresent([String: ToolPolicy].self, forKey: .policies) ?? [:]
        workspaces = try c.decodeIfPresent([String].self, forKey: .workspaces) ?? []
    }

    public static func defaultConfig() -> PolicyConfig {
        let allowAll = ToolPolicy(parent: .allow, subagent: .allow, timeout: .allow,
                                  awayWorkspace: .allow, awayOutside: .allow)
        let askAskDeny = ToolPolicy(parent: .ask, subagent: .ask, timeout: .deny,
                                    awayWorkspace: .allow, awayOutside: .deny)
        let askDenyDeny = ToolPolicy(parent: .ask, subagent: .deny, timeout: .deny,
                                     awayWorkspace: .deny, awayOutside: .deny)
        return PolicyConfig(server: ServerConfig(), policies: [
            "Read":             allowAll,
            "Glob":             allowAll,
            "Grep":             allowAll,
            "WebFetch":         allowAll,
            "WebSearch":        allowAll,
            "Task":             allowAll,
            "AskUserQuestion":  allowAll,
            "Write":            askAskDeny,
            "Edit":             askAskDeny,
            "Bash":             askDenyDeny,
        ])
    }

    public func policy(for toolName: String) -> ToolPolicy {
        policies[toolName] ?? ToolPolicy(parent: .ask, subagent: .ask, timeout: .deny,
                                         awayWorkspace: .deny, awayOutside: .deny)
    }

    /// Returns true if the given path is inside any configured workspace.
    public func isInsideWorkspace(_ path: String) -> Bool {
        guard !workspaces.isEmpty else { return false }
        for ws in workspaces {
            if ws.hasSuffix("/*") {
                let dir = String(ws.dropLast(2))
                if path.hasPrefix(dir + "/") { return true }
            } else {
                if path.hasPrefix(ws + "/") || path == ws { return true }
            }
        }
        return false
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> PolicyConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return defaultConfig()
        }
        return try JSONDecoder().decode(PolicyConfig.self, from: Data(contentsOf: url))
    }
}

// MARK: - FileWatcher

public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?

    public init(url: URL, onChange: @escaping () -> Void) {
        let dir = url.deletingLastPathComponent()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
    }

    deinit { source?.cancel() }
}
