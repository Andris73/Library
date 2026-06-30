//
//  TitleMatching.swift
//  Library
//
//  Lightweight bibliographic title matching used to line up a wanted book
//  title against messy AudiobookBay release titles. Token-overlap rather than
//  substring: a release that pads the title with series, author, narrator, or
//  format words still matches, while unrelated books don't.
//

import Foundation

enum TitleMatching {
    private static let stopwords: Set<String> = ["the", "a", "an", "of", "and", "to", "in", "or"]

    /// Significant lowercased, diacritic-folded word tokens (articles and
    /// one-character fragments dropped).
    static func tokens(_ value: String) -> Set<String> {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let words = String(mapped).split(separator: " ").map(String.init)
        return Set(words.filter { $0.count >= 2 }).subtracting(stopwords)
    }

    /// How completely `candidate` covers the `wanted` title's significant words.
    /// 1.0 when every wanted word is present (the candidate may carry extra
    /// series/author/format words); the covered fraction otherwise; 0 when
    /// there's no overlap.
    static func score(wanted: String, candidate: String) -> Double {
        let want = tokens(wanted)
        let cand = tokens(candidate)
        guard !want.isEmpty, !cand.isEmpty else { return 0 }

        let shared = want.intersection(cand)
        guard !shared.isEmpty else { return 0 }
        if want.isSubset(of: cand) { return 1.0 }
        return Double(shared.count) / Double(want.count)
    }
}
