import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct JamSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var jam: JamSessionService
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var api: SoundCloudAPI

    @State private var joinCodeInput: String = ""
    @State private var copiedCode: Bool = false
    @State private var showQRCode: Bool = false
    @State private var pulseAnimate: Bool = false

    // Collaborative Queue Quick Search
    @State private var queueQuery: String = ""
    @State private var queueResults: [SCTrack] = []
    @State private var isSearchingQueue: Bool = false

    private let reactionEmojis = ["🔥", "❤️", "🙌", "🤯", "🎧"]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        if jam.isActive {
                            activeJamContent
                        } else {
                            lobbyContent
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }

                // Floating Live Reactions Overlay
                GeometryReader { geo in
                    ForEach(jam.activeReactions) { burst in
                        FloatingReactionView(burst: burst, containerHeight: geo.size.height)
                            .position(x: geo.size.width * burst.xFraction, y: geo.size.height * 0.72)
                    }
                }
                .allowsHitTesting(false)
            }
            .navigationTitle(jam.isActive ? "Live Jam" : "Group Listening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if jam.isActive {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                jam.leaveJam()
                            }
                        } label: {
                            Text(jam.isHost ? "End Jam" : "Leave")
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Lobby (Start or Join a Worldwide Jam)
    private var lobbyContent: some View {
        VStack(spacing: 22) {
            // Animated Worldwide Radar Emblem
            ZStack {
                Circle()
                    .stroke(theme.accent.opacity(0.18), lineWidth: 2)
                    .frame(width: 132, height: 132)
                    .scaleEffect(pulseAnimate ? 1.18 : 0.92)
                    .opacity(pulseAnimate ? 0.15 : 0.75)

                Circle()
                    .stroke(theme.accent.opacity(0.32), lineWidth: 2)
                    .frame(width: 98, height: 98)
                    .scaleEffect(pulseAnimate ? 1.12 : 0.94)
                    .opacity(pulseAnimate ? 0.35 : 0.9)

                Circle()
                    .fill(LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: theme.accent.opacity(0.45), radius: 16, y: 6)
                    .overlay(
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .padding(.top, 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulseAnimate = true
                }
            }

            VStack(spacing: 6) {
                Text("Listen Together Worldwide")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("Start a Jam and share your 6-character code or link with friends anywhere on Earth. Everyone streams ad-free in real-time sync.")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Host a New Jam Card
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                        jam.startJam()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 17, weight: .bold))
                        Text("Start a Jam")
                            .font(.headline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 5)
                }
                .buttonStyle(SpringPressButtonStyle())

                if let track = player.currentTrack {
                    HStack(spacing: 8) {
                        HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 5)
                            .frame(width: 28, height: 28)
                        Text("Will share: \(track.displayTitle)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            // Divider
            HStack {
                Rectangle().fill(theme.divider).frame(height: 1)
                Text("OR JOIN A FRIEND")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(theme.textTertiary)
                    .tracking(0.8)
                Rectangle().fill(theme.divider).frame(height: 1)
            }

            // Join by Code / Link Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter Jam Code or Invite Link")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(theme.textPrimary)

                HStack(spacing: 8) {
                    TextField("e.g. K7M4P2", text: $joinCodeInput)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textPrimary)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            joinCodeInput = JamSessionService.normalizeCode(clip)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Text("Paste")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(theme.accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SpringPressButtonStyle())
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                        jam.joinJam(codeOrUrl: joinCodeInput)
                    }
                } label: {
                    Text("Join Jam")
                        .font(.headline.weight(.bold))
                        .foregroundColor(theme.playCircleFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(JamSessionService.normalizeCode(joinCodeInput).count >= 4 ? theme.playCircleBg : theme.playCircleBg.opacity(0.35))
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringPressButtonStyle())
                .disabled(JamSessionService.normalizeCode(joinCodeInput).count < 4)

                if !jam.statusNote.isEmpty {
                    Text(jam.statusNote)
                        .font(.caption)
                        .foregroundColor(theme.accent)
                }
            }
            .padding(16)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.divider, lineWidth: 0.7))
        }
    }

    // MARK: - Active Live Jam View
    private var activeJamContent: some View {
        VStack(spacing: 16) {
            // Live Status Header + Shareable Code Card
            VStack(spacing: 14) {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(connectionDotColor)
                            .frame(width: 9, height: 9)
                        Text(jam.isHost ? "HOSTING LIVE JAM" : "LISTENING IN JAM")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundColor(connectionDotColor)
                    }

                    Spacer()

                    Text("\(jam.listenerCount) \(jam.listenerCount == 1 ? "listener" : "listeners")")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.pillFill)
                        .clipShape(Capsule())
                }

                // Giant Tap-to-Copy Room Code
                VStack(spacing: 4) {
                    Text(jam.roomCode)
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .tracking(5)
                        .foregroundColor(theme.textPrimary)

                    Text(jam.statusNote.isEmpty ? "Connected globally" : jam.statusNote)
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }

                // Action Row: Copy Code · Share Link · QR Code
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = jam.roomCode
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            copiedCode = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation { copiedCode = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                            Text(copiedCode ? "Copied" : "Copy Code")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.surfaceElevated)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle())

                    ShareLink(item: jam.shareMessage) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Invite")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.accent)
                        .clipShape(Capsule())
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            showQRCode.toggle()
                        }
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(showQRCode ? .white : theme.textPrimary)
                            .frame(width: 42, height: 36)
                            .background(showQRCode ? theme.accent : theme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle())
                }

                if showQRCode, let qrImage = generateQRCode(from: jam.inviteLink) {
                    VStack(spacing: 8) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 170, height: 170)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Scan to open SoundCloud RPC & join \(jam.roomCode)")
                            .font(.caption2)
                            .foregroundColor(theme.textSecondary)
                    }
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(16)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.accent.opacity(0.35), lineWidth: 1))

            // Active Listeners Avatar Strip
            VStack(alignment: .leading, spacing: 10) {
                Text("LISTENING NOW")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundColor(theme.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(jam.participants) { person in
                            VStack(spacing: 5) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let av = person.avatarUrl, !av.isEmpty {
                                        HDArtworkView(rawUrl: av, cornerRadius: 24)
                                            .frame(width: 48, height: 48)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(person.isHost ? theme.accent : theme.divider, lineWidth: 2))
                                    } else {
                                        Circle()
                                            .fill(theme.accent.opacity(0.22))
                                            .frame(width: 48, height: 48)
                                            .overlay(
                                                Text(String(person.name.prefix(1)).uppercased())
                                                    .font(.headline.bold())
                                                    .foregroundColor(theme.accent)
                                            )
                                            .overlay(Circle().stroke(person.isHost ? theme.accent : theme.divider, lineWidth: 2))
                                    }

                                    if person.isHost {
                                        Circle()
                                            .fill(theme.accent)
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Image(systemName: "crown.fill")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.white)
                                            )
                                    } else {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(theme.surface, lineWidth: 2))
                                    }
                                }

                                Text(person.name)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 62)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Now Playing in Jam Card (Like any song played in the Jam directly to YOUR SoundCloud!)
            if let current = player.currentTrack {
                let currentLiked = api.likedTrackIds.contains(current.id)
                HStack(spacing: 12) {
                    HDArtworkView(rawUrl: current.rawArtwork, cornerRadius: 8)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW PLAYING IN JAM")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundColor(theme.accent)
                        Text(current.displayTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)
                        Text(current.artistName)
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    AnimatedHeartButton(
                        isLiked: currentLiked,
                        size: 22,
                        accentColor: theme.accent,
                        inactiveColor: theme.textSecondary
                    ) {
                        Task { _ = await api.toggleLike(track: current) }
                    }
                }
                .padding(12)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.divider, lineWidth: 0.7))
            }

            // Host Playback Control Mode (Host Only vs Everyone) OR Guest Status + Resync Bar
            VStack(alignment: .leading, spacing: 10) {
                if jam.isHost {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Who can control playback")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(theme.textPrimary)
                            Text(jam.allowGuestControl ? "Everyone can play, pause, skip & scrub" : "Only you (Host) control playback — guests stay synced")
                                .font(.caption2)
                                .foregroundColor(theme.textSecondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                jam.setAllowGuestControl(false)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill").font(.caption.bold())
                                Text("Host Only").font(.caption.weight(.bold))
                            }
                            .foregroundColor(!jam.allowGuestControl ? .white : theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!jam.allowGuestControl ? theme.accent : theme.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.94))

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                jam.setAllowGuestControl(true)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill").font(.caption.bold())
                                Text("Everyone").font(.caption.weight(.bold))
                            }
                            .foregroundColor(jam.allowGuestControl ? .white : theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(jam.allowGuestControl ? theme.accent : theme.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.94))
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: jam.allowGuestControl ? "person.2.fill" : "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(theme.accent)
                                Text(jam.allowGuestControl ? "Shared Controls Enabled" : "Host-Only Controls Active")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(theme.textPrimary)
                            }
                            Text("Like any track, add to queue, or send live reactions")
                                .font(.caption2)
                                .foregroundColor(theme.textSecondary)
                        }
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            jam.requestResync()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Resync")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle())
                    }
                }
            }
            .padding(14)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Live Emoji Reactions Bar
            HStack(spacing: 8) {
                ForEach(reactionEmojis, id: \.self) { emoji in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        jam.sendReaction(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(theme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.85))
                }
            }
            .padding(10)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Collaborative Queue Search + Shared Queue
            VStack(alignment: .leading, spacing: 12) {
                Text("SHARED JAM QUEUE")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundColor(theme.textSecondary)

                // Add Track to Jam Search Box
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                    TextField("Add a SoundCloud track to this Jam...", text: $queueQuery)
                        .font(.subheadline)
                        .foregroundColor(theme.textPrimary)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await searchForJamQueue() }
                        }
                    if !queueQuery.isEmpty {
                        Button {
                            queueQuery = ""
                            queueResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(theme.surfaceElevated)
                .clipShape(Capsule())

                if isSearchingQueue {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }.padding(.vertical, 8)
                } else if !queueResults.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(queueResults.prefix(6)) { track in
                            HStack(spacing: 10) {
                                HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 6)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(track.displayTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(theme.textPrimary)
                                        .lineLimit(1)
                                    Text(track.artistName)
                                        .font(.caption2)
                                        .foregroundColor(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    jam.addTrackToJam(track)
                                    queueQuery = ""
                                    queueResults = []
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(theme.accent)
                                }
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                // Current Queue List
                if jam.sharedQueue.isEmpty {
                    Text("Play any song or search above to build the shared Jam queue.")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(jam.sharedQueue) { item in
                            let isCurrent = player.currentTrack?.id == item.id
                            let itemLiked = api.likedTrackIds.contains(item.id)
                            HStack(spacing: 10) {
                                HDArtworkView(rawUrl: item.artworkUrl, cornerRadius: 6)
                                    .frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(isCurrent ? theme.accent : theme.textPrimary)
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.caption)
                                        .foregroundColor(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isCurrent {
                                    AnimatedEqualizerBars(isPlaying: player.isPlaying, color: theme.accent, maxHeight: 14)
                                }
                                AnimatedHeartButton(
                                    isLiked: itemLiked,
                                    size: 17,
                                    accentColor: theme.accent,
                                    inactiveColor: theme.textSecondary
                                ) {
                                    Task { _ = await api.toggleLike(track: item.toSCTrack()) }
                                }
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if jam.canControlPlayback {
                                    let tracks = jam.sharedQueue.map { $0.toSCTrack() }
                                    if let chosen = tracks.first(where: { $0.id == item.id }) {
                                        player.play(track: chosen, in: tracks)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Leave / End Jam Button
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    jam.leaveJam()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: jam.isHost ? "xmark.circle.fill" : "rectangle.portrait.and.arrow.right")
                    Text(jam.isHost ? "End Jam for Everyone" : "Leave Jam")
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(SpringPressButtonStyle())
        }
    }

    private var connectionDotColor: Color {
        switch jam.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .gray
        }
    }

    private func searchForJamQueue() async {
        let q = queueQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearchingQueue = true
        let res = await api.search(query: q, filter: .tracks)
        queueResults = res.tracks
        isSearchingQueue = false
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImg)
    }
}

private struct FloatingReactionView: View {
    let burst: JamReactionBurst
    let containerHeight: CGFloat
    @State private var rise: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(burst.emoji)
                .font(.system(size: 36))
            Text(burst.senderName)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
        }
        .offset(y: rise ? -(containerHeight * 0.48) : 0)
        .scaleEffect(rise ? 1.15 : 0.65)
        .opacity(rise ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 1.85)) {
                rise = true
            }
        }
    }
}
