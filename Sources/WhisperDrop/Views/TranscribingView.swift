import SwiftUI

struct TranscribingView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            fileHeader

            Spacer(minLength: 0)
            TranscriptionAnimation(progress: store.progress)

            VStack(spacing: 6) {
                Text(store.phase == .preparing
                     ? AppText.pick("Подготовка аудио…", "Preparing audio…")
                     : AppText.pick("Создание субтитров…", "Creating subtitles…"))
                    .font(.system(size: 15, weight: .semibold))
                Text(AppText.pick(
                    "Распознано \(Int(store.progress * 100))%",
                    "Transcribed \(Int(store.progress * 100))%"
                ))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

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
            Text("Whisper Large v3")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 32)
    }

}

private struct TranscriptionAnimation: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.012, progress))
                    .stroke(progressGradient(time: time), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.32 : 0.18), radius: 5)
                    .animation(reduceMotion ? nil : .smooth(duration: 1.1), value: progress)

                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        let wave = reduceMotion ? 0.5 : (sin(time * 3.6 + Double(index) * 0.82) + 1) / 2
                        Capsule()
                            .fill(waveGradient(time: time, index: index))
                            .frame(width: 4, height: 9 + wave * 22)
                    }
                }
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel(AppText.pick("Транскрибирование", "Transcribing"))
        .accessibilityValue(AppText.pick(
            "\(Int(progress * 100)) процентов",
            "\(Int(progress * 100)) percent"
        ))
    }

    private func progressGradient(time: TimeInterval) -> LinearGradient {
        let drift = reduceMotion ? 0 : sin(time * 0.55) * 0.18
        return LinearGradient(
            colors: [deepBlue, lightBlue],
            startPoint: UnitPoint(x: -0.55 + drift, y: -0.25),
            endPoint: UnitPoint(x: 1.55 + drift, y: 1.25)
        )
    }

    private func waveGradient(time: TimeInterval, index: Int) -> LinearGradient {
        let travel = reduceMotion ? 0.5 : (sin(time * 1.7 + Double(index) * 0.35) + 1) / 2
        return LinearGradient(
            colors: [deepBlue, lightBlue],
            startPoint: UnitPoint(x: -0.65, y: travel - 0.5),
            endPoint: UnitPoint(x: 1.65, y: 1.5 - travel)
        )
    }

    private var deepBlue: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.52, blue: 1.0)
            : Color(red: 0.02, green: 0.42, blue: 0.92)
    }

    private var lightBlue: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.82, blue: 1.0)
            : Color(red: 0.22, green: 0.72, blue: 0.98)
    }
}
