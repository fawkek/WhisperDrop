import AppKit
import SwiftUI

struct AboutView: View {
    private let metadata = AppMetadata.current

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 88, height: 88)
            VStack(spacing: 5) {
                Text("WhisperDrop").font(.system(size: 20, weight: .semibold))
                Text(AppText.pick(
                    "Создаёт субтитры из видео и аудио локально на Mac с помощью OpenAI Whisper.",
                    "Creates subtitles from video and audio locally on your Mac using OpenAI Whisper."
                ))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 330)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                metadataRow(AppText.pick("Версия", "Version"), metadata.version)
                metadataRow("Build", metadata.build)
                metadataRow("Commit", metadata.commit)
            }
            .font(.system(size: 11))
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://x.com/fawkek_obj")!) {
                    Label("@fawkek_obj", systemImage: "person.crop.circle")
                }
                .buttonStyle(.bordered)
                Link(destination: URL(string: "https://github.com/fawkek/WhisperDrop")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
                .help("github.com/fawkek/WhisperDrop")
            }
            Text("© 2026 Igor Sevcenko")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(24).frame(width: 400, height: 355)
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontDesign(.monospaced).textSelection(.enabled)
        }
    }
}

private struct AppMetadata {
    let version: String
    let build: String
    let commit: String

    static var current: AppMetadata {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppMetadata(
            version: info["CFBundleShortVersionString"] as? String ?? "Development",
            build: info["CFBundleVersion"] as? String ?? "Development",
            commit: info["WhisperDropCommit"] as? String ?? "Development"
        )
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(AppText.pick("О WhisperDrop", "About WhisperDrop")) {
                openWindow(id: "about")
            }
        }
    }
}
