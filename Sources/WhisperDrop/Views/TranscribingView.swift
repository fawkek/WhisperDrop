import SwiftUI

struct TranscribingView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 26) {
            AccentRing(progress: store.progress, lineWidth: 8) {
                WaveBars(barWidth: 6, maxHeight: 46)
            }
            .frame(width: 160, height: 160)
            .accessibilityElement()
            .accessibilityLabel(AppText.pick("Создание субтитров", "Creating subtitles"))
            .accessibilityValue(AppText.pick(
                "\(Int(store.progress * 100)) процентов",
                "\(Int(store.progress * 100)) percent"
            ))

            VStack(spacing: 8) {
                Text(store.phase == .preparing
                     ? AppText.pick("Готовим аудио", "Preparing audio")
                     : AppText.pick("Создаём субтитры", "Creating subtitles"))
                    .font(.system(size: 22, weight: .semibold))
                HStack(spacing: 6) {
                    Text(store.selectedFile?.lastPathComponent ?? "")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text("\(Int(store.progress * 100))%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            }

            Button(AppText.pick("Отменить", "Cancel"), action: store.cancel)
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}
