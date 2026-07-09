import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            switch store.phase {
            case .needsModel, .downloading:
                ModelSetupView(store: store)
            case .ready:
                FileDropView(store: store, isTargeted: isTargeted)
            case .preparing, .transcribing:
                TranscribingView(store: store)
            case .finished:
                TranscriptionFinishedView(store: store)
            case .needsImprovementModel, .downloadingImprovementModel:
                ImprovementModelSetupView(store: store)
            case .improvingSubtitles:
                ImprovingSubtitlesView(store: store)
            case let .failed(message):
                FailureView(message: message, retry: store.reset)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.phase)
        .frame(minWidth: 500, idealWidth: 520, minHeight: 370, idealHeight: 400)
        .background(GlassWindowConfigurator().frame(width: 0, height: 0))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: store.accept)
    }
}

private struct ModelSetupView: View {
    let store: AppStore

    var body: some View {
        StateLayout {
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    Text(store.phase == .downloading
                         ? AppText.pick("Загрузка модели", "Downloading model")
                         : AppText.pick("Модель распознавания", "Speech recognition model"))
                        .font(.system(size: 17, weight: .semibold))

                    Text(ModelLocator.displayName)
                        .font(.system(size: 13, weight: .medium))

                    Text(ModelLocator.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                if store.phase == .downloading {
                    VStack(spacing: 10) {
                        ProgressView(value: store.progress).frame(width: 280)
                        HStack {
                            Text(AppText.pick(
                                "Загружено \(byteCount(store.downloadedModelBytes)) из \(byteCount(store.modelDownloadTotalBytes))",
                                "Downloaded \(byteCount(store.downloadedModelBytes)) of \(byteCount(store.modelDownloadTotalBytes))"
                            ))
                            Spacer()
                            Text("\(Int(store.progress * 100))%")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 280)
                        .contentTransition(.numericText())
                    }
                    Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                } else {
                    Label(byteCount(ModelLocator.expectedDownloadBytes), systemImage: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let error = store.modelDownloadError {
                        Label {
                            Text(error)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 320)
                    }

                    Button(
                        store.modelDownloadError == nil
                            ? AppText.pick("Скачать модель", "Download model")
                            : AppText.pick("Повторить загрузку", "Retry download"),
                        systemImage: "arrow.down",
                        action: store.downloadModel
                    )
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

}

private struct FileDropView: View {
    let store: AppStore
    let isTargeted: Bool

    var body: some View {
        Button(action: store.chooseFile) {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: isTargeted ? "arrow.down" : "film.stack")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }

                VStack(spacing: 6) {
                    Text(isTargeted
                         ? AppText.pick("Отпустите файл", "Drop the file")
                         : AppText.pick("Перетащите видео, аудио или субтитры", "Drop video, audio, or subtitles"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(AppText.pick("Видео распознается, субтитры сразу отправятся на исправление", "Video is transcribed; subtitles go straight to proofreading"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(AppText.pick("Выбрать файл", "Choose file"))
                        .font(.system(size: 13, weight: .medium))
                    ShortcutHint(keys: "⌘O")
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(20)
        .background(isTargeted ? Color.accentColor.opacity(0.035) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.24),
                    style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [7, 5])
                )
                .padding(20)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

private struct TranscriptionFinishedView: View {
    @Bindable var store: AppStore

    var body: some View {
        StateLayout {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text(AppText.pick("Субтитры готовы", "Subtitles are ready"))
                    .font(.system(size: 17, weight: .semibold))
                Text(store.selectedFile?.lastPathComponent ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Label(AppText.lineCount(store.cues.count), systemImage: "captions.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ExportMenu(title: store.exportFormat.title) {
                    ForEach(SubtitleFormat.allCases) { format in
                        Button {
                            store.exportFormat = format
                        } label: {
                            if store.exportFormat == format {
                                Label(format.title, systemImage: "checkmark")
                            } else {
                                Text(format.title)
                            }
                        }
                    }
                }

                ExportMenu(title: store.exportEncoding.title) {
                    ForEach(availableEncodings) { encoding in
                        Button {
                            store.exportEncoding = encoding
                        } label: {
                            if store.exportEncoding == encoding {
                                Label(encoding.title, systemImage: "checkmark")
                            } else {
                                Text(encoding.title)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(AppText.pick("Другой файл", "Another file"), action: store.reset)
                Button(AppText.pick("Исправить субтитры", "Proofread subtitles"), action: store.improveSubtitles)
                Button(action: store.save) {
                    HStack(spacing: 8) {
                        Text(AppText.pick("Сохранить…", "Save…"))
                        ShortcutHint(keys: "⌘S", inverted: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private var availableEncodings: [SubtitleEncoding] {
        store.exportFormat.requiresUTF8 ? [.utf8] : SubtitleEncoding.allCases
    }
}

private struct ImprovementModelSetupView: View {
    let store: AppStore

    var body: some View {
        StateLayout {
            VStack(spacing: 20) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    Text(store.phase == .downloadingImprovementModel
                         ? AppText.pick("Загрузка модели правки", "Downloading proofreading model")
                         : AppText.pick("Модель для исправления", "Proofreading model"))
                        .font(.system(size: 17, weight: .semibold))

                    Text(TextImprovementModelLocator.displayName)
                        .font(.system(size: 13, weight: .medium))

                    Text(TextImprovementModelLocator.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                if store.phase == .downloadingImprovementModel {
                    VStack(spacing: 10) {
                        ProgressView(value: store.progress).frame(width: 280)
                        HStack {
                            Text(AppText.pick(
                                "Загружено \(byteCount(store.improvementDownloadBytes)) из \(byteCount(store.improvementDownloadTotalBytes))",
                                "Downloaded \(byteCount(store.improvementDownloadBytes)) of \(byteCount(store.improvementDownloadTotalBytes))"
                            ))
                            Spacer()
                            Text("\(Int(store.progress * 100))%")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 280)
                        .contentTransition(.numericText())
                    }
                    Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                } else {
                    Label(byteCount(TextImprovementModelLocator.expectedDownloadBytes), systemImage: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let error = store.improvementDownloadError {
                        Label {
                            Text(error)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 320)
                    }

                    HStack(spacing: 8) {
                        Button(AppText.pick("Назад", "Back")) {
                            store.cancel()
                        }
                        Button(
                            store.improvementDownloadError == nil
                                ? AppText.pick("Скачать модель", "Download model")
                                : AppText.pick("Повторить загрузку", "Retry download"),
                            systemImage: "arrow.down",
                            action: store.downloadImprovementModel
                        )
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct ImprovingSubtitlesView: View {
    let store: AppStore
    @State private var words: [String] = []

    var body: some View {
        StateLayout {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, store.progress)))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(store.progress * 100))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(width: 86, height: 86)

                VStack(spacing: 6) {
                    Text(AppText.pick("Исправление субтитров…", "Proofreading subtitles…"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(TextImprovementModelLocator.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                WordFlowView(words: words)
                    .frame(width: 330, height: 92)

                Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
            }
        }
        .onChange(of: store.improvementWord) { _, word in
            guard !word.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                words.append(word)
                if words.count > 18 { words.removeFirst(words.count - 18) }
            }
        }
    }
}

private struct WordFlowView: View {
    let words: [String]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(words.suffix(8).enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: index == words.suffix(8).count - 1 ? 15 : 13, weight: index == words.suffix(8).count - 1 ? .semibold : .regular))
                    .foregroundStyle(index == words.suffix(8).count - 1 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(index == words.suffix(8).count - 1 ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.25),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct ExportMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: {
            Text(title)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct FailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        StateLayout {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.orange)
            VStack(spacing: 6) {
                Text(AppText.pick("Не удалось создать субтитры", "Couldn’t create subtitles"))
                    .font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Button(AppText.pick("Вернуться", "Go back"), action: retry).buttonStyle(.borderedProminent)
        }
    }
}

private struct StateLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 24) { content }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct ShortcutHint: View {
    let keys: String
    var inverted = false

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(inverted ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(inverted ? AnyShapeStyle(.white.opacity(0.13)) : AnyShapeStyle(.quaternary.opacity(0.7)), in: RoundedRectangle(cornerRadius: 4))
    }
}
