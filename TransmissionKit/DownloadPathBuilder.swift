import Foundation

public struct DownloadPathBuilder {
    public static let defaultTemplate = "{author}/{series}/{title}"

    public static func build(
        template: String = defaultTemplate,
        author: String? = nil,
        narrator: String? = nil,
        series: String? = nil,
        title: String? = nil,
        year: String? = nil,
        basePath: String = "/downloads/audiobooks"
    ) -> String {
        var path = template

        let replacements: [(String, String?)] = [
            ("{author}", author),
            ("{narrator}", narrator),
            ("{series}", series),
            ("{title}", title),
            ("{year}", year),
        ]

        for (placeholder, value) in replacements {
            let sanitized = sanitize(value ?? "Unknown")
            path = path.replacingOccurrences(of: placeholder, with: sanitized)
        }

        let cleaned = path.components(separatedBy: "/")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "/")

        return "\(basePath)/\(cleaned)"
            .replacingOccurrences(of: "//", with: "/")
    }

    private static func sanitize(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return input
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
