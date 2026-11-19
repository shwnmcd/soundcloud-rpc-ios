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

struct NowPlayingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var webController: WebViewController
    @ObservedObject var settings: AppSettings
    @ObservedObject var adBlocker: AdBlockerService

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showDiscordCard = false

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
            let maxContentWidth: CGFloat = sizeClass == .regular ? min(520, geo.size.width - 80) : geo.size.width - 48
            let artSize: CGFloat = min(maxContentWidth, sizeClass == .regular ? 380 : max(240, geo.size.height * 0.38))

            VStack(spacing: 0) {
                // Spotify-style Top Bar (Down Chevron · Source · Share/More)
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
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer(minLength: 14)

                // Large Rounded Album Artwork
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
                .shadow(color: .black.opacity(0.5), radius: 26, x: 0, y: 14)
                .scaleEffect(track.isPlaying ? 1.0 : 0.93)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)

                Spacer(minLength: 20)

                // Track Info + Spotify-inspired Like Button
                VStack(spacing: 18) {
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

                    // Crisp Seek Scrubber + Elapsed / Remaining Timestamps
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { displayedProgress },
                                set: { scrubValue = $0 }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if !editing {
                                    webController.seek(toFraction: scrubValue)
                                }
                            }
                        )
                        .tint(.white)

                        HStack {
                            Text(TrackTimeParser.format(displayedProgress * track.durationSeconds))
                            Spacer()
                            Text("-\(TrackTimeParser.format(max(0, track.durationSeconds - displayedProgress * track.durationSeconds)))")
                        }
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundColor(.white.opacity(0.65))
                    }

                    // Spotify-style Main Transport Row: Shuffle · Prev · Big White Play/Pause · Next · Repeat
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
                                    .frame(width: 66, height: 66)
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

                    // Bottom Utility Row: AirPlay (left) · Discord RPC + Shield + Share (right)
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
                    .padding(.top, 4)
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.bottom, 26)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Bounded backdrop so scaledToFill artwork NEVER widens the VStack beyond screen width!
            .background {
                ZStack {
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                    if !track.highResArtwork.isEmpty {
                        AsyncImage(url: URL(string: track.highResArtwork)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .blur(radius: 65)
                                .opacity(0.45)
                                .clipped()
                        } placeholder: {
                            EmptyView()
                        }
                    }
                    LinearGradient(
                        colors: [Color.black.opacity(0.28), Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
