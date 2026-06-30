import Foundation

/// Best-effort series detection from AudiobookBay titles.
///
/// ABB has no structured series metadata; the series name and position are only
/// inferrable from the title string (e.g. "Reborn Mercenary 1 - Kaz Hunter").
/// This parser handles the common numbered patterns and degrades to `nil` when
/// it can't confidently detect a series — name-only series (e.g. "The Way of
/// Kings") legitimately return `nil` here and need an external metadata source.
public struct ABBSeriesParser {
    public struct Parsed: Sendable, Hashable {
        public let seriesName: String
        public let position: Double?

        public init(seriesName: String, position: Double?) {
            self.seriesName = seriesName
            self.position = position
        }
    }

    /// Detects the series name and (when present) the position from a book title.
    /// Returns `nil` when no trailing volume number can be found.
    public static func parse(title: String, author: String?) -> Parsed? {
        let base = titleWithoutAuthor(title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        let pattern = #/(?i)^(?<series>.*?)[\s,]+(?:book|vol\.?|volume|#)?\s*(?<num>\d+(?:\.\d+)?)(?:\s*[:\-–—].*)?$/#
        guard let match = try? pattern.wholeMatch(in: base) else { return nil }

        var series = String(match.output.series)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,:-–—\t"))
        guard !series.isEmpty else { return nil }

        // Handle the "{Book Title}: {Series}, Book N" convention (e.g.
        // "This Inevitable Ruin: Dungeon Crawler Carl, Book 7") by keeping the
        // segment after the last separator, which is the series name.
        for separator in [": ", " - ", " – ", " — "] {
            if let range = series.range(of: separator, options: .backwards) {
                let candidate = String(series[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,:-–—\t"))
                if !candidate.isEmpty {
                    series = candidate
                }
                break
            }
        }

        let position = Double(String(match.output.num))
        return Parsed(seriesName: series, position: position)
    }

    /// Strips the trailing " - {Author}" segment that ABB appends to every title.
    public static func titleWithoutAuthor(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" - ", " – ", " — "] {
            if let range = trimmed.range(of: separator, options: .backwards) {
                return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }

    /// Renders a position for display, dropping a trailing ".0" for whole numbers.
    public static func formatPosition(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }
}
