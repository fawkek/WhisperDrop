import AppKit
import SwiftUI

/// Developer tools for reviewing the design:
/// - `WhisperDrop --snapshots <folder>` renders every screen in light and dark to PNG.
/// - `WHISPERDROP_DEMO=<screen> WhisperDrop` opens the real app on one screen with
///   sample data, for README screenshots. Screens: see `screens`.
@MainActor
enum Snapshots {
    private static let sample = URL(filePath: "/Users/demo/Movies/interview.mp4")

    static let screens: [(String, (AppStore) -> Void)] = [
        ("model", { $0.phase = .needsModel }),
        ("downloading", { store in
            store.phase = .downloading
            store.downloadedModelBytes = 1_052_000_000
            store.progress = 0.65
        }),
        ("drop", { $0.phase = .ready }),
        ("transcribing", { store in
            store.selectedFile = sample
            store.phase = .transcribing
            store.progress = 0.62
        }),
        ("finished", { store in
            store.selectedFile = sample
            store.cues = Array(repeating: SubtitleCue(start: 0, end: 1, text: "x"), count: 128)
            store.phase = .finished
        }),
        ("proofreading", { store in
            store.selectedFile = sample
            store.cues = Array(repeating: SubtitleCue(start: 0, end: 1, text: "x"), count: 128)
            store.phase = .improvingSubtitles
            store.progress = 0.42
            store.improvementWord = AppText.pick("субтитры", "subtitles")
        }),
        ("failed", { $0.phase = .failed(AppText.pick("Не удалось извлечь аудио из видео.", "Could not extract audio from the video.")) }),
    ]

    /// Applies a demo screen when `WHISPERDROP_DEMO` is set. Returns true if it did.
    @discardableResult
    static func applyDemo(to store: AppStore) -> Bool {
        guard let name = ProcessInfo.processInfo.environment["WHISPERDROP_DEMO"],
              let screen = screens.first(where: { $0.0 == name }) else { return false }
        screen.1(store)
        return true
    }

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            for (index, (name, configure)) in screens.enumerated() {
                let store = AppStore()
                configure(store)
                let view = ZStack {
                    // Stand-in for the window's glass material, which can't be rendered offscreen.
                    (scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                    ContentView(store: store, isSnapshot: true)
                }
                .frame(width: 600, height: 600)
                .environment(\.colorScheme, scheme)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                let file = folder.appending(path: "\(index + 1)-\(name)-\(scheme == .dark ? "dark" : "light").png")
                try? png.write(to: file)
            }
        }
        print("snapshots written to \(folder.path)")
    }
}
