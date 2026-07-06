import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            WindowGlassBackground()
                .ignoresSafeArea()

            switch store.phase {
            case .needsModel, .downloading:
                ModelSetupView(store: store)
            case .ready:
                FileDropView(store: store, isTargeted: isTargeted)
            case .preparing, .transcribing:
                TranscribingView(store: store)
            case .finished:
                TranscriptionFinishedView(store: store)
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
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text(store.phase == .downloading ? "Загрузка модели" : "Установите модель")
                    .font(.system(size: 17, weight: .semibold))
                Text("Large v3 Turbo работает полностью на этом Mac")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if store.phase == .downloading {
                VStack(spacing: 8) {
                    ProgressView(value: store.progress).frame(width: 280)
                    Text("\(Int(store.progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Button("Отменить", action: store.cancel)
            } else {
                Button("Скачать модель", systemImage: "arrow.down", action: store.downloadModel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
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
                    Text(isTargeted ? "Отпустите файл" : "Перетащите видео или аудио")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Файл останется на вашем Mac")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("Выбрать файл")
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
    let store: AppStore

    var body: some View {
        StateLayout {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text("Субтитры готовы").font(.system(size: 17, weight: .semibold))
                Text(store.selectedFile?.lastPathComponent ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Label("\(store.cues.count) \(lineWord(store.cues.count))  •  SRT, UTF‑8", systemImage: "captions.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("Другой файл", action: store.reset)
                Button(action: store.save) {
                    HStack(spacing: 8) {
                        Text("Сохранить…")
                        ShortcutHint(keys: "⌘S", inverted: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
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
                Text("Не удалось создать субтитры").font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Button("Вернуться", action: retry).buttonStyle(.borderedProminent)
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

private func lineWord(_ count: Int) -> String {
    let lastTwo = count % 100
    let last = count % 10
    if (11...14).contains(lastTwo) { return "строк" }
    if last == 1 { return "строка" }
    if (2...4).contains(last) { return "строки" }
    return "строк"
}
