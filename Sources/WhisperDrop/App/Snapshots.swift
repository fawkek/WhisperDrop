import AppKit
import SwiftUI

/// Developer tool: `WhisperDrop --snapshots <folder>` renders every screen in light and
/// dark appearance to PNG files, so the design can be reviewed without clicking through.
@MainActor
enum Snapshots {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sample = URL(filePath: "/Users/demo/Movies/interview.mp4")
        let screens: [(String, (AppStore) -> Void)] = [
            ("1-model", { $0.phase = .needsModel }),
            ("2-downloading", { store in
                store.phase = .downloading
                store.downloadedModelBytes = 1_052_000_000
                store.progress = 0.65
            }),
            ("3-drop", { $0.phase = .ready }),
            ("4-transcribing", { store in
                store.selectedFile = sample
                store.phase = .transcribing
                store.progress = 0.62
            }),
            ("5-finished", { store in
                store.selectedFile = sample
                store.cues = Array(repeating: SubtitleCue(start: 0, end: 1, text: "x"), count: 128)
                store.phase = .finished
            }),
            ("6-failed", { $0.phase = .failed("Не удалось извлечь аудио из видео.") }),
        ]
        for scheme in [ColorScheme.dark, .light] {
            for (name, configure) in screens {
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
                let file = folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png")
                try? png.write(to: file)
            }
        }
        print("snapshots written to \(folder.path)")
    }
}
