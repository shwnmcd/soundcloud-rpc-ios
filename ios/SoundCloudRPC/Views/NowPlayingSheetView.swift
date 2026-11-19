import SwiftUI
import AVKit
import UIKit

struct AirPlayPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor.systemOrange
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Sleek custom interactive progress scrubber (millisecond-accurate native AVPlayer seeking!)
struct SleekScrubberBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = min(1.0, max(0.0, progress))
            let thumbSize: CGFloat = isScrubbing ? 16 : 11
            let barHeight: CGFloat = isScrubbing ? 6 : 3.5

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: barHeight)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, width * clamped), height: barHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 1)
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
            .animation(.easeOut(duration: 0.12), value: isScrubbing)
        }
        .frame(height: 30)
    }
}

struct NowPlayingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var api: SoundCloudAPI
    @ObservedObject var settings: AppSettings

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showDiscordCard = false
    @State private var showQueueSheet = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var swipeXOffset: CGFloat = 0

    private var track: SCTrack? { player.currentTrack }

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

    var body: some View {
        ZStack {
            // === TRUE EDGE-TO-EDGE FULL-SCREEN HD ARTWORK WITH SEAMLESS FADE-TO-BLACK TOP & BOTTOM ===
            Color.black.ignoresSafeArea()

            GeometryReader { bgGeo in
                HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: true, cornerRadius: 0)
                    .frame(width: bgGeo.size.width, height: bgGeo.size.height)
                    .clipped()
                    .offset(x: swipeXOffset * 0.35)
                    .opacity(max(0.55, 1.0 - abs(swipeXOffset) / 360.0))
            }
            .ignoresSafeArea()

            // Seamless Fade-to-Black Top (integrates smoothly into Dynamic Island / Status Bar) & Rich Bottom Scrim
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.black, location: 0.0),
                        .init(color: Color.black.opacity(0.88), location: 0.28),
                        .init(color: Color.black.opacity(0.35), location: 0.68),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 195)

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
            .ignoresSafeArea()

            // === FLOATING CONTROLS LAYER (Positioned Cleanly Above Bottom Safe Area) ===
            VStack(spacing: 0) {
                // Top Bar: Down Chevron · Source Title · Share/More
                HStack {
                    Button {
                        haptic(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("PLAYING FROM SOUNDCLOUD")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.7))
                        Text(normalized.artist)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let urlStr = track?.permalinkUrl, let shareURL = URL(string: urlStr) {
                        ShareLink(item: shareURL) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                    } else {
                        Color.clear.frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                Spacer()

                // Floating Playback Controls Block — Elevated & Cleanly Formatted!
                VStack(spacing: 18) {
                    if showDiscordCard {
                        RichPresencePreviewView(track: player.currentTrackInfo, settings: settings)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Compact HD Cover + Title + Artist + Heart
                    HStack(alignment: .center, spacing: 12) {
                        HDArtworkView(rawUrl: track?.rawArtwork, preferOriginal: false, cornerRadius: 8)
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(normalized.track)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(normalized.artist)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button {
                            haptic(.medium)
                            player.toggleLikeCurrent()
                        } label: {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundColor(isLiked ? .orange : .white.opacity(0.88))
                                .frame(width: 40, height: 40)
                        }
                    }
                    .offset(x: swipeXOffset * 0.22)

                    // Native Instant AVPlayer Scrubber
                    VStack(spacing: 2) {
                        SleekScrubberBar(
                            progress: Binding(
                                get: { displayedProgress },
                                set: { scrubValue = $0 }
                            ),
                            isScrubbing: $isScrubbing
                        ) { committedFraction in
                            player.seek(toFraction: committedFraction)
                        }

                        HStack {
                            Text(TrackTimeParser.format(displayedProgress * player.durationSeconds))
                            Spacer()
                            Text("-\(TrackTimeParser.format(max(0, player.durationSeconds - displayedProgress * player.durationSeconds)))")
                        }
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.68))
                    }

                    // Balanced Primary Transport Row: Shuffle · Prev · Play/Pause · Next · Repeat
                    HStack(alignment: .center, spacing: 0) {
                        Button {
                            haptic(.light)
                            player.toggleShuffle()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(player.isShuffling ? .orange : .white.opacity(0.78))
                                .frame(width: 44, height: 44)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            haptic(.light)
                            player.previousTrack()
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            haptic(.medium)
                            player.togglePlayPause()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                                if player.isLoadingTrack {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 25, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: player.isPlaying ? 0 : 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            haptic(.light)
                            player.nextTrack()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            haptic(.light)
                            player.cycleRepeat()
                        } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(player.repeatMode == .none ? .white.opacity(0.78) : .orange)
                                .frame(width: 44, height: 44)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 2)

                    // Elevated Utility Dock: AirPlay · Discord RPC · Share · Queue
                    HStack(spacing: 0) {
                        AirPlayPickerButton()
                            .frame(width: 28, height: 28)
                            .frame(maxWidth: .infinity)

                        Button {
                            haptic(.light)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showDiscordCard.toggle()
                            }
                        } label: {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(showDiscordCard ? .orange : .white.opacity(0.82))
                                .frame(width: 40, height: 36)
                        }
                        .frame(maxWidth: .infinity)

                        if let urlStr = track?.permalinkUrl, let shareURL = URL(string: urlStr) {
                            ShareLink(item: shareURL) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 40, height: 36)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Button {
                            haptic(.light)
                            showQueueSheet = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.88))
                                .frame(width: 40, height: 36)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .frame(maxWidth: sizeClass == .regular ? 500 : .infinity)
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
        }
        .offset(y: max(0, dismissDragOffset))
        // Swipe Left/Right to Skip Tracks in Queue, OR Swipe Down to Dismiss!
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard !isScrubbing else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) {
                        swipeXOffset = dx
                    } else if dy > 0 {
                        dismissDragOffset = dy
                    }
                }
                .onEnded { value in
                    guard !isScrubbing else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height

                    if abs(dx) > abs(dy) {
                        if dx < -65 {
                            haptic(.medium)
                            player.nextTrack()
                        } else if dx > 65 {
                            haptic(.medium)
                            player.previousTrack()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            swipeXOffset = 0
                        }
                    } else if dy > 110 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dismissDragOffset = 0
                            swipeXOffset = 0
                        }
                    }
                }
        )
        .sheet(isPresented: $showQueueSheet) {
            NavigationStack {
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 10) {
                            HDArtworkView(rawUrl: item.rawArtwork, cornerRadius: 6)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(idx == player.currentIndex ? .orange : .primary)
                                    .lineLimit(1)
                                Text(item.artistName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if idx == player.currentIndex {
                                Image(systemName: "waveform").foregroundColor(.orange)
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
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
