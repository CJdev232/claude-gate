import Foundation
import Observation

public enum GateMode: String, CaseIterable {
    case present, remote, away
}

@Observable
@MainActor
public final class GateModeState {
    public var current: GateMode = .present

    public init() {}
}
