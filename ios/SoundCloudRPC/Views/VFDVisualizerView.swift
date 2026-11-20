import SwiftUI
import Combine
import UIKit

// MARK: - VFD Visualizer Modes & Phosphor Presets

enum VFDVisualizerMode: String, CaseIterable, Identifiable {
    case spectrum = "spectrum"
    case mirror = "mirror"
    case dotWave = "dotWave"
    case vuBars = "vuBars"
    case vfdTimer = "vfdTimer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .mirror: return "Mirror"
        case .dotWave: return "Dot Wave"
        case .vuBars: return "VU Bars"
        case .vfdTimer: return "VFD Timer"
        }
    }

    var icon: String {
        switch self {
        case .spectrum: return "chart.bar.fill"
        case .mirror: return "align.vertical.center.fill"
        case .dotWave: return "waveform.path"
        case .vuBars: return "equal"
        case .vfdTimer: return "clock.fill"
        }
    }
}

enum VFDPhosphorTheme: String, CaseIterable, Identifiable {
    case vfdMint = "vfdMint"
    case studioAmber = "studioAmber"
    case cyberCyan = "cyberCyan"
    case scFlame = "scFlame"
    case neonMagenta = "neonMagenta"
    case rainbow = "rainbow"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vfdMint: return "VFD Mint"
        case .studioAmber: return "Amber"
        case .cyberCyan: return "Cyan"
        case .scFlame: return "Flame"
        case .neonMagenta: return "Magenta"
        case .rainbow: return "RGB"
        }
    }

    func color(bandIndex: Int, totalBands: Int, rowRatio: Double) -> Color {
        switch self {
        case .vfdMint:
            // Authentic fluorescent VFD turquoise-mint with subtle hot-top brilliance
            return rowRatio > 0.86
                ? Color(red: 0.65, green: 1.0, blue: 0.88)
                : Color(red: 0.18, green: 0.96, blue: 0.62)
        case .studioAmber:
            return rowRatio > 0.85
                ? Color(red: 1.0, green: 0.90, blue: 0.55)
                : Color(red: 1.0, green: 0.68, blue: 0.05)
        case .cyberCyan:
            return rowRatio > 0.85
                ? Color(red: 0.72, green: 0.98, blue: 1.0)
                : Color(red: 0.04, green: 0.88, blue: 1.0)
        case .scFlame:
            return rowRatio > 0.82
                ? Color(red: 1.0, green: 0.84, blue: 0.20)
                : Color(red: 1.0, green: 0.34, blue: 0.02)
        case .neonMagenta:
            return rowRatio > 0.85
                ? Color(red: 1.0, green: 0.72, blue: 0.92)
                : Color(red: 1.0, green: 0.16, blue: 0.58)
        case .rainbow:
            let hue = Double(bandIndex) / Double(max(1, totalBands))
            return Color(hue: hue, saturation: 0.92, brightness: rowRatio > 0.85 ? 1.0 : 0.94)
        }
    }

    var primarySwatch: Color {
        color(bandIndex: 3, totalBands: 12, rowRatio: 0.5)
    }
}

// MARK: - Fullscreen Customizable Retro Hardware VFD Spectrum Visualizer
struct VFDVisualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var api: SoundCloudAPI
    @ObservedObject var settings: AppSettings
    @ObservedObject var jam: JamSessionService

    @State private var showHUD: Bool = true
    @State private var showCustomizer: Bool = false
    @State private var bandLevels: [Double] = Array(repeating: 0.05, count: 32)
    @State private var peakLevels: [Double] = Array(repeating: 0.05, count: 32)
    @State private var peakHoldTicks: [Int] = Array(repeating: 0, count: 32)
    @State private var phaseTime: Double = 0

    private let frameTimer = Timer.publish(every: 1.0 / 50.0, on: .main, in: .common).autoconnect()

    private var mode: VFDVisualizerMode {
        VFDVisualizerMode(rawValue: settings.vizMode) ?? .spectrum
    }

    private var phosphor: VFDPhosphorTheme {
        VFDPhosphorTheme(rawValue: settings.vizColor) ?? .vfdMint
    }

    private var activeBands: Int {
        min(32, max(12, settings.vizBands))
    }

    private var isLiked: Bool {
        guard let id = player.currentTrack?.id else { return false }
        return api.likedTrackIds.contains(id)
    }

    var body: some View {
        ZStack {
            // Pure obsidian background for infinite OLED phosphor contrast
            Color.black.ignoresSafeArea()

            // Subtle ambient phosphor glow behind hardware display
            RadialGradient(
                colors: [phosphor.primarySwatch.opacity(player.isPlaying ? 0.16 : 0.06), Color.black],
                center: .center,
                startRadius: 30,
                endRadius: 380
            )
            .ignoresSafeArea()

            // === MAIN VFD VISUALIZER STAGE ===
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                VStack(spacing: 0) {
                    Spacer(minLength: isLandscape ? 12 : 40)

                    vfdHardwareEnclosure(
                        width: settings.vizShowBezel ? max(260, geo.size.width - (isLandscape ? 40 : 20)) : geo.size.width,
                        height: settings.vizShowBezel
                            ? (isLandscape ? min(geo.size.height * 0.70, 290) : min(geo.size.height * 0.44, 320))
                            : geo.size.height * (isLandscape ? 0.82 : 0.62)
                    )
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: isLandscape ? 12 : 40)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if showCustomizer {
                            showCustomizer = false
                        } else {
                            showHUD.toggle()
                        }
                    }
                }
            }

            // === OVERLAY HUD & CUSTOMIZER ===
            if showHUD {
                VStack(spacing: 0) {
                    topHudBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    Spacer()

                    if showCustomizer {
                        customizerPanel
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    bottomTransportHud
                        .padding(.horizontal, 16)
                        .padding(.bottom, 22)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showHUD)
        .onReceive(frameTimer) { _ in
            stepVisualizerPhysics()
        }
    }

    // MARK: - Hardware VFD Enclosure (Glass Rack Unit vs Borderless OLED)
    @ViewBuilder
    private func vfdHardwareEnclosure(width: CGFloat, height: CGFloat) -> some View {
        let screenContent = ZStack {
            // Deep phosphor glass backing
            Color(red: 0.025, green: 0.032, blue: 0.030)

            // Fine hardware wire-mesh scanlines (classic VFD filament texture!)
            Canvas { ctx, size in
                let step: CGFloat = 4
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(Color.white.opacity(0.022))
                    )
                    y += step
                }
            }
            .allowsHitTesting(false)

            // Active VFD Display Mode
            if mode == .vfdTimer {
                vfdTimerDisplay
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                vfdSpectrumCanvas
                    .padding(.horizontal, settings.vizShowBezel ? 14 : 8)
                    .padding(.vertical, settings.vizShowBezel ? 14 : 10)
            }

            // Subtle glass diagonal reflection glare (when bezel is ON)
            if settings.vizShowBezel {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.07), location: 0.0),
                        .init(color: Color.white.opacity(0.02), location: 0.26),
                        .init(color: Color.clear, location: 0.30),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)

        if settings.vizShowBezel {
            // Authentic Brushed Dark Aluminum Rack-Mount VFD Unit (Matches User Screenshot!)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.07), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                    )
                    .shadow(color: phosphor.primarySwatch.opacity(0.22), radius: 24, y: 8)

                // Top heat-vent fins accent strip
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(0..<28, id: \.self) { _ in
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 5)
                    Spacer()
                }

                // Inner recessed glass screen
                screenContent
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.85), lineWidth: 2)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)

                // 4 Corner Rack-Mount Hex Screws
                VStack {
                    HStack {
                        rackScrew
                        Spacer()
                        rackScrew
                    }
                    Spacer()
                    HStack {
                        rackScrew
                        Spacer()
                        rackScrew
                    }
                }
                .padding(7)
            }
            .frame(width: width, height: height)
        } else {
            screenContent
        }
    }

    private var rackScrew: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.55), Color(white: 0.18)],
                    center: .topLeading,
                    startRadius: 0.5,
                    endRadius: 5
                )
            )
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 0.8))
    }

    // MARK: - 60FPS Segmented VFD Spectrum Canvas (Spectrum / Mirror / Dot Wave / VU Bars)
    private var vfdSpectrumCanvas: some View {
        Canvas { ctx, size in
            let cols = activeBands
            let rows = mode == .vuBars ? 16 : 18
            let colGap: CGFloat = mode == .vuBars ? 5.5 : 3.5
            let rowGap: CGFloat = 2.6
            let cellW = max(3, (size.width - CGFloat(cols - 1) * colGap) / CGFloat(cols))
            let cellH = max(2.5, (size.height - CGFloat(rows - 1) * rowGap) / CGFloat(rows))

            for c in 0..<cols {
                let x = CGFloat(c) * (cellW + colGap)
                let level = min(1.0, max(0.0, bandLevels[c]))
                let peak = min(1.0, max(0.0, peakLevels[c]))
                let activeCount = Int(round(level * Double(rows)))
                let peakRow = min(rows - 1, max(0, Int(round(peak * Double(rows - 1)))))

                for r in 0..<rows {
                    // r = 0 is bottom, r = rows-1 is top
                    let y = size.height - CGFloat(r + 1) * cellH - CGFloat(r) * rowGap
                    let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                    let rowRatio = Double(r) / Double(max(1, rows - 1))
                    let segColor = phosphor.color(bandIndex: c, totalBands: cols, rowRatio: rowRatio)

                    let isLit: Bool
                    let isPeakDot: Bool
                    switch mode {
                    case .spectrum, .vuBars:
                        isLit = r < activeCount
                        isPeakDot = settings.vizPeakHold && r == peakRow && peak > 0.08
                    case .mirror:
                        let mid = Double(rows - 1) / 2.0
                        let distFromMid = abs(Double(r) - mid) / max(1.0, mid)
                        isLit = distFromMid <= level
                        isPeakDot = settings.vizPeakHold && abs(distFromMid - peak) < (1.0 / Double(rows)) && peak > 0.1
                    case .dotWave:
                        let crestRow = min(rows - 1, max(0, Int(round(level * Double(rows - 1)))))
                        isLit = (r == crestRow || r == max(0, crestRow - 1))
                        isPeakDot = settings.vizPeakHold && r == peakRow && peak > 0.08
                    case .vfdTimer:
                        isLit = false
                        isPeakDot = false
                    }

                    // Iconic red-amber baseline strip on bottom row (matches user's VFD photo!)
                    if r == 0 && (mode == .spectrum || mode == .dotWave) {
                        let baseColor = Color(red: 0.95, green: 0.25, blue: 0.15).opacity(isLit ? 0.92 : 0.35)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(baseColor))
                        continue
                    }

                    if isLit || isPeakDot {
                        let glowRect = rect.insetBy(dx: -1.0, dy: -1.0)
                        ctx.fill(
                            Path(roundedRect: glowRect, cornerRadius: 2),
                            with: .color(segColor.opacity(isPeakDot ? 0.40 : 0.26))
                        )
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 1.3),
                            with: .color(isPeakDot ? Color.white.opacity(0.92) : segColor)
                        )
                    } else {
                        // Subtle unlit phosphor filament grid cell
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 1.2),
                            with: .color(Color.white.opacity(0.055))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Retro 7-Segment VFD Digital Timer Mode (Matches Bottom of Screenshot!)
    private var vfdTimerDisplay: some View {
        let elapsedStr = formatVFDClock(player.elapsedSeconds)
        let remainingStr = formatVFDClock(max(0, player.durationSeconds - player.elapsedSeconds))
        let glowColor = phosphor.primarySwatch

        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(player.isPlaying ? "PLAY" : "PAUSE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(glowColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(glowColor.opacity(0.65), lineWidth: 1))

                Spacer()

                Text("REM -\(remainingStr)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(glowColor.opacity(0.75))
            }

            // Huge Glowing Retro VFD Digital Readout
            ZStack {
                Text("88:88")
                    .font(.system(size: 74, weight: .black, design: .monospaced))
                    .foregroundColor(glowColor.opacity(0.08))
                Text(elapsedStr)
                    .font(.system(size: 74, weight: .black, design: .monospaced))
                    .foregroundColor(glowColor)
                    .shadow(color: glowColor.opacity(0.75), radius: 14)
                    .shadow(color: glowColor.opacity(0.45), radius: 4)
            }
            .minimumScaleFactor(0.55)
            .lineLimit(1)

            // Mini VFD Bar Meter Strip Underneath
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    let h = max(3, CGFloat(bandLevels[i]) * 26)
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(phosphor.color(bandIndex: i, totalBands: 20, rowRatio: bandLevels[i]))
                            .frame(height: h)
                            .shadow(color: glowColor.opacity(0.5), radius: 3)
                    }
                    .frame(height: 28)
                }
            }
        }
    }

    // MARK: - Top & Bottom Overlay HUDs
    private var topHudBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.displayTitle ?? "VFD Spectrum")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(player.currentTrack?.artistName ?? "SoundCloud RPC")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                    if jam.isActive {
                        Text("· JAM \(jam.roomCode)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(phosphor.primarySwatch)
                    }
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                    showCustomizer.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Style")
                }
                .font(.caption.weight(.bold))
                .foregroundColor(showCustomizer ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(showCustomizer ? phosphor.primarySwatch : Color.white.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))
        }
    }

    private var customizerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VFDVisualizerMode.allCases) { item in
                        let selected = mode == item
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            settings.vizMode = item.rawValue
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon).font(.caption)
                                Text(item.displayName).font(.caption.weight(.bold))
                            }
                            .foregroundColor(selected ? .black : .white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(selected ? phosphor.primarySwatch : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Phosphor Color Swatches
            HStack(spacing: 10) {
                ForEach(VFDPhosphorTheme.allCases) { swatch in
                    let selected = phosphor == swatch
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        settings.vizColor = swatch.rawValue
                    } label: {
                        VStack(spacing: 3) {
                            ZStack {
                                if swatch == .rainbow {
                                    Circle()
                                        .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                                        .frame(width: 26, height: 26)
                                } else {
                                    Circle()
                                        .fill(swatch.primarySwatch)
                                        .frame(width: 26, height: 26)
                                }
                                if selected {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 32, height: 32)
                                }
                            }
                            Text(swatch.displayName)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(selected ? .white : .white.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Bands + Sensitivity + Toggles
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Bands")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.7))
                    ForEach([16, 24, 32], id: \.self) { count in
                        Button {
                            settings.vizBands = count
                        } label: {
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(activeBands == count ? .black : .white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(activeBands == count ? phosphor.primarySwatch : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    settings.vizPeakHold.toggle()
                } label: {
                    Text("Peaks")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(settings.vizPeakHold ? .black : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(settings.vizPeakHold ? phosphor.primarySwatch : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    settings.vizShowBezel.toggle()
                } label: {
                    Text("Bezel")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(settings.vizShowBezel ? .black : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(settings.vizShowBezel ? phosphor.primarySwatch : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Text("Gain")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.7))
                Slider(value: $settings.vizSensitivity, in: 0.5...1.9, step: 0.05)
                    .tint(phosphor.primarySwatch)
                Text(String(format: "%.1fx", settings.vizSensitivity))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundColor(phosphor.primarySwatch)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(14)
        .background(Color(white: 0.09).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(phosphor.primarySwatch.opacity(0.35), lineWidth: 1))
    }

    private var bottomTransportHud: some View {
        HStack(spacing: 22) {
            AnimatedHeartButton(
                isLiked: isLiked,
                size: 22,
                accentColor: phosphor.primarySwatch,
                inactiveColor: .white.opacity(0.8)
            ) {
                player.toggleLikeCurrent()
            }

            Spacer()

            if jam.isGuestLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption)
                    Text("Host controls playback").font(.caption.weight(.semibold))
                }
                .foregroundColor(.white.opacity(0.72))
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    player.previousTrack()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.togglePlayPause()
                } label: {
                    Circle()
                        .fill(phosphor.primarySwatch)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.black)
                                .offset(x: player.isPlaying ? 0 : 1.5)
                        )
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    player.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
            }

            Spacer()

            Text("Tap screen to hide")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.42))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - 50FPS Organic Spectrum Physics + Peak Hold Gravity
    private func stepVisualizerPhysics() {
        let dt = 0.02
        phaseTime += dt * (player.isPlaying ? 1.0 : 0.15)
        let seed = Double((player.currentTrack?.id ?? 42) % 97) * 0.17
        let gain = settings.vizSensitivity
        let beatPulse = player.isPlaying
            ? (0.55 + 0.45 * pow(max(0.0, sin(phaseTime * 6.4 + seed)), 2.0))
            : 0.0

        for i in 0..<32 {
            let normIdx = Double(i) / 31.0
            let target: Double
            if player.isPlaying {
                // Realistic musical frequency contour: warm bass left, punchy mids center, sparkling highs right
                let bassBoost = max(0.0, 1.0 - normIdx * 1.9) * beatPulse * 0.65
                let midWave = sin(phaseTime * 4.7 + Double(i) * 0.55 + seed) * 0.25 + 0.28
                let highSparkle = abs(sin(phaseTime * 11.3 + Double(i) * 1.37 + seed * 2.1)) * (0.28 + normIdx * 0.35)
                let microJitter = Double.random(in: -0.06...0.09)
                target = min(1.0, max(0.06, (bassBoost + midWave + highSparkle * 0.65 + microJitter) * gain))
            } else {
                target = 0.04
            }

            // Fast attack, smooth musical decay
            let cur = bandLevels[i]
            let smoothed = target > cur
                ? cur + (target - cur) * 0.48
                : cur + (target - cur) * 0.14
            bandLevels[i] = smoothed

            // Authentic hardware Peak-Hold LED gravity physics
            if smoothed >= peakLevels[i] {
                peakLevels[i] = smoothed
                peakHoldTicks[i] = 18
            } else if peakHoldTicks[i] > 0 {
                peakHoldTicks[i] -= 1
            } else {
                peakLevels[i] = max(smoothed, peakLevels[i] - 0.022)
            }
        }
    }

    private func formatVFDClock(_ sec: TimeInterval) -> String {
        let s = max(0, Int(sec))
        let mins = s / 60
        let rem = s % 60
        return String(format: "%02d:%02d", mins, rem)
    }
}
