import SwiftUI
import UIKit

struct NativeHomeView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var settings: AppSettings

    let onOpenSettings: () -> Void

    @State private var shelves: [SCHomeShelf] = []
    @State private var quickCards: [SCQuickCard] = []
    @State private var likesPreview: [SCTrack] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Official SoundCloud iOS Home Top Row (Avatar · Ad-Free Pill · Settings)
                    HStack(spacing: 10) {
                        Group {
                            if let avatar = api.currentUser?.avatarUrl, !avatar.isEmpty {
                                HDArtworkView(rawUrl: avatar, cornerRadius: 17)
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.25, blue: 0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "waveform").font(.caption.bold()).foregroundColor(.white))
                            }
                        }
                        .onTapGesture { onOpenSettings() }

                        Button {
                            onOpenSettings()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                Text("Ad-Free Studio")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            onOpenSettings()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(.white.opacity(0.88))
                                .frame(width: 34, height: 34)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    // Burnt-Orange "Your likes" Hero Card with Shuffle Button (matches Screenshot 1!)
                    NavigationLink {
                        NativeLikesView()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Image(systemName: "heart")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.orange.opacity(0.45))
                                    .offset(x: -5, y: 4)
                                Image(systemName: "heart")
                                    .font(.system(size: 34, weight: .light))
                                    .foregroundColor(.orange.opacity(0.7))
                                    .offset(x: -2, y: 2)
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color(red: 0.14, green: 0.06, blue: 0.02))
                                Image(systemName: "heart")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            .frame(width: 44, height: 44)

                            Text("Your likes")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)

                            Spacer()

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if !likesPreview.isEmpty {
                                    player.playShuffled(list: likesPreview)
                                }
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.42))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.48, green: 0.16, blue: 0.04), Color(red: 0.16, green: 0.11, blue: 0.09)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 14)

                    // Compact 2x2 Quick-Access Grid (exact Official SoundCloud iOS Home layout!)
                    if !quickCards.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(quickCards) { card in
                                if let pl = card.playlist {
                                    NavigationLink {
                                        NativePlaylistDetailView(playlist: pl)
                                    } label: {
                                        quickCardRow(card)
                                    }
                                } else if let artist = card.user {
                                    NavigationLink {
                                        NativeArtistProfileView(user: artist)
                                    } label: {
                                        quickCardRow(card)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // Shelves: More of what you like · Mixed for you · Curated by SoundCloud
                    if isLoading && shelves.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(.orange).padding(.vertical, 40)
                            Spacer()
                        }
                    } else {
                        ForEach(shelves) { shelf in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(shelf.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(shelf.playlists) { playlist in
                                            NavigationLink {
                                                NativePlaylistDetailView(playlist: playlist)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HDArtworkView(rawUrl: playlist.rawArtwork, preferOriginal: false, cornerRadius: 6)
                                                        .frame(width: 152, height: 152)

                                                    Text(playlist.displayTitle)
                                                        .font(.system(size: 13.5, weight: .semibold))
                                                        .foregroundColor(.white)
                                                        .lineLimit(1)
                                                        .frame(width: 152, alignment: .leading)

                                                    Text(playlist.creatorName)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(Color(white: 0.62))
                                                        .lineLimit(2)
                                                        .frame(width: 152, alignment: .leading)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
            .refreshable {
                await loadHome()
            }
            .task {
                if shelves.isEmpty {
                    await loadHome()
                }
            }
        }
    }

    private func quickCardRow(_ card: SCQuickCard) -> some View {
        HStack(spacing: 10) {
            HDArtworkView(rawUrl: card.artworkUrl, cornerRadius: card.isCircular ? 20 : 6)
                .frame(width: 40, height: 40)
                .clipShape(card.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))

            VStack(alignment: .leading, spacing: 1.5) {
                Text(card.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(white: 0.125))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadHome() async {
        isLoading = true
        if api.currentUser == nil {
            _ = await api.fetchMe()
        }
        async let shelvesTask = api.fetchHomeSelections()
        async let libTask = api.fetchLibraryPlaylistsAndAlbums()
        async let followTask = api.fetchFollowing()
        async let likesTask = api.fetchLikes(limit: 40)

        let (loadedShelves, lib, following, likesRes) = await (shelvesTask, libTask, followTask, likesTask)
        self.shelves = loadedShelves
        self.likesPreview = likesRes.tracks
        self.quickCards = api.fetchQuickCards(playlists: lib.playlists, following: following)
        isLoading = false
    }
}
