import XCTest
@testable import WhisperDrop

final class SubtitleDraftStoreTests: XCTestCase {
    func testDraftRoundTripPreservesUnsavedCues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "draft.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let draft = SubtitleDraft(
            sourcePath: "/tmp/video.mp4",
            cues: [SubtitleCue(start: 1.25, end: 3.5, text: "Несохранённые субтитры 👋🏽")],
            format: .srt,
            encoding: .utf8,
            changedCueCount: nil,
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        try SubtitleDraftStore.save(draft, to: url)

        XCTAssertEqual(SubtitleDraftStore.load(from: url), draft)
    }

    func testEmptyDraftIsNotRestored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "draft.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let draft = SubtitleDraft(
            sourcePath: nil,
            cues: [],
            format: .srt,
            encoding: .utf8,
            changedCueCount: nil,
            updatedAt: Date()
        )
        try SubtitleDraftStore.save(draft, to: url)

        XCTAssertNil(SubtitleDraftStore.load(from: url))
    }
}
