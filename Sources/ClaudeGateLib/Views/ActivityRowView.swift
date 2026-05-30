import SwiftUI

public struct ActivityRowView: View {
    public let entry: ActivityEntry

    private static let tealColor  = Color(red: 0/255,   green: 178/255, blue: 169/255) // #00B2A9
    private static let pinkColor  = Color(red: 204/255, green: 121/255, blue: 167/255) // #CC79A7
    private static let blueColor  = Color(red: 0/255,   green: 114/255, blue: 178/255) // #0072B2

    public init(entry: ActivityEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            decisionBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.toolName)
                        .font(.system(size: 11, weight: .semibold))
                    if entry.isObserver {
                        Text("observer")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Self.blueColor)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Self.blueColor.opacity(0.15))
                            .cornerRadius(3)
                    }
                    Spacer()
                    Text(timeAgo(entry.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if !entry.inputPreview.isEmpty {
                    Text(entry.inputPreview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    @ViewBuilder
    private var decisionBadge: some View {
        let (symbol, color): (String, Color) = entry.decision == "allow"
            ? ("▲", Self.tealColor)
            : ("▼", Self.pinkColor)
        Text(symbol)
            .font(.system(size: 9))
            .foregroundColor(color)
            .frame(width: 14, alignment: .center)
            .padding(.top, 2)
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
