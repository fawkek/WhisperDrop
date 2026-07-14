import Foundation

struct SubtitleDraft: Codable, Equatable {
    let sourcePath: String?
    let cues: [SubtitleCue]
    let format: SubtitleFormat
    let encoding: SubtitleEncoding
    let changedCueCount: Int?
    let updatedAt: Date
}

enum SubtitleDraftStore {
    static let draftURL: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WhisperDrop", directoryHint: .isDirectory)
            .appending(path: "Recovery", directoryHint: .isDirectory)
        return root.appending(path: "CurrentSubtitleDraft.json")
    }()

    static func load(from url: URL = draftURL) -> SubtitleDraft? {
        guard let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(SubtitleDraft.self, from: data),
              !draft.cues.isEmpty else { return nil }
        return draft
    }

    static func save(_ draft: SubtitleDraft, to url: URL = draftURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(draft)
        try data.write(to: url, options: .atomic)
    }

    static func clear(at url: URL = draftURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
