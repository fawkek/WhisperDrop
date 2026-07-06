import SwiftUI

struct TranscribingView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            TranscriptionAnimation(progress: store.progress)

            VStack(spacing: 7) {
                Text(store.phase == .preparing ? "Подготавливаем аудио" : "Создаём субтитры")
                    .font(.title2.weight(.semibold))
                Text(store.selectedFile?.lastPathComponent ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 8) {
                Text("\(store.liveLineCount)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(lineLabel).foregroundStyle(.secondary)
            }

            ProgressView(value: store.progress)
                .progressViewStyle(.linear)
                .frame(width: 310)

            HStack(spacing: 12) {
                Text("\(Int(store.progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Отменить", action: store.cancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(44)
    }

    private var lineLabel: String {
        store.liveLineCount == 1 ? "готовая строка" : "готовых строк"
    }
}

private struct TranscriptionAnimation: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(.tertiary.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.015, progress))
                    .stroke(.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<5, id: \.self) { index in
                        let wave = (sin(time * 5 + Double(index) * 0.8) + 1) / 2
                        Capsule()
                            .fill(.green)
                            .frame(width: 5, height: 12 + wave * 26)
                    }
                }
            }
        }
        .frame(width: 128, height: 128)
        .accessibilityLabel("Транскрибирование")
        .accessibilityValue("\(Int(progress * 100)) процентов")
    }
}

