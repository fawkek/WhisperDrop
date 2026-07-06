import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let symbol: String

    var body: some View {
        ZStack {
            Circle().stroke(.tertiary.opacity(0.35), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.002, progress))
                .stroke(.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progress)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 116, height: 116)
    }
}

