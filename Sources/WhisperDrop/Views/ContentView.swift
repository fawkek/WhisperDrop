import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isTargeted = false

    var body: some View {
        Group {
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
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.easeInOut(duration: 0.25), value: store.phase)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 430, idealHeight: 470)
        .background(.regularMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: store.accept)
    }
}

private struct ModelSetupView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 22) {
            ProgressRing(progress: store.progress, symbol: "arrow.down.circle")
            Text(store.phase == .downloading ? "Загрузка модели" : "Нужна модель распознавания")
                .font(.title2.weight(.semibold))
            Text("Модель хранится локально. Видео и аудио не отправляются в интернет.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.phase == .downloading {
                ProgressView(value: store.progress).frame(width: 300)
                Button("Отменить", action: store.cancel)
            } else {
                Button("Скачать модель Large v3 Turbo", action: store.downloadModel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(44)
    }
}

private struct FileDropView: View {
    let store: AppStore
    let isTargeted: Bool

    var body: some View {
        Button(action: store.chooseFile) {
            VStack(spacing: 18) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                VStack(spacing: 6) {
                    Text("Перетащите видео сюда").font(.title2.weight(.semibold))
                    Text("или нажмите, чтобы выбрать видео или аудио")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(34)
        .background(isTargeted ? Color.accentColor.opacity(0.10) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.32), style: StrokeStyle(lineWidth: 2, dash: [9]))
                .padding(34)
        }
    }
}

private struct TranscriptionFinishedView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            ProgressRing(progress: 1, symbol: "checkmark")
            Text("Субтитры готовы").font(.title2.weight(.semibold))
            Text("\(store.cues.count) \(lineWord(store.cues.count))")
                .foregroundStyle(.secondary)
            HStack {
                Button("Другой файл", action: store.reset)
                Button("Сохранить субтитры…", action: store.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(44)
    }
}

private struct FailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Не удалось завершить").font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
            Button("Вернуться", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(44)
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

