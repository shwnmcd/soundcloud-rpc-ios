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
        ZStack {
            // Blurred Album Art Backdrop (Apple Music style)
            backdropLayer

            VStack(spacing: 22) {
                // Drag grabber pill
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)

                Spacer(minLength: 4)

                // Album Artwork
                AsyncImage(url: URL(string: track.highResArtwork)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.system(size: 56, weight: .semibold))
                                .foregroundColor(.orange)
                        )
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
                .scaleEffect(track.isPlaying ? 1.0 : 0.91)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)

                Spacer(minLength: 4)

                // Title, Artist & Native Heart Button
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(normalized.track)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(normalized.artist)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()

                    Button {
                        haptic(.medium)
                        webController.toggleLike()
                    } label: {
                        Image(systemName: track.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(track.isLiked ? .orange : .white.opacity(0.85))
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 26)

                // Interactive Apple-style Progress Scrubber
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { displayedProgress },
                            set: { newVal in
                                scrubValue = newVal
                            }
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
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 26)

                // Native Apple Transport Controls
                HStack(spacing: 0) {
                    Button {
                        haptic(.light)
                        webController.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(track.isShuffling ? .orange : .white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        haptic(.light)
                        webController.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        haptic(.medium)
                        webController.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 68))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        haptic(.light)
                        webController.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        haptic(.light)
                        webController.cycleRepeat()
                    } label: {
                        Image(systemName: track.repeatMode == "one" ? "repeat.1" : "repeat")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(track.repeatMode == "none" ? .white.opacity(0.7) : .orange)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)

                if showDiscordCard {
                    RichPresencePreviewView(track: track, settings: settings)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Bottom Utility Row: AirPlay, Discord Preview, AdBlock Pill, Share
                HStack(spacing: 24) {
                    AirPlayPickerButton()
                        .frame(width: 28, height: 28)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDiscordCard.toggle()
                        }
                    } label: {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 19))
                            .foregroundColor(showDiscordCard ? .orange : .white.opacity(0.75))
                    }

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

                    if let shareURL = URL(string: track.url), !track.url.isEmpty {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 19))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.bottom, 22)
            }
        }
    }

    private var backdropLayer: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
            if !track.highResArtwork.isEmpty {
                AsyncImage(url: URL(string: track.highResArtwork)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 55)
                        .opacity(0.42)
                } placeholder: {
                    EmptyView()
                }
                .ignoresSafeArea()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
