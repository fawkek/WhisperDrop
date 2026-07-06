import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)
            ProgressRing(progress: ringProgress, symbol: symbol)

            VStack(spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            if store.phase == .ready || isFailure {
                dropZone
            } else if store.isWorking {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 330)
                Text("\(Int(store.progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            actions
            Spacer(minLength: 12)
        }
        .padding(34)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 500, idealHeight: 540)
        .background(.regularMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: store.accept)
    }

    private var dropZone: some View {
        Button(action: store.chooseFile) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.title2)
                Text("Перетащите видео или аудио сюда")
                Text("или нажмите, чтобы выбрать файл").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isTargeted ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035), in: .rect(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7])))
    }

    @ViewBuilder private var actions: some View {
        switch store.phase {
        case .needsModel:
            Button("Скачать модель Large v3 Turbo", action: store.downloadModel).buttonStyle(.borderedProminent).controlSize(.large)
        case .downloading, .preparing, .transcribing:
            Button("Отменить", action: store.cancel).keyboardShortcut(.cancelAction)
        case .finished:
            HStack {
                Button("Другой файл", action: store.reset)
                Button("Сохранить субтитры…", action: store.save).buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
            }
        case .failed:
            Button("Попробовать снова", action: store.reset).buttonStyle(.borderedProminent)
        case .ready:
            EmptyView()
        }
    }

    private var ringProgress: Double {
        store.phase == .ready || store.phase == .needsModel ? 0 : store.progress
    }

    private var symbol: String {
        switch store.phase {
        case .needsModel, .downloading: "arrow.down.circle"
        case .ready: "waveform"
        case .preparing: "film"
        case .transcribing: "captions.bubble"
        case .finished: "checkmark"
        case .failed: "exclamationmark"
        }
    }

    private var title: String {
        switch store.phase {
        case .needsModel: "Нужна модель распознавания"
        case .downloading: "Загрузка модели"
        case .ready: "Создать субтитры"
        case .preparing: "Подготовка аудио"
        case .transcribing: "Распознавание"
        case .finished: "Субтитры готовы"
        case .failed: "Не удалось завершить"
        }
    }

    private var detail: String {
        switch store.phase {
        case .needsModel: "Модель хранится локально в папке приложения. Файлы не отправляются в интернет."
        case .downloading: "Large v3 Turbo загружается один раз"
        case .ready: "Локально, без облака"
        case .preparing: store.selectedFile?.lastPathComponent ?? "Извлекаем звуковую дорожку"
        case .transcribing: store.selectedFile?.lastPathComponent ?? "Определяем язык автоматически"
        case .finished: "\(store.cues.count) реплик с точными тайм-кодами"
        case let .failed(message): message
        }
    }

    private var isFailure: Bool {
        if case .failed = store.phase { return true }
        return false
    }
}

