const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('scDesktop', {
  init: () => ipcRenderer.invoke('store:init'),
  updateSettings: (patch) => ipcRenderer.invoke('settings:update', patch),
  openLogin: () => ipcRenderer.invoke('auth:login'),
  signOut: () => ipcRenderer.invoke('auth:signout'),

  // SoundCloud API v2
  fetchMe: () => ipcRenderer.invoke('sc:me'),
  fetchHome: () => ipcRenderer.invoke('sc:home'),
  fetchLikes: (nextHref = null, limit = 80) => ipcRenderer.invoke('sc:likes', { nextHref, limit }),
  fetchLibrary: () => ipcRenderer.invoke('sc:library'),
  fetchPlaylistTracks: (playlistId, fallbackTracks = []) =>
    ipcRenderer.invoke('sc:playlistTracks', { playlistId, fallbackTracks }),
  fetchFeed: (nextHref = null) => ipcRenderer.invoke('sc:feed', { nextHref }),
  fetchHistory: () => ipcRenderer.invoke('sc:history'),
  fetchFollowing: () => ipcRenderer.invoke('sc:following'),
  fetchArtist: (userId) => ipcRenderer.invoke('sc:artist', userId),
  search: (query, filter = 'all') => ipcRenderer.invoke('sc:search', { query, filter }),
  toggleLike: (trackId, currentlyLiked) => ipcRenderer.invoke('sc:toggleLike', { trackId, currentlyLiked }),
  toggleFollow: (userId, currentlyFollowing) => ipcRenderer.invoke('sc:toggleFollow', { userId, currentlyFollowing }),
  createPlaylist: (title, isPrivate, initialTrackId = null) =>
    ipcRenderer.invoke('sc:createPlaylist', { title, isPrivate, initialTrackId }),
  addTrackToPlaylist: (playlistId, trackId) =>
    ipcRenderer.invoke('sc:addTrackToPlaylist', { playlistId, trackId }),
  resolveStream: (track) => ipcRenderer.invoke('sc:resolveStream', track),

  // Discord RPC + Last.fm + Webhooks + Jam Relay
  syncPlayback: (payload) => ipcRenderer.invoke('playback:sync', payload),
  testWebhook: () => ipcRenderer.invoke('integrations:testWebhook'),
  openExternal: (url) => ipcRenderer.invoke('shell:openExternal', url),
  jamPublish: (url, bodyText) => ipcRenderer.invoke('jam:publish', { url, bodyText }),

  // Install / uninstall & auto-updater
  getAppInfo: () => ipcRenderer.invoke('app:info'),
  uninstallApp: () => ipcRenderer.invoke('app:uninstall'),
  showInstallFolder: () => ipcRenderer.invoke('app:showInstallFolder'),
  checkUpdates: () => ipcRenderer.invoke('updater:check'),
  installUpdate: (downloadUrl) => ipcRenderer.invoke('updater:install', downloadUrl),
  onUpdaterProgress: (cb) => ipcRenderer.on('updater-progress', (_e, data) => cb(data)),

  // Push events from Main
  onAuthUpdated: (cb) => ipcRenderer.on('auth-updated', (_e, data) => cb(data)),
  onRpcStatus: (cb) => ipcRenderer.on('rpc-status', (_e, data) => cb(data)),
  onMediaCommand: (cb) => ipcRenderer.on('media-command', (_e, cmd) => cb(cmd)),
  onDeepLink: (cb) => ipcRenderer.on('deep-link', (_e, url) => cb(url))
});
