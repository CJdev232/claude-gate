import Foundation
import Observation
import os

public struct ActivityEntry: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let toolName: String
    public let inputPreview: String
    public let decision: String
    public let isObserver: Bool
    public let sessionID: String

    public init(
        toolName: String, inputPreview: String, decision: String,
        isObserver: Bool, sessionID: String
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.toolName = toolName
        self.inputPreview = inputPreview
        self.decision = decision
        self.isObserver = isObserver
        self.sessionID = sessionID
    }
}

@Observable
@MainActor
public final class ActivityLog {
    private var buffer: [ActivityEntry] = []
    private var writeIndex = 0
    private(set) var totalCount = 0
    private let capacity: Int

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "com.claude-gate", category: "activity")

    public var entries: [ActivityEntry] {
        guard totalCount > 0 else { return [] }
        if totalCount <= capacity {
            return Array(buffer[0..<min(totalCount, buffer.count)].reversed())
        }
        let tail = Array(buffer[writeIndex..<buffer.count])
        let head = Array(buffer[0..<writeIndex])
        return (tail + head).reversed()
    }

    public init(capacity: Int = 200) {
        self.capacity = capacity
        self.fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/activity.jsonl")
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(_ entry: ActivityEntry) {
        // Ring buffer
        if buffer.count < capacity {
            buffer.append(entry)
        } else {
            buffer[writeIndex] = entry
        }
        writeIndex = (writeIndex + 1) % capacity
        totalCount += 1

        // JSONL file
        writeToFile(entry)
    }

    private func writeToFile(_ entry: ActivityEntry) {
        do {
            var line = try encoder.encode(entry)
            line.append(0x0A) // newline
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(line)
                handle.closeFile()
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            logger.error("Failed to write activity log: \(error)")
        }
    }
}
