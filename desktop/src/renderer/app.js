(() => {
  const api = window.scDesktop;

  // MARK: - App State
  const state = {
    isLoggedIn: false,
    version: '2.7.0',
    rpcConnected: false,
    user: null,
    settings: {},
    nav: 'home', // home, feed, search, likes, playlists, albums, following, history, playlistDetail, artistProfile
    detailPlaylist: null,
    detailArtist: null,
    shelves: [],
    feed: [],
    likes: [],
    likedIds: new Set(),
    playlists: [],
    albums: [],
    following: [],
    followingIds: new Set(),
    history: [],
    searchQuery: '',
    searchFilter: 'all',
    searchResults: { tracks: [], users: [], playlists: [] },
    isLoadingView: false,

    // Playback
    queue: [],
    originalQueue: [],
    currentIndex: 0,
    currentTrack: null,
    isPlaying: false,
    isShuffling: false,
    repeatMode: 'none', // none, all, one
    elapsedSec: 0,
    durationSec: 0,
    isScrubbing: false,
    isApplyingRemoteJam: false,
    hls: null,
    vinylAngle: 0,
    lastVinylTick: performance.now(),
    modalType: null // jam | settings | createPlaylist | addToPlaylist
  };

  const audio = document.getElementById('audio-player');
  const $ = (id) => document.getElementById(id);

  // MARK: - Helpers
  function esc(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function artUrl(raw, size = 't500x500') {
    if (!raw) return 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="#222228"/><path d="M28 60V42M40 68V32M52 72V28M64 66V36M76 58V44" stroke="#ff5500" stroke-width="6" stroke-linecap="round"/></svg>');
    return String(raw)
      .replace('-large.', `-${size}.`)
      .replace('-t50x50.', `-${size}.`)
      .replace('-t200x200.', `-${size}.`)
      .replace('-t300x300.', `-${size}.`);
  }

  function fmtSec(sec) {
    const s = Math.max(0, Math.floor(sec || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}` : `${m}:${String(r).padStart(2, '0')}`;
  }

  function fmtCount(n) {
    if (!n || n <= 0) return '';
    if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
    if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
    return String(n);
  }

  function normalizeTrackInfo(title, artist) {
    const cleanTitle = String(title || 'Untitled Track').split('\n')[0].trim();
    const fallbackArtist = String(artist || 'Unknown Artist').trim();
    if (!state.settings.trackParserEnabled) return { artist: fallbackArtist, title: cleanTitle };
    const m = cleanTitle.match(/^(.+?)\s+[-–—]\s+(.+)$/);
    if (m && m[1].trim().length > 0 && m[2].trim().length > 0) {
      return { artist: m[1].trim(), title: m[2].trim() };
    }
    return { artist: fallbackArtist, title: cleanTitle };
  }

  let toastTimer = null;
  function showToast(msg) {
    const el = $('toast');
    el.textContent = msg;
    el.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add('hidden'), 2500);
  }

  function spawnFloatingReaction({ emoji, senderName }) {
    const layer = $('reactions-layer');
    const div = document.createElement('div');
    div.className = 'floating-emoji';
    div.style.left = `${16 + Math.random() * 68}%`;
    div.innerHTML = `${esc(emoji)}<span>${esc(senderName || 'Friend')}</span>`;
    layer.appendChild(div);
    setTimeout(() => div.remove(), 2000);
  }

  // MARK: - Theme Application
  function applyTheme() {
    let mode = state.settings.themeMode || 'dark';
    if (mode === 'system') {
      mode = window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    }
    document.body.setAttribute('data-theme', mode);
    document.body.setAttribute('data-accent', state.settings.accentPreset || 'orange');
  }

  // MARK: - VFD Visualizer Engine
  const vfdEngine = new window.VFDVisualizerEngine(
    $('vfd-canvas'),
    () => ({
      isPlaying: state.isPlaying,
      elapsedSec: state.elapsedSec,
      durationSec: state.durationSec,
      trackId: state.currentTrack?.id || 0
    }),
    () => state.settings
  );

  // MARK: - Worldwide Group Jam Engine
  const jam = new window.DesktopJamManager({
    getRelayUrl: () => state.settings.jamRelayUrl || 'https://ntfy.sh',
    getDisplayName: () => state.user?.username || state.user?.full_name || 'Windows Listener',
    getAvatarUrl: () => state.user?.avatar_url || null,
    getCurrentTrack: () => state.currentTrack,
    getQueue: () => state.queue,
    getIsPlaying: () => state.isPlaying,
    getElapsedSec: () => state.elapsedSec,
    onApplyRemoteState: async (track, queueTracks, shouldPlay, targetPos) => {
      state.isApplyingRemoteJam = true;
      try {
        const merged = queueTracks.length ? queueTracks : [track];
        state.queue = merged;
        state.originalQueue = merged;
        const idx = Math.max(0, merged.findIndex((t) => Number(t.id) === Number(track.id)));
        if (Number(state.currentTrack?.id) !== Number(track.id)) {
          await loadTrackAt(idx, { initialSeekSec: targetPos, autoPlay: shouldPlay, notifyJam: false });
        } else {
          state.currentIndex = idx;
          if (Math.abs(audio.currentTime - targetPos) > 1.8) {
            audio.currentTime = Math.max(0, targetPos);
            state.elapsedSec = audio.currentTime;
          }
          if (shouldPlay && audio.paused) {
            audio.play().catch(() => {});
          } else if (!shouldPlay && !audio.paused) {
            audio.pause();
          }
        }
      } finally {
        state.isApplyingRemoteJam = false;
      }
      renderPlayerUI();
    },
    onApplyGuestControl: (action, trackRef, seekSec) => {
      if (action === 'play' && audio.paused) togglePlayPause();
      else if (action === 'pause' && !audio.paused) togglePlayPause();
      else if (action === 'next') nextTrack();
      else if (action === 'prev') prevTrack(true);
      else if (action === 'seek' && typeof seekSec === 'number') seekToSeconds(seekSec, true);
      else if (action === 'track' && trackRef) {
        const t = window.DesktopJamManager.refToTrack(trackRef);
        const merged = [t, ...state.queue.filter((x) => Number(x.id) !== Number(t.id))];
        playTrack(t, merged);
      }
    },
    onHostAppendQueue: (track) => {
      if (!state.queue.length) {
        playTrack(track, [track]);
      } else if (!state.queue.some((x) => Number(x.id) === Number(track.id))) {
        state.queue.push(track);
        state.originalQueue.push(track);
      }
    },
    onReaction: (burst) => spawnFloatingReaction(burst),
    onToast: (msg) => showToast(msg),
    onUpdate: () => {
      updateJamIndicators();
      if (state.modalType === 'jam') renderJamModal();
    }
  });

  function updateJamIndicators() {
    const sideBtn = $('btn-open-jam');
    const label = $('jam-btn-label');
    const barTag = $('bar-jam-tag');
    const npJam = $('btn-np-jam');
    const barLock = $('bar-lock-note');
    const npLock = $('np-lock-banner');

    if (jam.isActive) {
      sideBtn.classList.add('live');
      label.textContent = `Live Jam · ${jam.listenerCount}`;
      barTag.classList.remove('hidden');
      barTag.textContent = `JAM · ${jam.listenerCount}`;
      npJam.classList.remove('hidden');
      npJam.textContent = `● JAM · ${jam.listenerCount}`;
    } else {
      sideBtn.classList.remove('live');
      label.textContent = 'Group Jam';
      barTag.classList.add('hidden');
      npJam.classList.add('hidden');
    }

    const locked = jam.isGuestLocked;
    barLock.classList.toggle('hidden', !locked);
    npLock.classList.toggle('hidden', !locked);
    $('scrubber').disabled = locked;
    $('np-scrubber').disabled = locked;
    $('btn-play').textContent = locked ? '🔒' : state.isPlaying ? '❚❚' : '▶';
    $('np-play').textContent = locked ? '🔒' : state.isPlaying ? '❚❚' : '▶';
    $('vfd-play').textContent = locked ? '🔒' : state.isPlaying ? '❚❚' : '▶';
  }

  // MARK: - Playback Engine (Ad-Free HLS + Progressive + Discord RPC Sync!)
  async function playTrack(track, list = [track], shuffle = false) {
    if (jam.isGuestLocked) {
      showToast('Host controls playback in this Jam');
      return;
    }
    const source = Array.isArray(list) && list.length ? [...list] : [track];
    state.originalQueue = source;
    if (shuffle) {
      state.isShuffling = true;
      const rest = source.filter((t) => Number(t.id) !== Number(track.id)).sort(() => Math.random() - 0.5);
      state.queue = [track, ...rest];
      state.currentIndex = 0;
    } else {
      state.isShuffling = false;
      state.queue = source;
      state.currentIndex = Math.max(0, source.findIndex((t) => Number(t.id) === Number(track.id)));
    }
    await loadTrackAt(state.currentIndex, { autoPlay: true, notifyJam: true });
  }

  function playShuffled(list) {
    if (!Array.isArray(list) || !list.length) return;
    const shuffled = [...list].sort(() => Math.random() - 0.5);
    playTrack(shuffled[0], shuffled, true);
  }

  async function loadTrackAt(index, { initialSeekSec = 0, autoPlay = true, notifyJam = true } = {}) {
    if (index < 0 || index >= state.queue.length) return;
    const track = state.queue[index];
    state.currentIndex = index;
    state.currentTrack = track;
    state.elapsedSec = initialSeekSec || 0;
    state.durationSec = Math.max(1, Math.floor((track.duration || 0) / 1000));
    renderPlayerUI();
    renderCurrentViewTracksState();

    const stream = await api.resolveStream(track);
    if (!stream || !stream.url) {
      if (!state.isApplyingRemoteJam && index + 1 < state.queue.length) {
        return loadTrackAt(index + 1);
      }
      showToast('Track unavailable on SoundCloud');
      return;
    }

    if (state.hls) {
      state.hls.destroy();
      state.hls = null;
    }

    vfdEngine.attachAudioElement(audio);
    vfdEngine.resumeAudioContext();

    if (stream.protocol === 'hls' && window.Hls && window.Hls.isSupported()) {
      const hls = new window.Hls({ enableWorker: true });
      state.hls = hls;
      hls.loadSource(stream.url);
      hls.attachMedia(audio);
      await new Promise((resolve) => {
        hls.once(window.Hls.Events.MANIFEST_PARSED, resolve);
        setTimeout(resolve, 1800);
      });
    } else {
      audio.src = stream.url;
    }

    if (initialSeekSec > 0.4) {
      audio.currentTime = initialSeekSec;
    }

    if (autoPlay) {
      await audio.play().catch(() => {});
      state.isPlaying = !audio.paused;
    } else {
      audio.pause();
      state.isPlaying = false;
    }

    renderPlayerUI();
    syncDesktopServices();
    if (notifyJam && !state.isApplyingRemoteJam) {
      jam.onLocalPlaybackChange('track', state.elapsedSec);
    }
  }

  function togglePlayPause() {
    if (jam.isGuestLocked) {
      showToast('Host controls playback in this Jam');
      return;
    }
    if (!state.currentTrack) return;
    vfdEngine.resumeAudioContext();
    if (audio.paused) {
      audio.play().catch(() => {});
      state.isPlaying = true;
    } else {
      audio.pause();
      state.isPlaying = false;
    }
    renderPlayerUI();
    syncDesktopServices();
    if (!state.isApplyingRemoteJam) {
      jam.onLocalPlaybackChange(state.isPlaying ? 'play' : 'pause', state.elapsedSec);
    }
  }

  function nextTrack() {
    if (jam.isGuestLocked) { showToast('Host controls playback in this Jam'); return; }
    if (!state.queue.length) return;
    if (state.currentIndex + 1 < state.queue.length) {
      loadTrackAt(state.currentIndex + 1);
    } else if (state.repeatMode === 'all') {
      loadTrackAt(0);
    }
  }

  function prevTrack(forcePrev = false) {
    if (jam.isGuestLocked) { showToast('Host controls playback in this Jam'); return; }
    if (!state.queue.length) return;
    if (!forcePrev && state.elapsedSec > 3) {
      seekToSeconds(0, true);
      return;
    }
    if (state.currentIndex > 0) {
      loadTrackAt(state.currentIndex - 1);
    } else if (state.repeatMode === 'all') {
      loadTrackAt(state.queue.length - 1);
    } else {
      seekToSeconds(0, true);
    }
  }

  function seekToSeconds(sec, notifyJam = true) {
    if (jam.isGuestLocked && notifyJam) return;
    const clamped = Math.max(0, Math.min(state.durationSec || sec, sec));
    audio.currentTime = clamped;
    state.elapsedSec = clamped;
    renderPlayerUI();
    syncDesktopServices();
    if (notifyJam && !state.isApplyingRemoteJam) {
      jam.onLocalPlaybackChange('seek', clamped);
    }
  }

  function toggleShuffle() {
    if (jam.isGuestLocked) { showToast('Host controls playback in this Jam'); return; }
    state.isShuffling = !state.isShuffling;
    if (state.currentTrack) {
      if (state.isShuffling) {
        const rest = state.originalQueue.filter((t) => Number(t.id) !== Number(state.currentTrack.id)).sort(() => Math.random() - 0.5);
        state.queue = [state.currentTrack, ...rest];
        state.currentIndex = 0;
      } else {
        state.queue = [...state.originalQueue];
        state.currentIndex = Math.max(0, state.queue.findIndex((t) => Number(t.id) === Number(state.currentTrack.id)));
      }
    }
    renderPlayerUI();
  }

  function cycleRepeat() {
    if (jam.isGuestLocked) { showToast('Host controls playback in this Jam'); return; }
    state.repeatMode = state.repeatMode === 'none' ? 'all' : state.repeatMode === 'all' ? 'one' : 'none';
    renderPlayerUI();
  }

  async function toggleLikeTrack(track) {
    if (!track || !track.id) return;
    const id = Number(track.id);
    const wasLiked = state.likedIds.has(id);
    if (wasLiked) {
      state.likedIds.delete(id);
      state.likes = state.likes.filter((t) => Number(t.id) !== id);
    } else {
      state.likedIds.add(id);
      if (!state.likes.some((t) => Number(t.id) === id)) {
        state.likes.unshift(track);
      }
    }
    renderPlayerUI();
    renderCurrentViewTracksState();
    if (state.modalType === 'jam') renderJamModal();

    const finalLiked = await api.toggleLike(id, wasLiked);
    if (finalLiked) state.likedIds.add(id);
    else state.likedIds.delete(id);
    showToast(finalLiked ? 'Liked & synced to SoundCloud' : 'Removed from SoundCloud likes');
    renderPlayerUI();
    updateSidebarBadges();
  }

  function syncDesktopServices() {
    if (!state.currentTrack) return;
    const norm = normalizeTrackInfo(state.currentTrack.title, state.currentTrack.user?.username || state.currentTrack.user?.full_name);
    api.syncPlayback({
      id: state.currentTrack.id,
      title: norm.title,
      artist: norm.artist,
      artwork: artUrl(state.currentTrack.artwork_url || state.currentTrack.user?.avatar_url, 't500x500'),
      url: state.currentTrack.permalink_url || '',
      elapsedSec: state.elapsedSec,
      durationSec: state.durationSec,
      isPlaying: state.isPlaying,
      jamCode: jam.isActive ? jam.roomCode : ''
    }).catch(() => {});
  }

  // Audio Element Listeners
  audio.volume = 0.85;
  audio.addEventListener('play', () => { state.isPlaying = true; renderPlayerUI(); });
  audio.addEventListener('pause', () => { state.isPlaying = false; renderPlayerUI(); });
  audio.addEventListener('timeupdate', () => {
    if (!state.isScrubbing) {
      state.elapsedSec = audio.currentTime || 0;
      if (audio.duration && Number.isFinite(audio.duration)) {
        state.durationSec = audio.duration;
      }
      updateScrubberDOM();
    }
  });
  audio.addEventListener('ended', () => {
    if (jam.isGuestLocked) return;
    if (state.repeatMode === 'one') {
      seekToSeconds(0, true);
      audio.play().catch(() => {});
    } else {
      nextTrack();
    }
  });

  // Periodic RPC + Last.fm + Webhook sync every 3s while playing
  setInterval(() => {
    if (state.currentTrack && state.isPlaying) syncDesktopServices();
  }, 3000);

  // Smooth 60fps Vinyl Rotation Loop (pauses cleanly in place!)
  function vinylLoop(now) {
    const dt = Math.min(0.05, (now - state.lastVinylTick) / 1000);
    state.lastVinylTick = now;
    if (state.isPlaying && !$('now-playing-overlay').classList.contains('hidden')) {
      state.vinylAngle = (state.vinylAngle + dt * 28) % 360;
      $('vinyl-disc').style.transform = `rotate(${state.vinylAngle}deg)`;
    }
    requestAnimationFrame(vinylLoop);
  }
  requestAnimationFrame(vinylLoop);

  // MARK: - Player & Now Playing Rendering
  function updateScrubberDOM() {
    const frac = state.durationSec > 0 ? Math.min(1, state.elapsedSec / state.durationSec) : 0;
    const val = Math.round(frac * 1000);
    $('scrubber').value = val;
    $('np-scrubber').value = val;
    $('time-elapsed').textContent = fmtSec(state.elapsedSec);
    $('time-duration').textContent = fmtSec(state.durationSec);
    $('np-elapsed').textContent = fmtSec(state.elapsedSec);
    $('np-remaining').textContent = `-${fmtSec(Math.max(0, state.durationSec - state.elapsedSec))}`;
  }

  function renderPlayerUI() {
    const t = state.currentTrack;
    const liked = t ? state.likedIds.has(Number(t.id)) : false;
    const rawArt = t ? (t.artwork_url || t.user?.avatar_url) : '';
    const norm = t ? normalizeTrackInfo(t.title, t.user?.username || t.user?.full_name) : { artist: '—', title: 'Select a track to play' };

    $('bar-art').src = artUrl(rawArt, 't200x200');
    $('bar-title').textContent = norm.title;
    $('bar-artist').textContent = norm.artist;
    $('bar-like').textContent = liked ? '🧡' : '♡';
    $('bar-like').classList.toggle('liked', liked);

    $('np-title').textContent = norm.title;
    $('np-artist').textContent = norm.artist;
    $('np-like').textContent = liked ? '🧡' : '♡';
    $('np-like').classList.toggle('liked', liked);
    $('vinyl-art').src = artUrl(rawArt, 't500x500');
    $('card-art').src = artUrl(rawArt, 't500x500');
    $('card-art').classList.toggle('paused', !state.isPlaying);
    $('vinyl-tonearm').classList.toggle('playing', state.isPlaying);

    $('vfd-title').textContent = norm.title;
    $('vfd-artist').textContent = jam.isActive ? `${norm.artist} · JAM ${jam.roomCode}` : norm.artist;
    $('vfd-like').textContent = liked ? '🧡' : '♡';
    $('vfd-like').classList.toggle('liked', liked);

    const style = state.settings.playbackStyle || 'vinyl';
    document.querySelectorAll('.style-pill').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.style === style);
    });
    $('np-vinyl-wrap').classList.toggle('hidden', style !== 'vinyl');
    $('np-card-wrap').classList.toggle('hidden', style !== 'card');

    const bgEl = $('np-bg');
    bgEl.style.backgroundImage = `url("${artUrl(rawArt, style === 'fullscreen' ? 'original' : 't500x500')}")`;
    bgEl.style.filter = style === 'fullscreen' ? 'none' : 'blur(52px) saturate(1.25)';
    bgEl.style.opacity = style === 'fullscreen' ? '1' : '0.45';

    $('btn-shuffle').classList.toggle('active', state.isShuffling);
    $('np-shuffle').classList.toggle('active', state.isShuffling);
    $('btn-repeat').classList.toggle('active', state.repeatMode !== 'none');
    $('np-repeat').classList.toggle('active', state.repeatMode !== 'none');
    $('btn-repeat').textContent = state.repeatMode === 'one' ? '🔂' : '🔁';
    $('np-repeat').textContent = state.repeatMode === 'one' ? '🔂' : '🔁';

    updateJamIndicators();
    updateScrubberDOM();
  }

  function updateSidebarBadges() {
    $('badge-likes').textContent = state.likes.length ? `${state.likes.length}+` : '';
    $('badge-playlists').textContent = state.playlists.length ? `${state.playlists.length}` : '';
  }

  // MARK: - Parallel SoundCloud Data Sync
  async function syncAllData(showConfirm = false) {
    state.isLoadingView = true;
    renderView();

    const pMe = api.fetchMe().then((me) => { state.user = me; });
    const pHome = api.fetchHome().then((shelves) => {
      state.shelves = shelves || [];
      if (state.nav === 'home') renderView();
    });
    const pFeed = api.fetchFeed().then((res) => {
      state.feed = res?.items || [];
      if (state.nav === 'feed') renderView();
    });
    const pHist = api.fetchHistory().then((h) => {
      state.history = h || [];
      if (state.nav === 'history') renderView();
    });

    await pMe;
    const pLikes = api.fetchLikes(null, 80).then((res) => {
      state.likes = res?.tracks || [];
      state.likedIds = new Set(state.likes.map((t) => Number(t.id)));
      updateSidebarBadges();
      if (state.nav === 'likes' || state.nav === 'home') renderView();
    });
    const pLib = api.fetchLibrary().then((res) => {
      state.playlists = res?.playlists || [];
      state.albums = res?.albums || [];
      updateSidebarBadges();
      if (state.nav === 'playlists' || state.nav === 'albums' || state.nav === 'home') renderView();
    });
    const pFol = api.fetchFollowing().then((f) => {
      state.following = f || [];
      state.followingIds = new Set(state.following.map((u) => Number(u.id)));
      if (state.nav === 'following' || state.nav === 'home') renderView();
    });

    await Promise.allSettled([pHome, pFeed, pHist, pLikes, pLib, pFol]);
    state.isLoadingView = false;
    renderView();
    if (showConfirm) {
      showToast(`Synced ${state.likes.length} likes & ${state.playlists.length} playlists`);
    }
  }

  // MARK: - Main View Rendering
  function setNav(navName) {
    state.nav = navName;
    document.querySelectorAll('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.nav === navName));
    renderView();
  }

  function renderTrackRowsHTML(tracks, listKey) {
    if (!tracks.length) return `<p class="muted">No tracks found yet.</p>`;
    return `<div class="track-list" data-list-key="${esc(listKey)}">` + tracks.map((t, idx) => {
      const isCur = Number(state.currentTrack?.id) === Number(t.id);
      const isLiked = state.likedIds.has(Number(t.id));
      const plays = fmtCount(t.playback_count);
      const dur = fmtSec((t.duration || 0) / 1000);
      const artist = t.user?.username || t.user?.full_name || 'Unknown Artist';
      return `
        <div class="track-row ${isCur ? 'playing' : ''}" data-track-idx="${idx}">
          <div class="track-art-wrap">
            <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't200x200'))}" alt="" loading="lazy" />
            ${isCur ? `<div class="eq-overlay"><div class="eq-bar"></div><div class="eq-bar"></div><div class="eq-bar"></div><div class="eq-bar"></div></div>` : ''}
          </div>
          <div class="track-info">
            <div class="track-title">${esc(t.title || 'Untitled Track')}</div>
            <div class="track-sub">${esc(artist)} ${plays ? `· ▶ ${plays}` : ''} · ${dur}</div>
          </div>
          <div class="track-actions">
            ${jam.isActive ? `<button class="icon-btn" data-jam-add="${idx}" title="Add to Jam Queue">👥+</button>` : ''}
            <button class="icon-btn" data-pl-add="${idx}" title="Add to Playlist">＋</button>
            <button class="icon-btn heart-btn ${isLiked ? 'liked' : ''}" data-like-idx="${idx}" title="Like">${isLiked ? '🧡' : '♡'}</button>
          </div>
        </div>
      `;
    }).join('') + `</div>`;
  }

  const activeTrackLists = new Map();

  function wireTrackListHandlers(container) {
    container.querySelectorAll('.track-list').forEach((listEl) => {
      const tracks = activeTrackLists.get(listEl.dataset.listKey) || [];
      listEl.querySelectorAll('.track-row').forEach((row) => {
        const idx = Number(row.dataset.trackIdx);
        const track = tracks[idx];
        if (!track) return;
        row.addEventListener('click', (e) => {
          if (e.target.closest('.track-actions')) return;
          playTrack(track, tracks);
        });
        row.querySelector('[data-like-idx]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          toggleLikeTrack(track);
        });
        row.querySelector('[data-pl-add]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          openAddToPlaylistModal(track);
        });
        row.querySelector('[data-jam-add]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          jam.addTrackToJam(track);
        });
      });
    });
  }

  function renderCurrentViewTracksState() {
    if (state.nav === 'likes' || state.nav === 'feed' || state.nav === 'history' || state.nav === 'playlistDetail' || state.nav === 'artistProfile') {
      renderView();
    }
  }

  function renderView() {
    const root = $('view-content');
    activeTrackLists.clear();

    if (state.nav === 'home') {
      const quickCards = [];
      if (state.playlists[0]) quickCards.push({ type: 'pl', item: state.playlists[0], title: state.playlists[0].title, sub: state.playlists[0].user?.username || 'Playlist', art: state.playlists[0].artwork_url, circle: false });
      if (state.following[0]) quickCards.push({ type: 'artist', item: state.following[0], title: state.following[0].username || 'Artist', sub: 'Artist', art: state.following[0].avatar_url, circle: true });
      for (const pl of state.playlists.slice(1, 4 - quickCards.length + 1)) {
        quickCards.push({ type: 'pl', item: pl, title: pl.title, sub: pl.user?.username || 'Playlist', art: pl.artwork_url, circle: false });
      }

      root.innerHTML = `
        <div class="page-header">
          <h1 class="page-title">Home</h1>
          <div class="row-gap">
            <button id="home-open-jam" class="btn-secondary">👥 ${jam.isActive ? `Live Jam (${jam.listenerCount})` : 'Start / Join Jam'}</button>
            <button id="home-open-vfd" class="vfd-pill-btn">VFD Visualizer</button>
          </div>
        </div>

        <div id="home-likes-hero" class="likes-hero">
          <div class="likes-hero-left">
            <span style="font-size:32px">🧡</span>
            <div>
              <h2>Your likes</h2>
              <div class="tiny" style="opacity:0.8">${state.likes.length ? `${state.likes.length}+ synced SoundCloud tracks` : 'Syncing your liked tracks...'}</div>
            </div>
          </div>
          <button id="home-shuffle-likes" class="btn-primary">🔀 Shuffle Likes</button>
        </div>

        ${quickCards.length ? `
          <div class="quick-grid">
            ${quickCards.map((c, i) => `
              <div class="quick-card" data-quick-idx="${i}">
                <img class="${c.circle ? 'circle' : ''}" src="${esc(artUrl(c.art, 't200x200'))}" alt="" />
                <div class="quick-meta">
                  <div class="quick-title">${esc(c.title)}</div>
                  <div class="quick-sub">${esc(c.sub)}</div>
                </div>
              </div>
            `).join('')}
          </div>
        ` : ''}

        ${state.shelves.map((shelf, sIdx) => `
          <section class="shelf">
            <div class="shelf-title">${esc(shelf.title)}</div>
            <div class="shelf-row">
              ${shelf.playlists.map((pl, pIdx) => `
                <div class="media-card" data-shelf="${sIdx}" data-pl="${pIdx}">
                  <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
                  <div class="media-card-title">${esc(pl.title)}</div>
                  <div class="media-card-sub">${esc(pl.user?.username || 'SoundCloud')}</div>
                </div>
              `).join('')}
            </div>
          </section>
        `).join('')}
      `;

      $('home-open-jam')?.addEventListener('click', () => openJamModal());
      $('home-open-vfd')?.addEventListener('click', () => openVFDVisualizer());
      $('home-likes-hero')?.addEventListener('click', (e) => {
        if (e.target.closest('#home-shuffle-likes')) return;
        setNav('likes');
      });
      $('home-shuffle-likes')?.addEventListener('click', (e) => {
        e.stopPropagation();
        playShuffled(state.likes);
      });
      root.querySelectorAll('[data-quick-idx]').forEach((el) => {
        el.addEventListener('click', () => {
          const card = quickCards[Number(el.dataset.quickIdx)];
          if (card.type === 'pl') openPlaylistDetail(card.item);
          else openArtistProfile(card.item);
        });
      });
      root.querySelectorAll('[data-shelf]').forEach((el) => {
        el.addEventListener('click', () => {
          const pl = state.shelves[Number(el.dataset.shelf)]?.playlists[Number(el.dataset.pl)];
          if (pl) openPlaylistDetail(pl);
        });
      });
      return;
    }

    if (state.nav === 'feed') {
      const feedTracks = state.feed.map((f) => f.track).filter(Boolean);
      activeTrackLists.set('feed', feedTracks);
      root.innerHTML = `
        <div class="page-header">
          <h1 class="page-title">Feed</h1>
          <button id="btn-refresh-feed" class="btn-secondary">🔄 Refresh</button>
        </div>
        ${renderTrackRowsHTML(feedTracks, 'feed')}
      `;
      $('btn-refresh-feed')?.addEventListener('click', () => syncAllData(true));
      wireTrackListHandlers(root);
      return;
    }

    if (state.nav === 'search') {
      activeTrackLists.set('search-tracks', state.searchResults.tracks);
      root.innerHTML = `
        <div class="page-header"><h1 class="page-title">Search</h1></div>
        <div class="search-bar-row">
          <input id="search-input" class="search-input" placeholder="Search tracks, artists, albums, playlists..." value="${esc(state.searchQuery)}" />
          <button id="btn-run-search" class="btn-primary">Search</button>
        </div>
        <div class="chip-row">
          ${[
            ['all', 'All'],
            ['tracks', 'Tracks'],
            ['people', 'Artists'],
            ['albums', 'Albums'],
            ['sets', 'Playlists']
          ].map(([k, lbl]) => `<button class="chip ${state.searchFilter === k ? 'active' : ''}" data-sf="${k}">${lbl}</button>`).join('')}
        </div>
        ${state.searchResults.users.length ? `
          <div class="shelf">
            <div class="shelf-title">Artists</div>
            <div class="shelf-row">
              ${state.searchResults.users.map((u, i) => `
                <div class="media-card" data-search-user="${i}">
                  <img style="border-radius:50%" src="${esc(artUrl(u.avatar_url, 't500x500'))}" alt="" />
                  <div class="media-card-title">${esc(u.username || u.full_name || 'Artist')}</div>
                  <div class="media-card-sub">${fmtCount(u.followers_count)} followers</div>
                </div>
              `).join('')}
            </div>
          </div>
        ` : ''}
        ${state.searchResults.tracks.length ? `<div class="shelf-title">Tracks</div>${renderTrackRowsHTML(state.searchResults.tracks, 'search-tracks')}` : ''}
        ${state.searchResults.playlists.length ? `
          <div class="shelf" style="margin-top:20px">
            <div class="shelf-title">Playlists & Albums</div>
            <div class="shelf-row">
              ${state.searchResults.playlists.map((pl, i) => `
                <div class="media-card" data-search-pl="${i}">
                  <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" />
                  <div class="media-card-title">${esc(pl.title)}</div>
                  <div class="media-card-sub">${esc(pl.user?.username || 'SoundCloud')}</div>
                </div>
              `).join('')}
            </div>
          </div>
        ` : ''}
      `;
      const runSearch = async () => {
        state.searchQuery = $('search-input').value.trim();
        if (!state.searchQuery) return;
        state.searchResults = await api.search(state.searchQuery, state.searchFilter);
        renderView();
      };
      $('btn-run-search')?.addEventListener('click', runSearch);
      $('search-input')?.addEventListener('keydown', (e) => { if (e.key === 'Enter') runSearch(); });
      root.querySelectorAll('[data-sf]').forEach((b) => b.addEventListener('click', () => {
        state.searchFilter = b.dataset.sf;
        if (state.searchQuery) runSearch();
        else renderView();
      }));
      root.querySelectorAll('[data-search-user]').forEach((el) => el.addEventListener('click', () => openArtistProfile(state.searchResults.users[Number(el.dataset.searchUser)])));
      root.querySelectorAll('[data-search-pl]').forEach((el) => el.addEventListener('click', () => openPlaylistDetail(state.searchResults.playlists[Number(el.dataset.searchPl)])));
      wireTrackListHandlers(root);
      return;
    }

    if (state.nav === 'likes') {
      activeTrackLists.set('likes', state.likes);
      root.innerHTML = `
        <div class="page-header">
          <h1 class="page-title">Your likes (${state.likes.length})</h1>
          <div class="row-gap">
            <button id="likes-shuffle" class="btn-secondary">🔀 Shuffle</button>
            <button id="likes-play" class="btn-primary">▶ Play All</button>
          </div>
        </div>
        ${renderTrackRowsHTML(state.likes, 'likes')}
      `;
      $('likes-shuffle')?.addEventListener('click', () => playShuffled(state.likes));
      $('likes-play')?.addEventListener('click', () => state.likes[0] && playTrack(state.likes[0], state.likes));
      wireTrackListHandlers(root);
      return;
    }

    if (state.nav === 'playlists' || state.nav === 'albums') {
      const list = state.nav === 'albums' ? state.albums : state.playlists;
      root.innerHTML = `
        <div class="page-header">
          <h1 class="page-title">${state.nav === 'albums' ? 'Albums' : 'Playlists'} (${list.length})</h1>
          ${state.nav === 'playlists' ? `<button id="pl-create-btn" class="btn-primary">➕ New Playlist</button>` : ''}
        </div>
        <div class="shelf-row" style="flex-wrap:wrap; overflow:visible">
          ${list.map((pl, i) => `
            <div class="media-card" data-lib-pl="${i}">
              <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
              <div class="media-card-title">${esc(pl.title)}</div>
              <div class="media-card-sub">${esc(pl.user?.username || 'SoundCloud')} · ${pl.track_count || 0} tracks</div>
            </div>
          `).join('')}
        </div>
      `;
      $('pl-create-btn')?.addEventListener('click', () => openCreatePlaylistModal());
      root.querySelectorAll('[data-lib-pl]').forEach((el) => el.addEventListener('click', () => openPlaylistDetail(list[Number(el.dataset.libPl)])));
      return;
    }

    if (state.nav === 'following') {
      root.innerHTML = `
        <div class="page-header"><h1 class="page-title">Following (${state.following.length})</h1></div>
        <div class="shelf-row" style="flex-wrap:wrap; overflow:visible">
          ${state.following.map((u, i) => `
            <div class="media-card" data-fol-u="${i}">
              <img style="border-radius:50%" src="${esc(artUrl(u.avatar_url, 't500x500'))}" alt="" loading="lazy" />
              <div class="media-card-title">${esc(u.username || u.full_name || 'Artist')}</div>
              <div class="media-card-sub">${fmtCount(u.followers_count)} followers</div>
            </div>
          `).join('')}
        </div>
      `;
      root.querySelectorAll('[data-fol-u]').forEach((el) => el.addEventListener('click', () => openArtistProfile(state.following[Number(el.dataset.folU)])));
      return;
    }

    if (state.nav === 'history') {
      activeTrackLists.set('history', state.history);
      root.innerHTML = `
        <div class="page-header"><h1 class="page-title">Listening History</h1></div>
        ${renderTrackRowsHTML(state.history, 'history')}
      `;
      wireTrackListHandlers(root);
      return;
    }

    if (state.nav === 'playlistDetail' && state.detailPlaylist) {
      const { playlist, tracks, loading } = state.detailPlaylist;
      activeTrackLists.set('detail-pl', tracks);
      root.innerHTML = `
        <div class="detail-hero">
          <img src="${esc(artUrl(playlist.artwork_url, 't500x500'))}" alt="" />
          <div class="detail-hero-meta">
            <span class="tiny muted">${playlist.is_album ? 'ALBUM' : 'PLAYLIST'} · ${tracks.length || playlist.track_count || 0} TRACKS</span>
            <h1 class="page-title">${esc(playlist.title)}</h1>
            <button id="pl-owner-btn" class="link-btn">By ${esc(playlist.user?.username || 'SoundCloud')}</button>
            <div class="detail-hero-actions">
              <button id="pl-play-all" class="btn-primary">▶ Play</button>
              <button id="pl-shuffle-all" class="btn-secondary">🔀 Shuffle</button>
            </div>
          </div>
        </div>
        ${loading && !tracks.length ? '<p class="muted">Loading tracks...</p>' : renderTrackRowsHTML(tracks, 'detail-pl')}
      `;
      $('pl-play-all')?.addEventListener('click', () => tracks[0] && playTrack(tracks[0], tracks));
      $('pl-shuffle-all')?.addEventListener('click', () => playShuffled(tracks));
      $('pl-owner-btn')?.addEventListener('click', () => playlist.user?.id && openArtistProfile(playlist.user));
      wireTrackListHandlers(root);
      return;
    }

    if (state.nav === 'artistProfile' && state.detailArtist) {
      const { user, profile, loading } = state.detailArtist;
      const u = profile?.user || user;
      const isFollowing = state.followingIds.has(Number(u.id));
      const top = profile?.topTracks || [];
      const trks = profile?.tracks || [];
      const primary = top.length ? top : trks;
      activeTrackLists.set('artist-top', top);
      activeTrackLists.set('artist-tracks', trks);

      root.innerHTML = `
        <div class="detail-hero">
          <img class="circle" src="${esc(artUrl(u.avatar_url, 't500x500'))}" alt="" />
          <div class="detail-hero-meta">
            <span class="tiny muted">ARTIST</span>
            <h1 class="page-title">${esc(u.username || u.full_name || 'Artist')}</h1>
            <div class="muted tiny">${fmtCount(u.followers_count)} Followers · ${fmtCount(u.followings_count)} Following</div>
            <div class="detail-hero-actions">
              <button id="artist-play" class="btn-primary">▶ Play Top</button>
              <button id="artist-shuffle" class="btn-secondary">🔀 Shuffle</button>
              <button id="artist-follow" class="btn-secondary">${isFollowing ? 'Following ✓' : '+ Follow'}</button>
            </div>
          </div>
        </div>
        ${loading ? '<p class="muted">Loading artist profile...</p>' : `
          ${top.length ? `<div class="shelf-title">Top tracks</div>${renderTrackRowsHTML(top.slice(0, 6), 'artist-top')}` : ''}
          ${(profile?.albums?.length || 0) ? `
            <section class="shelf" style="margin-top:20px">
              <div class="shelf-title">Albums</div>
              <div class="shelf-row">
                ${profile.albums.map((pl, i) => `
                  <div class="media-card" data-ap-alb="${i}">
                    <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" />
                    <div class="media-card-title">${esc(pl.title)}</div>
                  </div>
                `).join('')}
              </div>
            </section>
          ` : ''}
          ${(profile?.playlists?.length || 0) ? `
            <section class="shelf" style="margin-top:16px">
              <div class="shelf-title">Playlists</div>
              <div class="shelf-row">
                ${profile.playlists.map((pl, i) => `
                  <div class="media-card" data-ap-pl="${i}">
                    <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" />
                    <div class="media-card-title">${esc(pl.title)}</div>
                  </div>
                `).join('')}
              </div>
            </section>
          ` : ''}
          ${trks.length ? `<div class="shelf-title" style="margin-top:18px">Tracks</div>${renderTrackRowsHTML(trks.slice(0, 15), 'artist-tracks')}` : ''}
        `}
      `;

      $('artist-play')?.addEventListener('click', () => primary[0] && playTrack(primary[0], primary));
      $('artist-shuffle')?.addEventListener('click', () => playShuffled(primary));
      $('artist-follow')?.addEventListener('click', async () => {
        const nowFol = await api.toggleFollow(u.id, isFollowing);
        if (nowFol) state.followingIds.add(Number(u.id));
        else state.followingIds.delete(Number(u.id));
        showToast(nowFol ? `Following ${u.username}` : `Unfollowed ${u.username}`);
        renderView();
      });
      root.querySelectorAll('[data-ap-alb]').forEach((el) => el.addEventListener('click', () => openPlaylistDetail(profile.albums[Number(el.dataset.apAlb)])));
      root.querySelectorAll('[data-ap-pl]').forEach((el) => el.addEventListener('click', () => openPlaylistDetail(profile.playlists[Number(el.dataset.apPl)])));
      wireTrackListHandlers(root);
    }
  }

  async function openPlaylistDetail(playlist) {
    state.detailPlaylist = { playlist, tracks: playlist.tracks || [], loading: true };
    setNav('playlistDetail');
    const res = await api.fetchPlaylistTracks(playlist.numericId ?? playlist.id, playlist.tracks || []);
    if (state.detailPlaylist) {
      state.detailPlaylist = {
        playlist: res?.playlist || playlist,
        tracks: res?.tracks || [],
        loading: false
      };
      if (state.nav === 'playlistDetail') renderView();
    }
  }

  async function openArtistProfile(user) {
    if (!user || !user.id) return;
    $('now-playing-overlay').classList.add('hidden');
    state.detailArtist = { user, profile: null, loading: true };
    setNav('artistProfile');
    const profile = await api.fetchArtist(user.id);
    if (state.detailArtist) {
      state.detailArtist = { user, profile, loading: false };
      if (state.nav === 'artistProfile') renderView();
    }
  }

  // MARK: - Modals (Jam, Settings, Create Playlist, Add to Playlist)
  function openModal(type) {
    state.modalType = type;
    $('modal-backdrop').classList.remove('hidden');
  }

  function closeModal() {
    state.modalType = null;
    $('modal-backdrop').classList.add('hidden');
    $('modal-box').innerHTML = '';
  }

  function openJamModal() {
    openModal('jam');
    renderJamModal();
  }

  function renderJamModal() {
    const box = $('modal-box');
    if (!jam.isActive) {
      box.innerHTML = `
        <div class="modal-header">
          <div class="modal-title">👥 Worldwide Group Listening (Jam)</div>
          <button id="m-close" class="icon-btn">✕</button>
        </div>
        <p class="muted">Listen in real-time sync with friends on Windows, iPhone, iPad, or Android anywhere in the world.</p>
        <button id="jam-start-btn" class="btn-primary big">📡 Start a Jam</button>
        <div class="card-box">
          <span class="field-label">Join a Friend's Jam</span>
          <div class="row-gap">
            <input id="jam-join-input" class="text-input mono" placeholder="Enter 6-char code (e.g. K7M4P2) or invite link" />
            <button id="jam-join-btn" class="btn-primary">Join</button>
          </div>
          ${jam.statusNote ? `<div class="tiny" style="color:var(--accent)">${esc(jam.statusNote)}</div>` : ''}
        </div>
      `;
      $('m-close').onclick = closeModal;
      $('jam-start-btn').onclick = () => jam.startJam();
      $('jam-join-btn').onclick = () => jam.joinJam($('jam-join-input').value);
      return;
    }

    const cur = state.currentTrack;
    const curLiked = cur ? state.likedIds.has(Number(cur.id)) : false;

    box.innerHTML = `
      <div class="modal-header">
        <button id="jam-leave-top" class="btn-danger">${jam.isHost ? 'End Jam' : 'Leave Jam'}</button>
        <div class="modal-title">● Live Jam (${jam.listenerCount})</div>
        <button id="m-close" class="btn-secondary">Done</button>
      </div>

      <div class="card-box">
        <div class="row-between">
          <span class="tiny" style="color:#30d158; font-weight:800">${jam.isHost ? 'HOSTING LIVE JAM' : 'LISTENING IN JAM'}</span>
          <span class="tiny muted">${esc(jam.statusNote || jam.connectionState)}</span>
        </div>
        <div class="jam-code-big">${esc(jam.roomCode)}</div>
        <div class="row-gap">
          <button id="jam-copy-code" class="btn-secondary" style="flex:1">📋 Copy Code</button>
          <button id="jam-copy-invite" class="btn-primary" style="flex:1">🔗 Copy Invite Link</button>
        </div>
      </div>

      ${cur ? `
        <div class="card-box">
          <div class="row-between">
            <div class="row-gap" style="min-width:0">
              <img src="${esc(artUrl(cur.artwork_url || cur.user?.avatar_url, 't200x200'))}" style="width:46px;height:46px;border-radius:8px;object-fit:cover" />
              <div style="min-width:0">
                <div class="tiny" style="color:var(--accent);font-weight:800">NOW PLAYING IN JAM</div>
                <div style="font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(cur.title)}</div>
                <div class="tiny muted">${esc(cur.user?.username || 'Artist')}</div>
              </div>
            </div>
            <button id="jam-like-cur" class="icon-btn heart-btn big ${curLiked ? 'liked' : ''}" title="Like to YOUR SoundCloud">${curLiked ? '🧡' : '♡'}</button>
          </div>
        </div>
      ` : ''}

      <div class="card-box">
        ${jam.isHost ? `
          <span class="field-label">Who can control playback</span>
          <div class="row-gap">
            <button id="jam-host-only" class="${!jam.allowGuestControl ? 'btn-primary' : 'btn-secondary'}" style="flex:1">🔒 Host Only</button>
            <button id="jam-everyone" class="${jam.allowGuestControl ? 'btn-primary' : 'btn-secondary'}" style="flex:1">👥 Everyone</button>
          </div>
        ` : `
          <div class="row-between">
            <div>
              <div style="font-weight:700;font-size:13.5px">${jam.allowGuestControl ? '👥 Shared Controls Enabled' : '🔒 Host-Only Controls Active'}</div>
              <div class="tiny muted">Like any song, queue tracks, or send reactions</div>
            </div>
            <button id="jam-resync-btn" class="btn-primary">🔄 Resync</button>
          </div>
        `}
      </div>

      <div class="card-box">
        <span class="field-label">Listening Now (${jam.participants.length})</span>
        <div class="row-gap" style="flex-wrap:wrap">
          ${jam.participants.map((p) => `<span class="chip ${p.isHost ? 'active' : ''}">${p.isHost ? '👑 ' : ''}${esc(p.name)}</span>`).join('')}
        </div>
        <div class="row-gap">
          ${['🔥', '❤️', '🙌', '🤯', '🎧'].map((em) => `<button class="btn-secondary" data-react="${em}" style="flex:1;font-size:18px;padding:6px">${em}</button>`).join('')}
        </div>
      </div>

      <div class="card-box">
        <span class="field-label">Shared Jam Queue (${jam.sharedQueue.length})</span>
        <div class="row-gap">
          <input id="jam-q-search" class="text-input" placeholder="Search SoundCloud to queue for everyone..." />
          <button id="jam-q-go" class="btn-secondary">Search</button>
        </div>
        <div id="jam-q-results"></div>
        <div class="track-list">
          ${jam.sharedQueue.map((item, i) => {
            const isLiked = state.likedIds.has(Number(item.id));
            return `
              <div class="track-row" style="padding:5px 6px">
                <img src="${esc(artUrl(item.artworkUrl, 't200x200'))}" style="width:36px;height:36px;border-radius:6px;object-fit:cover" />
                <div class="track-info">
                  <div class="track-title" style="font-size:13px">${esc(item.title)}</div>
                  <div class="track-sub" style="font-size:11.5px">${esc(item.artist)}</div>
                </div>
                <button class="icon-btn heart-btn ${isLiked ? 'liked' : ''}" data-jam-q-like="${i}" title="Like track">${isLiked ? '🧡' : '♡'}</button>
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;

    $('m-close').onclick = closeModal;
    $('jam-leave-top').onclick = () => { jam.leaveJam(); closeModal(); };
    $('jam-copy-code').onclick = () => { navigator.clipboard.writeText(jam.roomCode); showToast(`Copied ${jam.roomCode}`); };
    $('jam-copy-invite').onclick = () => { navigator.clipboard.writeText(jam.shareText); showToast('Copied Jam invite link!'); };
    $('jam-like-cur')?.addEventListener('click', () => cur && toggleLikeTrack(cur));
    $('jam-host-only')?.addEventListener('click', () => jam.setAllowGuestControl(false));
    $('jam-everyone')?.addEventListener('click', () => jam.setAllowGuestControl(true));
    $('jam-resync-btn')?.addEventListener('click', () => jam.requestResync());

    box.querySelectorAll('[data-react]').forEach((b) => b.onclick = () => jam.sendReaction(b.dataset.react));
    box.querySelectorAll('[data-jam-q-like]').forEach((b) => b.onclick = () => {
      const item = jam.sharedQueue[Number(b.dataset.jamQLike)];
      if (item) toggleLikeTrack(window.DesktopJamManager.refToTrack(item));
    });

    const runQueueSearch = async () => {
      const q = $('jam-q-search').value.trim();
      if (!q) return;
      const res = await api.search(q, 'tracks');
      const target = $('jam-q-results');
      const tracks = (res?.tracks || []).slice(0, 5);
      target.innerHTML = tracks.map((t, i) => `
        <div class="row-between" style="padding:4px 0">
          <div style="min-width:0;flex:1">
            <div style="font-size:13px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(t.title)}</div>
            <div class="tiny muted">${esc(t.user?.username || 'Artist')}</div>
          </div>
          <button class="btn-primary" data-qadd="${i}" style="padding:5px 11px;font-size:11.5px">+ Queue</button>
        </div>
      `).join('');
      target.querySelectorAll('[data-qadd]').forEach((btn) => btn.onclick = () => {
        jam.addTrackToJam(tracks[Number(btn.dataset.qadd)]);
        target.innerHTML = '';
        $('jam-q-search').value = '';
      });
    };
    $('jam-q-go').onclick = runQueueSearch;
    $('jam-q-search').onkeydown = (e) => { if (e.key === 'Enter') runQueueSearch(); };
  }

  function openSettingsModal() {
    openModal('settings');
    const s = state.settings;
    const box = $('modal-box');
    const accents = [
      ['orange', '#ff5500'],
      ['crimson', '#ff2d55'],
      ['blue', '#0a84ff'],
      ['emerald', '#30d158'],
      ['violet', '#af52de'],
      ['gold', '#ffb300']
    ];

    box.innerHTML = `
      <div class="modal-header">
        <div class="modal-title">⚙️ Settings & Themes</div>
        <button id="m-close" class="btn-secondary">Done</button>
      </div>

      <div class="card-box">
        <span class="field-label">Theme Mode</span>
        <div class="chip-row" style="margin:0">
          ${[['dark', '🌙 Dark'], ['light', '☀️ Light'], ['amoled', '✨ Midnight OLED'], ['system', '💻 System']].map(([k, l]) =>
            `<button class="chip ${s.themeMode === k ? 'active' : ''}" data-set-theme="${k}">${l}</button>`
          ).join('')}
        </div>
        <span class="field-label" style="margin-top:6px">Accent Color</span>
        <div class="swatch-row">
          ${accents.map(([k, hex]) => `<button class="swatch-btn ${s.accentPreset === k ? 'active' : ''}" data-set-accent="${k}" style="background:${hex}"></button>`).join('')}
        </div>
        <span class="field-label" style="margin-top:6px">Now Playing Style</span>
        <div class="chip-row" style="margin:0">
          ${[['vinyl', '💿 Vinyl Record'], ['fullscreen', '🖼 Full Artwork'], ['card', '🎴 Ambient Card']].map(([k, l]) =>
            `<button class="chip ${s.playbackStyle === k ? 'active' : ''}" data-set-style="${k}">${l}</button>`
          ).join('')}
        </div>
      </div>

      <div class="card-box">
        <div class="row-between">
          <span class="field-label">Discord Rich Presence (Native Windows IPC)</span>
          <span class="tiny" style="color:${state.rpcConnected ? '#30d158' : 'var(--accent)'};font-weight:700">${state.rpcConnected ? '● Connected to Discord' : '○ Open Discord Desktop'}</span>
        </div>
        <label class="row-between"><span>Enable Discord Rich Presence</span><input type="checkbox" id="s-rpc" ${s.discordRichPresence ? 'checked' : ''} /></label>
        <label class="row-between"><span>Display When Paused</span><input type="checkbox" id="s-paused" ${s.displayWhenPaused ? 'checked' : ''} /></label>
        <label class="row-between"><span>Show SoundCloud Small Icon</span><input type="checkbox" id="s-small" ${s.displaySmallIcon ? 'checked' : ''} /></label>
        <label class="row-between"><span>Show "Listen on SoundCloud" Button</span><input type="checkbox" id="s-btns" ${s.displayButtons ? 'checked' : ''} /></label>
        <label class="row-between"><span>Smart Track Parser (Artist - Title)</span><input type="checkbox" id="s-parser" ${s.trackParserEnabled ? 'checked' : ''} /></label>
        <label class="row-between"><span>Minimize to System Tray on Close</span><input type="checkbox" id="s-tray" ${s.minimizeToTray ? 'checked' : ''} /></label>
      </div>

      <div class="card-box">
        <span class="field-label">Group Listening Relay</span>
        <input id="s-jam-relay" class="text-input" value="${esc(s.jamRelayUrl || 'https://ntfy.sh')}" placeholder="https://ntfy.sh" />
      </div>

      <div class="card-box">
        <span class="field-label">Last.fm Scrobbling</span>
        <label class="row-between"><span>Enable Last.fm</span><input type="checkbox" id="s-lfm" ${s.lastFmEnabled ? 'checked' : ''} /></label>
        <input id="s-lfm-key" class="text-input" placeholder="Last.fm API Key" value="${esc(s.lastFmApiKey)}" />
        <input id="s-lfm-sec" class="text-input" type="password" placeholder="Last.fm API Secret" value="${esc(s.lastFmApiSecret)}" />
        <input id="s-lfm-sk" class="text-input" placeholder="Last.fm Session Key" value="${esc(s.lastFmSessionKey)}" />
      </div>

      <div class="card-box">
        <span class="field-label">Webhooks (Custom JSON or Discord)</span>
        <label class="row-between"><span>Enable Webhooks</span><input type="checkbox" id="s-wh" ${s.webhookEnabled ? 'checked' : ''} /></label>
        <input id="s-wh-url" class="text-input" placeholder="https://discord.com/api/webhooks/..." value="${esc(s.webhookUrl)}" />
        <label class="row-between"><span>Format as Discord Embed</span><input type="checkbox" id="s-wh-disc" ${s.webhookDiscordFormat ? 'checked' : ''} /></label>
        <button id="s-wh-test" class="btn-secondary">🚀 Send Test Webhook</button>
      </div>

      <div class="card-box">
        <div class="row-between">
          <div>
            <div style="font-weight:700">${esc(state.user?.username || 'Signed In')}</div>
            <div class="tiny muted">SoundCloud RPC Desktop v${esc(state.version)} · Ad-Free Engine</div>
          </div>
          <button id="s-signout" class="btn-danger">Sign Out</button>
        </div>
      </div>
    `;

    const patch = async (p) => {
      state.settings = await api.updateSettings(p);
      applyTheme();
      renderPlayerUI();
      syncDesktopServices();
    };

    $('m-close').onclick = closeModal;
    box.querySelectorAll('[data-set-theme]').forEach((b) => b.onclick = async () => { await patch({ themeMode: b.dataset.setTheme }); openSettingsModal(); });
    box.querySelectorAll('[data-set-accent]').forEach((b) => b.onclick = async () => { await patch({ accentPreset: b.dataset.setAccent }); openSettingsModal(); });
    box.querySelectorAll('[data-set-style]').forEach((b) => b.onclick = async () => { await patch({ playbackStyle: b.dataset.setStyle }); openSettingsModal(); });

    $('s-rpc').onchange = (e) => patch({ discordRichPresence: e.target.checked });
    $('s-paused').onchange = (e) => patch({ displayWhenPaused: e.target.checked });
    $('s-small').onchange = (e) => patch({ displaySmallIcon: e.target.checked });
    $('s-btns').onchange = (e) => patch({ displayButtons: e.target.checked });
    $('s-parser').onchange = (e) => patch({ trackParserEnabled: e.target.checked });
    $('s-tray').onchange = (e) => patch({ minimizeToTray: e.target.checked });
    $('s-jam-relay').onchange = (e) => patch({ jamRelayUrl: e.target.value.trim() || 'https://ntfy.sh' });
    $('s-lfm').onchange = (e) => patch({ lastFmEnabled: e.target.checked });
    $('s-lfm-key').onchange = (e) => patch({ lastFmApiKey: e.target.value.trim() });
    $('s-lfm-sec').onchange = (e) => patch({ lastFmApiSecret: e.target.value.trim() });
    $('s-lfm-sk').onchange = (e) => patch({ lastFmSessionKey: e.target.value.trim() });
    $('s-wh').onchange = (e) => patch({ webhookEnabled: e.target.checked });
    $('s-wh-url').onchange = (e) => patch({ webhookUrl: e.target.value.trim() });
    $('s-wh-disc').onchange = (e) => patch({ webhookDiscordFormat: e.target.checked });
    $('s-wh-test').onclick = async () => {
      const res = await api.testWebhook();
      showToast(`Webhook: ${res}`);
    };
    $('s-signout').onclick = async () => {
      await api.signOut();
      state.isLoggedIn = false;
      closeModal();
      showAuthState();
    };
  }

  function openCreatePlaylistModal(initialTrack = null) {
    openModal('createPlaylist');
    const box = $('modal-box');
    box.innerHTML = `
      <div class="modal-header">
        <div class="modal-title">➕ New SoundCloud Playlist</div>
        <button id="m-close" class="icon-btn">✕</button>
      </div>
      <div class="card-box">
        <span class="field-label">Playlist Name</span>
        <input id="cp-title" class="text-input" placeholder="Late Night Mix..." />
        <label class="row-between"><span>Private Playlist</span><input type="checkbox" id="cp-priv" /></label>
        ${initialTrack ? `<div class="tiny muted">Will include: <b>${esc(initialTrack.title)}</b></div>` : ''}
        <button id="cp-submit" class="btn-primary big">☁️ Create & Sync to SoundCloud</button>
      </div>
    `;
    $('m-close').onclick = closeModal;
    $('cp-submit').onclick = async () => {
      const title = $('cp-title').value.trim();
      if (!title) return;
      const created = await api.createPlaylist(title, $('cp-priv').checked, initialTrack?.id || null);
      if (created) {
        state.playlists.unshift(created);
        updateSidebarBadges();
        showToast(`Created "${title}" on SoundCloud`);
        closeModal();
        if (state.nav === 'playlists') renderView();
      } else {
        showToast('Could not create playlist');
      }
    };
  }

  function openAddToPlaylistModal(track) {
    openModal('addToPlaylist');
    const own = state.user ? state.playlists.filter((p) => Number(p.user?.id) === Number(state.user.id)) : state.playlists;
    const list = own.length ? own : state.playlists;
    const box = $('modal-box');
    box.innerHTML = `
      <div class="modal-header">
        <div class="modal-title">Add to Playlist</div>
        <button id="m-close" class="icon-btn">✕</button>
      </div>
      <div class="tiny muted">Track: <b>${esc(track.title)}</b></div>
      <button id="atp-new" class="btn-primary">➕ Create New Playlist with Track</button>
      <div class="track-list">
        ${list.map((pl, i) => `
          <div class="track-row" data-atp-idx="${i}">
            <img src="${esc(artUrl(pl.artwork_url, 't200x200'))}" style="width:42px;height:42px;border-radius:6px;object-fit:cover" />
            <div class="track-info">
              <div class="track-title">${esc(pl.title)}</div>
              <div class="track-sub">${pl.track_count || 0} tracks</div>
            </div>
            <span style="color:var(--accent);font-weight:800">+ Add</span>
          </div>
        `).join('')}
      </div>
    `;
    $('m-close').onclick = closeModal;
    $('atp-new').onclick = () => openCreatePlaylistModal(track);
    box.querySelectorAll('[data-atp-idx]').forEach((el) => el.onclick = async () => {
      const pl = list[Number(el.dataset.atpIdx)];
      if (!pl || !pl.numericId) return;
      await api.addTrackToPlaylist(pl.numericId, track.id);
      showToast(`Added to "${pl.title}"`);
      closeModal();
    });
  }

  // MARK: - Fullscreen VFD Visualizer Controls
  function openVFDVisualizer() {
    $('vfd-overlay').classList.remove('hidden');
    syncVFDControlsUI();
    vfdEngine.start();
  }

  function closeVFDVisualizer() {
    vfdEngine.stop();
    $('vfd-overlay').classList.add('hidden');
  }

  function syncVFDControlsUI() {
    const s = state.settings;
    $('vfd-chassis').classList.toggle('bezel-on', s.vizShowBezel !== false);
    $('viz-peak-hold').checked = s.vizPeakHold !== false;
    $('viz-bezel').checked = s.vizShowBezel !== false;
    $('viz-gain').value = s.vizSensitivity || 1.15;
    $('viz-gain-val').textContent = `${Number(s.vizSensitivity || 1.15).toFixed(1)}x`;

    const modes = [['spectrum', 'Spectrum'], ['mirror', 'Mirror'], ['dotWave', 'Dot Wave'], ['vuBars', 'VU Bars'], ['vfdTimer', 'VFD Timer']];
    $('viz-modes').innerHTML = modes.map(([k, l]) =>
      `<button class="chip ${(s.vizMode || 'spectrum') === k ? 'active' : ''}" data-vm="${k}">${l}</button>`
    ).join('');
    $('viz-modes').querySelectorAll('[data-vm]').forEach((b) => b.onclick = async () => {
      state.settings = await api.updateSettings({ vizMode: b.dataset.vm });
      syncVFDControlsUI();
    });

    const colors = [['vfdMint', 'VFD Mint'], ['studioAmber', 'Amber'], ['cyberCyan', 'Cyan'], ['scFlame', 'Flame'], ['neonMagenta', 'Magenta'], ['rainbow', 'RGB']];
    $('viz-colors').innerHTML = colors.map(([k, l]) =>
      `<button class="chip ${(s.vizColor || 'vfdMint') === k ? 'active' : ''}" data-vc="${k}">${l}</button>`
    ).join('');
    $('viz-colors').querySelectorAll('[data-vc]').forEach((b) => b.onclick = async () => {
      state.settings = await api.updateSettings({ vizColor: b.dataset.vc });
      syncVFDControlsUI();
    });

    $('viz-bands').innerHTML = [16, 24, 32].map((n) =>
      `<button class="chip ${Number(s.vizBands || 24) === n ? 'active' : ''}" data-vb="${n}">${n}</button>`
    ).join('');
    $('viz-bands').querySelectorAll('[data-vb]').forEach((b) => b.onclick = async () => {
      state.settings = await api.updateSettings({ vizBands: Number(b.dataset.vb) });
      syncVFDControlsUI();
    });
  }

  // MARK: - Auth Screen Toggle
  function showAuthState() {
    $('signin-screen').classList.toggle('hidden', state.isLoggedIn);
    $('app-shell').classList.toggle('hidden', !state.isLoggedIn);
  }

  // MARK: - Wire Global DOM Events
  function wireEvents() {
    $('btn-signin').onclick = () => api.openLogin();
    document.querySelectorAll('.nav-item').forEach((b) => b.onclick = () => setNav(b.dataset.nav));
    $('btn-open-jam').onclick = () => openJamModal();
    $('btn-jam-bar').onclick = () => openJamModal();
    $('btn-np-jam').onclick = () => openJamModal();
    $('btn-new-playlist').onclick = () => openCreatePlaylistModal();
    $('btn-sync-library').onclick = () => syncAllData(true);
    $('btn-open-settings').onclick = () => openSettingsModal();

    $('btn-theme-quick').onclick = async () => {
      const next = document.body.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      state.settings = await api.updateSettings({ themeMode: next });
      applyTheme();
    };

    // Player bar
    $('btn-play').onclick = togglePlayPause;
    $('btn-next').onclick = nextTrack;
    $('btn-prev').onclick = () => prevTrack(false);
    $('btn-shuffle').onclick = toggleShuffle;
    $('btn-repeat').onclick = cycleRepeat;
    $('bar-like').onclick = () => state.currentTrack && toggleLikeTrack(state.currentTrack);
    $('bar-artist').onclick = () => state.currentTrack?.user?.id && openArtistProfile(state.currentTrack.user);
    $('btn-bar-resync').onclick = () => jam.requestResync();
    $('volume-slider').oninput = (e) => { audio.volume = Number(e.target.value) / 100; };

    const bindScrubber = (el) => {
      el.addEventListener('input', () => {
        if (jam.isGuestLocked) return;
        state.isScrubbing = true;
        state.elapsedSec = (Number(el.value) / 1000) * (state.durationSec || 0);
        updateScrubberDOM();
      });
      el.addEventListener('change', () => {
        state.isScrubbing = false;
        if (jam.isGuestLocked) return;
        seekToSeconds((Number(el.value) / 1000) * (state.durationSec || 0), true);
      });
    };
    bindScrubber($('scrubber'));
    bindScrubber($('np-scrubber'));

    // Fullscreen Now Playing
    const openNP = () => {
      if (!state.currentTrack) return;
      $('now-playing-overlay').classList.remove('hidden');
      renderPlayerUI();
    };
    $('bar-art-wrap').onclick = openNP;
    $('btn-expand-np').onclick = openNP;
    $('btn-np-close').onclick = () => $('now-playing-overlay').classList.add('hidden');
    $('np-play').onclick = togglePlayPause;
    $('np-next').onclick = nextTrack;
    $('np-prev').onclick = () => prevTrack(false);
    $('np-shuffle').onclick = toggleShuffle;
    $('np-repeat').onclick = cycleRepeat;
    $('np-like').onclick = () => state.currentTrack && toggleLikeTrack(state.currentTrack);
    $('np-artist').onclick = () => state.currentTrack?.user?.id && openArtistProfile(state.currentTrack.user);
    $('btn-np-resync').onclick = () => jam.requestResync();
    $('btn-np-add-pl').onclick = () => state.currentTrack && openAddToPlaylistModal(state.currentTrack);

    document.querySelectorAll('.style-pill').forEach((btn) => {
      btn.onclick = async () => {
        state.settings = await api.updateSettings({ playbackStyle: btn.dataset.style });
        renderPlayerUI();
      };
    });

    // VFD Visualizer
    $('btn-vfd-bar').onclick = openVFDVisualizer;
    $('btn-np-vfd').onclick = openVFDVisualizer;
    $('btn-vfd-close').onclick = closeVFDVisualizer;
    $('btn-vfd-style-toggle').onclick = () => $('vfd-customizer').classList.toggle('hidden');
    $('vfd-play').onclick = togglePlayPause;
    $('vfd-next').onclick = nextTrack;
    $('vfd-prev').onclick = () => prevTrack(false);
    $('vfd-like').onclick = () => state.currentTrack && toggleLikeTrack(state.currentTrack);
    $('vfd-stage').onclick = () => {
      const cust = $('vfd-customizer');
      if (!cust.classList.contains('hidden')) {
        cust.classList.add('hidden');
        return;
      }
      const hidden = $('vfd-hud-top').style.opacity === '0';
      $('vfd-hud-top').style.opacity = hidden ? '1' : '0';
      $('vfd-hud-bottom').style.opacity = hidden ? '1' : '0';
    };
    $('viz-peak-hold').onchange = async (e) => { state.settings = await api.updateSettings({ vizPeakHold: e.target.checked }); };
    $('viz-bezel').onchange = async (e) => {
      state.settings = await api.updateSettings({ vizShowBezel: e.target.checked });
      $('vfd-chassis').classList.toggle('bezel-on', e.target.checked);
    };
    $('viz-gain').oninput = async (e) => {
      const v = Number(e.target.value);
      $('viz-gain-val').textContent = `${v.toFixed(1)}x`;
      state.settings = await api.updateSettings({ vizSensitivity: v });
    };

    // Modal backdrop click close
    $('modal-backdrop').onclick = (e) => { if (e.target === $('modal-backdrop')) closeModal(); };

    // Keyboard shortcuts
    window.addEventListener('keydown', (e) => {
      const tag = document.activeElement?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (e.code === 'Space') { e.preventDefault(); togglePlayPause(); }
      else if (e.key === 'f' || e.key === 'F') {
        if ($('vfd-overlay').classList.contains('hidden')) openVFDVisualizer();
        else closeVFDVisualizer();
      } else if (e.key === 'Escape') {
        if (!$('vfd-overlay').classList.contains('hidden')) closeVFDVisualizer();
        else if (!$('modal-backdrop').classList.contains('hidden')) closeModal();
        else if (!$('now-playing-overlay').classList.contains('hidden')) $('now-playing-overlay').classList.add('hidden');
      }
    });

    // Main-process push events
    api.onAuthUpdated(async ({ isLoggedIn }) => {
      state.isLoggedIn = isLoggedIn;
      showAuthState();
      if (isLoggedIn) await syncAllData(true);
    });

    api.onRpcStatus(({ connected }) => {
      state.rpcConnected = connected;
      const pill = $('rpc-pill');
      pill.textContent = connected ? '● Discord RPC Live' : '○ Waiting for Discord';
      pill.classList.toggle('connected', connected);
    });

    api.onMediaCommand((cmd) => {
      if (cmd === 'play-pause') togglePlayPause();
      else if (cmd === 'next') nextTrack();
      else if (cmd === 'prev') prevTrack(false);
    });

    api.onDeepLink((urlStr) => {
      const code = window.DesktopJamManager.normalizeCode(urlStr);
      if (code.length >= 4 && state.isLoggedIn) {
        jam.joinJam(code);
        openJamModal();
      }
    });
  }

  // MARK: - Boot
  async function boot() {
    wireEvents();
    const init = await api.init();
    state.isLoggedIn = init.isLoggedIn;
    state.settings = init.settings || {};
    state.rpcConnected = init.rpcConnected;
    state.version = init.version || '2.7.0';
    applyTheme();
    showAuthState();
    renderPlayerUI();

    const pill = $('rpc-pill');
    pill.textContent = state.rpcConnected ? '● Discord RPC Live' : '○ Waiting for Discord';
    pill.classList.toggle('connected', state.rpcConnected);

    if (state.isLoggedIn) {
      await syncAllData(false);
    }
  }

  boot();
})();
