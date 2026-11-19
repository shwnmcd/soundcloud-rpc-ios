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

/// Sleek custom Spotify / SoundCloud-style interactive progress scrubber
struct SleekScrubberBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let clamped = min(1.0, max(0.0, progress))
            let thumbSize: CGFloat = isScrubbing ? 16 : 12
            let barHeight: CGFloat = isScrubbing ? 6 : 4

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
        .frame(height: 32)
    }
}

struct NowPlayingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var webController: WebViewController
    @ObservedObject var settings: AppSettings
    @ObservedObject var adBlocker: AdBlockerService

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var pendingSeekFraction: Double? = nil
    @State private var showDiscordCard = false
    @State private var dismissDragOffset: CGFloat = 0

    private var track: TrackInfo { webController.currentTrack }

    private var normalized: (artist: String, track: String) {
        TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: settings.trackParserEnabled
        )
    }

    private var displayedProgress: Double {
        if isScrubbing { return scrubValue }
        if let pending = pendingSeekFraction { return pending }
        return track.progressFraction
    }

    var body: some View {
        GeometryReader { geo in
            let maxContentWidth: CGFloat = sizeClass == .regular ? min(540, geo.size.width - 80) : geo.size.width - 40

            ZStack {
                // === FULL-SCREEN SHARP EDGE-TO-EDGE ALBUM ARTWORK (Spotify Canvas / SoundCloud Fullscreen Style) ===
                ZStack {
                    Color.black
                    if !track.highResArtwork.isEmpty {
                        AsyncImage(url: URL(string: track.highResArtwork)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
                                .clipped()
                        } placeholder: {
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.1, blue: 0.02), Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.1, blue: 0.02), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                    // Cinematic top & bottom scrim gradients so floating UI stays razor-sharp over any artwork
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.72), Color.black.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)

                        Spacer()

                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.45),
                                Color.black.opacity(0.84),
                                Color.black.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: max(390, geo.size.height * 0.52))
                    }
                }
                .ignoresSafeArea()

                // === FLOATING UI OVER FULL-SCREEN ARTWORK ===
                VStack(spacing: 0) {
                    // Top Bar: Down Chevron · Source Title · Share/More
                    HStack {
                        Button {
                            haptic(.light)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                                .frame(width: 40, height: 40)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("PLAYING FROM SOUNDCLOUD")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.78))
                            Text(normalized.artist)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                        Spacer()

                        if let shareURL = URL(string: track.url), !track.url.isEmpty {
                            ShareLink(item: shareURL) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                                    .frame(width: 40, height: 40)
                            }
                        } else {
                            Color.clear.frame(width: 40, height: 40)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    Spacer()

                    // Floating Bottom Controls Overlay (Spotify Full-Screen Canvas Layout)
                    VStack(spacing: 16) {
                        if showDiscordCard {
                            RichPresencePreviewView(track: track, settings: settings)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        // Compact Cover Thumbnail + Track Title + Artist + Like Button
                        HStack(alignment: .center, spacing: 12) {
                            AsyncImage(url: URL(string: track.highResArtwork)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.15))
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(normalized.track)
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(normalized.artist)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.78))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                haptic(.medium)
                                webController.toggleLike()
                            } label: {
                                Image(systemName: track.isLiked ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(track.isLiked ? .orange : .white.opacity(0.9))
                            }
                        }

                        // Sleek Interactive Scrubber + Timestamps
                        VStack(spacing: 2) {
                            SleekScrubberBar(
                                progress: Binding(
                                    get: { displayedProgress },
                                    set: { scrubValue = $0 }
                                ),
                                isScrubbing: $isScrubbing
                            ) { committedFraction in
                                pendingSeekFraction = committedFraction
                                webController.seek(toFraction: committedFraction)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    if pendingSeekFraction == committedFraction {
                                        pendingSeekFraction = nil
                                    }
                                }
                            }

                            HStack {
                                Text(TrackTimeParser.format(displayedProgress * track.durationSeconds))
                                Spacer()
                                Text("-\(TrackTimeParser.format(max(0, track.durationSeconds - displayedProgress * track.durationSeconds)))")
                            }
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white.opacity(0.72))
                        }

                        // Transport Row: Shuffle · Prev · Big White Play/Pause · Next · Repeat
                        HStack(spacing: 0) {
                            Button {
                                haptic(.light)
                                webController.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(track.isShuffling ? .orange : .white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                haptic(.light)
                                webController.previousTrack()
                            } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                haptic(.medium)
                                webController.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 66, height: 66)
                                        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: track.isPlaying ? 0 : 2)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                haptic(.light)
                                webController.nextTrack()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                haptic(.light)
                                webController.cycleRepeat()
                            } label: {
                                Image(systemName: track.repeatMode == "one" ? "repeat.1" : "repeat")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(track.repeatMode == "none" ? .white.opacity(0.8) : .orange)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Bottom Utility Row: AirPlay (left) · Shield + Discord + Share (right)
                        HStack(spacing: 20) {
                            AirPlayPickerButton()
                                .frame(width: 28, height: 28)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkered")
                                Text("\(adBlocker.blockedAdsCount)")
                                    .monospacedDigit()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.45))
                            .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
                            .clipShape(Capsule())

                            Button {
                                haptic(.light)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDiscordCard.toggle()
                                }
                            } label: {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 19))
                                    .foregroundColor(showDiscordCard ? .orange : .white.opacity(0.85))
                            }

                            if let shareURL = URL(string: track.url), !track.url.isEmpty {
                                ShareLink(item: shareURL) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 19))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.bottom, 22)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(y: max(0, dismissDragOffset))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if !isScrubbing && value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                            dismissDragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if !isScrubbing && value.translation.height > 110 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dismissDragOffset = 0
                            }
                        }
                    }
            )
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
