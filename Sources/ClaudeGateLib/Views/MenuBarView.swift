import SwiftUI

public struct MenuBarView: View {
    public let store: PermissionStore
    public let activityLog: ActivityLog
    @Binding public var config: PolicyConfig
    public let onConfigChanged: () -> Void
    public let onQuit: () -> Void

    private enum Tab { case requests, activity, policies }
    @State private var activeTab: Tab = .requests

    public init(
        store: PermissionStore,
        activityLog: ActivityLog,
        config: Binding<PolicyConfig>,
        onConfigChanged: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store; self.activityLog = activityLog; self._config = config
        self.onConfigChanged = onConfigChanged; self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                tabBtn("Requests (\(store.pendingRequests.count))", active: activeTab == .requests) {
                    activeTab = .requests
                }
                tabBtn("Activity (\(activityLog.totalCount))", active: activeTab == .activity) {
                    activeTab = .activity
                }
                tabBtn("Policies", active: activeTab == .policies) {
                    activeTab = .policies
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            switch activeTab {
            case .policies:
                ScrollView {
                    PolicyGridView(config: $config, onChanged: onConfigChanged)
                }
                .frame(maxHeight: 280)
            case .activity:
                activityPane
            case .requests:
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

    @ViewBuilder
    private var activityPane: some View {
        if activityLog.totalCount == 0 {
            VStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                Text("No activity yet")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(height: 72)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(activityLog.entries) { entry in
                        ActivityRowView(entry: entry)
                        if entry.id != activityLog.entries.last?.id { Divider() }
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
