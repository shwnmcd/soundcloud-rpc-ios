const { net, session } = require('electron');

/**
 * Authenticated SoundCloud API v2 Proxy (runs in Electron main process via Chromium net.fetch!)
 * Uses Chromium's real TLS stack + session cookies (datadome, oauth_token) + automatic client_id refresh!
 */
class SoundCloudDesktopAPI {
  constructor(getAuth, onClientIdRefreshed = null) {
    this.getAuth = getAuth;
    this.onClientIdRefreshed = onClientIdRefreshed;
    this.currentUser = null;
    this._refreshPromise = null;
  }

  cleanToken(raw) {
    let t = String(raw || '').trim();
    if (!t) return '';
    try { t = decodeURIComponent(t); } catch {}
    return t.replace(/^["']|["']$/g, '').trim();
  }

  async refreshClientId() {
    if (this._refreshPromise) return this._refreshPromise;
    this._refreshPromise = (async () => {
      try {
        const homeResp = await net.fetch('https://soundcloud.com', {
          session: session.defaultSession,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36'
          }
        });
        const html = await homeResp.text();
        const scriptMatches = [...html.matchAll(/https:\/\/a-v2\.sndcdn\.com\/assets\/[^"'\s]+\.js/g)].map((m) => m[0]);
        const candidates = scriptMatches.reverse().slice(0, 10);
        for (const scriptUrl of candidates) {
          try {
            const jsResp = await net.fetch(scriptUrl, { session: session.defaultSession });
            const js = await jsResp.text();
            const m = js.match(/client_id\s*[:=]\s*["']?([a-zA-Z0-9_-]{24,40})["']?/);
            if (m && m[1]) {
              this.onClientIdRefreshed?.(m[1]);
              return m[1];
            }
          } catch {}
        }
      } catch {}
      return null;
    })();
    try {
      return await this._refreshPromise;
    } finally {
      this._refreshPromise = null;
    }
  }

  async request(urlString, { method = 'GET', jsonBody = null, allowRetry = true } = {}) {
    let { oauthToken, clientId } = this.getAuth();
    oauthToken = this.cleanToken(oauthToken);
    if (!clientId) {
      clientId = (await this.refreshClientId()) || '';
    }

    const u = new URL(urlString);
    if (!u.searchParams.has('client_id') && clientId) {
      u.searchParams.set('client_id', clientId);
    }
    if (!u.searchParams.has('app_version')) {
      u.searchParams.set('app_version', '1732000000');
    }
    if (!u.searchParams.has('app_locale')) {
      u.searchParams.set('app_locale', 'en');
    }

    const headers = {
      Accept: 'application/json, text/javascript, */*; q=0.01',
      Origin: 'https://soundcloud.com',
      Referer: 'https://soundcloud.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36'
    };
    if (oauthToken) {
      headers.Authorization = `OAuth ${oauthToken}`;
    }
    let body;
    if (jsonBody !== null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
      body = JSON.stringify(jsonBody);
    }

    const resp = await net.fetch(u.toString(), {
      method,
      headers,
      body,
      credentials: 'include',
      session: session.defaultSession,
      cache: 'no-store'
    });

    if (!resp.ok) {
      if ((resp.status === 401 || resp.status === 403) && allowRetry) {
        const fresh = await this.refreshClientId();
        if (fresh) {
          return this.request(urlString, { method, jsonBody, allowRetry: false });
        }
      }
      throw new Error(`SoundCloud HTTP ${resp.status}`);
    }
    const text = await resp.text();
    if (!text) return {};
    try { return JSON.parse(text); } catch { return {}; }
  }

  normalizePlaylist(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const title = (raw.title || raw.short_title || '').trim();
    const numericId = typeof raw.id === 'number' ? raw.id : null;
    const id = numericId ?? String(raw.urn || raw.id || '');
    const tracks = Array.isArray(raw.tracks) ? raw.tracks : [];
    const firstArt = tracks.find((t) => t && (t.artwork_url || t.user?.avatar_url));
    const artwork =
      raw.artwork_url ||
      raw.calculated_artwork_url ||
      firstArt?.artwork_url ||
      firstArt?.user?.avatar_url ||
      raw.user?.avatar_url ||
      '';

    return {
      id,
      numericId,
      title,
      hasRealTitle: title.length > 0,
      artwork_url: artwork,
      permalink_url: raw.permalink_url || '',
      track_count: raw.track_count ?? tracks.length ?? 0,
      duration: raw.duration || 0,
      is_album: Boolean(raw.is_album),
      sharing: raw.sharing || 'public',
      user: raw.user || null,
      tracks
    };
  }

  async fetchMe() {
    try {
      const me = await this.request('https://api-v2.soundcloud.com/me');
      this.currentUser = me;
      return me;
    } catch {
      return null;
    }
  }

  async fetchHomeSelections() {
    try {
      const root = await this.request('https://api-v2.soundcloud.com/mixed-selections?variant_ids=&limit=12');
      const col = Array.isArray(root.collection) ? root.collection : [];
      const shelves = [];
      for (const item of col) {
        const items = Array.isArray(item?.items?.collection) ? item.items.collection : [];
        const playlists = items
          .map((e) => this.normalizePlaylist(e))
          .filter((p) => p && p.hasRealTitle);
        if (playlists.length > 0) {
          shelves.push({
            id: item.urn || `shelf-${shelves.length}`,
            title: item.title || 'Recommended',
            playlists
          });
        }
      }
      return shelves;
    } catch {
      return [];
    }
  }

  async fetchLikes(nextHref = null, limit = 80) {
    if (!this.currentUser) await this.fetchMe();
    const uid = this.currentUser?.id;
    if (!uid) return { tracks: [], nextHref: null };
    const url = nextHref || `https://api-v2.soundcloud.com/users/${uid}/track_likes?limit=${limit}&linked_partitioning=1`;
    try {
      const root = await this.request(url);
      const col = Array.isArray(root.collection) ? root.collection : [];
      const tracks = col.map((e) => e?.track).filter(Boolean);
      return { tracks, nextHref: root.next_href || null };
    } catch {
      return { tracks: [], nextHref: null };
    }
  }

  async fetchLibraryPlaylistsAndAlbums() {
    if (!this.currentUser) await this.fetchMe();
    const uid = this.currentUser?.id;

    const [allRes, createdRes, likedRes, albumsRes] = await Promise.allSettled([
      this.request('https://api-v2.soundcloud.com/me/library/all?limit=100'),
      uid ? this.request(`https://api-v2.soundcloud.com/users/${uid}/playlists_without_albums?limit=100`) : Promise.resolve({}),
      uid ? this.request(`https://api-v2.soundcloud.com/users/${uid}/playlist_likes?limit=100`) : Promise.resolve({}),
      uid ? this.request(`https://api-v2.soundcloud.com/users/${uid}/albums?limit=100`) : Promise.resolve({})
    ]);

    const extract = (settled, unwrapKey = null) => {
      if (settled.status !== 'fulfilled') return [];
      const col = Array.isArray(settled.value?.collection) ? settled.value.collection : [];
      return col
        .map((e) => {
          if (unwrapKey === 'library') return this.normalizePlaylist(e?.playlist || e?.system_playlist);
          if (unwrapKey === 'playlist') return this.normalizePlaylist(e?.playlist || e);
          return this.normalizePlaylist(e);
        })
        .filter(Boolean);
    };

    const byId = new Map();
    const orderedIds = [];

    const merge = (list) => {
      for (const pl of list) {
        const key = String(pl.id);
        const existing = byId.get(key);
        if (existing) {
          const oldScore = (existing.hasRealTitle ? 10 : 0) + (existing.artwork_url ? 4 : 0) + (existing.tracks?.length || 0);
          const newScore = (pl.hasRealTitle ? 10 : 0) + (pl.artwork_url ? 4 : 0) + (pl.tracks?.length || 0);
          if (newScore > oldScore) byId.set(key, pl);
        } else {
          orderedIds.push(key);
          byId.set(key, pl);
        }
      }
    };

    merge(extract(createdRes));
    merge(extract(likedRes, 'playlist'));
    merge(extract(albumsRes));
    merge(extract(allRes, 'library'));

    // Hydrate any stub playlists missing a title
    const missing = orderedIds
      .map((k) => byId.get(k))
      .filter((p) => p && !p.hasRealTitle && p.numericId)
      .slice(0, 20);

    await Promise.allSettled(
      missing.map(async (stub) => {
        const full = await this.request(`https://api-v2.soundcloud.com/playlists/${stub.numericId}`);
        const norm = this.normalizePlaylist(full);
        if (norm && norm.hasRealTitle) byId.set(String(norm.id), norm);
      })
    );

    // Hydrate missing cover art from first stub track
    const needArt = [];
    for (const k of orderedIds) {
      const p = byId.get(k);
      if (p && p.hasRealTitle && !p.artwork_url && p.tracks?.length > 0 && p.tracks[0]?.id) {
        needArt.push({ key: k, trackId: p.tracks[0].id });
      }
    }
    if (needArt.length > 0) {
      const ids = [...new Set(needArt.map((x) => x.trackId))].slice(0, 50).join(',');
      try {
        const loaded = await this.request(`https://api-v2.soundcloud.com/tracks?ids=${ids}`);
        if (Array.isArray(loaded)) {
          const artMap = new Map(loaded.map((t) => [t.id, t.artwork_url || t.user?.avatar_url || '']));
          for (const item of needArt) {
            const art = artMap.get(item.trackId);
            if (art) byId.get(item.key).artwork_url = art;
          }
        }
      } catch {}
    }

    const playlists = [];
    const albums = [];
    for (const k of orderedIds) {
      const pl = byId.get(k);
      if (!pl || !pl.hasRealTitle) continue;
      if (pl.is_album) albums.push(pl);
      else playlists.push(pl);
    }

    return { playlists, albums };
  }

  async fetchFullPlaylistTracks(playlistId, fallbackTracks = []) {
    try {
      if (typeof playlistId !== 'number' && !/^\d+$/.test(String(playlistId))) {
        const hydrated = await this.hydrateTracks(fallbackTracks);
        return { playlist: null, tracks: hydrated };
      }
      const pl = await this.request(`https://api-v2.soundcloud.com/playlists/${playlistId}?representation=full`);
      const hydrated = await this.hydrateTracks(Array.isArray(pl.tracks) ? pl.tracks : []);
      return { playlist: this.normalizePlaylist(pl), tracks: hydrated };
    } catch {
      return { playlist: null, tracks: fallbackTracks };
    }
  }

  async hydrateTracks(tracks) {
    if (!Array.isArray(tracks) || tracks.length === 0) return [];
    const stubIds = tracks.filter((t) => t && !t.title && t.id).map((t) => t.id);
    if (stubIds.length === 0) return tracks.filter((t) => t && t.title);

    const map = new Map();
    for (let i = 0; i < stubIds.length; i += 50) {
      const batch = stubIds.slice(i, i + 50).join(',');
      try {
        const loaded = await this.request(`https://api-v2.soundcloud.com/tracks?ids=${batch}`);
        if (Array.isArray(loaded)) {
          for (const t of loaded) map.set(t.id, t);
        }
      } catch {}
    }
    return tracks.map((t) => (t?.title ? t : map.get(t?.id))).filter(Boolean);
  }

  async fetchFeed(nextHref = null) {
    const url = nextHref || 'https://api-v2.soundcloud.com/stream?limit=30&linked_partitioning=1';
    try {
      const root = await this.request(url);
      const col = Array.isArray(root.collection) ? root.collection : [];
      const items = [];
      for (const e of col) {
        const type = String(e?.type || 'track');
        if (type.includes('promoted') || type.includes('ad')) continue;
        if (e.track) {
          items.push({ type, isRepost: type.includes('repost'), reposter: e.user || null, track: e.track, playlist: null });
        } else if (e.playlist) {
          const pl = this.normalizePlaylist(e.playlist);
          if (pl?.hasRealTitle) {
            items.push({ type, isRepost: type.includes('repost'), reposter: e.user || null, track: null, playlist: pl });
          }
        }
      }
      return { items, nextHref: root.next_href || null };
    } catch {
      return { items: [], nextHref: null };
    }
  }

  async fetchHistory() {
    try {
      const root = await this.request('https://api-v2.soundcloud.com/me/play-history/tracks?limit=50');
      const tracks = (root.collection || []).map((e) => e?.track).filter(Boolean);
      if (tracks.length > 0) return tracks;
    } catch {}
    try {
      const root = await this.request('https://api-v2.soundcloud.com/me/play-history?limit=50');
      return (root.collection || []).map((e) => e?.track).filter(Boolean);
    } catch {
      return [];
    }
  }

  async fetchFollowing() {
    if (!this.currentUser) await this.fetchMe();
    const uid = this.currentUser?.id;
    if (!uid) return [];
    try {
      const root = await this.request(`https://api-v2.soundcloud.com/users/${uid}/followings?limit=100`);
      return Array.isArray(root.collection) ? root.collection : [];
    } catch {
      return [];
    }
  }

  async fetchArtistProfile(userId) {
    const [u, spot, top, albs, pls, trks, reps, lks] = await Promise.allSettled([
      this.request(`https://api-v2.soundcloud.com/users/${userId}`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/spotlight?limit=15`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/toptracks?limit=25`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/albums?limit=20`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/playlists_without_albums?limit=20`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/tracks?limit=40`),
      this.request(`https://api-v2.soundcloud.com/stream/users/${userId}/reposts?limit=25`),
      this.request(`https://api-v2.soundcloud.com/users/${userId}/track_likes?limit=25`)
    ]);

    const col = (res) => (res.status === 'fulfilled' && Array.isArray(res.value?.collection) ? res.value.collection : []);
    const spotCol = col(spot);

    return {
      user: u.status === 'fulfilled' ? u.value : null,
      spotlightTracks: spotCol.filter((e) => e?.kind === 'track'),
      spotlightPlaylists: spotCol.filter((e) => e?.kind === 'playlist').map((e) => this.normalizePlaylist(e)).filter((p) => p?.hasRealTitle),
      topTracks: col(top),
      albums: col(albs).map((e) => this.normalizePlaylist(e)).filter((p) => p?.hasRealTitle),
      playlists: col(pls).map((e) => this.normalizePlaylist(e)).filter((p) => p?.hasRealTitle),
      tracks: col(trks),
      reposts: col(reps).map((e) => e?.track).filter(Boolean),
      likes: col(lks).map((e) => e?.track).filter(Boolean)
    };
  }

  async search(query, filter = 'all') {
    const q = encodeURIComponent(String(query || '').trim());
    if (!q) return { tracks: [], users: [], playlists: [] };
    const endpoints = {
      all: `https://api-v2.soundcloud.com/search?q=${q}&limit=30`,
      tracks: `https://api-v2.soundcloud.com/search/tracks?q=${q}&limit=30`,
      people: `https://api-v2.soundcloud.com/search/users?q=${q}&limit=30`,
      albums: `https://api-v2.soundcloud.com/search/albums?q=${q}&limit=30`,
      sets: `https://api-v2.soundcloud.com/search/playlists_without_albums?q=${q}&limit=30`
    };
    try {
      const root = await this.request(endpoints[filter] || endpoints.all);
      const col = Array.isArray(root.collection) ? root.collection : [];
      const tracks = [];
      const users = [];
      const playlists = [];
      for (const e of col) {
        if (e?.kind === 'track') tracks.push(e);
        else if (e?.kind === 'user') users.push(e);
        else if (e?.kind === 'playlist') {
          const pl = this.normalizePlaylist(e);
          if (pl?.hasRealTitle) playlists.push(pl);
        }
      }
      return { tracks, users, playlists };
    } catch {
      return { tracks: [], users: [], playlists: [] };
    }
  }

  async toggleLike(trackId, currentlyLiked) {
    if (!this.currentUser) await this.fetchMe();
    const uid = this.currentUser?.id;
    if (!uid) return currentlyLiked;
    const method = currentlyLiked ? 'DELETE' : 'PUT';
    try {
      await this.request(`https://api-v2.soundcloud.com/users/${uid}/track_likes/${trackId}`, { method });
      return !currentlyLiked;
    } catch {
      try {
        await this.request(`https://api-v2.soundcloud.com/me/track_likes/${trackId}`, { method });
        return !currentlyLiked;
      } catch {
        return currentlyLiked;
      }
    }
  }

  async toggleFollow(userId, currentlyFollowing) {
    const method = currentlyFollowing ? 'DELETE' : 'PUT';
    try {
      await this.request(`https://api-v2.soundcloud.com/me/followings/${userId}`, { method });
      return !currentlyFollowing;
    } catch {
      return currentlyFollowing;
    }
  }

  async createPlaylist(title, isPrivate, initialTrackId = null) {
    const clean = String(title || '').trim();
    if (!clean) return null;
    const body = {
      playlist: {
        title: clean,
        sharing: isPrivate ? 'private' : 'public',
        tracks: initialTrackId ? [initialTrackId] : []
      }
    };
    const created = await this.request('https://api-v2.soundcloud.com/playlists', { method: 'POST', jsonBody: body });
    return this.normalizePlaylist(created);
  }

  async addTrackToPlaylist(playlistId, trackId) {
    const full = await this.fetchFullPlaylistTracks(playlistId);
    const ids = full.tracks.map((t) => t.id);
    if (!ids.includes(trackId)) ids.push(trackId);
    await this.request(`https://api-v2.soundcloud.com/playlists/${playlistId}`, {
      method: 'PUT',
      jsonBody: { playlist: { tracks: ids } }
    });
    return true;
  }

  async resolveStreamUrl(track) {
    let transcodings = track?.media?.transcodings || [];
    let trackAuth = track?.track_authorization;

    if (transcodings.length === 0 && track?.id) {
      try {
        const full = await this.request(`https://api-v2.soundcloud.com/tracks/${track.id}`);
        transcodings = full?.media?.transcodings || [];
        trackAuth = full?.track_authorization;
      } catch {}
    }

    const candidates = transcodings
      .filter((t) => t?.format?.protocol === 'progressive' || t?.format?.protocol === 'hls')
      .sort((a, b) => this.scoreTranscoding(b) - this.scoreTranscoding(a));

    for (const tc of candidates) {
      if (!tc.url) continue;
      let target = tc.url;
      if (trackAuth) {
        target += (target.includes('?') ? '&' : '?') + `track_authorization=${encodeURIComponent(trackAuth)}`;
      }
      try {
        const res = await this.request(target);
        if (res?.url) {
          return { url: res.url, protocol: tc.format.protocol };
        }
      } catch {}
    }
    return null;
  }

  scoreTranscoding(t) {
    let score = t.snipped ? 0 : 100;
    const proto = t?.format?.protocol || '';
    const mime = t?.format?.mime_type || '';
    // Progressive MP3 gives instantaneous native <audio> playback + real Web Audio FFT!
    if (proto === 'progressive') score += 60;
    else if (proto === 'hls' && mime.includes('mpeg')) score += 50;
    else if (proto === 'hls' && mime.includes('mp4')) score += 40;
    else if (proto === 'hls') score += 20;
    return score;
  }
}

module.exports = { SoundCloudDesktopAPI };
