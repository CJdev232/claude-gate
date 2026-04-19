import SwiftUI

public struct PolicyGridView: View {
    @Binding public var config: PolicyConfig
    public let onChanged: () -> Void

    private static let toolOrder = [
        "Read","Glob","Grep","WebFetch","WebSearch","Task","Write","Edit","Bash"
    ]

    public init(config: Binding<PolicyConfig>, onChanged: @escaping () -> Void) {
        self._config = config; self.onChanged = onChanged
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Tool").frame(width: 72, alignment: .leading)
                Text("Parent").frame(maxWidth: .infinity)
                Text("Subagent").frame(maxWidth: .infinity)
                Text("Timeout").frame(maxWidth: .infinity)
            }
            .font(.system(size: 9)).foregroundColor(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 4)

            Divider()

            ForEach(Self.toolOrder, id: \.self) { tool in
                if config.policies[tool] != nil {
                    HStack(spacing: 0) {
                        Text(tool).font(.system(size: 11))
                            .frame(width: 72, alignment: .leading)
                        PolicyCell(value: Binding(
                            get: { config.policies[tool]!.parent },
                            set: { config.policies[tool]!.parent = $0; onChanged() }
                        )).frame(maxWidth: .infinity)
                        PolicyCell(value: Binding(
                            get: { config.policies[tool]!.subagent },
                            set: { config.policies[tool]!.subagent = $0; onChanged() }
                        )).frame(maxWidth: .infinity)
                        PolicyCell(value: Binding(
                            get: { config.policies[tool]!.timeout },
                            set: { config.policies[tool]!.timeout = $0; onChanged() }
                        )).frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
        }
    }
}

private struct PolicyCell: View {
    @Binding var value: PolicyValue

    private func color(_ v: PolicyValue) -> Color {
        switch v {
        case .allow: Color(red: 0/255,   green: 178/255, blue: 169/255) // #00B2A9
        case .ask:   Color(red: 230/255, green: 159/255, blue: 0/255)   // #E69F00
        case .deny:  Color(red: 204/255, green: 121/255, blue: 167/255) // #CC79A7
        }
    }

    private func icon(_ v: PolicyValue) -> String {
        switch v { case .allow: "✓"; case .ask: "◦"; case .deny: "✕" }
    }

    private func next(_ v: PolicyValue) -> PolicyValue {
        switch v { case .allow: .ask; case .ask: .deny; case .deny: .allow }
    }

    var body: some View {
        Button { value = next(value) } label: {
            Text("\(icon(value)) \(value.rawValue)")
                .font(.system(size: 11))
                .foregroundColor(color(value))
        }
        .buttonStyle(.plain)
    }
}
