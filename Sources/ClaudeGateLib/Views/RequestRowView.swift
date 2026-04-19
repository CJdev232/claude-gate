import SwiftUI

public struct RequestRowView: View {
    public let request: PendingRequest
    public let onAllow: () -> Void
    public let onDeny: () -> Void

    // Accessible color system: cyan ✓ / orange ◦ / pink ✕
    private static let cyanColor   = Color(red: 0/255,   green: 178/255, blue: 169/255) // #00B2A9
    private static let orangeColor = Color(red: 230/255, green: 159/255, blue: 0/255)   // #E69F00
    private static let pinkColor   = Color(red: 204/255, green: 121/255, blue: 167/255) // #CC79A7

    public init(request: PendingRequest, onAllow: @escaping () -> Void, onDeny: @escaping () -> Void) {
        self.request = request; self.onAllow = onAllow; self.onDeny = onDeny
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.toolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Self.orangeColor)
                Text(request.sessionContext == .parent ? "parent" : "subagent")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeAgo(request.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(request.inputPreview.isEmpty ? "(no preview)" : request.inputPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.black.opacity(0.15))
                .cornerRadius(3)
            HStack(spacing: 6) {
                Button(action: onDeny) {
                    Text("✕ Deny")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Self.pinkColor)
                .foregroundColor(.white)
                .cornerRadius(4)
                .keyboardShortcut("n", modifiers: [.control, .shift])

                Button(action: onAllow) {
                    Text("✓ Allow")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Self.cyanColor)
                .foregroundColor(.white)
                .cornerRadius(4)
                .keyboardShortcut("y", modifiers: [.control, .shift])

                Spacer()
                Text("⌃⇧N / ⌃⇧Y")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        return s < 60 ? "\(s)s ago" : "\(s / 60)m ago"
    }
}
