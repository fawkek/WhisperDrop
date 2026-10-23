import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    /// True when rendered offscreen by the snapshot tool, which can't draw AppKit views.
    var isSnapshot = false
    @State private var isTargeted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch store.phase {
            case .needsModel, .downloading, .importingModel:
                ModelSetupView(store: store)
            case .ready:
                FileDropView(store: store, isTargeted: isTargeted)
            case .preparing, .transcribing:
                TranscribingView(store: store)
            case .selectingAudioTrack:
                AudioTrackSelectionView(store: store)
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
        .frame(width: 600, height: 600)
        .background(Theme.windowTint(colorScheme).ignoresSafeArea())
        .background {
            if !isSnapshot { GlassWindowConfigurator().frame(width: 0, height: 0) }
        }
        .tint(Theme.buttonEnd)
        .modifier(FileDropTarget(isEnabled: !isSnapshot, isTargeted: $isTargeted, perform: store.accept))
    }
}

/// The window-wide drop target. Off in offscreen snapshots, where AppKit-backed
/// modifiers can't be drawn.
private struct FileDropTarget: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: perform)
        } else {
            content
        }
    }
}

private struct AudioTrackSelectionView: View {
    let store: AppStore

    var body: some View {
        StateLayout {
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.purple)

                Text(AppText.pick("Выберите аудиодорожку", "Choose an audio track"))
                    .font(.system(size: 22, weight: .semibold))

                Text(store.selectedFile?.lastPathComponent ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 390)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.audioTracks) { track in
                        AudioTrackRow(
                            track: track,
                            isSelected: store.selectedAudioTrackID == track.id
                        ) {
                            store.selectAudioTrack(track.id)
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
            .frame(width: 390)
            .frame(maxHeight: 220)

            Text(AppText.pick(
                "Для распознавания будет использована только выбранная дорожка",
                "Only the selected track will be used for transcription"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                    .keyboardShortcut(.cancelAction)

                Button(AppText.pick("Продолжить", "Continue"), action: store.continueWithSelectedAudioTrack)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}

private struct AudioTrackRow: View {
    let track: AudioTrackOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.purple : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if !track.details.isEmpty {
                        Text(track.details)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.purple)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(
                isSelected ? Theme.purple.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.purple.opacity(0.55) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ModelSetupView: View {
    let store: AppStore

    private var isBusy: Bool { store.phase == .downloading || store.phase == .importingModel }

    var body: some View {
        StateLayout {
            AppMark(size: 76)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(ModelLocator.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(ModelLocator.description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if isBusy {
                VStack(spacing: 10) {
                    AccentBar(progress: store.progress).frame(width: 300)
                    HStack {
                        Text(statusLine)
                        Spacer()
                        Text("\(Int(store.progress * 100))%")
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 300)
                    .contentTransition(.numericText())
                }
                if store.phase == .downloading {
                    Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                Label(byteCount(ModelLocator.expectedDownloadBytes), systemImage: "internaldrive")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if let error = store.modelDownloadError {
                    Label {
                        Text(error).multilineTextAlignment(.center)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
                }

                VStack(spacing: 10) {
                    Button(action: store.downloadModel) {
                        Label(
                            store.modelDownloadError == nil
                                ? AppText.pick("Скачать модель", "Download model")
                                : AppText.pick("Повторить загрузку", "Retry download"),
                            systemImage: "arrow.down"
                        )
                    }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    Button(AppText.pick("У меня уже есть модель…", "I already have the model…"), action: store.importExistingModel)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var title: String {
        switch store.phase {
        case .downloading: AppText.pick("Загрузка модели", "Downloading model")
        case .importingModel: AppText.pick("Проверка модели", "Checking model")
        default: AppText.pick("Модель распознавания", "Speech recognition model")
        }
    }

    private var statusLine: String {
        if store.phase == .importingModel {
            return AppText.pick("Сверяем файлы и копируем", "Verifying and copying files")
        }
        return AppText.pick(
            "\(byteCount(store.downloadedModelBytes)) из \(byteCount(store.modelDownloadTotalBytes))",
            "\(byteCount(store.downloadedModelBytes)) of \(byteCount(store.modelDownloadTotalBytes))"
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Gifski-style: the whole window is the drop target, framed by a slowly turning glow.
private struct FileDropView: View {
    let store: AppStore
    let isTargeted: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        ZStack {
            RotatingGlow(blur: isTargeted ? 18 : 24)
                .opacity(isTargeted ? 1 : 0.9)
                .clipShape(shape)

            shape
                .fill(Theme.surface(colorScheme))
                .padding(isTargeted ? 3 : 2)

            // A faint echo of the glow inside the zone.
            RotatingGlow(period: 20, blur: 70)
                .opacity(colorScheme == .dark ? 0.16 : 0.12)
                .clipShape(shape)
                .padding(2)

            VStack(spacing: 0) {
                Image(systemName: isTargeted ? "arrow.down" : "square.and.arrow.down")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(isTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.accent))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 68, height: 68)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary.opacity(0.06)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.primary.opacity(isTargeted ? 0 : 0.1), lineWidth: 1)
                    }

                Text(isTargeted
                     ? AppText.pick("Отпустите файл", "Drop the file")
                     : AppText.pick("Перетащите видео", "Drop a video"))
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.top, 20)

                Text(AppText.pick("или аудио, или готовые субтитры", "or audio, or existing subtitles"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                Button(action: store.chooseFile) {
                    HStack(spacing: 10) {
                        Text(AppText.pick("Выбрать файл", "Choose file"))
                        Text("⌘O")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.8)
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 24)
                .opacity(isTargeted ? 0 : 1)
            }
        }
        .padding(.top, 44)
        .padding([.horizontal, .bottom], 20)
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.2), value: isTargeted)
        .contentShape(Rectangle())
        .onTapGesture(perform: store.chooseFile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppText.pick("Перетащите видео, аудио или субтитры", "Drop a video, audio, or subtitles"))
    }
}

private struct TranscriptionFinishedView: View {
    @Bindable var store: AppStore

    var body: some View {
        StateLayout {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 76, height: 76)
                    .shadow(color: Theme.purple.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text(AppText.pick("Субтитры готовы", "Subtitles are ready"))
                    .font(.system(size: 22, weight: .semibold))
                Text(store.selectedFile?.lastPathComponent ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 14) {
                Label(AppText.lineCount(store.cues.count), systemImage: "captions.bubble")
                if let changedCount = store.proofreadingChangedCueCount {
                    Label(AppText.correctionCount(changedCount), systemImage: "text.badge.checkmark")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
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

            Button(action: store.save) {
                HStack(spacing: 10) {
                    Text(AppText.pick("Сохранить субтитры", "Save subtitles"))
                    Text("⌘S").font(.system(size: 12, weight: .medium)).opacity(0.8)
                }
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut("s", modifiers: .command)

            HStack(spacing: 8) {
                Button(AppText.pick("Исправить текст", "Proofread text"), action: store.improveSubtitles)
                Button(AppText.pick("Другой файл", "Another file"), action: store.reset)
            }
            .buttonStyle(QuietButtonStyle())
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
                    .foregroundStyle(Theme.purple)

                VStack(spacing: 6) {
                    Text(store.phase == .downloadingImprovementModel
                         ? AppText.pick("Загрузка модели правки", "Downloading proofreading model")
                         : AppText.pick("Модель для исправления", "Proofreading model"))
                        .font(.system(size: 22, weight: .semibold))

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
                        .buttonStyle(QuietButtonStyle())
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
                        .buttonStyle(AccentButtonStyle())
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
                            Theme.accent,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(store.progress * 100))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(width: 86, height: 86)

                VStack(spacing: 6) {
                    Text(AppText.pick("Исправление субтитров…", "Proofreading subtitles…"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(TextImprovementModelLocator.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                WordFlowView(words: words)
                    .frame(width: 340, height: 86)
                    .clipped()

                Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                    .buttonStyle(QuietButtonStyle())
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
            colors: [Theme.violet, Theme.purple, Theme.pink],
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
                    .font(.system(size: 22, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Button(AppText.pick("Вернуться", "Go back"), action: retry).buttonStyle(AccentButtonStyle())
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
