import SwiftUI

struct TranscribingView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            fileHeader

            Spacer(minLength: 0)
            TranscriptionAnimation(progress: store.progress)

            VStack(spacing: 5) {
                Text(store.phase == .preparing ? "Подготовка аудио…" : "Создание субтитров…")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(store.liveLineCount) \(lineLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            VStack(spacing: 8) {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                HStack {
                    Text("Распознано \(Int(store.progress * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Отменить", action: store.cancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(maxWidth: 320)
            Spacer(minLength: 0)
        }
        .padding(20)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private var fileHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            Text(store.selectedFile?.lastPathComponent ?? "")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("Large v3 Turbo")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 32)
    }

    private var lineLabel: String {
        let count = store.liveLineCount
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "готовых строк" }
        if last == 1 { return "готовая строка" }
        if (2...4).contains(last) { return "готовые строки" }
        return "готовых строк"
    }
}

private struct TranscriptionAnimation: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.012, progress))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        let wave = (sin(time * 5 + Double(index) * 0.82) + 1) / 2
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 9 + wave * 22)
                    }
                }
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel("Транскрибирование")
        .accessibilityValue("\(Int(progress * 100)) процентов")
    }
}

