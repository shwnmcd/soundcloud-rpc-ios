import SwiftUI
import AVKit
import UIKit

struct AirPlayPickerButton: UIViewRepresentable {
    var tint: UIColor = .white
    var activeTint: UIColor = .systemOrange

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tint
        picker.activeTintColor = activeTint
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = activeTint
    }
}

/// Sleek custom interactive progress scrubber (millisecond-accurate native AVPlayer seeking!)
struct SleekScrubberBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    var trackColor: Color = .white
    var trackBgColor: Color = Color.white.opacity(0.28)
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = min(1.0, max(0.0, progress))
            let thumbSize: CGFloat = isScrubbing ? 16 : 11
            let barHeight: CGFloat = isScrubbing ? 6 : 3.5

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackBgColor)
                    .frame(height: barHeight)

                Capsule()
                    .fill(trackColor)
                    .frame(width: max(0, width * clamped), height: barHeight)

                Circle()
                    .fill(trackColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                    .offset(x: max(0, min(width - thumbSize, width * clamped - thumbSize / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing { isScrubbing = true }
                        progress = min(1.0, max(0.0, value.location.x / width))
                    }
                    .onEnded { value in
                        let fraction = min(1.0, max(0.0, value.location.x / width))
                        progress = fraction
                        isScrubbing = false
                        onCommit(fraction)
                    }
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isScrubbing)
        }
        .frame(height: 30)
    }
}

struct NowPlayingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scTheme) private var theme
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var api: SoundCloudAPI
    @ObservedObject var settings: AppSettings
    @ObservedObject var jam: JamSessionService
    var onOpenArtist: ((SCUser) -> Void)? = nil

    @Namespace private var stylePillNamespace

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showDiscordCard = false
    @State private var showQueueSheet = false
    @State private var showAddToPlaylist = false
    @State private var showJamSheet = false
    @State private var showVisualizer = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var swipeXOffset: CGFloat = 0

    private var track: SCTrack? { player.currentTrack }

    private var style: PlaybackStyle { settings.playbackStyle }

    /// Fullscreen style always renders dark scrims with crisp white ink;
    /// Vinyl & Ambient Card adapt beautifully to Dark Mode OR Light Mode!
    private var useLightInk: Bool {
        style == .fullscreen || theme.isDark
    }

    private var fgPrimary: Color {
        useLightInk ? .white : Color(red: 0.08, green: 0.08, blue: 0.11)
    }

    private var fgSecondary: Color {
        useLightInk ? Color.white.opacity(0.75) : Color(white: 0.36)
    }

    private var fgMuted: Color {
        useLightInk ? Color.white.opacity(0.55) : Color(white: 0.48)
    }

    private var dockBg: Color {
        useLightInk ? Color.white.opacity(0.10) : Color.black.opacity(0.065)
    }

    private var playCircleFill: Color {
        useLightInk ? .white : Color(red: 0.09, green: 0.09, blue: 0.12)
    }

    private var playCircleIcon: Color {
        useLightInk ? .black : .white
    }

    private var normalized: (artist: String, track: String) {
        guard let t = track else { return ("", "") }
        return TrackParser.normalizeTrackInfo(
            titleFromPage: t.displayTitle,
            authorFromPage: t.artistName,
            useTrackParser: settings.trackParserEnabled
        )
    }

    private var displayedProgress: Double {
        isScrubbing ? scrubValue : player.progressFraction
    }

    private var isLiked: Bool {
        guard let id = track?.id else { return false }
        return api.likedTrackIds.contains(id)
    }

    private func openCurrentArtist() {
        guard let artist = track?.user else { return }
        haptic(.light)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenArtist?(artist)
        }
    }

    var body: some View {
        ZStack {
            // === LAYER 1: STYLE-AWARE BACKGROUND (Non-hit-testing!) ===
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // === LAYER 2: INTERACTIVE FOREGROUND UI ===
            VStack(spacing: 0) {
                // Top Bar: Down Chevron · Clickable Artist Source · Real Action Menu
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                // Sleek Animated 3-Style Switcher Pill + Fullscreen VFD Visualizer Toggle + Live Jam Badge
                HStack(spacing: 8) {
                    playbackStyleSwitcher

                    Button {
                        haptic(.medium)
                        showVisualizer = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12, weight: .bold))
                            Text("VFD")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                        }
                        .foregroundColor(Color(red: 0.18, green: 0.96, blue: 0.62))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(useLightInk ? 0.55 : 0.82))
                        .overlay(Capsule().stroke(Color(red: 0.18, green: 0.96, blue: 0.62).opacity(0.55), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))

                    if jam.isActive {
                        Button {
                            haptic(.light)
                            showJamSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                Text("JAM · \(jam.listenerCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 6)

                // === MIDDLE INTERACTIVE SWIPE STAGE ===
                // Slide LEFT -> Previous Song · Slide RIGHT -> Next Song · Slide DOWN -> Dismiss!
                ZStack {
                    Color.clear

                    if style == .vinyl {
                        VinylRecordPlayerView(
                            artworkUrl: track?.rawArtwork,
                            isPlaying: player.isPlaying,
                            accentColor: theme.accent,
                            discSize: sizeClass == .regular ? 328 : 262
                        )
                        .id(track?.id ?? 0)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.86).combined(with: .opacity),
                            removal: .scale(scale: 0.90).combined(with: .opacity)
                        ))
                        .offset(x: swipeXOffset * 0.55)
                        .rotationEffect(.degrees(Double(swipeXOffset) / 26.0))
                        .opacity(max(0.55, 1.0 - abs(swipeXOffset) / 340.0))
                    } else if style == .card {
                        HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: true, cornerRadius: 18)
                            .frame(
                                width: sizeClass == .regular ? 336 : 278,
                                height: sizeClass == .regular ? 336 : 278
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(useLightInk ? Color.white.opacity(0.18) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(
                                color: .black.opacity(useLightInk ? 0.55 : 0.22),
                                radius: player.isPlaying ? 28 : 14,
                                x: 0,
                                y: player.isPlaying ? 16 : 8
                            )
                            .scaleEffect(player.isPlaying ? 1.0 : 0.90)
                            .animation(.spring(response: 0.52, dampingFraction: 0.72), value: player.isPlaying)
                            .id(track?.id ?? 0)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.90).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            ))
                            .offset(x: swipeXOffset * 0.62)
                            .rotationEffect(.degrees(Double(swipeXOffset) / 30.0))
                            .opacity(max(0.55, 1.0 - abs(swipeXOffset) / 340.0))
                    }

                    // Live Directional Swipe Indicator Pill (Slide Left = Previous, Slide Right = Next!)
                    if abs(swipeXOffset) > 22 {
                        let goingPrev = swipeXOffset < 0
                        HStack(spacing: 6) {
                            if goingPrev {
                                Image(systemName: "backward.end.fill")
                                Text("Previous")
                            } else {
                                Text("Next")
                                Image(systemName: "forward.end.fill")
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(theme.accent.opacity(0.65), lineWidth: 1))
                        .frame(maxWidth: .infinity, alignment: goingPrev ? .leading : .trailing)
                        .padding(.horizontal, 22)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) {
                                if !jam.isGuestLocked {
                                    swipeXOffset = dx
                                }
                            } else if dy > 0 {
                                dismissDragOffset = dy
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) {
                                if !jam.isGuestLocked {
                                    // User preference: Slide LEFT -> Previous Song · Slide RIGHT -> Next Song!
                                    if dx < -55 {
                                        haptic(.medium)
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                            player.previousTrack(forcePrevious: true)
                                        }
                                    } else if dx > 55 {
                                        haptic(.medium)
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                            player.nextTrack()
                                        }
                                    }
                                } else if abs(dx) > 55 {
                                    api.showToast("Host controls playback in this Jam")
                                }
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                    swipeXOffset = 0
                                }
                            } else if dy > 95 {
                                haptic(.light)
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                    dismissDragOffset = 0
                                    swipeXOffset = 0
                                }
                            }
                        }
                )
                .animation(.spring(response: 0.42, dampingFraction: 0.80), value: track?.id)
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: style)

                // === FLOATING PLAYBACK CONTROLS BLOCK ===
                controlsBlock
                    .frame(maxWidth: sizeClass == .regular ? 500 : .infinity)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 30)
            }

            // Floating Sync Toast inside FullScreenCover
            if let toast = api.syncToastMessage {
                VStack {
                    SyncToastBanner(message: toast)
                        .padding(.top, 56)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: api.syncToastMessage)
        .offset(y: max(0, dismissDragOffset))
        .sheet(isPresented: $showQueueSheet) {
            queueSheetView
                .environment(\.scTheme, theme)
                .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let current = track {
                AddToPlaylistSheet(track: current)
                    .environmentObject(api)
                    .environment(\.scTheme, theme)
                    .preferredColorScheme(settings.themeMode.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showJamSheet) {
            JamSessionSheet()
                .environmentObject(jam)
                .environmentObject(player)
                .environmentObject(api)
                .environment(\.scTheme, theme)
                .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .fullScreenCover(isPresented: $showVisualizer) {
            VFDVisualizerView(
                player: player,
                api: api,
                settings: settings,
                jam: jam
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Style-Aware Background Layer
    @ViewBuilder
    private var backgroundLayer: some View {
        if style == .fullscreen {
            ZStack {
                Color.black

                GeometryReader { bgGeo in
                    HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: true, cornerRadius: 0)
                        .frame(width: bgGeo.size.width, height: bgGeo.size.height)
                        .clipped()
                        .id(track?.id ?? 0)
                        .transition(.opacity)
                        .offset(x: swipeXOffset * 0.35)
                        .opacity(max(0.55, 1.0 - abs(swipeXOffset) / 360.0))
                }

                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black, location: 0.0),
                            .init(color: Color.black.opacity(0.86), location: 0.30),
                            .init(color: Color.black.opacity(0.32), location: 0.70),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 215)

                    Spacer()

                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.black.opacity(0.45), location: 0.22),
                            .init(color: Color.black.opacity(0.86), location: 0.56),
                            .init(color: Color.black, location: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 440)
                }
            }
        } else {
            // Atmospheric Blurred Artwork Backdrop (Adapts to Dark Mode & Light Mode!)
            ZStack {
                theme.bg

                GeometryReader { bgGeo in
                    HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: false, cornerRadius: 0)
                        .frame(width: bgGeo.size.width * 1.25, height: bgGeo.size.height * 1.25)
                        .position(x: bgGeo.size.width / 2, y: bgGeo.size.height * 0.38)
                        .blur(radius: 68)
                        .saturation(theme.isDark ? 1.25 : 1.15)
                        .opacity(theme.isDark ? 0.44 : 0.22)
                        .id(track?.id ?? 0)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: theme.isDark
                        ? [Color.black.opacity(0.45), Color.black.opacity(0.65), Color.black.opacity(0.92)]
                        : [Color.white.opacity(0.52), Color.white.opacity(0.72), Color(red: 0.96, green: 0.96, blue: 0.98).opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button {
                haptic(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(fgPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SpringPressButtonStyle())

            Spacer()

            Button {
                openCurrentArtist()
            } label: {
                VStack(spacing: 2) {
                    Text("PLAYING FROM SOUNDCLOUD")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(fgMuted)
                    HStack(spacing: 3) {
                        Text(normalized.artist)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(fgPrimary)
                            .lineLimit(1)
                        if track?.user != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(fgMuted)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))

            Spacer()

            Menu {
                if let artist = track?.user {
                    Button {
                        openCurrentArtist()
                    } label: {
                        Label("Go to \(artist.displayName)", systemImage: "person.circle")
                    }
                }

                if track != nil {
                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Label("Add to Playlist", systemImage: "text.badge.plus")
                    }
                }

                Button {
                    player.toggleLikeCurrent()
                } label: {
                    Label(isLiked ? "Unlike Track" : "Like Track", systemImage: isLiked ? "heart.slash" : "heart")
                }

                Button {
                    showQueueSheet = true
                } label: {
                    Label("View Up Next (\(player.queue.count))", systemImage: "list.bullet")
                }

                Button {
                    showVisualizer = true
                } label: {
                    Label("Fullscreen VFD Visualizer", systemImage: "waveform.path.ecg")
                }

                if jam.isActive {
                    Button(role: .destructive) {
                        jam.leaveJam()
                    } label: {
                        Label(jam.isHost ? "End Jam Session" : "Leave Jam Session", systemImage: "xmark.circle")
                    }
                }

                if let urlStr = track?.permalinkUrl, let shareURL = URL(string: urlStr) {
                    ShareLink(item: shareURL) {
                        Label("Share Track", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(fgPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Playback Style Switcher Pill (Vinyl · Full · Card)
    private var playbackStyleSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(PlaybackStyle.allCases) { item in
                let selected = settings.playbackStyle == item
                Button {
                    haptic(.light)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        settings.playbackStyle = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(item.shortName)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(selected ? (useLightInk ? .black : .white) : fgSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(useLightInk ? Color.white : Color(red: 0.10, green: 0.10, blue: 0.13))
                                .matchedGeometryEffect(id: "stylePillBg", in: stylePillNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3.5)
        .background(dockBg)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(useLightInk ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Bottom Controls Block
    private var controlsBlock: some View {
        VStack(spacing: 16) {
            if showDiscordCard {
                RichPresencePreviewView(track: player.currentTrackInfo, settings: settings)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Cover Thumbnail (in Fullscreen) + Track Title + Clickable Artist + Animated Heart
            HStack(alignment: .center, spacing: 12) {
                if style == .fullscreen {
                    Button {
                        openCurrentArtist()
                    } label: {
                        HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: false, cornerRadius: 8)
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(SpringPressButtonStyle())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(normalized.track)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(fgPrimary)
                        .lineLimit(1)
                        .id("title-\(track?.id ?? 0)")
                        .transition(.opacity)

                    Button {
                        openCurrentArtist()
                    } label: {
                        HStack(spacing: 4) {
                            Text(normalized.artist)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(fgSecondary)
                                .lineLimit(1)
                            if track?.user != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(fgMuted)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.97))
                }

                Spacer(minLength: 8)

                AnimatedHeartButton(
                    isLiked: isLiked,
                    size: 24,
                    accentColor: theme.accent,
                    inactiveColor: fgSecondary
                ) {
                    player.toggleLikeCurrent()
                }
            }
            .offset(x: swipeXOffset * 0.18)

            // Native Instant AVPlayer Scrubber (Locked when Guest in Host-Only Jam)
            VStack(spacing: 2) {
                SleekScrubberBar(
                    progress: Binding(
                        get: { displayedProgress },
                        set: { if !jam.isGuestLocked { scrubValue = $0 } }
                    ),
                    isScrubbing: $isScrubbing,
                    trackColor: fgPrimary,
                    trackBgColor: useLightInk ? Color.white.opacity(0.24) : Color.black.opacity(0.14)
                ) { committedFraction in
                    if !jam.isGuestLocked {
                        player.seek(toFraction: committedFraction)
                    }
                }
                .allowsHitTesting(!jam.isGuestLocked)
                .opacity(jam.isGuestLocked ? 0.65 : 1.0)

                HStack {
                    Text(TrackTimeParser.format(displayedProgress * player.durationSeconds))
                    Spacer()
                    if jam.isGuestLocked {
                        Button {
                            haptic(.light)
                            jam.requestResync()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 9.5))
                                Text("Host controls · Tap to resync")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(theme.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Text("-\(TrackTimeParser.format(max(0, player.durationSeconds - displayedProgress * player.durationSeconds)))")
                }
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundColor(fgMuted)
            }

            // Primary Transport Row: Shuffle · Prev · Play/Pause · Next · Repeat
            HStack(alignment: .center, spacing: 0) {
                Button {
                    guard !jam.isGuestLocked else {
                        api.showToast("Host controls playback in this Jam")
                        return
                    }
                    haptic(.light)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        player.toggleShuffle()
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(player.isShuffling ? theme.accent : fgSecondary)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    guard !jam.isGuestLocked else {
                        api.showToast("Host controls playback in this Jam")
                        return
                    }
                    haptic(.light)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        player.previousTrack()
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundColor(fgPrimary)
                        .frame(width: 54, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    guard !jam.isGuestLocked else {
                        api.showToast("Host controls playback in this Jam")
                        return
                    }
                    haptic(.medium)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        player.togglePlayPause()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(playCircleFill)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(useLightInk ? 0.42 : 0.18), radius: 12, x: 0, y: 4)
                        if player.isLoadingTrack {
                            ProgressView().tint(playCircleIcon)
                        } else if jam.isGuestLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(playCircleIcon.opacity(0.65))
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 25, weight: .bold))
                                .foregroundColor(playCircleIcon)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                .frame(maxWidth: .infinity)

                Button {
                    guard !jam.isGuestLocked else {
                        api.showToast("Host controls playback in this Jam")
                        return
                    }
                    haptic(.light)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        player.nextTrack()
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundColor(fgPrimary)
                        .frame(width: 54, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    guard !jam.isGuestLocked else {
                        api.showToast("Host controls playback in this Jam")
                        return
                    }
                    haptic(.light)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        player.cycleRepeat()
                    }
                } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(player.repeatMode == .none ? fgSecondary : theme.accent)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)
            }
            .opacity(jam.isGuestLocked ? 0.55 : 1.0)
            .padding(.vertical, 2)

            // Elevated Utility Dock: AirPlay · Jam · Add to Playlist · Discord RPC · Queue
            HStack(spacing: 0) {
                AirPlayPickerButton(
                    tint: useLightInk ? .white : .label,
                    activeTint: UIColor(theme.accent)
                )
                .frame(width: 28, height: 28)
                .frame(maxWidth: .infinity)

                Button {
                    haptic(.light)
                    showJamSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(jam.isActive ? theme.accent : fgSecondary)
                            .frame(width: 42, height: 40)
                        if jam.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .offset(x: -5, y: 7)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    haptic(.light)
                    showAddToPlaylist = true
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(fgSecondary)
                        .frame(width: 42, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    haptic(.light)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        showDiscordCard.toggle()
                    }
                } label: {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(showDiscordCard ? theme.accent : fgSecondary)
                        .frame(width: 42, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)

                Button {
                    haptic(.light)
                    showQueueSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(fgPrimary.opacity(0.9))
                        .frame(width: 42, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(dockBg)
            .clipShape(Capsule())
        }
    }

    // MARK: - Queue Sheet
    private var queueSheetView: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        HDArtworkView(rawUrl: item.rawArtwork, cornerRadius: 6)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(idx == player.currentIndex ? theme.accent : theme.textPrimary)
                                .lineLimit(1)
                            Text(item.artistName)
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if idx == player.currentIndex {
                            AnimatedEqualizerBars(isPlaying: player.isPlaying, color: theme.accent, maxHeight: 15)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.play(track: item, in: player.queue)
                        showQueueSheet = false
                    }
                }
            }
            .navigationTitle("Up Next (\(player.queue.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showQueueSheet = false }
                }
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
