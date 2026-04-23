import SwiftUI

public struct MenuBarView: View {
    public let store: PermissionStore
    @Binding public var config: PolicyConfig
    public let onConfigChanged: () -> Void
    public let onQuit: () -> Void

    @State private var showPolicy = false

    public init(
        store: PermissionStore,
        config: Binding<PolicyConfig>,
        onConfigChanged: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store; self._config = config
        self.onConfigChanged = onConfigChanged; self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                tabBtn("Requests (\(store.pendingRequests.count))", active: !showPolicy) {
                    showPolicy = false
                }
                tabBtn("Policies", active: showPolicy) {
                    showPolicy = true
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if showPolicy {
                ScrollView {
                    PolicyGridView(config: $config, onChanged: onConfigChanged)
                }
                .frame(maxHeight: 280)
            } else {
                requestsPane
            }

            Divider()

            Button("Quit claude-gate", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
        }
        .frame(width: 400)
    }

    @ViewBuilder
    private var requestsPane: some View {
        if store.pendingRequests.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                Text("No pending requests")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(height: 72)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.pendingRequests) { req in
                        RequestRowView(
                            request: req,
                            onAllow: { store.decide(id: req.id, allow: true) },
                            onDeny:  { store.decide(id: req.id, allow: false) }
                        )
                        if req.id != store.pendingRequests.last?.id { Divider() }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func tabBtn(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundColor(active ? .primary : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }
}
