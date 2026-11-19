import Foundation

struct TrackInfo: Equatable, Codable {
    var title: String = ""
    var author: String = ""
    var artwork: String = ""
    var elapsed: String = "0:00"
    var duration: String = "0:00"
    var isPlaying: Bool = false
    var url: String = ""
    var isLiked: Bool = false
    var isShuffling: Bool = false
    var repeatMode: String = "none" // "none", "one", "all"

    var highResArtwork: String {
        artwork
            .replacingOccurrences(of: "50x50.", with: "500x500.")
            .replacingOccurrences(of: "t50x50", with: "t500x500")
            .replacingOccurrences(of: "large.", with: "t500x500.")
    }

    var elapsedSeconds: TimeInterval {
        TrackTimeParser.toSeconds(elapsed)
    }

    var durationSeconds: TimeInterval {
        let parsed = TrackTimeParser.toSignedSeconds(duration)
        if parsed < 0 {
            return max(1, elapsedSeconds + abs(parsed))
        }
        return max(0, parsed)
    }

    var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, elapsedSeconds / durationSeconds))
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TrackTimeParser {
    static func toSignedSeconds(_ timeStr: String) -> TimeInterval {
        let trimmed = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let isNegative = trimmed.hasPrefix("-")
        let raw = isNegative ? String(trimmed.dropFirst()) : trimmed
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }

        var seconds: Double = 0
        for part in parts {
            seconds = seconds * 60 + part
        }
        return isNegative ? -seconds : seconds
    }

    static func toSeconds(_ timeStr: String) -> TimeInterval {
        abs(toSignedSeconds(timeStr))
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct ItemMetadata: Equatable, Codable {
    var name: String = ""
    var author: String = "Unknown"
    var version: String = "0.0.0"
    var description: String = ""
    var license: String = ""
    var homepage: String = ""
}

struct CustomTheme: Identifiable, Equatable, Codable {
    var id: String { name }
    var name: String
    var css: String
    var metadata: ItemMetadata
}

struct CustomPlugin: Identifiable, Equatable, Codable {
    var id: String { name }
    var name: String
    var code: String
    var enabled: Bool
    var metadata: ItemMetadata
}
