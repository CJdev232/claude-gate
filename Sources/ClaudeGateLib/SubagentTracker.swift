import Foundation

public actor SubagentTracker {
    private var sessionIDs: Set<String> = []

    public init() {}

    public func add(_ id: String)    { sessionIDs.insert(id) }
    public func remove(_ id: String) { sessionIDs.remove(id) }
    public func isSubagent(_ id: String) -> Bool { sessionIDs.contains(id) }
}
