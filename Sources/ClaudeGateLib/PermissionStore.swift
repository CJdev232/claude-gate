import Foundation
import Observation

public enum Decision: Equatable {
    case allow, deny
}

public enum SessionContext {
    case parent, subagent
}

public struct PendingRequest: Identifiable {
    public let id: UUID
    public let toolName: String
    public let sessionContext: SessionContext
    public let inputPreview: String
    public let timestamp: Date
    let continuation: CheckedContinuation<Decision, Never>

    public init(
        id: UUID, toolName: String, sessionContext: SessionContext,
        inputPreview: String, timestamp: Date,
        continuation: CheckedContinuation<Decision, Never>
    ) {
        self.id = id; self.toolName = toolName
        self.sessionContext = sessionContext; self.inputPreview = inputPreview
        self.timestamp = timestamp; self.continuation = continuation
    }
}

@Observable
@MainActor
public final class PermissionStore {
    public var pendingRequests: [PendingRequest] = []

    public init() {}

    public func add(_ request: PendingRequest) {
        pendingRequests.append(request)
    }

    public func decide(id: UUID, allow: Bool) {
        guard let idx = pendingRequests.firstIndex(where: { $0.id == id }) else { return }
        let req = pendingRequests.remove(at: idx)
        req.continuation.resume(returning: allow ? .allow : .deny)
    }

    /// Called when the timeout fires; applies the tool's timeout policy.
    public func decideTimeout(id: UUID, timeoutPolicy: PolicyValue) {
        switch timeoutPolicy {
        case .allow:       decide(id: id, allow: true)
        case .deny, .ask:  decide(id: id, allow: false)
        }
    }
}
