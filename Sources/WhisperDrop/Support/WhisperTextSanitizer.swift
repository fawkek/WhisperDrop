import Foundation

enum WhisperTextSanitizer {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<\|[^>]*\|>"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
