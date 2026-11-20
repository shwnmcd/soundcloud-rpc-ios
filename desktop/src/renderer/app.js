(() => {
  const api = window.scDesktop;

  // MARK: - App State
  const state = {
    isLoggedIn: false,
    version: '3.0.0',
    rpcConnected: false,
    user: null,
    settings: {},

    // Top Navigation: 'home' | 'feed' | 'library' | 'search' | 'playlistDetail' | 'artistProfile'
    nav: 'home',
    // Library Sub-tab: 'overview' | 'likes' | 'playlists' | 'albums' | 'following' | 'history'
    libraryTab: 'likes',
    libraryView: 'grid', // 'grid' | 'list'
    libraryFilter: '',
    showReposts: true,

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
    lastVolume: 0.85,
    hls: null,
    vinylAngle: 0,
    lastVinylTick: performance.now(),
    modalType: null // jam | games | settings | createPlaylist | addToPlaylist
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
    if (!raw) {
      return 'data:image/svg+xml,' + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="#202024"/><path d="M28 60V42M40 68V32M52 72V28M64 66V36M76 58V44" stroke="#ff5500" stroke-width="6" stroke-linecap="round"/></svg>'
      );
    }
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

  // Deterministic organic SoundCloud waveform bar heights for any track ID
  function waveformHeights(trackId, barCount = 78) {
    let seed = Math.abs(Number(trackId || 12345)) || 12345;
    const out = [];
    for (let i = 0; i < barCount; i++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const rnd = (seed % 1000) / 1000;
      const env = Math.sin((i / barCount) * Math.PI) * 0.45 + 0.55;
      const wave = Math.abs(Math.sin(i * 0.24 + (trackId % 17))) * 0.35 + 0.65;
      const h = Math.max(16, Math.min(98, Math.round((rnd * 0.65 + 0.35) * env * wave * 100)));
      out.push(h);
    }
    return out;
  }

  let toastTimer = null;
  function showToast(msg) {
    const el = $('toast');
    el.textContent = msg;
    el.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.add('hidden'), 2600);
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
    $('btn-theme-quick').textContent = mode === 'light' ? '🌙' : '☀️';
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
  let games = null;
  const jam = new window.DesktopJamManager({
    getRelayUrl: () => state.settings.jamRelayUrl || 'https://ntfy.sh',
    getDisplayName: () => state.user?.username || state.user?.full_name || 'CloudWave Desktop',
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
            try { audio.currentTime = Math.max(0, targetPos); } catch {}
            state.elapsedSec = audio.currentTime || targetPos;
          }
          if (shouldPlay && audio.paused) {
            await audio.play().catch(() => {});
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
    onChessRemote: (payload, sender) => games?.applyRemoteChess(payload, sender),
    onBlackjackRemote: (summary) => {
      showToast(`🃏 ${summary}`);
      if (state.modalType === 'games') renderGamesModal();
    },
    onToast: (msg) => showToast(msg),
    onUpdate: () => {
      updateJamIndicators();
      if (state.modalType === 'jam') renderJamModal();
      if (state.modalType === 'games') renderGamesModal();
      if (state.nav === 'feed' || state.nav === 'home') updateRightRailLiveBadges();
    }
  });

  games = new window.CloudWaveGames(
    jam,
    () => { if (state.modalType === 'games') renderGamesModal(); },
    (msg) => showToast(msg)
  );

  function updateJamIndicators() {
    const topBtn = $('btn-top-jam');
    const label = $('jam-btn-label');
    const barTag = $('bar-jam-tag');
    const npJam = $('btn-np-jam');
    const barLock = $('bar-lock-note');
    const npLock = $('np-lock-banner');

    if (jam.isActive) {
      topBtn.classList.add('live');
      label.textContent = `Jam · ${jam.listenerCount}`;
      barTag.classList.remove('hidden');
      barTag.textContent = `JAM · ${jam.listenerCount}`;
      npJam.classList.remove('hidden');
      npJam.textContent = `● JAM · ${jam.listenerCount}`;
    } else {
      topBtn.classList.remove('live');
      label.textContent = 'Jam';
      barTag.classList.add('hidden');
      npJam.classList.add('hidden');
    }

    const locked = jam.isGuestLocked;
    barLock.classList.toggle('hidden', !locked);
    npLock.classList.toggle('hidden', !locked);
    $('scrubber').disabled = locked;
    $('np-scrubber').disabled = locked;
    const playGlyph = locked ? '🔒' : state.isPlaying ? '❚❚' : '▶';
    $('btn-play').textContent = playGlyph;
    $('np-play').textContent = playGlyph;
    $('vfd-play').textContent = playGlyph;
  }

  function updateRightRailLiveBadges() {
    const rpcBadge = document.getElementById('rail-rpc-badge');
    if (rpcBadge) {
      rpcBadge.textContent = state.rpcConnected ? '● Discord RPC Connected' : '○ Open Discord Desktop';
      rpcBadge.classList.toggle('connected', state.rpcConnected);
    }
    const jamBadge = document.getElementById('rail-jam-status');
    if (jamBadge) {
      jamBadge.textContent = jam.isActive ? `● Live · ${jam.roomCode} (${jam.listenerCount})` : 'Ready to host or join';
    }
  }

  // MARK: - Playback Engine (Ad-Free Progressive + HLS + Jam + Discord RPC)
  async function playTrack(track, list = [track], shuffle = false, startAtSec = 0) {
    if (jam.isGuestLocked) {
      showToast('Host controls playback in this Jam');
      return;
    }
    // If clicking the exact currently playing track without a seek, toggle play/pause cleanly
    if (startAtSec <= 0 && state.currentTrack && Number(state.currentTrack.id) === Number(track.id)) {
      togglePlayPause();
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
    await loadTrackAt(state.currentIndex, { initialSeekSec: startAtSec, autoPlay: true, notifyJam: true });
  }

  function playShuffled(list) {
    if (!Array.isArray(list) || !list.length) return;
    const shuffled = [...list].sort(() => Math.random() - 0.5);
    playTrack(shuffled[0], shuffled, true);
  }

  let activeLoadSeq = 0;
  async function loadTrackAt(index, { initialSeekSec = 0, autoPlay = true, notifyJam = true } = {}) {
    if (index < 0 || index >= state.queue.length) return;
    const mySeq = ++activeLoadSeq;
    const track = state.queue[index];
    state.currentIndex = index;
    state.currentTrack = track;
    state.elapsedSec = initialSeekSec || 0;
    state.durationSec = Math.max(1, Math.floor((track.duration || 0) / 1000));
    renderPlayerUI();
    renderQueueDrawer();
    highlightPlayingItems();

    const stream = await api.resolveStream(track);
    if (mySeq !== activeLoadSeq) return; // User clicked another track while resolving

    if (!stream || !stream.url) {
      if (!state.isApplyingRemoteJam && index + 1 < state.queue.length) {
        return loadTrackAt(index + 1);
      }
      showToast('Track stream unavailable on SoundCloud');
      return;
    }

    if (state.hls) {
      try { state.hls.destroy(); } catch {}
      state.hls = null;
    }
    audio.pause();

    vfdEngine.attachAudioElement(audio);
    vfdEngine.resumeAudioContext();

    if (stream.protocol === 'hls' && window.Hls && window.Hls.isSupported()) {
      const hls = new window.Hls({ enableWorker: true, lowLatencyMode: false });
      state.hls = hls;
      hls.on(window.Hls.Events.ERROR, (_e, data) => {
        if (data?.fatal) {
          if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad();
          else if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
        }
      });
      hls.loadSource(stream.url);
      hls.attachMedia(audio);
      await new Promise((resolve) => {
        hls.once(window.Hls.Events.MANIFEST_PARSED, resolve);
        setTimeout(resolve, 2200);
      });
    } else {
      audio.src = stream.url;
      audio.load();
    }

    if (mySeq !== activeLoadSeq) return;

    if (initialSeekSec > 0.4) {
      try { audio.currentTime = initialSeekSec; } catch {}
    }

    if (autoPlay) {
      try {
        await audio.play();
        state.isPlaying = !audio.paused;
      } catch (err) {
        state.isPlaying = false;
        showToast('Click Play to start audio');
      }
    } else {
      audio.pause();
      state.isPlaying = false;
    }

    renderPlayerUI();
    highlightPlayingItems();
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
    highlightPlayingItems();
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
    try { audio.currentTime = clamped; } catch {}
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
    renderQueueDrawer();
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
    renderView();
    if (state.modalType === 'jam') renderJamModal();

    const finalLiked = await api.toggleLike(id, wasLiked);
    if (finalLiked) state.likedIds.add(id);
    else state.likedIds.delete(id);
    showToast(finalLiked ? 'Liked & synced to SoundCloud' : 'Removed from SoundCloud likes');
    renderPlayerUI();
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
  audio.addEventListener('play', () => { state.isPlaying = true; renderPlayerUI(); highlightPlayingItems(); });
  audio.addEventListener('pause', () => { state.isPlaying = false; renderPlayerUI(); highlightPlayingItems(); });
  audio.addEventListener('timeupdate', () => {
    if (!state.isScrubbing) {
      state.elapsedSec = audio.currentTime || 0;
      if (audio.duration && Number.isFinite(audio.duration)) {
        state.durationSec = audio.duration;
      }
      updateScrubberDOM();
      updateLiveFeedWaveformProgress();
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

  setInterval(() => {
    if (state.currentTrack && state.isPlaying) syncDesktopServices();
  }, 3000);

  // Smooth 60fps Vinyl Rotation Loop
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

  // MARK: - Player & Waveform DOM Sync (Zero Flicker!)
  function updateScrubberDOM() {
    const frac = state.durationSec > 0 ? Math.min(1, state.elapsedSec / state.durationSec) : 0;
    const val = Math.round(frac * 1000);
    $('scrubber').value = val;
    $('scrubber-fill').style.width = `${(frac * 100).toFixed(2)}%`;
    $('np-scrubber').value = val;
    $('time-elapsed').textContent = fmtSec(state.elapsedSec);
    const rem = Math.max(0, state.durationSec - state.elapsedSec);
    $('time-duration').textContent = state.durationSec > 0 ? `-${fmtSec(rem)}` : '-0:00';
    $('np-elapsed').textContent = fmtSec(state.elapsedSec);
    $('np-remaining').textContent = `-${fmtSec(rem)}`;
  }

  function updateLiveFeedWaveformProgress() {
    if (!state.currentTrack) return;
    const activeWrap = document.querySelector(`.waveform-wrap[data-wf-id="${state.currentTrack.id}"]`);
    if (!activeWrap) return;
    const frac = state.durationSec > 0 ? state.elapsedSec / state.durationSec : 0;
    const bars = activeWrap.querySelectorAll('.wf-bar');
    const litCount = Math.floor(frac * bars.length);
    bars.forEach((b, i) => b.classList.toggle('played', i < litCount));
  }

  function highlightPlayingItems() {
    const curId = state.currentTrack ? Number(state.currentTrack.id) : -1;
    document.querySelectorAll('[data-track-id]').forEach((el) => {
      const isCur = Number(el.dataset.trackId) === curId;
      el.classList.toggle('playing', isCur);
      const pbtn = el.querySelector('.tile-play-glyph, .feed-play-btn');
      if (pbtn) pbtn.textContent = isCur && state.isPlaying ? '❚❚' : '▶';
    });
  }

  function renderPlayerUI() {
    const t = state.currentTrack;
    const liked = t ? state.likedIds.has(Number(t.id)) : false;
    const rawArt = t ? (t.artwork_url || t.user?.avatar_url) : '';
    const norm = t
      ? normalizeTrackInfo(t.title, t.user?.username || t.user?.full_name)
      : { artist: 'CloudWave', title: 'Select a track to play' };

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

  function renderQueueDrawer() {
    $('queue-count').textContent = String(state.queue.length);
    const list = $('queue-drawer-list');
    if (!state.queue.length) {
      list.innerHTML = `<div class="muted tiny" style="padding:14px;text-align:center">Queue is empty — click any track to start playing.</div>`;
      return;
    }
    list.innerHTML = state.queue.slice(0, 40).map((t, i) => {
      const isCur = i === state.currentIndex;
      return `
        <div class="mini-track-row ${isCur ? 'playing' : ''}" data-q-idx="${i}" style="${isCur ? 'background:var(--accent-soft)' : ''}">
          <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't200x200'))}" alt="" />
          <div class="mini-track-meta">
            <div class="mini-track-title" style="${isCur ? 'color:var(--accent)' : ''}">${esc(t.title || 'Untitled')}</div>
            <div class="mini-track-artist">${esc(t.user?.username || 'Artist')}</div>
          </div>
          <span class="tiny muted">${fmtSec((t.duration || 0) / 1000)}</span>
        </div>
      `;
    }).join('');
    list.querySelectorAll('[data-q-idx]').forEach((el) => {
      el.onclick = () => {
        if (jam.isGuestLocked) { showToast('Host controls playback'); return; }
        loadTrackAt(Number(el.dataset.qIdx));
      };
    });
  }

  // MARK: - Parallel SoundCloud Data Sync
  async function syncAllData(showConfirm = false) {
    state.isLoadingView = true;
    renderView();

    const pMe = api.fetchMe().then((me) => {
      state.user = me;
      $('top-user-avatar').src = artUrl(me?.avatar_url, 't200x200');
    });
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
      if (state.nav === 'feed' || state.nav === 'library') renderView();
    });

    await pMe;
    const pLikes = api.fetchLikes(null, 80).then((res) => {
      state.likes = res?.tracks || [];
      state.likedIds = new Set(state.likes.map((t) => Number(t.id)));
      if (state.nav === 'library' || state.nav === 'home') renderView();
    });
    const pLib = api.fetchLibrary().then((res) => {
      state.playlists = res?.playlists || [];
      state.albums = res?.albums || [];
      if (state.nav === 'library' || state.nav === 'home') renderView();
    });
    const pFol = api.fetchFollowing().then((f) => {
      state.following = f || [];
      state.followingIds = new Set(state.following.map((u) => Number(u.id)));
      if (state.nav === 'library' || state.nav === 'feed') renderView();
    });

    await Promise.allSettled([pHome, pFeed, pHist, pLikes, pLib, pFol]);
    state.isLoadingView = false;
    renderView();
    if (showConfirm) {
      showToast(`Synced ${state.likes.length} likes & ${state.playlists.length} playlists`);
    }
  }

  // MARK: - Navigation
  function setNav(navName, libSubTab = null) {
    state.nav = navName;
    if (libSubTab) state.libraryTab = libSubTab;
    document.querySelectorAll('.top-nav-item').forEach((b) => {
      b.classList.toggle('active', b.dataset.topNav === navName);
    });
    $('main-scroll').scrollTop = 0;
    renderView();
  }

  // MARK: - Reusable Renderers (6-Col Grid, Compact List, Right Ad-Free Rail)
  const activeTrackLists = new Map();

  function renderTrackGridHTML(tracks, listKey, showHeartPrefix = false) {
    if (!tracks.length) return `<p class="muted">No tracks found.</p>`;
    return `<div class="sc-grid" data-list-key="${esc(listKey)}">` + tracks.map((t, idx) => {
      const isCur = Number(state.currentTrack?.id) === Number(t.id);
      const isLiked = state.likedIds.has(Number(t.id));
      const artist = t.user?.username || t.user?.full_name || 'Unknown Artist';
      return `
        <div class="sc-tile ${isCur ? 'playing' : ''}" data-track-idx="${idx}" data-track-id="${t.id}">
          <div class="sc-tile-art">
            <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't500x500'))}" alt="" loading="lazy" />
            <div class="sc-tile-hover">
              <div class="sc-tile-play tile-play-glyph">${isCur && state.isPlaying ? '❚❚' : '▶'}</div>
              <div class="sc-tile-hover-actions">
                <button class="sc-tile-mini-btn ${isLiked ? 'liked' : ''}" data-like-idx="${idx}" title="Like">${isLiked ? '🧡' : '♡'}</button>
                ${jam.isActive ? `<button class="sc-tile-mini-btn" data-jam-add="${idx}" title="Queue in Jam">👥</button>` : ''}
                <button class="sc-tile-mini-btn" data-pl-add="${idx}" title="Add to Playlist">＋</button>
              </div>
            </div>
          </div>
          <div class="sc-tile-title">${showHeartPrefix ? '<span class="tiny-heart">♥</span>' : ''}<span>${esc(t.title || 'Untitled')}</span></div>
          <button class="sc-tile-sub link-btn" data-artist-idx="${idx}">${esc(artist)}</button>
        </div>
      `;
    }).join('') + `</div>`;
  }

  function renderTrackRowsHTML(tracks, listKey) {
    if (!tracks.length) return `<p class="muted">No tracks found.</p>`;
    return `<div class="track-list" data-list-key="${esc(listKey)}">` + tracks.map((t, idx) => {
      const isCur = Number(state.currentTrack?.id) === Number(t.id);
      const isLiked = state.likedIds.has(Number(t.id));
      const plays = fmtCount(t.playback_count);
      const dur = fmtSec((t.duration || 0) / 1000);
      const artist = t.user?.username || t.user?.full_name || 'Unknown Artist';
      return `
        <div class="track-row ${isCur ? 'playing' : ''}" data-track-idx="${idx}" data-track-id="${t.id}">
          <div class="track-art-wrap">
            <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't200x200'))}" alt="" loading="lazy" />
            ${isCur ? `<div class="eq-overlay"><div class="eq-bar"></div><div class="eq-bar"></div><div class="eq-bar"></div></div>` : ''}
          </div>
          <div class="track-info">
            <div class="track-title">${esc(t.title || 'Untitled Track')}</div>
            <div class="track-sub"><button class="link-btn" data-artist-idx="${idx}">${esc(artist)}</button> ${plays ? `· ▶ ${plays}` : ''} · ${dur}</div>
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

  function wireTrackContainers(container) {
    container.querySelectorAll('[data-list-key]').forEach((listEl) => {
      const tracks = activeTrackLists.get(listEl.dataset.listKey) || [];
      listEl.querySelectorAll('[data-track-idx]').forEach((item) => {
        const idx = Number(item.dataset.trackIdx);
        const track = tracks[idx];
        if (!track) return;

        item.addEventListener('click', (e) => {
          if (e.target.closest('[data-like-idx], [data-pl-add], [data-jam-add], [data-artist-idx]')) return;
          playTrack(track, tracks);
        });
        item.querySelector('[data-like-idx]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          toggleLikeTrack(track);
        });
        item.querySelector('[data-pl-add]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          openAddToPlaylistModal(track);
        });
        item.querySelector('[data-jam-add]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          jam.addTrackToJam(track);
        });
        item.querySelector('[data-artist-idx]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          if (track.user?.id) openArtistProfile(track.user);
        });
      });
    });
  }

  function renderRightRailHTML() {
    const folPreview = state.following.slice(0, 10);
    const recent = state.history.slice(0, 4);
    activeTrackLists.set('rail-history', recent);

    return `
      <aside class="right-rail">
        <div class="rail-card">
          <div class="rail-title">
            <span>Discord Rich Presence</span>
            <button id="rail-sync-btn" class="link-btn tiny" style="text-transform:none">🔄 Sync</button>
          </div>
          <div id="rail-rpc-badge" class="rpc-status-badge ${state.rpcConnected ? 'connected' : ''}">
            ${state.rpcConnected ? '● Discord RPC Connected' : '○ Open Discord Desktop'}
          </div>
          <div class="tiny muted">Zero ads · Synced with SoundCloud likes &amp; playlists</div>
        </div>

        <div class="rail-card">
          <div class="rail-title">
            <span>Jam &amp; Mini-Games</span>
          </div>
          <div id="rail-jam-status" class="tiny muted">${jam.isActive ? `● Live · ${esc(jam.roomCode)} (${jam.listenerCount})` : 'Listen together worldwide'}</div>
          <button id="rail-open-jam" class="btn-primary" style="width:100%">👥 ${jam.isActive ? `Open Live Jam (${jam.listenerCount})` : 'Start / Join Jam'}</button>
          <div class="row-gap">
            <button id="rail-play-chess" class="btn-secondary" style="flex:1">♟ Chess</button>
            <button id="rail-play-bj" class="btn-secondary" style="flex:1">🃏 21 Blackjack</button>
          </div>
        </div>

        ${folPreview.length ? `
          <div class="rail-card">
            <div class="rail-title">
              <span>Following</span>
              <button id="rail-see-following" class="link-btn tiny" style="text-transform:none">View all</button>
            </div>
            <div class="avatar-strip">
              ${folPreview.map((u, i) => `
                <div class="avatar-circle-item" data-rail-artist="${i}">
                  <div class="avatar-circle-wrap">
                    <img src="${esc(artUrl(u.avatar_url, 't200x200'))}" alt="" loading="lazy" />
                    <span class="avatar-badge"></span>
                  </div>
                  <div class="avatar-name">${esc(u.username || 'Artist')}</div>
                </div>
              `).join('')}
            </div>
          </div>
        ` : ''}

        ${recent.length ? `
          <div class="rail-card" data-list-key="rail-history">
            <div class="rail-title">
              <span>Listening History</span>
              <button id="rail-see-history" class="link-btn tiny" style="text-transform:none">View all</button>
            </div>
            ${recent.map((t, i) => `
              <div class="mini-track-row" data-track-idx="${i}" data-track-id="${t.id}">
                <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't200x200'))}" alt="" />
                <div class="mini-track-meta">
                  <div class="mini-track-title">${esc(t.title || 'Untitled')}</div>
                  <div class="mini-track-artist">${esc(t.user?.username || 'Artist')}</div>
                </div>
              </div>
            `).join('')}
          </div>
        ` : ''}
      </aside>
    `;
  }

  function wireRightRail(root) {
    root.querySelector('#rail-sync-btn')?.addEventListener('click', () => syncAllData(true));
    root.querySelector('#rail-open-jam')?.addEventListener('click', () => openJamModal());
    root.querySelector('#rail-play-chess')?.addEventListener('click', () => openGamesModal('chess'));
    root.querySelector('#rail-play-bj')?.addEventListener('click', () => openGamesModal('blackjack'));
    root.querySelector('#rail-see-following')?.addEventListener('click', () => setNav('library', 'following'));
    root.querySelector('#rail-see-history')?.addEventListener('click', () => setNav('library', 'history'));
    root.querySelectorAll('[data-rail-artist]').forEach((el) => {
      el.addEventListener('click', () => openArtistProfile(state.following[Number(el.dataset.railArtist)]));
    });
  }

  // MARK: - Main View Renderer
  function renderView() {
    const root = $('view-content');
    activeTrackLists.clear();

    // 1. HOME VIEW (2-Column Official SoundCloud Discover + Ad-Free Right Rail)
    if (state.nav === 'home') {
      root.innerHTML = `
        <div class="two-col-layout">
          <div>
            <div id="home-likes-hero" class="likes-hero">
              <div class="row-gap" style="gap:14px">
                <span style="font-size:30px">🧡</span>
                <div>
                  <h2>Your likes</h2>
                  <div class="tiny muted">${state.likes.length ? `${state.likes.length}+ synced SoundCloud tracks` : 'Syncing your liked tracks...'}</div>
                </div>
              </div>
              <div class="row-gap">
                <button id="home-open-likes" class="btn-secondary">Open Grid</button>
                <button id="home-shuffle-likes" class="btn-primary">🔀 Shuffle Likes</button>
              </div>
            </div>

            ${state.playlists.length ? `
              <section class="shelf">
                <div class="shelf-head">
                  <div class="shelf-title">Your Playlists</div>
                  <button id="home-all-pl" class="link-btn tiny">View all (${state.playlists.length})</button>
                </div>
                <div class="shelf-row">
                  ${state.playlists.slice(0, 10).map((pl, i) => `
                    <div class="sc-tile" data-home-pl="${i}">
                      <div class="sc-tile-art">
                        <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
                        <div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div>
                      </div>
                      <div class="sc-tile-title">${esc(pl.title)}</div>
                      <div class="sc-tile-sub">${esc(pl.user?.username || 'SoundCloud')}</div>
                    </div>
                  `).join('')}
                </div>
              </section>
            ` : ''}

            ${state.shelves.map((shelf, sIdx) => `
              <section class="shelf">
                <div class="shelf-head"><div class="shelf-title">${esc(shelf.title)}</div></div>
                <div class="shelf-row">
                  ${shelf.playlists.map((pl, pIdx) => `
                    <div class="sc-tile" data-shelf="${sIdx}" data-pl="${pIdx}">
                      <div class="sc-tile-art">
                        <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
                        <div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div>
                      </div>
                      <div class="sc-tile-title">${esc(pl.title)}</div>
                      <div class="sc-tile-sub">${esc(pl.user?.username || 'SoundCloud')}</div>
                    </div>
                  `).join('')}
                </div>
              </section>
            `).join('')}
          </div>
          ${renderRightRailHTML()}
        </div>
      `;

      $('home-likes-hero')?.addEventListener('click', (e) => {
        if (e.target.closest('button')) return;
        setNav('library', 'likes');
      });
      $('home-open-likes')?.addEventListener('click', () => setNav('library', 'likes'));
      $('home-shuffle-likes')?.addEventListener('click', () => playShuffled(state.likes));
      $('home-all-pl')?.addEventListener('click', () => setNav('library', 'playlists'));
      root.querySelectorAll('[data-home-pl]').forEach((el) => {
        el.onclick = () => openPlaylistDetail(state.playlists[Number(el.dataset.homePl)]);
      });
      root.querySelectorAll('[data-shelf]').forEach((el) => {
        el.onclick = () => {
          const pl = state.shelves[Number(el.dataset.shelf)]?.playlists[Number(el.dataset.pl)];
          if (pl) openPlaylistDetail(pl);
        };
      });
      wireRightRail(root);
      wireTrackContainers(root);
      return;
    }

    // 2. FEED VIEW (Matches Screenshot 3 — Interactive Vertical-Bar Waveforms + Reposts Toggle + Right Rail!)
    if (state.nav === 'feed') {
      const filteredFeed = state.feed.filter((item) => item.track && (state.showReposts || !item.isRepost));
      const feedTracks = filteredFeed.map((f) => f.track);
      activeTrackLists.set('feed-tracks', feedTracks);

      root.innerHTML = `
        <div class="two-col-layout">
          <div>
            <div class="feed-header">
              <div class="feed-heading">Hear the latest posts from the people you’re following:</div>
              <button id="btn-toggle-reposts" class="repost-toggle-wrap">
                <span>Reposts</span>
                <span class="sc-switch ${state.showReposts ? 'on' : ''}"></span>
              </button>
            </div>

            <div class="feed-list">
              ${filteredFeed.length ? filteredFeed.map((item, idx) => {
                const t = item.track;
                const isCur = Number(state.currentTrack?.id) === Number(t.id);
                const isLiked = state.likedIds.has(Number(t.id));
                const actor = item.isRepost ? (item.reposter || t.user) : t.user;
                const actorName = actor?.username || actor?.full_name || 'Artist';
                const artistName = t.user?.username || t.user?.full_name || 'Artist';
                const bars = waveformHeights(t.id, 78);
                const frac = isCur && state.durationSec > 0 ? state.elapsedSec / state.durationSec : 0;
                const litCount = Math.floor(frac * bars.length);
                const durStr = fmtSec((t.duration || 0) / 1000);

                return `
                  <article class="feed-card ${isCur ? 'playing' : ''}" data-feed-idx="${idx}" data-track-id="${t.id}">
                    <div class="feed-card-top">
                      <img src="${esc(artUrl(actor?.avatar_url || t.artwork_url, 't200x200'))}" alt="" loading="lazy" />
                      <span><b>${esc(actorName)}</b> ${item.isRepost ? '🔁 reposted a track' : 'posted a track'}</span>
                    </div>

                    <div class="feed-card-body">
                      <div class="feed-art-box" data-feed-play="${idx}">
                        <img src="${esc(artUrl(t.artwork_url || t.user?.avatar_url, 't500x500'))}" alt="" loading="lazy" />
                      </div>

                      <div class="feed-right-col">
                        <div class="feed-track-head">
                          <button class="feed-play-btn" data-feed-play="${idx}">${isCur && state.isPlaying ? '❚❚' : '▶'}</button>
                          <div class="feed-track-titles">
                            <button class="feed-track-artist link-btn" data-feed-artist="${idx}">${esc(artistName)}</button>
                            <div class="feed-track-title" data-feed-play="${idx}">${esc(t.title || 'Untitled Track')}</div>
                          </div>
                          ${t.genre ? `<span class="genre-pill"># ${esc(t.genre)}</span>` : ''}
                        </div>

                        <div class="waveform-wrap" data-wf-idx="${idx}" data-wf-id="${t.id}" title="Click anywhere on waveform to play/seek">
                          ${bars.map((h, bi) => `<div class="wf-bar ${bi < litCount ? 'played' : ''}" style="height:${h}%"></div>`).join('')}
                          <span class="wf-dur-tag">${durStr}</span>
                        </div>

                        <div class="feed-actions-row">
                          <div class="feed-action-btns">
                            <button class="sc-action-btn ${isLiked ? 'liked' : ''}" data-feed-like="${idx}">
                              ${isLiked ? '🧡' : '♡'} ${fmtCount(t.likes_count) || 'Like'}
                            </button>
                            <button class="sc-action-btn" data-feed-pl="${idx}">＋ Playlist</button>
                            ${jam.isActive ? `<button class="sc-action-btn" data-feed-jam="${idx}">👥 Jam Queue</button>` : ''}
                          </div>
                          <div class="feed-stats">
                            ${t.playback_count ? `<span>▶ ${fmtCount(t.playback_count)}</span>` : ''}
                            ${t.comment_count ? `<span>💬 ${fmtCount(t.comment_count)}</span>` : ''}
                          </div>
                        </div>
                      </div>
                    </div>
                  </article>
                `;
              }).join('') : `<p class="muted">No feed posts yet. Follow artists on SoundCloud or toggle Reposts on.</p>`}
            </div>
          </div>

          ${renderRightRailHTML()}
        </div>
      `;

      $('btn-toggle-reposts')?.addEventListener('click', () => {
        state.showReposts = !state.showReposts;
        renderView();
      });

      root.querySelectorAll('[data-feed-play]').forEach((el) => {
        el.onclick = () => {
          const track = feedTracks[Number(el.dataset.feedPlay)];
          if (track) playTrack(track, feedTracks);
        };
      });
      root.querySelectorAll('[data-feed-artist]').forEach((el) => {
        el.onclick = () => {
          const track = feedTracks[Number(el.dataset.feedArtist)];
          if (track?.user?.id) openArtistProfile(track.user);
        };
      });
      root.querySelectorAll('[data-feed-like]').forEach((el) => {
        el.onclick = () => toggleLikeTrack(feedTracks[Number(el.dataset.feedLike)]);
      });
      root.querySelectorAll('[data-feed-pl]').forEach((el) => {
        el.onclick = () => openAddToPlaylistModal(feedTracks[Number(el.dataset.feedPl)]);
      });
      root.querySelectorAll('[data-feed-jam]').forEach((el) => {
        el.onclick = () => jam.addTrackToJam(feedTracks[Number(el.dataset.feedJam)]);
      });
      root.querySelectorAll('[data-wf-idx]').forEach((wf) => {
        wf.onclick = (e) => {
          const rect = wf.getBoundingClientRect();
          const frac = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
          const track = feedTracks[Number(wf.dataset.wfIdx)];
          if (!track) return;
          const targetSec = frac * ((track.duration || 0) / 1000);
          if (state.currentTrack && Number(state.currentTrack.id) === Number(track.id)) {
            seekToSeconds(targetSec, true);
          } else {
            playTrack(track, feedTracks, false, targetSec);
          }
        };
      });

      wireRightRail(root);
      wireTrackContainers(root);
      return;
    }

    // 3. LIBRARY VIEW (Matches Screenshot 1 — Sub-Tabs + View Toggle + Filter + 6-Column Artwork Grid!)
    if (state.nav === 'library') {
      const subTabs = [
        ['overview', 'Overview'],
        ['likes', 'Likes'],
        ['playlists', 'Playlists'],
        ['albums', 'Albums'],
        ['following', 'Following'],
        ['history', 'History']
      ];
      const q = state.libraryFilter.trim().toLowerCase();

      const filterTrack = (t) => !q || (t.title || '').toLowerCase().includes(q) || (t.user?.username || '').toLowerCase().includes(q);
      const filterPl = (p) => !q || (p.title || '').toLowerCase().includes(q) || (p.user?.username || '').toLowerCase().includes(q);
      const filterUser = (u) => !q || (u.username || u.full_name || '').toLowerCase().includes(q);

      const headings = {
        overview: 'Your library overview:',
        likes: 'Hear the tracks you’ve liked:',
        playlists: 'Your synced SoundCloud playlists:',
        albums: 'Your saved albums:',
        following: 'Hear what the people you follow have posted:',
        history: 'Recently played tracks:'
      };

      const isTrackTab = state.libraryTab === 'likes' || state.libraryTab === 'history';

      let bodyHTML = '';
      if (state.libraryTab === 'overview') {
        const recentLikes = state.likes.filter(filterTrack).slice(0, 6);
        const recentPls = state.playlists.filter(filterPl).slice(0, 6);
        const recentHist = state.history.filter(filterTrack).slice(0, 6);
        activeTrackLists.set('ov-likes', recentLikes);
        activeTrackLists.set('ov-hist', recentHist);
        bodyHTML = `
          <div class="shelf">
            <div class="shelf-head">
              <div class="shelf-title">Recently Liked</div>
              <button class="link-btn tiny" data-goto-lib="likes">View all (${state.likes.length})</button>
            </div>
            ${renderTrackGridHTML(recentLikes, 'ov-likes', true)}
          </div>
          <div class="shelf">
            <div class="shelf-head">
              <div class="shelf-title">Playlists</div>
              <button class="link-btn tiny" data-goto-lib="playlists">View all (${state.playlists.length})</button>
            </div>
            <div class="sc-grid">
              ${recentPls.map((pl, i) => `
                <div class="sc-tile" data-lib-pl-ov="${i}">
                  <div class="sc-tile-art">
                    <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
                    <div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div>
                  </div>
                  <div class="sc-tile-title">${esc(pl.title)}</div>
                  <div class="sc-tile-sub">${esc(pl.user?.username || 'SoundCloud')} · ${pl.track_count || 0} tracks</div>
                </div>
              `).join('')}
            </div>
          </div>
          ${recentHist.length ? `
            <div class="shelf">
              <div class="shelf-head">
                <div class="shelf-title">Recently Played</div>
                <button class="link-btn tiny" data-goto-lib="history">View all</button>
              </div>
              ${renderTrackGridHTML(recentHist, 'ov-hist', false)}
            </div>
          ` : ''}
        `;
      } else if (state.libraryTab === 'likes' || state.libraryTab === 'history') {
        const list = (state.libraryTab === 'likes' ? state.likes : state.history).filter(filterTrack);
        activeTrackLists.set(`lib-${state.libraryTab}`, list);
        bodyHTML = state.libraryView === 'grid'
          ? renderTrackGridHTML(list, `lib-${state.libraryTab}`, state.libraryTab === 'likes')
          : renderTrackRowsHTML(list, `lib-${state.libraryTab}`);
      } else if (state.libraryTab === 'playlists' || state.libraryTab === 'albums') {
        const list = (state.libraryTab === 'albums' ? state.albums : state.playlists).filter(filterPl);
        bodyHTML = list.length ? `
          <div class="sc-grid">
            ${list.map((pl, i) => `
              <div class="sc-tile" data-lib-pl="${i}">
                <div class="sc-tile-art">
                  <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" loading="lazy" />
                  <div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div>
                </div>
                <div class="sc-tile-title">${esc(pl.title)}</div>
                <div class="sc-tile-sub">${esc(pl.user?.username || 'SoundCloud')} · ${pl.track_count || 0} tracks</div>
              </div>
            `).join('')}
          </div>
        ` : `<p class="muted">No ${state.libraryTab} matched your filter.</p>`;
      } else if (state.libraryTab === 'following') {
        const list = state.following.filter(filterUser);
        bodyHTML = list.length ? `
          <div class="sc-grid">
            ${list.map((u, i) => `
              <div class="sc-tile" data-lib-user="${i}">
                <div class="sc-tile-art circle">
                  <img src="${esc(artUrl(u.avatar_url, 't500x500'))}" alt="" loading="lazy" />
                </div>
                <div class="sc-tile-title" style="justify-content:center">${esc(u.username || u.full_name || 'Artist')}</div>
                <div class="sc-tile-sub" style="text-align:center">${fmtCount(u.followers_count)} followers</div>
              </div>
            `).join('')}
          </div>
        ` : `<p class="muted">No followed artists matched your filter.</p>`;
      }

      root.innerHTML = `
        <div class="lib-subtabs">
          ${subTabs.map(([k, lbl]) =>
            `<button class="lib-tab ${state.libraryTab === k ? 'active' : ''}" data-lib-sub="${k}">${lbl}</button>`
          ).join('')}
        </div>

        <div class="lib-toolbar">
          <div class="lib-heading">${headings[state.libraryTab]}</div>
          <div class="lib-controls">
            ${state.libraryTab === 'playlists' ? `<button id="lib-new-pl" class="btn-primary" style="height:30px;padding:0 12px;font-size:12px">➕ New Playlist</button>` : ''}
            ${state.libraryTab === 'likes' && state.likes.length ? `<button id="lib-shuffle-likes" class="btn-secondary" style="height:30px;padding:0 11px;font-size:12px">🔀 Shuffle</button>` : ''}
            ${isTrackTab ? `
              <div class="view-toggle-group">
                <span>View</span>
                <button class="view-toggle-btn ${state.libraryView === 'grid' ? 'active' : ''}" data-lib-view="grid" title="Grid View">⊞</button>
                <button class="view-toggle-btn ${state.libraryView === 'list' ? 'active' : ''}" data-lib-view="list" title="List View">☰</button>
              </div>
            ` : ''}
            <input id="lib-filter-input" class="filter-input" placeholder="Filter" value="${esc(state.libraryFilter)}" />
          </div>
        </div>

        ${bodyHTML}
      `;

      root.querySelectorAll('[data-lib-sub]').forEach((b) => {
        b.onclick = () => {
          state.libraryTab = b.dataset.libSub;
          state.libraryFilter = '';
          renderView();
        };
      });
      root.querySelectorAll('[data-goto-lib]').forEach((b) => {
        b.onclick = () => { state.libraryTab = b.dataset.gotoLib; renderView(); };
      });
      root.querySelectorAll('[data-lib-view]').forEach((b) => {
        b.onclick = () => { state.libraryView = b.dataset.libView; renderView(); };
      });
      $('lib-filter-input')?.addEventListener('input', (e) => {
        state.libraryFilter = e.target.value;
        const caret = e.target.selectionStart;
        renderView();
        const inp = $('lib-filter-input');
        if (inp) { inp.focus(); inp.setSelectionRange(caret, caret); }
      });
      $('lib-new-pl')?.addEventListener('click', () => openCreatePlaylistModal());
      $('lib-shuffle-likes')?.addEventListener('click', () => playShuffled(state.likes));

      const filteredPls = (state.libraryTab === 'albums' ? state.albums : state.playlists).filter(filterPl);
      root.querySelectorAll('[data-lib-pl]').forEach((el) => {
        el.onclick = () => openPlaylistDetail(filteredPls[Number(el.dataset.libPl)]);
      });
      const ovPls = state.playlists.filter(filterPl).slice(0, 6);
      root.querySelectorAll('[data-lib-pl-ov]').forEach((el) => {
        el.onclick = () => openPlaylistDetail(ovPls[Number(el.dataset.libPlOv)]);
      });
      const filteredUsers = state.following.filter(filterUser);
      root.querySelectorAll('[data-lib-user]').forEach((el) => {
        el.onclick = () => openArtistProfile(filteredUsers[Number(el.dataset.libUser)]);
      });
      wireTrackContainers(root);
      return;
    }

    // 4. SEARCH VIEW
    if (state.nav === 'search') {
      activeTrackLists.set('search-tracks', state.searchResults.tracks);
      root.innerHTML = `
        <div class="lib-toolbar">
          <div class="lib-heading">Search results for “${esc(state.searchQuery)}”</div>
          <div class="chip-row" style="margin:0">
            ${[['all','All'],['tracks','Tracks'],['people','Artists'],['albums','Albums'],['sets','Playlists']].map(([k, lbl]) =>
              `<button class="chip ${state.searchFilter === k ? 'active' : ''}" data-sf="${k}">${lbl}</button>`
            ).join('')}
          </div>
        </div>

        ${state.searchResults.users.length ? `
          <section class="shelf">
            <div class="shelf-head"><div class="shelf-title">Artists</div></div>
            <div class="shelf-row">
              ${state.searchResults.users.map((u, i) => `
                <div class="sc-tile" data-search-user="${i}">
                  <div class="sc-tile-art circle"><img src="${esc(artUrl(u.avatar_url, 't500x500'))}" alt="" /></div>
                  <div class="sc-tile-title" style="justify-content:center">${esc(u.username || u.full_name || 'Artist')}</div>
                  <div class="sc-tile-sub" style="text-align:center">${fmtCount(u.followers_count)} followers</div>
                </div>
              `).join('')}
            </div>
          </section>
        ` : ''}

        ${state.searchResults.tracks.length ? `
          <section class="shelf">
            <div class="shelf-head"><div class="shelf-title">Tracks</div></div>
            ${renderTrackRowsHTML(state.searchResults.tracks, 'search-tracks')}
          </section>
        ` : ''}

        ${state.searchResults.playlists.length ? `
          <section class="shelf">
            <div class="shelf-head"><div class="shelf-title">Playlists &amp; Albums</div></div>
            <div class="sc-grid">
              ${state.searchResults.playlists.map((pl, i) => `
                <div class="sc-tile" data-search-pl="${i}">
                  <div class="sc-tile-art">
                    <img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" />
                    <div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div>
                  </div>
                  <div class="sc-tile-title">${esc(pl.title)}</div>
                  <div class="sc-tile-sub">${esc(pl.user?.username || 'SoundCloud')}</div>
                </div>
              `).join('')}
            </div>
          </section>
        ` : ''}
      `;

      root.querySelectorAll('[data-sf]').forEach((b) => {
        b.onclick = async () => {
          state.searchFilter = b.dataset.sf;
          if (state.searchQuery) {
            state.searchResults = await api.search(state.searchQuery, state.searchFilter);
          }
          renderView();
        };
      });
      root.querySelectorAll('[data-search-user]').forEach((el) => {
        el.onclick = () => openArtistProfile(state.searchResults.users[Number(el.dataset.searchUser)]);
      });
      root.querySelectorAll('[data-search-pl]').forEach((el) => {
        el.onclick = () => openPlaylistDetail(state.searchResults.playlists[Number(el.dataset.searchPl)]);
      });
      wireTrackContainers(root);
      return;
    }

    // 5. PLAYLIST DETAIL VIEW
    if (state.nav === 'playlistDetail' && state.detailPlaylist) {
      const { playlist, tracks, loading } = state.detailPlaylist;
      activeTrackLists.set('detail-pl', tracks);
      root.innerHTML = `
        <div class="detail-hero">
          <img src="${esc(artUrl(playlist.artwork_url, 't500x500'))}" alt="" />
          <div class="detail-hero-meta">
            <span class="tiny muted">${playlist.is_album ? 'ALBUM' : 'PLAYLIST'} · ${tracks.length || playlist.track_count || 0} TRACKS</span>
            <h1>${esc(playlist.title)}</h1>
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
      wireTrackContainers(root);
      return;
    }

    // 6. ARTIST PROFILE VIEW
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
            <h1>${esc(u.username || u.full_name || 'Artist')}</h1>
            <div class="muted tiny">${fmtCount(u.followers_count)} Followers · ${fmtCount(u.followings_count)} Following</div>
            <div class="detail-hero-actions">
              <button id="artist-play" class="btn-primary">▶ Play Top</button>
              <button id="artist-shuffle" class="btn-secondary">🔀 Shuffle</button>
              <button id="artist-follow" class="btn-secondary">${isFollowing ? 'Following ✓' : '+ Follow'}</button>
            </div>
          </div>
        </div>
        ${loading ? '<p class="muted">Loading artist profile...</p>' : `
          ${top.length ? `<div class="shelf"><div class="shelf-head"><div class="shelf-title">Top tracks</div></div>${renderTrackRowsHTML(top.slice(0, 6), 'artist-top')}</div>` : ''}
          ${profile?.albums?.length ? `
            <section class="shelf">
              <div class="shelf-head"><div class="shelf-title">Albums</div></div>
              <div class="shelf-row">
                ${profile.albums.map((pl, i) => `
                  <div class="sc-tile" data-ap-alb="${i}">
                    <div class="sc-tile-art"><img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" /><div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div></div>
                    <div class="sc-tile-title">${esc(pl.title)}</div>
                  </div>
                `).join('')}
              </div>
            </section>
          ` : ''}
          ${profile?.playlists?.length ? `
            <section class="shelf">
              <div class="shelf-head"><div class="shelf-title">Playlists</div></div>
              <div class="shelf-row">
                ${profile.playlists.map((pl, i) => `
                  <div class="sc-tile" data-ap-pl="${i}">
                    <div class="sc-tile-art"><img src="${esc(artUrl(pl.artwork_url, 't500x500'))}" alt="" /><div class="sc-tile-hover"><div class="sc-tile-play">▶</div></div></div>
                    <div class="sc-tile-title">${esc(pl.title)}</div>
                  </div>
                `).join('')}
              </div>
            </section>
          ` : ''}
          ${trks.length ? `<div class="shelf"><div class="shelf-head"><div class="shelf-title">Tracks</div></div>${renderTrackRowsHTML(trks.slice(0, 18), 'artist-tracks')}</div>` : ''}
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
      root.querySelectorAll('[data-ap-alb]').forEach((el) => el.onclick = () => openPlaylistDetail(profile.albums[Number(el.dataset.apAlb)]));
      root.querySelectorAll('[data-ap-pl]').forEach((el) => el.onclick = () => openPlaylistDetail(profile.playlists[Number(el.dataset.apPl)]));
      wireTrackContainers(root);
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

  // MARK: - Modals (Jam, Games, Settings, Create Playlist, Add to Playlist)
  function openModal(type) {
    state.modalType = type;
    $('modal-backdrop').classList.remove('hidden');
  }

  function closeModal() {
    state.modalType = null;
    $('modal-backdrop').classList.add('hidden');
    $('modal-box').innerHTML = '';
  }

  function openGamesModal(initialTab = null) {
    if (initialTab) games.activeTab = initialTab;
    openModal('games');
    renderGamesModal();
  }

  function renderGamesModal() {
    const box = $('modal-box');
    box.innerHTML = games.renderModalHTML(esc);
    games.wireModalEvents(box, closeModal);
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
          <div class="modal-title">👥 CloudWave Group Jam</div>
          <button id="m-close" class="icon-btn">✕</button>
        </div>
        <p class="muted">Listen in real-time sync &amp; play Chess or 21 Blackjack with friends on Windows, iPhone, iPad, or Android worldwide.</p>
        <button id="jam-start-btn" class="btn-primary big">📡 Start a Live Jam</button>
        <div class="card-box">
          <span class="field-label">Join a Friend’s Jam</span>
          <div class="row-gap">
            <input id="jam-join-input" class="text-input mono" placeholder="Enter 6-char code (e.g. K7M4P2) or invite link" />
            <button id="jam-join-btn" class="btn-primary">Join</button>
          </div>
          ${jam.statusNote ? `<div class="tiny" style="color:var(--accent)">${esc(jam.statusNote)}</div>` : ''}
        </div>
        <button id="jam-open-solo-games" class="btn-secondary">🎮 Play Solo Chess &amp; 21 Blackjack</button>
      `;
      $('m-close').onclick = closeModal;
      $('jam-start-btn').onclick = () => jam.startJam();
      $('jam-join-btn').onclick = () => jam.joinJam($('jam-join-input').value);
      $('jam-join-input').onkeydown = (e) => { if (e.key === 'Enter') jam.joinJam($('jam-join-input').value); };
      $('jam-open-solo-games').onclick = () => openGamesModal();
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

      <button id="jam-play-games" class="btn-primary big" style="width:100%">🎮 Play Together: Chess &amp; 21 Blackjack</button>

      ${cur ? `
        <div class="card-box">
          <div class="row-between">
            <div class="row-gap" style="min-width:0">
              <img src="${esc(artUrl(cur.artwork_url || cur.user?.avatar_url, 't200x200'))}" style="width:44px;height:44px;border-radius:6px;object-fit:cover" />
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
              <div style="font-weight:700;font-size:13px">${jam.allowGuestControl ? '👥 Shared Controls Enabled' : '🔒 Host-Only Controls Active'}</div>
              <div class="tiny muted">Like tracks, queue music, or play Chess together</div>
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
          ${['🔥', '❤️', '🙌', '🤯', '🎧'].map((em) => `<button class="btn-secondary" data-react="${em}" style="flex:1;font-size:17px;padding:5px">${em}</button>`).join('')}
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
                <img src="${esc(artUrl(item.artworkUrl, 't200x200'))}" style="width:36px;height:36px;border-radius:4px;object-fit:cover" />
                <div class="track-info">
                  <div class="track-title" style="font-size:12.5px">${esc(item.title)}</div>
                  <div class="track-sub" style="font-size:11px">${esc(item.artist)}</div>
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
    $('jam-play-games').onclick = () => openGamesModal();
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
            <div style="font-size:12.5px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(t.title)}</div>
            <div class="tiny muted">${esc(t.user?.username || 'Artist')}</div>
          </div>
          <button class="btn-primary" data-qadd="${i}" style="padding:5px 10px;font-size:11.5px">+ Queue</button>
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
      ['orange', '#ff5500'], ['crimson', '#ff2d55'], ['blue', '#0a84ff'],
      ['emerald', '#30d158'], ['violet', '#af52de'], ['gold', '#ffb300']
    ];

    box.innerHTML = `
      <div class="modal-header">
        <div class="modal-title">⚙️ CloudWave Settings &amp; Themes</div>
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
          <span class="field-label">Discord Rich Presence (Native IPC)</span>
          <span class="tiny" style="color:${state.rpcConnected ? '#30d158' : 'var(--accent)'};font-weight:700">${state.rpcConnected ? '● Connected' : '○ Open Discord'}</span>
        </div>
        <label class="row-between"><span>Enable Discord Rich Presence</span><input type="checkbox" id="s-rpc" ${s.discordRichPresence ? 'checked' : ''} /></label>
        <label class="row-between"><span>Display When Paused</span><input type="checkbox" id="s-paused" ${s.displayWhenPaused ? 'checked' : ''} /></label>
        <label class="row-between"><span>Show Small Icon</span><input type="checkbox" id="s-small" ${s.displaySmallIcon ? 'checked' : ''} /></label>
        <label class="row-between"><span>Show "Listen on SoundCloud" Button</span><input type="checkbox" id="s-btns" ${s.displayButtons ? 'checked' : ''} /></label>
        <label class="row-between"><span>Smart Track Parser (Artist - Title)</span><input type="checkbox" id="s-parser" ${s.trackParserEnabled ? 'checked' : ''} /></label>
        <label class="row-between"><span>Minimize to System Tray on Close</span><input type="checkbox" id="s-tray" ${s.minimizeToTray ? 'checked' : ''} /></label>
      </div>

      <div class="card-box">
        <span class="field-label">Group Listening Relay</span>
        <input id="s-jam-relay" class="text-input" value="${esc(s.jamRelayUrl || 'https://ntfy.sh')}" placeholder="https://ntfy.sh" />
      </div>

      <div class="card-box">
        <span class="field-label">Last.fm &amp; Webhooks</span>
        <label class="row-between"><span>Enable Last.fm Scrobbling</span><input type="checkbox" id="s-lfm" ${s.lastFmEnabled ? 'checked' : ''} /></label>
        <input id="s-lfm-key" class="text-input" placeholder="Last.fm API Key" value="${esc(s.lastFmApiKey)}" />
        <input id="s-lfm-sec" class="text-input" type="password" placeholder="Last.fm API Secret" value="${esc(s.lastFmApiSecret)}" />
        <input id="s-lfm-sk" class="text-input" placeholder="Last.fm Session Key" value="${esc(s.lastFmSessionKey)}" />
        <label class="row-between" style="margin-top:6px"><span>Enable Webhooks</span><input type="checkbox" id="s-wh" ${s.webhookEnabled ? 'checked' : ''} /></label>
        <input id="s-wh-url" class="text-input" placeholder="https://discord.com/api/webhooks/..." value="${esc(s.webhookUrl)}" />
        <label class="row-between"><span>Format as Discord Embed</span><input type="checkbox" id="s-wh-disc" ${s.webhookDiscordFormat ? 'checked' : ''} /></label>
        <button id="s-wh-test" class="btn-secondary">🚀 Send Test Webhook</button>
      </div>

      <div class="card-box">
        <div class="row-between">
          <div>
            <div style="font-weight:700">${esc(state.user?.username || 'Signed In')}</div>
            <div class="tiny muted">CloudWave v${esc(state.version)} · Native Windows Desktop</div>
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
        <button id="cp-submit" class="btn-primary big">☁️ Create &amp; Sync to SoundCloud</button>
      </div>
    `;
    $('m-close').onclick = closeModal;
    $('cp-submit').onclick = async () => {
      const title = $('cp-title').value.trim();
      if (!title) return;
      const created = await api.createPlaylist(title, $('cp-priv').checked, initialTrack?.id || null);
      if (created) {
        state.playlists.unshift(created);
        showToast(`Created "${title}" on SoundCloud`);
        closeModal();
        if (state.nav === 'library') renderView();
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
            <img src="${esc(artUrl(pl.artwork_url, 't200x200'))}" style="width:40px;height:40px;border-radius:4px;object-fit:cover" />
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

  function showAuthState() {
    $('signin-screen').classList.toggle('hidden', state.isLoggedIn);
    $('app-shell').classList.toggle('hidden', !state.isLoggedIn);
  }

  // MARK: - Wire Global DOM Events
  function wireEvents() {
    $('btn-signin').onclick = () => api.openLogin();
    $('brand-home').onclick = () => setNav('home');
    document.querySelectorAll('.top-nav-item').forEach((b) => b.onclick = () => setNav(b.dataset.topNav));

    const runGlobalSearch = async () => {
      const q = $('global-search-input').value.trim();
      if (!q) return;
      state.searchQuery = q;
      state.searchResults = await api.search(q, state.searchFilter);
      setNav('search');
    };
    $('global-search-btn').onclick = runGlobalSearch;
    $('global-search-input').onkeydown = (e) => { if (e.key === 'Enter') runGlobalSearch(); };

    $('btn-top-jam').onclick = () => openJamModal();
    $('btn-jam-bar').onclick = () => openJamModal();
    $('btn-np-jam').onclick = () => openJamModal();
    $('btn-top-games').onclick = () => openGamesModal();
    $('btn-top-vfd').onclick = () => openVFDVisualizer();
    $('btn-sync-top').onclick = () => syncAllData(true);
    $('btn-top-settings').onclick = () => openSettingsModal();
    $('btn-user-pill').onclick = () => openSettingsModal();

    $('btn-theme-quick').onclick = async () => {
      const next = document.body.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      state.settings = await api.updateSettings({ themeMode: next });
      applyTheme();
    };

    // Bottom Player Bar
    $('btn-play').onclick = togglePlayPause;
    $('btn-next').onclick = nextTrack;
    $('btn-prev').onclick = () => prevTrack(false);
    $('btn-shuffle').onclick = toggleShuffle;
    $('btn-repeat').onclick = cycleRepeat;
    $('bar-like').onclick = () => state.currentTrack && toggleLikeTrack(state.currentTrack);
    $('bar-artist').onclick = () => state.currentTrack?.user?.id && openArtistProfile(state.currentTrack.user);
    $('btn-bar-resync').onclick = () => jam.requestResync();

    $('btn-mute').onclick = () => {
      if (audio.volume > 0) {
        state.lastVolume = audio.volume;
        audio.volume = 0;
        $('volume-slider').value = 0;
        $('btn-mute').textContent = '🔇';
      } else {
        audio.volume = state.lastVolume || 0.85;
        $('volume-slider').value = Math.round(audio.volume * 100);
        $('btn-mute').textContent = '🔊';
      }
    };
    $('volume-slider').oninput = (e) => {
      const v = Number(e.target.value) / 100;
      audio.volume = v;
      $('btn-mute').textContent = v === 0 ? '🔇' : '🔊';
    };

    $('btn-queue-toggle').onclick = () => {
      $('queue-drawer').classList.toggle('hidden');
      renderQueueDrawer();
    };
    $('btn-close-queue').onclick = () => $('queue-drawer').classList.add('hidden');

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

    // Fullscreen Now Playing (Vinyl / Full / Card)
    const openNP = () => {
      if (!state.currentTrack) return;
      $('now-playing-overlay').classList.remove('hidden');
      renderPlayerUI();
    };
    $('bar-art-wrap').onclick = openNP;
    $('bar-title').onclick = openNP;
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
        else if (!$('queue-drawer').classList.contains('hidden')) $('queue-drawer').classList.add('hidden');
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
      updateRightRailLiveBadges();
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
    state.version = init.version || '3.0.0';
    applyTheme();
    showAuthState();
    renderPlayerUI();

    if (state.isLoggedIn) {
      await syncAllData(false);
    }
  }

  boot();
})();
