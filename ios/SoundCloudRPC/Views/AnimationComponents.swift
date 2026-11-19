import SwiftUI
import Combine
import UIKit

// MARK: - Tactile Spring Press Button Style
struct SpringPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

// MARK: - Animated 4-Bar Audio Equalizer
struct AnimatedEqualizerBars: View {
    let isPlaying: Bool
    var color: Color = .orange
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = Double(index) * 1.15
                    let raw = (sin(t * 7.2 + phase) + sin(t * 4.3 + phase * 1.7) * 0.5 + 1.5) / 3.0
                    let h = isPlaying
                        ? max(3.5, CGFloat(raw) * maxHeight)
                        : CGFloat(4.0 + Double(index % 2) * 2.5)
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: h)
                        .animation(.easeOut(duration: 0.14), value: isPlaying)
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
    }
}

// MARK: - Animated Like Heart with Spring Pop & Burst Ring
struct AnimatedHeartButton: View {
    let isLiked: Bool
    var size: CGFloat = 24
    var accentColor: Color = .orange
    var inactiveColor: Color = .white.opacity(0.88)
    let action: () -> Void

    @State private var popScale: CGFloat = 1.0
    @State private var burstOpacity: Double = 0
    @State private var burstScale: CGFloat = 0.6

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let willLike = !isLiked
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                popScale = willLike ? 1.34 : 0.84
            }
            if willLike {
                burstScale = 0.6
                burstOpacity = 0.9
                withAnimation(.easeOut(duration: 0.42)) {
                    burstScale = 1.85
                    burstOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.62)) {
                    popScale = 1.0
                }
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(accentColor, lineWidth: 2)
                    .frame(width: size * 1.25, height: size * 1.25)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)

                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(isLiked ? accentColor : inactiveColor)
                    .scaleEffect(popScale)
            }
            .frame(width: max(36, size + 18), height: max(36, size + 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Sync Confirmation Toast Banner
struct SyncToastBanner: View {
    @Environment(\.scTheme) private var theme
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.accent)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(theme.surface.opacity(theme.isDark ? 0.85 : 0.92))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(theme.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.42 : 0.14), radius: 14, x: 0, y: 6)
    }
}

// MARK: - Rotating Vinyl Record Player with Track Art Inside + Animated Tonearm!
struct VinylRecordPlayerView: View {
    let artworkUrl: String?
    let isPlaying: Bool
    let accentColor: Color
    var discSize: CGFloat = 274

    @State private var rotationDegrees: Double = 0
    @State private var lastFrameDate: Date = .now

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Soft radial vinyl ambient shadow under platter
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: discSize + 18, height: discSize + 18)
                .blur(radius: 18)
                .offset(y: 12)

            // Brushed aluminum turntable platter outer ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.10), Color(white: 0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: discSize + 10, height: discSize + 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            // === SPINNING VINYL DISC ===
            ZStack {
                // Deep obsidian vinyl body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.14), Color(white: 0.05), Color(white: 0.02)],
                            center: .center,
                            startRadius: discSize * 0.16,
                            endRadius: discSize * 0.50
                        )
                    )
                    .frame(width: discSize, height: discSize)

                // Concentric micro-grooves
                ForEach(0..<14, id: \.self) { i in
                    let fraction = 0.52 + Double(i) * 0.032
                    Circle()
                        .stroke(
                            Color.white.opacity(i % 3 == 0 ? 0.085 : 0.04),
                            lineWidth: i % 4 == 0 ? 0.9 : 0.55
                        )
                        .frame(width: discSize * fraction, height: discSize * fraction)
                }

                // Subtle groove highlight glint (rotates with vinyl)
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.0), location: 0.0),
                                .init(color: Color.white.opacity(0.13), location: 0.10),
                                .init(color: Color.white.opacity(0.0), location: 0.22),
                                .init(color: Color.white.opacity(0.0), location: 0.50),
                                .init(color: Color.white.opacity(0.11), location: 0.62),
                                .init(color: Color.white.opacity(0.0), location: 0.74),
                                .init(color: Color.white.opacity(0.0), location: 1.0)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: discSize - 4, height: discSize - 4)
                    .blendMode(.screen)

                // Outer edge rim bevel
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
                    .frame(width: discSize - 1, height: discSize - 1)

                // Track Art Center Vinyl Label (HD Artwork Inside Record!)
                let labelSize = discSize * 0.46
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: labelSize + 8, height: labelSize + 8)

                    HDArtworkView(rawUrl: artworkUrl, preferOriginal: true, cornerRadius: labelSize / 2)
                        .frame(width: labelSize, height: labelSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.26), lineWidth: 1.5)
                        )
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.45), lineWidth: 1)
                                .padding(3)
                        )

                    // Center metallic spindle ring & pin
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.92), Color(white: 0.45)],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 8
                            )
                        )
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
            }
            .rotationEffect(.degrees(rotationDegrees))

            // Fixed studio light reflection overlay (stays stationary while grooves rotate beneath!)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.clear, Color.clear, Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: discSize, height: discSize)
                .allowsHitTesting(false)

            // === ANIMATED PIVOTING TONEARM ===
            VinylTonearmView(isPlaying: isPlaying, accentColor: accentColor)
                .frame(width: 90, height: 180)
                .offset(x: discSize * 0.43, y: -discSize * 0.16)
                .allowsHitTesting(false)
        }
        .scaleEffect(isPlaying ? 1.0 : 0.965)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isPlaying)
        .onReceive(timer) { now in
            let dt = min(0.05, now.timeIntervalSince(lastFrameDate))
            lastFrameDate = now
            if isPlaying {
                // Smooth 33 1/3 RPM style rotation (~28 deg/sec) — pauses seamlessly in place!
                rotationDegrees = (rotationDegrees + dt * 28.0).truncatingRemainder(dividingBy: 360.0)
            }
        }
        .onAppear {
            lastFrameDate = .now
        }
    }
}

private struct VinylTonearmView: View {
    let isPlaying: Bool
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Pivoting arm assembly anchored at gimbal center
            ZStack(alignment: .top) {
                // Counterweight
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.72), Color(white: 0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 12, height: 18)
                    .offset(y: -14)

                // Slender chrome tonearm tube
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.90), Color(white: 0.55), Color(white: 0.80)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 4.5, height: 128)
                    .offset(y: 12)

                // Angled cartridge headshell + glowing accent needle tip
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color(white: 0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                        )
                        .frame(width: 15, height: 26)
                        .overlay(
                            Capsule()
                                .fill(accentColor)
                                .frame(width: 6, height: 3)
                                .offset(y: 7)
                        )
                }
                .rotationEffect(.degrees(18))
                .offset(x: -5, y: 128)
            }
            .shadow(color: .black.opacity(0.5), radius: 5, x: -2, y: 4)
            .rotationEffect(.degrees(isPlaying ? 24 : 2), anchor: .top)
            .animation(.spring(response: 0.68, dampingFraction: 0.72), value: isPlaying)
            .offset(x: -14, y: 20)

            // Gimbal Pivot Base (stationary)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.42), Color(white: 0.14)],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 20
                        )
                    )
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 3)

                Circle()
                    .fill(Color(white: 0.75))
                    .frame(width: 12, height: 12)
            }
            .offset(x: -4, y: 4)
        }
    }
}
