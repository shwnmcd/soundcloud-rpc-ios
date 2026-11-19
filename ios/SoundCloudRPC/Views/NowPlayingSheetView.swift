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

/// Sleek custom Spotify / Apple Music-style interactive progress scrubber (no oversized system Slider thumb!)
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
                    .fill(Color.white.opacity(0.24))
                    .frame(height: barHeight)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, width * clamped), height: barHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                    .offset(x: max(0, min(width - thumbSize, width * clamped - thumbSize / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                        }
                        let fraction = min(1.0, max(0.0, value.location.x / width))
                        progress = fraction
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
        .frame(height: 26)
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
        isScrubbing ? scrubValue : track.progressFraction
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let maxContentWidth: CGFloat = sizeClass == .regular ? min(520, geo.size.width - 80) : geo.size.width - 44
            let artSize: CGFloat = min(maxContentWidth, sizeClass == .regular ? 390 : max(260, geo.size.height * 0.40))

            ZStack {
                // Edge-to-edge full-screen blurred album artwork backdrop (covers Dynamic Island & entire phone!)
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.07)
                    if !track.highResArtwork.isEmpty {
                        AsyncImage(url: URL(string: track.highResArtwork)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height + safeTop + safeBottom)
                                .blur(radius: 70)
                                .opacity(0.50)
                                .clipped()
                        } placeholder: {
                            EmptyView()
                        }
                    }
                    LinearGradient(
                        colors: [Color.black.opacity(0.22), Color.black.opacity(0.84)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Subtle top drag pill + Spotify-style header bar
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 38, height: 4.5)
                        .padding(.top, 8)

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
                                .foregroundColor(.white.opacity(0.65))
                            Text(normalized.artist)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let shareURL = URL(string: track.url), !track.url.isEmpty {
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
                    .padding(.top, 4)

                    Spacer(minLength: 16)

                    // Full-Impact Rounded Album Artwork
                    AsyncImage(url: URL(string: track.highResArtwork)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.system(size: 56, weight: .semibold))
                                    .foregroundColor(.orange)
                            )
                    }
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: 14)
                    .scaleEffect(track.isPlaying ? 1.0 : 0.92)
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)

                    Spacer(minLength: 22)

                    // Track Metadata + Scrubber + Transport Controls
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(normalized.track)
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(normalized.artist)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.white.opacity(0.72))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                haptic(.medium)
                                webController.toggleLike()
                            } label: {
                                Image(systemName: track.isLiked ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(track.isLiked ? .orange : .white.opacity(0.85))
                            }
                        }

                        // Custom Sleek Scrubber
                        VStack(spacing: 2) {
                            SleekScrubberBar(
                                progress: Binding(
                                    get: { displayedProgress },
                                    set: { scrubValue = $0 }
                                ),
                                isScrubbing: $isScrubbing
                            ) { committedFraction in
                                webController.seek(toFraction: committedFraction)
                            }

                            HStack {
                                Text(TrackTimeParser.format(displayedProgress * track.durationSeconds))
                                Spacer()
                                Text("-\(TrackTimeParser.format(max(0, track.durationSeconds - displayedProgress * track.durationSeconds)))")
                            }
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.white.opacity(0.65))
                        }

                        // Spotify-style Transport Row
                        HStack(spacing: 0) {
                            Button {
                                haptic(.light)
                                webController.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(track.isShuffling ? .orange : .white.opacity(0.72))
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
                                        .frame(width: 68, height: 68)
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
                                    .foregroundColor(track.repeatMode == "none" ? .white.opacity(0.72) : .orange)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if showDiscordCard {
                            RichPresencePreviewView(track: track, settings: settings)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        // Bottom Utility Row
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
                            .background(Color.orange.opacity(0.18))
                            .clipShape(Capsule())

                            Button {
                                haptic(.light)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDiscordCard.toggle()
                                }
                            } label: {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 19))
                                    .foregroundColor(showDiscordCard ? .orange : .white.opacity(0.8))
                            }

                            if let shareURL = URL(string: track.url), !track.url.isEmpty {
                                ShareLink(item: shareURL) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 19))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.bottom, 18)
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
                        if !isScrubbing && value.translation.height > 120 {
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
