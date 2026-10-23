import SwiftUI

/// "Amethyst" palette shared by the icon and every screen.
enum Theme {
    static let violet = Color(red: 0x6D / 255, green: 0x4A / 255, blue: 0xFF / 255)
    static let purple = Color(red: 0xB0 / 255, green: 0x4B / 255, blue: 0xFF / 255)
    static let pink = Color(red: 0xFF / 255, green: 0x5F / 255, blue: 0xA2 / 255)
    /// Darker pair for filled buttons so white text keeps 4.5:1 contrast.
    static let buttonStart = Color(red: 0x6D / 255, green: 0x4A / 255, blue: 0xFF / 255)
    static let buttonEnd = Color(red: 0x9B / 255, green: 0x3B / 255, blue: 0xF0 / 255)

    static let accent = LinearGradient(
        colors: [violet, purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentStops: [Color] = [violet, purple, pink, violet]

    /// Window tint laid over the system glass material.
    static func windowTint(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.10, green: 0.08, blue: 0.15).opacity(0.78), Color(red: 0.12, green: 0.08, blue: 0.16).opacity(0.70)]
                : [Color(red: 0.97, green: 0.95, blue: 1.0).opacity(0.70), Color(red: 0.99, green: 0.95, blue: 0.98).opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.07, blue: 0.13).opacity(0.86)
            : Color.white.opacity(0.86)
    }
}

/// A conic gradient that turns slowly; used as the glow behind the drop zone and rings.
struct RotatingGlow: View {
    var period: TimeInterval = 14
    var blur: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let angle = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360
            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height) * 1.6
                AngularGradient(colors: Theme.accentStops, center: .center)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(angle))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .blur(radius: blur)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Filled capsule button with the accent gradient.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(
                LinearGradient(colors: [Theme.buttonStart, Theme.buttonEnd], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Theme.purple.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet capsule button for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    /// Smaller text and padding, for secondary buttons sitting next to the main one.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, compact ? 14 : 16)
            .frame(height: height)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.07), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Circular progress with the accent gradient and a gently turning highlight.
struct AccentRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.012, min(1, progress)))
                .stroke(
                    // Spread the palette over the filled arc so its start never meets its end.
                    AngularGradient(
                        colors: [Theme.violet, Theme.purple, Theme.pink],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(1, 360 * min(1, progress)))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.purple.opacity(0.35), radius: 6)
                .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: progress)
            center
        }
    }
}

/// Five bars that breathe while work is in progress.
struct WaveBars: View {
    var barWidth: CGFloat = 6
    var maxHeight: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [
        Theme.violet,
        Color(red: 0x8E / 255, green: 0x4B / 255, blue: 1),
        Theme.purple,
        Color(red: 0xD8 / 255, green: 0x55 / 255, blue: 0xD2 / 255),
        Theme.pink,
    ]
    private let shape: [CGFloat] = [0.5, 0.82, 1, 0.73, 0.45]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: barWidth) {
                ForEach(0..<5, id: \.self) { index in
                    let wave = reduceMotion ? 1 : 0.55 + 0.45 * (sin(time * 3.4 + Double(index) * 0.8) + 1) / 2
                    Capsule()
                        .fill(colors[index])
                        .frame(width: barWidth, height: maxHeight * shape[index] * wave)
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }
}

/// Thin capsule progress bar with the accent gradient.
struct AccentBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(6, proxy.size.width * min(1, max(0, progress))))
                    .animation(.smooth(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }
}

/// App mark (the icon's waveform) on a gradient tile.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        let bar = size * 0.066
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(Theme.accent)
            .overlay(
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: size * 0.85)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            )
            .overlay {
                HStack(spacing: bar * 0.8) {
                    ForEach(Array([0.40, 0.73, 1.0, 0.66, 0.34].enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(.white.opacity(index == 2 ? 1 : 0.85))
                            .frame(width: bar, height: size * 0.36 * height)
                    }
                }
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.purple.opacity(0.35), radius: size * 0.2, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
