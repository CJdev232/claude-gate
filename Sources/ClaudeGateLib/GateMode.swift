import Foundation
import Observation

public enum GateMode: String, CaseIterable {
    case present, remote, away, observer, observerWorkspace

    public var displayName: String {
        switch self {
        case .present: "Present"
        case .remote: "Remote"
        case .away: "Away"
        case .observer: "Observer"
        case .observerWorkspace: "Observer (Workspace)"
        }
    }
}

@Observable
@MainActor
public final class GateModeState {
    public var current: GateMode = .present

    public init() {}
}
