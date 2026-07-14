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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color.cyan.opacity(colorScheme == .dark ? 0.10 : 0.07), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .allowsHitTesting(false)

            Button(action: store.chooseFile) {
                VStack(spacing: 0) {
                    Image(systemName: isTargeted ? "arrow.down" : "film.stack")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(isTargeted ? Color.white : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                        .background(iconBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text(isTargeted
                         ? AppText.pick("Отпустите файл", "Drop the file")
                         : AppText.pick("Перетащите файл", "Drop a file"))
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.top, 18)

                    Text(AppText.pick("Видео, аудио или субтитры", "Video, audio, or subtitles"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)

                    Text(AppText.pick("или", "or"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 12)

                    HStack(spacing: 9) {
                        Text(AppText.pick("Выбрать файл", "Choose file"))
                            .font(.system(size: 13, weight: .semibold))
                        ShortcutHint(keys: "⌘O", inverted: true)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .foregroundStyle(.white)
                    .background(buttonBackground, in: Capsule())
                    .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 12, y: 5)
                }
                .frame(width: 300, height: 252)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .strokeBorder(cardBorder, style: StrokeStyle(lineWidth: isTargeted ? 1.8 : 1, dash: isTargeted ? [7, 5] : []))
                }
                .shadow(color: Color.cyan.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 28, y: 10)
                .scaleEffect(isTargeted ? 1.025 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppText.pick("Выбрать видео, аудио или субтитры", "Choose video, audio, or subtitles"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: isTargeted)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.blue.opacity(0.20), Color.cyan.opacity(0.10), Color.blue.opacity(0.08)]
                : [Color.white.opacity(0.78), Color.cyan.opacity(0.16), Color.blue.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: LinearGradient {
        LinearGradient(
            colors: [Color.cyan.opacity(isTargeted ? 0.95 : 0.55), Color.blue.opacity(isTargeted ? 0.90 : 0.38)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: isTargeted
                ? [Color.cyan, Color.blue]
                : [Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.14), Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var buttonBackground: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.18, green: 0.72, blue: 1.0), Color(red: 0.05, green: 0.42, blue: 0.96)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

                if let changedCount = store.proofreadingChangedCueCount {
                    Label(AppText.correctionCount(changedCount), systemImage: "text.badge.checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

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
            VStack(spacing: 18) {
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
                    .frame(width: 340, height: 86)
                    .clipped()

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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 4) {
                ForEach(Array(displayRows.enumerated()), id: \.offset) { index, word in
                    let isCenter = index == 1
                    Text(word)
                        .font(.system(size: isCenter ? 16 : 13, weight: isCenter ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isCenter ? AnyShapeStyle(animatedGradient(phase)) : AnyShapeStyle(.secondary))
                        .opacity(isCenter ? 1 : 0.38)
                        .padding(.horizontal, 12)
                        .frame(width: 320, height: 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.25),
                        .init(color: .black, location: 0.75),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var displayRows: [String] {
        let recent = Array(words.suffix(3))
        switch recent.count {
        case 0:
            return ["", AppText.pick("Подготовка текста", "Preparing text"), ""]
        case 1:
            return ["", recent[0], ""]
        case 2:
            return [recent[0], recent[1], ""]
        default:
            return [recent[0], recent[2], recent[1]]
        }
    }

    private func animatedGradient(_ phase: TimeInterval) -> LinearGradient {
        let travel = sin(phase * 1.2) * 0.5 + 0.5
        return LinearGradient(
            colors: [
                Color.blue.opacity(0.95),
                Color.cyan,
                Color.blue.opacity(0.85)
            ],
            startPoint: UnitPoint(x: -0.4 + travel * 0.8, y: 0.5),
            endPoint: UnitPoint(x: 0.8 + travel * 0.8, y: 0.5)
        )
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
