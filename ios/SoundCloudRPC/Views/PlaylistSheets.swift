import SwiftUI
import PhotosUI
import UIKit

// MARK: - Create New SoundCloud Playlist Sheet (Syncs Title, Privacy, Initial Track & Cover Image!)
struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI

    var initialTrack: SCTrack? = nil
    var onCreated: ((SCPlaylist) -> Void)? = nil

    @State private var title: String = ""
    @State private var isPrivate: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var previewImage: UIImage? = nil
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cover Image Picker (Syncs Directly with SoundCloud!)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let uiImg = previewImage {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else if let trackArt = initialTrack?.rawArtwork {
                                    HDArtworkView(rawUrl: trackArt, cornerRadius: 14)
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(theme.surfaceElevated)
                                        .overlay(
                                            VStack(spacing: 6) {
                                                Image(systemName: "photo.badge.plus")
                                                    .font(.system(size: 32, weight: .medium))
                                                    .foregroundColor(theme.accent)
                                                Text("Add Cover")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(theme.textSecondary)
                                            }
                                        )
                                }
                            }
                            .frame(width: 164, height: 164)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(theme.pillStroke, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.12), radius: 14, y: 6)

                            Circle()
                                .fill(theme.accent)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 6, y: 6)
                        }
                    }
                    .padding(.top, 10)
                    .onChange(of: selectedPhotoItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                self.selectedImageData = data
                                self.previewImage = UIImage(data: data)
                            }
                        }
                    }

                    // Playlist Title Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYLIST NAME")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textSecondary)
                            .tracking(0.6)

                        TextField("My SoundCloud Mix...", text: $title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(theme.pillStroke, lineWidth: 1)
                            )
                    }

                    // Privacy Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private Playlist")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.textPrimary)
                            Text(isPrivate ? "Only visible to you on SoundCloud" : "Public on your SoundCloud profile")
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isPrivate)
                            .labelsHidden()
                            .tint(theme.accent)
                    }
                    .padding(14)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let track = initialTrack {
                        HStack(spacing: 10) {
                            HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 6)
                                .frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Including track")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(theme.accent)
                                Text(track.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(theme.textPrimary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        Task { await createNow() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "icloud.and.arrow.up.fill")
                                Text("Create & Sync to SoundCloud")
                            }
                        }
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.accent.opacity(0.45) : theme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
                .padding(20)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createNow() async {
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let created = await api.createPlaylist(
            title: title,
            isPrivate: isPrivate,
            initialTrack: initialTrack,
            coverImageData: selectedImageData
        )
        isSubmitting = false
        if let created {
            onCreated?(created)
            dismiss()
        }
    }
}

// MARK: - Add Track to Existing SoundCloud Playlist Sheet
struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI

    let track: SCTrack

    @State private var showingCreateSheet = false
    @State private var addingPlaylistId: Int? = nil

    private var editablePlaylists: [SCPlaylist] {
        guard let meId = api.currentUser?.id else { return api.userPlaylists }
        let owned = api.userPlaylists.filter { $0.user?.id == meId }
        return owned.isEmpty ? api.userPlaylists : owned
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Track Header Preview
                    HStack(spacing: 12) {
                        HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 8)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                            Text(track.artistName)
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                    // Create New Playlist CTA
                    Button {
                        showingCreateSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.accent.opacity(0.16))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create New Playlist")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(theme.textPrimary)
                                Text("Adds this track & syncs to SoundCloud")
                                    .font(.caption)
                                    .foregroundColor(theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(theme.textTertiary)
                        }
                        .padding(10)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .padding(.horizontal, 16)

                    if editablePlaylists.isEmpty {
                        Text("No playlists found yet. Create your first playlist above!")
                            .font(.subheadline)
                            .foregroundColor(theme.textSecondary)
                            .padding(24)
                    } else {
                        Text("YOUR SOUNDCLOUD PLAYLISTS")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textSecondary)
                            .tracking(0.6)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        LazyVStack(spacing: 4) {
                            ForEach(editablePlaylists) { pl in
                                Button {
                                    Task {
                                        addingPlaylistId = pl.id
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        _ = await api.addTrack(track, to: pl)
                                        addingPlaylistId = nil
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        HDArtworkView(rawUrl: api.resolvedArtwork(for: pl), cornerRadius: 8)
                                            .frame(width: 50, height: 50)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pl.displayTitle)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(theme.textPrimary)
                                                .lineLimit(1)
                                            Text("\(pl.resolvedTrackCount) tracks")
                                                .font(.caption)
                                                .foregroundColor(theme.textSecondary)
                                        }

                                        Spacer()

                                        if addingPlaylistId == pl.id {
                                            ProgressView().tint(theme.accent)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.97))
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if api.userPlaylists.isEmpty {
                    _ = await api.fetchLibraryPlaylistsAndAlbums()
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreatePlaylistSheet(initialTrack: track) { _ in
                    dismiss()
                }
                .environment(\.scTheme, theme)
            }
        }
    }
}
