import Foundation

/// Swift port of soundcloud-rpc's metadataParser.ts
enum MetadataParser {
    enum Style {
        case css
        case js
    }

    static func parse(source: String, style: Style) -> ItemMetadata {
        var meta = ItemMetadata()
        let pattern = style == .js ? #"/\*\*([\s\S]*?)\*/"# : #"/\*([\s\S]*?)\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
              let range = Range(match.range(at: 1), in: source) else {
            return meta
        }

        let block = String(source[range])
        for line in block.components(separatedBy: .newlines) {
            var cleaned = line.trimmingCharacters(in: .whitespaces)
            if cleaned.hasPrefix("*") {
                cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard cleaned.hasPrefix("@") else { continue }
            let parts = cleaned.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "name": meta.name = val
            case "author": meta.author = val
            case "version": meta.version = val
            case "description": meta.description = val
            case "license": meta.license = val
            case "homepage": meta.homepage = val
            default: break
            }
        }
        return meta
    }

    /// Extracts @target all|content CSS sections (matching soundcloud-rpc themeService)
    static func extractContentCSS(from css: String) -> String {
        let pattern = #"/\*\s*@target\s+(all|content|header|settings)\s*\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return css
        }
        let nsRange = NSRange(css.startIndex..<css.endIndex, in: css)
        let matches = regex.matches(in: css, range: nsRange)
        guard !matches.isEmpty else { return css }

        var allCSS = ""
        var contentCSS = ""

        for (index, match) in matches.enumerated() {
            guard let targetRange = Range(match.range(at: 1), in: css),
                  let markerRange = Range(match.range, in: css) else { continue }
            let target = css[targetRange].lowercased()
            let bodyStart = markerRange.upperBound
            let bodyEnd: String.Index
            if index + 1 < matches.count, let nextRange = Range(matches[index + 1].range, in: css) {
                bodyEnd = nextRange.lowerBound
            } else {
                bodyEnd = css.endIndex
            }
            let body = String(css[bodyStart..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if target == "all" {
                allCSS += (allCSS.isEmpty ? "" : "\n") + body
            } else if target == "content" {
                contentCSS += (contentCSS.isEmpty ? "" : "\n") + body
            }
        }

        if allCSS.isEmpty { return contentCSS }
        if contentCSS.isEmpty { return allCSS }
        return allCSS + "\n" + contentCSS
    }
}
