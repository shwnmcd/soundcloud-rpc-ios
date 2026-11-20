const { app, BrowserWindow, ipcMain, session, shell, Tray, Menu, globalShortcut, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const { DiscordRPCClient } = require('./discord-rpc');
const { SoundCloudDesktopAPI } = require('./soundcloud-api');
const { IntegrationsService } = require('./integrations');

// Allow remote Jam tracks to autoplay without requiring a fresh click gesture
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

const DEFAULT_SETTINGS = {
  themeMode: 'dark', // dark, light, amoled, system
  accentPreset: 'orange', // orange, crimson, blue, emerald, violet, gold
  playbackStyle: 'vinyl', // vinyl, fullscreen, card
  trackParserEnabled: true,
  discordRichPresence: true,
  discordClientId: '1090770350251458592',
  displayWhenPaused: false,
  displaySmallIcon: true,
  displayButtons: true,
  lastFmEnabled: false,
  lastFmApiKey: '',
  lastFmApiSecret: '',
  lastFmSessionKey: '',
  webhookEnabled: false,
  webhookUrl: '',
  webhookTriggerPercent: 50,
  webhookDiscordFormat: false,
  jamRelayUrl: 'https://ntfy.sh',
  minimizeToTray: false,
  vizMode: 'spectrum',
  vizColor: 'vfdMint',
  vizBands: 24,
  vizSensitivity: 1.15,
  vizPeakHold: true,
  vizShowBezel: true
};

let mainWindow = null;
let loginWindow = null;
let tray = null;
let isQuitting = false;
let pendingDeepLink = null;

const configPath = () => path.join(app.getPath('userData'), 'config.json');

// Earlier builds were named "CloudWave" / "SoundCloud RPC" — carry their sign-in & settings over once.
function readLegacyConfigRaw() {
  const legacyNames = ['CloudWave', 'SoundCloud RPC', 'cloudwave-desktop', 'soundcloud-rpc-desktop'];
  for (const name of legacyNames) {
    try {
      const p = path.join(app.getPath('appData'), name, 'config.json');
      if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8');
    } catch {}
  }
  return null;
}

function loadStore() {
  try {
    let raw = null;
    try { raw = fs.readFileSync(configPath(), 'utf8'); } catch { raw = readLegacyConfigRaw(); }
    const parsed = JSON.parse(raw);
    return {
      auth: parsed.auth || { oauthToken: '', clientId: '' },
      settings: { ...DEFAULT_SETTINGS, ...(parsed.settings || {}) }
    };
  } catch {
    return {
      auth: { oauthToken: '', clientId: '' },
      settings: { ...DEFAULT_SETTINGS }
    };
  }
}

function saveStore(store) {
  try {
    fs.mkdirSync(path.dirname(configPath()), { recursive: true });
    fs.writeFileSync(configPath(), JSON.stringify(store, null, 2), 'utf8');
  } catch {}
}

let store = { auth: { oauthToken: '', clientId: '' }, settings: { ...DEFAULT_SETTINGS } };
const rpc = new DiscordRPCClient(DEFAULT_SETTINGS.discordClientId);
const integrations = new IntegrationsService();
const scApi = new SoundCloudDesktopAPI(() => store.auth);

// Register soundcloudrpc:// Jam invite deep links (shared with iOS & Android)
if (process.defaultApp && process.argv.length >= 2) {
  app.setAsDefaultProtocolClient('soundcloudrpc', process.execPath, [path.resolve(process.argv[1])]);
} else {
  app.setAsDefaultProtocolClient('soundcloudrpc');
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_event, argv) => {
    const deep = argv.find((a) => typeof a === 'string' && /^(cloudwave|soundcloudrpc):\/\//i.test(a));
    if (deep) handleDeepLink(deep);
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });
}

function handleDeepLink(urlStr) {
  if (!urlStr) return;
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('deep-link', urlStr);
  } else {
    pendingDeepLink = urlStr;
  }
}

function createTrayIcon() {
  // Crisp inline SVG SoundCloud RPC orange circle icon for Windows tray
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><circle cx="32" cy="32" r="30" fill="#FF5500"/><path d="M18 38V28M25 42V22M32 45V19M39 42V24M46 38V30" stroke="#FFFFFF" stroke-width="4.5" stroke-linecap="round"/></svg>`;
  const img = nativeImage.createFromDataURL(`data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`);
  tray = new Tray(img.resize({ width: 16, height: 16 }));
  tray.setToolTip('SoundCloud S');
  const menu = Menu.buildFromTemplate([
    { label: 'Show SoundCloud S', click: () => { mainWindow?.show(); mainWindow?.focus(); } },
    { type: 'separator' },
    { label: 'Play / Pause', click: () => mainWindow?.webContents.send('media-command', 'play-pause') },
    { label: 'Next Track', click: () => mainWindow?.webContents.send('media-command', 'next') },
    { label: 'Previous Track', click: () => mainWindow?.webContents.send('media-command', 'prev') },
    { type: 'separator' },
    { label: 'Quit', click: () => { isQuitting = true; app.quit(); } }
  ]);
  tray.setContextMenu(menu);
  tray.on('double-click', () => {
    mainWindow?.show();
    mainWindow?.focus();
  });
}

function createMainWindow() {
  const iconSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><circle cx="32" cy="32" r="30" fill="#FF5500"/><path d="M18 38V28M25 42V22M32 45V19M39 42V24M46 38V30" stroke="#FFFFFF" stroke-width="4.5" stroke-linecap="round"/></svg>`;
  const appIcon = nativeImage.createFromDataURL(`data:image/svg+xml;base64,${Buffer.from(iconSvg).toString('base64')}`);

  mainWindow = new BrowserWindow({
    width: 1240,
    height: 820,
    minWidth: 920,
    minHeight: 620,
    backgroundColor: '#111111',
    icon: appIcon,
    autoHideMenuBar: true,
    title: 'SoundCloud S',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: false // Allows Web Audio API AnalyserNode FFT on SoundCloud CDN streams!
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow?.webContents.send('rpc-status', { connected: rpc.ready, clientId: rpc.clientId });
    if (pendingDeepLink) {
      mainWindow?.webContents.send('deep-link', pendingDeepLink);
      pendingDeepLink = null;
    }
  });

  mainWindow.on('close', (e) => {
    if (!isQuitting && store.settings.minimizeToTray) {
      e.preventDefault();
      mainWindow.hide();
    }
  });
}

async function readSoundCloudCookie() {
  try {
    const cookies = await session.defaultSession.cookies.get({ domain: 'soundcloud.com', name: 'oauth_token' });
    const found = cookies.find((c) => c.value && c.value.length > 8);
    return found ? found.value : '';
  } catch {
    return '';
  }
}

function openSoundCloudLoginWindow() {
  if (loginWindow && !loginWindow.isDestroyed()) {
    loginWindow.focus();
    return;
  }

  loginWindow = new BrowserWindow({
    width: 520,
    height: 700,
    parent: mainWindow || undefined,
    modal: false,
    title: 'Sign in to SoundCloud',
    autoHideMenuBar: true,
    backgroundColor: '#111111',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  let finished = false;
  const checkAndFinish = async () => {
    if (finished) return;
    const token = await readSoundCloudCookie();
    if (token) {
      store.auth.oauthToken = token;
      saveStore(store);
    }
    if (store.auth.oauthToken && store.auth.clientId) {
      finished = true;
      saveStore(store);
      if (loginWindow && !loginWindow.isDestroyed()) loginWindow.close();
      mainWindow?.webContents.send('auth-updated', { isLoggedIn: true });
    } else if (store.auth.oauthToken && !store.auth.clientId) {
      const curUrl = loginWindow?.webContents?.getURL() || '';
      if (!curUrl.includes('soundcloud.com/discover')) {
        loginWindow?.loadURL('https://soundcloud.com/discover').catch(() => {});
      }
    }
  };

  loginWindow.webContents.on('did-finish-load', () => { checkAndFinish(); });
  loginWindow.webContents.on('did-navigate', () => { checkAndFinish(); });
  loginWindow.on('closed', () => { loginWindow = null; });

  loginWindow.loadURL('https://soundcloud.com/signin');
}

function attachClientIdSniffer() {
  session.defaultSession.webRequest.onBeforeRequest(
    { urls: ['https://api-v2.soundcloud.com/*'] },
    (details, callback) => {
      try {
        const u = new URL(details.url);
        const cid = u.searchParams.get('client_id');
        if (cid && cid.length >= 16 && cid !== store.auth.clientId) {
          store.auth.clientId = cid;
          saveStore(store);
          if (loginWindow && !loginWindow.isDestroyed()) {
            readSoundCloudCookie().then((tok) => {
              if (tok) {
                store.auth.oauthToken = tok;
                saveStore(store);
                if (loginWindow && !loginWindow.isDestroyed()) loginWindow.close();
                mainWindow?.webContents.send('auth-updated', { isLoggedIn: true });
              }
            });
          }
        }
      } catch {}
      callback({});
    }
  );
}

function registerIPC() {
  ipcMain.handle('store:init', async () => {
    const cookieTok = await readSoundCloudCookie();
    if (cookieTok && !store.auth.oauthToken) {
      store.auth.oauthToken = cookieTok;
      saveStore(store);
    }
    return {
      isLoggedIn: Boolean(store.auth.oauthToken && store.auth.clientId),
      settings: store.settings,
      rpcConnected: rpc.ready,
      version: app.getVersion()
    };
  });

  ipcMain.handle('settings:update', (_e, patch) => {
    store.settings = { ...store.settings, ...patch };
    saveStore(store);
    if (patch.discordClientId !== undefined) {
      rpc.setClientId(store.settings.discordClientId);
    }
    if (patch.discordRichPresence === false) {
      rpc.clearActivity();
    }
    return store.settings;
  });

  ipcMain.handle('auth:login', () => {
    openSoundCloudLoginWindow();
    return true;
  });

  ipcMain.handle('auth:signout', async () => {
    store.auth.oauthToken = '';
    saveStore(store);
    scApi.currentUser = null;
    rpc.clearActivity();
    try {
      const cookies = await session.defaultSession.cookies.get({ domain: 'soundcloud.com' });
      for (const c of cookies) {
        const url = `https://${c.domain.replace(/^\./, '')}${c.path}`;
        await session.defaultSession.cookies.remove(url, c.name);
      }
    } catch {}
    return true;
  });

  // SoundCloud API v2 IPC bridge
  ipcMain.handle('sc:me', () => scApi.fetchMe());
  ipcMain.handle('sc:home', () => scApi.fetchHomeSelections());
  ipcMain.handle('sc:likes', (_e, args) => scApi.fetchLikes(args?.nextHref, args?.limit));
  ipcMain.handle('sc:library', () => scApi.fetchLibraryPlaylistsAndAlbums());
  ipcMain.handle('sc:playlistTracks', (_e, args) => scApi.fetchFullPlaylistTracks(args.playlistId, args.fallbackTracks));
  ipcMain.handle('sc:feed', (_e, args) => scApi.fetchFeed(args?.nextHref));
  ipcMain.handle('sc:history', () => scApi.fetchHistory());
  ipcMain.handle('sc:following', () => scApi.fetchFollowing());
  ipcMain.handle('sc:artist', (_e, userId) => scApi.fetchArtistProfile(userId));
  ipcMain.handle('sc:search', (_e, args) => scApi.search(args.query, args.filter));
  ipcMain.handle('sc:toggleLike', (_e, args) => scApi.toggleLike(args.trackId, args.currentlyLiked));
  ipcMain.handle('sc:toggleFollow', (_e, args) => scApi.toggleFollow(args.userId, args.currentlyFollowing));
  ipcMain.handle('sc:createPlaylist', (_e, args) => scApi.createPlaylist(args.title, args.isPrivate, args.initialTrackId));
  ipcMain.handle('sc:addTrackToPlaylist', (_e, args) => scApi.addTrackToPlaylist(args.playlistId, args.trackId));
  ipcMain.handle('sc:resolveStream', (_e, track) => scApi.resolveStreamUrl(track));

  // Playback -> Discord Rich Presence + Last.fm + Webhooks
  ipcMain.handle('playback:sync', (_e, payload) => {
    rpc.updateFromPlayback(payload, store.settings);
    integrations.onPlaybackProgress(payload, store.settings).catch(() => {});
    return { rpcConnected: rpc.ready, scrobbleCount: integrations.scrobbleCount };
  });

  ipcMain.handle('integrations:testWebhook', () => integrations.sendTestWebhook(store.settings));
  ipcMain.handle('shell:openExternal', (_e, url) => shell.openExternal(url));

  // Worldwide Jam ntfy.sh relay publish (runs in Node main process -> zero CORS issues & text/plain!)
  ipcMain.handle('jam:publish', async (_e, { url, bodyText }) => {
    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          Firebase: 'no',
          Priority: '1'
        },
        body: String(bodyText || '')
      });
      return { ok: resp.ok, status: resp.status };
    } catch (err) {
      return { ok: false, error: String(err?.message || err) };
    }
  });

  // Install info + in-app uninstall (NSIS places "Uninstall SoundCloud S.exe" next to the app)
  const uninstallerPath = () => path.join(path.dirname(process.execPath), `Uninstall ${app.getName()}.exe`);

  ipcMain.handle('app:info', () => ({
    version: app.getVersion(),
    installDir: path.dirname(process.execPath),
    isInstalled: app.isPackaged && fs.existsSync(uninstallerPath())
  }));

  ipcMain.handle('app:uninstall', () => {
    const exe = uninstallerPath();
    if (!app.isPackaged || !fs.existsSync(exe)) {
      return { ok: false, error: 'Uninstaller not found (portable or dev build).' };
    }
    try {
      spawn(exe, [], { detached: true, stdio: 'ignore' }).unref();
      isQuitting = true;
      rpc.clearActivity();
      setTimeout(() => app.quit(), 400);
      return { ok: true };
    } catch (err) {
      return { ok: false, error: String(err?.message || err) };
    }
  });

  ipcMain.handle('app:showInstallFolder', () => shell.openPath(path.dirname(process.execPath)));
}

app.whenReady().then(() => {
  store = loadStore();
  attachClientIdSniffer();
  registerIPC();
  createTrayIcon();
  createMainWindow();

  rpc.setClientId(store.settings.discordClientId);
  rpc.onStatusChange((status) => {
    mainWindow?.webContents.send('rpc-status', status);
  });
  rpc.connect(0);

  // Check command-line deep link on first launch
  const initialDeep = process.argv.find((a) => typeof a === 'string' && /^soundcloudrpc:\/\//i.test(a));
  if (initialDeep) handleDeepLink(initialDeep);

  // Register global Windows Media Keys
  try {
    globalShortcut.register('MediaPlayPause', () => mainWindow?.webContents.send('media-command', 'play-pause'));
    globalShortcut.register('MediaNextTrack', () => mainWindow?.webContents.send('media-command', 'next'));
    globalShortcut.register('MediaPreviousTrack', () => mainWindow?.webContents.send('media-command', 'prev'));
  } catch {}
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  rpc.clearActivity();
  rpc.disconnect();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
