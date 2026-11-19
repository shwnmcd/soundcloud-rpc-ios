import { normalizeTrackInfo, formatSeconds } from './core/trackParser.js';
import { parseMetadata } from './core/metadataParser.js';
import { BLOCKED_DOMAINS, COSMETIC_SELECTORS } from './core/adblockRules.js';
import { getLastFmSession, updateLastFmNowPlaying, scrobbleLastFmTrack } from './core/lastFmClient.js';
import { sendWebhookPayload } from './core/webhookClient.js';

const STORAGE_KEY = 'sc_rpc_web_settings_v1';

const state = {
  darkMode: true,
  rpcEnabled: true,
  trackParser: true,
  useArtistHeader: true,
  displaySmallIcon: true,
  displayButtons: true,
  displayPaused: false,
  whEnabled: false,
  whUrl: '',
  whDiscordFormat: false,
  whPercent: 50,
  lfmEnabled: false,
  lfmKey: '',
  lfmSecret: '',
  lfmSessionKey: '',
  lfmUser: '',
};

const currentTrack = {
  title: '',
  author: '',
  artwork: '',
  url: '',
  elapsedSec: 0,
  durationSec: 0,
  isPlaying: false,
  scrobbled: false,
  webhookSent: false,
};

function loadSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    Object.assign(state, saved);
  } catch {}
}

function saveSettings() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

// Register PWA service worker
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}

// DOM Helpers
const $ = (id) => document.getElementById(id);

function renderDiscordPreview() {
  const container = $('rpcPreviewCard');
  if (!state.rpcEnabled) {
    container.innerHTML = `<div class="discord-empty">Rich Presence disabled</div>`;
    return;
  }

  if (currentTrack.isPlaying && currentTrack.title) {
    const norm = normalizeTrackInfo(currentTrack.title, currentTrack.author, state.trackParser);
    const pct = currentTrack.durationSec > 0 ? Math.min(100, (currentTrack.elapsedSec / currentTrack.durationSec) * 100) : 0;
    const header = state.useArtistHeader ? `LISTENING TO ${norm.artist}` : 'LISTENING TO SOUNDCLOUD';
    const art = currentTrack.artwork || './icons/icon-192.png';

    container.innerHTML = `
      <div class="discord-header">${escapeHtml(header)}</div>
      <div class="discord-body">
        <div class="discord-art-wrap">
          <img class="discord-art" src="${escapeHtml(art)}" alt="Artwork" />
          ${state.displaySmallIcon ? '<div class="discord-small-badge">☁️</div>' : ''}
        </div>
        <div class="discord-meta">
          <div class="discord-title">${escapeHtml(norm.track)}</div>
          <div class="discord-artist">${escapeHtml(norm.artist)}</div>
          <div class="discord-progress">
            <div class="discord-bar"><div class="discord-bar-fill" style="width:${pct.toFixed(1)}%"></div></div>
            <div class="discord-times">
              <span>${formatSeconds(currentTrack.elapsedSec)}</span>
              <span>${formatSeconds(currentTrack.durationSec)}</span>
            </div>
          </div>
        </div>
      </div>
      ${
        state.displayButtons && currentTrack.url
          ? `<a class="discord-button" href="${escapeHtml(currentTrack.url)}" target="_blank" rel="noreferrer">▶️ Listen on SoundCloud</a>`
          : ''
      }
    `;
    return;
  }

  if (state.displayPaused) {
    container.innerHTML = `
      <div class="discord-header">LISTENING TO SOUNDCLOUD</div>
      <div class="discord-body">
        <div class="discord-art-wrap"><img class="discord-art" src="./icons/icon-192.png" alt="Paused" /></div>
        <div class="discord-meta">
          <div class="discord-title">Listening to SoundCloud</div>
          <div class="discord-artist">Paused</div>
        </div>
      </div>
    `;
    return;
  }

  container.innerHTML = `<div class="discord-empty">Play a track above to preview live Discord Rich Presence</div>`;
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function applyDarkMode() {
  document.documentElement.classList.toggle('theme-dark', state.darkMode);
  document.documentElement.classList.toggle('theme-light', !state.darkMode);
  $('themeToggleBtn').textContent = state.darkMode ? '🌙 Dark' : '☀️ Light';
}

function updateParserTester() {
  const title = $('parserTestTitle').value;
  const author = $('parserTestAuthor').value;
  const result = normalizeTrackInfo(title, author, state.trackParser);
  $('parserOutput').textContent = JSON.stringify(result, null, 2);
}

function updateThemeMeta() {
  const css = $('themeCssInput').value;
  const meta = parseMetadata(css, 'css');
  $('themeMetaBox').textContent = `Parsed Theme Metadata:\n${JSON.stringify(meta, null, 2)}`;
}

function updateWebhookExample() {
  const example = state.whDiscordFormat
    ? {
        username: 'SoundCloud RPC',
        embeds: [{ title: 'Instant Crush', description: 'by **Daft Punk**', color: 16733440 }],
      }
    : {
        timestamp: new Date().toISOString(),
        artist: 'Daft Punk',
        track: 'Instant Crush',
        duration: 337,
        originUrl: 'https://soundcloud.com/...',
        trackArt: 'https://i1.sndcdn.com/artworks-...-t500x500.jpg',
      };
  $('whExamplePayload').textContent = JSON.stringify(example, null, 2);
}

function renderAdblockInspector() {
  $('domainRuleCount').textContent = BLOCKED_DOMAINS.length;
  $('cosmeticRuleCount').textContent = COSMETIC_SELECTORS.length;
  const list = $('adblockList');
  list.innerHTML = BLOCKED_DOMAINS.map((d) => `<span class="rule-chip">${escapeHtml(d)}</span>`).join('');
}

async function handlePlaybackProgress() {
  if (!currentTrack.isPlaying || !currentTrack.title || currentTrack.durationSec <= 0) return;

  const norm = normalizeTrackInfo(currentTrack.title, currentTrack.author, state.trackParser);

  // Trigger Webhook at configured percentage
  if (state.whEnabled && state.whUrl && !currentTrack.webhookSent) {
    const pct = (currentTrack.elapsedSec / currentTrack.durationSec) * 100;
    if (pct >= state.whPercent) {
      currentTrack.webhookSent = true;
      try {
        const res = await sendWebhookPayload({
          url: state.whUrl,
          discordFormat: state.whDiscordFormat,
          artist: norm.artist,
          track: norm.track,
          duration: currentTrack.durationSec,
          originUrl: currentTrack.url,
          trackArt: currentTrack.artwork,
        });
        $('whStatus').textContent = res.ok ? `Sent (${res.status}): ${norm.artist} – ${norm.track}` : `Failed (${res.status})`;
      } catch (e) {
        $('whStatus').textContent = `Error: ${e.message}`;
      }
    }
  }

  // Trigger Last.fm Scrobble at min(50%, 240s)
  if (state.lfmEnabled && state.lfmSessionKey && !currentTrack.scrobbled) {
    const threshold = Math.min(currentTrack.durationSec / 2, 240);
    if (currentTrack.elapsedSec >= Math.max(10, threshold)) {
      currentTrack.scrobbled = true;
      try {
        await scrobbleLastFmTrack({
          apiKey: state.lfmKey,
          apiSecret: state.lfmSecret,
          sessionKey: state.lfmSessionKey,
          artist: norm.artist,
          track: norm.track,
        });
        $('lfmBanner').textContent = `Scrobbled: ${norm.artist} – ${norm.track}`;
      } catch {}
    }
  }
}

function setupSoundCloudWidget() {
  if (!window.SC || !window.SC.Widget) return;
  const widget = window.SC.Widget($('scWidget'));

  function syncSound(isPlaying) {
    widget.getCurrentSound((sound) => {
      if (!sound) return;
      const changed = currentTrack.title !== sound.title || currentTrack.url !== sound.permalink_url;
      currentTrack.title = sound.title || '';
      currentTrack.author = sound.user?.username || '';
      currentTrack.artwork = (sound.artwork_url || sound.user?.avatar_url || '').replace('-large.', '-t500x500.');
      currentTrack.url = sound.permalink_url || '';
      currentTrack.durationSec = (sound.duration || 0) / 1000;
      currentTrack.isPlaying = isPlaying;

      if (changed) {
        currentTrack.scrobbled = false;
        currentTrack.webhookSent = false;
        if (isPlaying && state.lfmEnabled && state.lfmSessionKey) {
          const norm = normalizeTrackInfo(currentTrack.title, currentTrack.author, state.trackParser);
          updateLastFmNowPlaying({
            apiKey: state.lfmKey,
            apiSecret: state.lfmSecret,
            sessionKey: state.lfmSessionKey,
            artist: norm.artist,
            track: norm.track,
          }).catch(() => {});
        }
      }

      const pill = $('playbackPill');
      pill.textContent = isPlaying ? 'Playing' : 'Paused';
      pill.classList.toggle('playing', isPlaying);
      renderDiscordPreview();
    });
  }

  widget.bind(window.SC.Widget.Events.PLAY, () => syncSound(true));
  widget.bind(window.SC.Widget.Events.PAUSE, () => syncSound(false));
  widget.bind(window.SC.Widget.Events.FINISH, () => syncSound(false));
  widget.bind(window.SC.Widget.Events.PLAY_PROGRESS, (ev) => {
    currentTrack.elapsedSec = (ev.currentPosition || 0) / 1000;
    if (!currentTrack.title) {
      syncSound(true);
    } else {
      renderDiscordPreview();
      handlePlaybackProgress();
    }
  });

  $('loadUrlForm').addEventListener('submit', (e) => {
    e.preventDefault();
    const url = $('scUrlInput').value.trim();
    if (!url) return;
    widget.load(url, {
      color: '#ff5500',
      auto_play: true,
      hide_related: true,
      show_comments: false,
      show_reposts: false,
      show_teaser: false,
    });
  });
}

async function checkLastFmCallback() {
  const params = new URLSearchParams(window.location.search);
  const token = params.get('token');
  if (token && state.lfmKey && state.lfmSecret) {
    try {
      const data = await getLastFmSession(state.lfmKey, state.lfmSecret, token);
      if (data.session?.key) {
        state.lfmSessionKey = data.session.key;
        state.lfmUser = data.session.name || 'Connected';
        state.lfmEnabled = true;
        saveSettings();
        window.history.replaceState({}, document.title, window.location.pathname);
      }
    } catch {}
  }
  updateLastFmBanner();
}

function updateLastFmBanner() {
  $('lfmBanner').textContent = state.lfmSessionKey
    ? `Status: Connected (${state.lfmUser || 'Session Active'})`
    : 'Status: Not Connected';
}

function downloadFile(filename, content, mime = 'text/plain') {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function initUI() {
  loadSettings();
  applyDarkMode();

  // Tabs
  document.querySelectorAll('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach((b) => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach((p) => p.classList.remove('active'));
      btn.classList.add('active');
      $(btn.dataset.tab).classList.add('active');
    });
  });

  // Theme toggle
  $('themeToggleBtn').addEventListener('click', () => {
    state.darkMode = !state.darkMode;
    saveSettings();
    applyDarkMode();
  });

  // Bind checkboxes
  const checkboxMap = [
    ['optRpcEnabled', 'rpcEnabled'],
    ['optTrackParser', 'trackParser'],
    ['optUseArtistHeader', 'useArtistHeader'],
    ['optDisplaySmallIcon', 'displaySmallIcon'],
    ['optDisplayButtons', 'displayButtons'],
    ['optDisplayPaused', 'displayPaused'],
    ['whEnabled', 'whEnabled'],
    ['whDiscordFormat', 'whDiscordFormat'],
    ['lfmEnabled', 'lfmEnabled'],
  ];

  checkboxMap.forEach(([id, key]) => {
    const el = $(id);
    el.checked = !!state[key];
    el.addEventListener('change', () => {
      state[key] = el.checked;
      saveSettings();
      renderDiscordPreview();
      updateParserTester();
      updateWebhookExample();
    });
  });

  // Bind text/range inputs
  $('whUrl').value = state.whUrl;
  $('whUrl').addEventListener('input', (e) => { state.whUrl = e.target.value; saveSettings(); });

  $('whPercent').value = state.whPercent;
  $('whPercentVal').textContent = `${state.whPercent}%`;
  $('whPercent').addEventListener('input', (e) => {
    state.whPercent = Number(e.target.value);
    $('whPercentVal').textContent = `${state.whPercent}%`;
    saveSettings();
  });

  $('lfmKey').value = state.lfmKey;
  $('lfmKey').addEventListener('input', (e) => { state.lfmKey = e.target.value.trim(); saveSettings(); });
  $('lfmSecret').value = state.lfmSecret;
  $('lfmSecret').addEventListener('input', (e) => { state.lfmSecret = e.target.value.trim(); saveSettings(); });

  // Test Webhook
  $('whTestBtn').addEventListener('click', async () => {
    if (!state.whUrl.trim()) {
      $('whStatus').textContent = 'Enter a webhook URL first.';
      return;
    }
    $('whStatus').textContent = 'Sending...';
    try {
      const res = await sendWebhookPayload({
        url: state.whUrl.trim(),
        discordFormat: state.whDiscordFormat,
        artist: 'Daft Punk',
        track: 'Instant Crush (Test)',
        duration: 337,
        originUrl: 'https://soundcloud.com',
        trackArt: 'https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8fe7.png',
      });
      $('whStatus').textContent = res.ok ? `Success (HTTP ${res.status})` : `Failed (HTTP ${res.status})`;
    } catch (err) {
      $('whStatus').textContent = `Blocked/Error: ${err.message}`;
    }
  });

  // Last.fm Auth
  $('lfmAuthBtn').addEventListener('click', () => {
    if (!state.lfmKey || !state.lfmSecret) {
      $('lfmBanner').textContent = 'Enter both Last.fm API Key and Secret first.';
      return;
    }
    const cb = encodeURIComponent(window.location.href.split('?')[0]);
    window.location.href = `https://www.last.fm/api/auth/?api_key=${encodeURIComponent(state.lfmKey)}&cb=${cb}`;
  });

  $('lfmDisconnectBtn').addEventListener('click', () => {
    state.lfmSessionKey = '';
    state.lfmUser = '';
    state.lfmEnabled = false;
    $('lfmEnabled').checked = false;
    saveSettings();
    updateLastFmBanner();
  });

  // Track parser tester
  $('parserTestTitle').addEventListener('input', updateParserTester);
  $('parserTestAuthor').addEventListener('input', updateParserTester);
  updateParserTester();

  // Theme studio
  $('themeCssInput').addEventListener('input', updateThemeMeta);
  updateThemeMeta();
  $('exportThemeBtn').addEventListener('click', () => {
    const css = $('themeCssInput').value;
    const meta = parseMetadata(css, 'css');
    const filename = (meta.name || 'CustomTheme').replace(/[^a-z0-9_-]+/gi, '-') + '.css';
    downloadFile(filename, css, 'text/css');
  });

  // AdBlocker export
  renderAdblockInspector();
  $('exportContentBlockerBtn').addEventListener('click', () => {
    const rules = BLOCKED_DOMAINS.map((d) => ({
      trigger: { 'url-filter': `^https?://([^/]+\\.)?${d.replace(/\./g, '\\.')}.*` },
      action: { type: 'block' },
    }));
    rules.push({
      trigger: { 'url-filter': '^https?://([^/]+\\.)?soundcloud\\.com/.*' },
      action: { type: 'css-display-none', selector: COSMETIC_SELECTORS.join(', ') },
    });
    downloadFile('soundcloud-content-blocker.json', JSON.stringify(rules, null, 2), 'application/json');
  });

  updateWebhookExample();
  renderDiscordPreview();
  checkLastFmCallback();
  setupSoundCloudWidget();
}

initUI();
