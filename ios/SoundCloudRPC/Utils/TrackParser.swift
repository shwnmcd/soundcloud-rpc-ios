import Foundation

/// Swift port of soundcloud-rpc's trackParser.ts
enum TrackParser {
    private static let dashChars: Set<Character> = ["-", "\u{2013}", "\u{2014}", "\u{2015}"]

    private static let separatorRegex = try? NSRegularExpression(
        pattern: #"(\s+[\u002D\u2013\u2014\u2015]+\s+|[\u002D\u2013\u2014\u2015]{2,})"#,
        options: []
    )

    private static let doubleDashRegex = try? NSRegularExpression(
        pattern: #"[\u002D\u2013\u2014\u2015]{2,}"#,
        options: []
    )

    private static func hasRepeatedCharacters(_ text: String, threshold: Int = 5) -> Bool {
        var lastChar: Character?
        var run = 0
        for ch in text {
            if ch == lastChar {
                run += 1
                if run >= threshold { return true }
            } else {
                lastChar = ch
                run = 1
            }
        }
        return false
    }

    private static func hasInvalidPatterns(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let first = trimmed.first, dashChars.contains(first) { return true }
        if let last = trimmed.last, dashChars.contains(last) { return true }
        if hasRepeatedCharacters(trimmed, threshold: 5) { return true }

        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let regex = doubleDashRegex, regex.firstMatch(in: trimmed, range: nsRange) != nil {
            return true
        }
        return false
    }

    static func parseSoundCloudTitle(_ title: String) -> (artist: String?, track: String) {
        let cleanTitle = title.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanTitle.isEmpty else { return (nil, "") }

        let nsRange = NSRange(cleanTitle.startIndex..<cleanTitle.endIndex, in: cleanTitle)
        if let regex = separatorRegex,
           let match = regex.firstMatch(in: cleanTitle, range: nsRange),
           match.range.location > 0,
           let range = Range(match.range, in: cleanTitle) {
            let artist = String(cleanTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let track = String(cleanTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty && !track.isEmpty && !hasInvalidPatterns(artist) && !hasInvalidPatterns(track) {
                return (artist, track)
            }
        }

        return (nil, cleanTitle)
    }

    static func normalizeTrackInfo(
        titleFromPage: String,
        authorFromPage: String,
        useTrackParser: Bool = true
    ) -> (artist: String, track: String) {
        let fallbackArtist = authorFromPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Unknown Artist"
            : authorFromPage.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = titleFromPage.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTrack = firstLine.isEmpty ? "Unknown Track" : firstLine

        guard useTrackParser, !titleFromPage.isEmpty else {
            return (fallbackArtist, fallbackTrack)
        }

        let parsed = parseSoundCloudTitle(titleFromPage)
        return (
            artist: parsed.artist ?? fallbackArtist,
            track: parsed.track.isEmpty ? "Unknown Track" : parsed.track
        )
    }
}
