/**
 * SoundCloud S Worldwide Group Listening ("Jam") & Multiplayer Game Sync Engine
 * Wire-compatible with SoundCloud S for iOS & Android.
 */
class DesktopJamManager {
  constructor(hooks) {
    this.hooks = hooks;
    this.clientId = localStorage.getItem('scrpc_jam_uuid') || crypto.randomUUID();
    localStorage.setItem('scrpc_jam_uuid', this.clientId);

    this.isActive = false;
    this.isHost = false;
    this.roomCode = '';
    this.connectionState = 'disconnected'; // disconnected | connecting | connected | reconnecting
    this.allowGuestControl = false; // Host Only by default!
    this.participants = [];
    this.sharedQueue = [];
    this.statusNote = '';
    this.ws = null;
    this.heartbeatTimer = null;
    this.reconnectTimer = null;
    this.lastNtfyId = null;
    this.reconnectAttempt = 0;

    // Cross-platform Multiplayer Mini-Game Sync
    this.gameMatches = new Map(); // matchId -> match (Chess / Connect Four)
    this.blackjackFeed = [];
  }

  get canControlPlayback() {
    return !this.isActive || this.isHost || this.allowGuestControl;
  }

  get isGuestLocked() {
    return this.isActive && !this.isHost && !this.allowGuestControl;
  }

  get listenerCount() {
    return Math.max(1, this.participants.length);
  }

  get myId() {
    return this.clientId;
  }

  get myName() {
    return this.hooks.getDisplayName();
  }

  get otherParticipants() {
    return this.participants.filter((p) => p.id !== this.clientId);
  }

  get inviteLink() {
    return this.roomCode ? `soundcloudrpc://jam/${this.roomCode}` : '';
  }

  get shareText() {
    return `Join my Jam on SoundCloud S! Open SoundCloud S and enter code ${this.roomCode} or tap: ${this.inviteLink}`;
  }

  get relayBase() {
    const raw = String(this.hooks.getRelayUrl() || '').trim();
    if (!raw) return 'https://ntfy.sh';
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  static normalizeCode(input) {
    let s = String(input || '').trim();
    const idx = s.toLowerCase().indexOf('jam/');
    if (idx >= 0) s = s.slice(idx + 4);
    return s.toUpperCase().replace(/^JAM-/, '').replace(/[^A-Z0-9]/g, '').slice(0, 8);
  }

  static generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let out = '';
    for (let i = 0; i < 6; i++) out += chars[Math.floor(Math.random() * chars.length)];
    return out;
  }

  static async topicName(code) {
    const data = new TextEncoder().encode(`scrpc-jam-v1:${code.toUpperCase()}`);
    const buf = await crypto.subtle.digest('SHA-256', data);
    const hex = [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
    return `scrpc-jam-${hex.slice(0, 20)}`;
  }

  static trackToRef(track) {
    if (!track) return null;
    return {
      id: Number(track.id),
      title: track.title || 'Untitled Track',
      artist: track.user?.username || track.user?.full_name || track.artist || 'Unknown Artist',
      artworkUrl: track.artwork_url || track.user?.avatar_url || track.artworkUrl || null,
      durationMs: track.duration || track.durationMs || 0,
      permalinkUrl: track.permalink_url || track.permalinkUrl || null
    };
  }

  static refToTrack(ref) {
    return {
      id: Number(ref.id),
      title: ref.title || 'Untitled Track',
      duration: ref.durationMs || 0,
      artwork_url: ref.artworkUrl || null,
      permalink_url: ref.permalinkUrl || null,
      user: { id: 0, username: ref.artist || 'Unknown Artist', full_name: ref.artist || 'Unknown Artist' }
    };
  }

  async startJam() {
    await this.leaveJam(true);
    const code = DesktopJamManager.generateCode();
    this.roomCode = code;
    this.isHost = true;
    this.isActive = true;
    this.allowGuestControl = false; // Host Only by default!
    this.lastNtfyId = null;
    this.reconnectAttempt = 0;
    this.statusNote = 'Connecting live Jam...';
    this.blackjackFeed = [];
    this.participants = [
      {
        id: this.clientId,
        name: this.hooks.getDisplayName(),
        avatarUrl: this.hooks.getAvatarUrl(),
        isHost: true,
        lastSeen: Date.now() / 1000
      }
    ];
    this.syncQueueFromPlayer();
    this.hooks.onUpdate();
    await this.connectSocket();
    this.startHeartbeat();
    this.hooks.onToast(`Jam started · Code ${code}`);
  }

  async joinJam(codeOrUrl) {
    const code = DesktopJamManager.normalizeCode(codeOrUrl);
    if (code.length < 4) {
      this.statusNote = 'Enter a valid 6-character Jam code';
      this.hooks.onUpdate();
      return;
    }
    await this.leaveJam(true);
    this.roomCode = code;
    this.isHost = false;
    this.isActive = true;
    this.allowGuestControl = false;
    this.lastNtfyId = null;
    this.reconnectAttempt = 0;
    this.statusNote = `Connecting to Jam ${code}...`;
    this.blackjackFeed = [];
    this.participants = [
      {
        id: this.clientId,
        name: this.hooks.getDisplayName(),
        avatarUrl: this.hooks.getAvatarUrl(),
        isHost: false,
        lastSeen: Date.now() / 1000
      }
    ];
    this.hooks.onUpdate();
    await this.connectSocket();
    this.startHeartbeat();
    this.hooks.onToast(`Joined Jam ${code}`);
  }

  async leaveJam(silent = false) {
    const wasActive = this.isActive;
    const wasHost = this.isHost;
    const oldCode = this.roomCode;

    if (wasActive && oldCode) {
      this.publish(wasHost ? 'ended' : 'leave', { explicitCode: oldCode }).catch(() => {});
    }

    clearInterval(this.heartbeatTimer);
    clearTimeout(this.reconnectTimer);
    this.heartbeatTimer = null;
    this.reconnectTimer = null;
    if (this.ws) {
      try { this.ws.close(1000, 'Leave'); } catch {}
      this.ws = null;
    }

    this.isActive = false;
    this.isHost = false;
    this.roomCode = '';
    this.connectionState = 'disconnected';
    this.participants = [];
    this.sharedQueue = [];
    this.statusNote = '';
    this.lastNtfyId = null;
    this.gameMatches = new Map();
    this.blackjackFeed = [];
    this.hooks.onUpdate();

    if (wasActive && !silent) {
      this.hooks.onToast(wasHost ? 'Ended Jam session' : 'Left Jam session');
    }
  }

  setAllowGuestControl(enabled) {
    this.allowGuestControl = Boolean(enabled);
    this.hooks.onUpdate();
    if (this.isActive && this.isHost) {
      this.broadcastHostState();
    }
  }

  requestResync() {
    if (!this.isActive) return;
    this.statusNote = 'Syncing with Host...';
    this.hooks.onUpdate();
    this.publish('sync_request');
  }

  addTrackToJam(track) {
    if (!this.isActive) return;
    const ref = DesktopJamManager.trackToRef(track);
    if (this.isHost) {
      this.hooks.onHostAppendQueue(track);
      this.syncQueueFromPlayer();
      this.broadcastHostState();
      this.hooks.onToast(`Queued "${ref.title}" for Jam`);
    } else {
      this.publish('queue_add', { track: ref });
      this.hooks.onToast(`Sent "${ref.title}" to Jam queue`);
    }
  }

  sendReaction(emoji) {
    if (!this.isActive) return;
    this.hooks.onReaction({ emoji, senderName: this.hooks.getDisplayName() });
    this.publish('reaction', { emoji });
  }

  sendChessState(jsonString) {
    if (!this.isActive) return;
    this.publish('game_chess', { gameData: jsonString });
  }

  sendConnect4State(jsonString) {
    if (!this.isActive) return;
    this.publish('game_connect4', { gameData: jsonString });
  }

  sendBlackjackUpdate(jsonString) {
    if (!this.isActive) return;
    this.publish('game_blackjack', { gameData: jsonString });
  }

  onLocalPlaybackChange(action, seekSec = null) {
    if (!this.isActive) return;
    if (this.isHost) {
      this.syncQueueFromPlayer();
      this.broadcastHostState();
    } else if (this.allowGuestControl) {
      const ref = action === 'track' ? DesktopJamManager.trackToRef(this.hooks.getCurrentTrack()) : null;
      this.publish('control', { action, track: ref, seekSec });
    }
  }

  syncQueueFromPlayer() {
    const q = this.hooks.getQueue() || [];
    this.sharedQueue = q.slice(0, 25).map((t) => DesktopJamManager.trackToRef(t)).filter(Boolean);
  }

  async connectSocket() {
    if (!this.isActive || !this.roomCode) return;
    if (this.ws) {
      try { this.ws.close(); } catch {}
      this.ws = null;
    }

    this.connectionState = this.reconnectAttempt === 0 ? 'connecting' : 'reconnecting';
    this.hooks.onUpdate();

    const topic = await DesktopJamManager.topicName(this.roomCode);
    const wsBase = this.relayBase.replace(/^https:\/\//i, 'wss://').replace(/^http:\/\//i, 'ws://');
    const since = this.lastNtfyId || 'latest';
    const ws = new WebSocket(`${wsBase}/${topic}/ws?since=${encodeURIComponent(since)}`);
    this.ws = ws;

    ws.onopen = async () => {
      if (this.ws !== ws) return;
      this.connectionState = 'connected';
      this.reconnectAttempt = 0;
      this.statusNote = this.isHost ? 'Live · Sharing with friends' : 'Connected · Waiting for Host';
      this.hooks.onUpdate();

      // Immediately announce presence & sync once socket is confirmed open!
      if (this.isHost) {
        await this.broadcastHostState();
      } else {
        await this.publish('join');
        setTimeout(() => {
          if (this.isActive && !this.isHost) this.publish('sync_request');
        }, 450);
      }
    };

    ws.onmessage = (msg) => {
      if (this.ws !== ws) return;
      this.handleRawFrame(msg.data);
    };

    ws.onerror = () => {};

    ws.onclose = () => {
      if (this.ws !== ws || !this.isActive) return;
      this.connectionState = 'reconnecting';
      this.reconnectAttempt = Math.min(this.reconnectAttempt + 1, 4);
      const delaySec = Math.min(15, Math.pow(2, this.reconnectAttempt));
      this.statusNote = `Reconnecting in ${delaySec}s...`;
      this.hooks.onUpdate();
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = setTimeout(() => {
        if (this.isActive) this.connectSocket();
      }, delaySec * 1000);
    };
  }

  startHeartbeat() {
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = setInterval(() => {
      if (!this.isActive) return;
      const now = Date.now() / 1000;
      this.participants = this.participants.filter((p) => p.id === this.clientId || now - p.lastSeen < 70);
      this.hooks.onUpdate();
      this.publish('heartbeat');
      if (this.isHost) this.broadcastHostState();
    }, 18000);
  }

  async broadcastHostState() {
    if (!this.isActive || !this.isHost) return;
    this.syncQueueFromPlayer();
    const cur = this.hooks.getCurrentTrack();
    await this.publish('state', {
      allowGuestControl: this.allowGuestControl,
      track: DesktopJamManager.trackToRef(cur),
      isPlaying: this.hooks.getIsPlaying(),
      positionSec: this.hooks.getElapsedSec(),
      queue: this.sharedQueue
    });
  }

  async publish(type, extra = {}) {
    const code = extra.explicitCode || this.roomCode;
    if (!code) return;
    const topic = await DesktopJamManager.topicName(code);
    const ev = {
      v: 1,
      type,
      senderId: this.clientId,
      senderName: this.hooks.getDisplayName(),
      senderAvatar: this.hooks.getAvatarUrl() || null,
      isHost: this.isHost,
      sentAt: Date.now() / 1000,
      allowGuestControl: extra.allowGuestControl ?? null,
      track: extra.track ?? null,
      isPlaying: extra.isPlaying ?? null,
      positionSec: extra.positionSec ?? null,
      queue: extra.queue ?? null,
      action: extra.action ?? null,
      seekSec: extra.seekSec ?? null,
      emoji: extra.emoji ?? null,
      gameData: extra.gameData ?? null
    };

    const url = `${this.relayBase}/${topic}`;
    const bodyText = JSON.stringify(ev);

    // Publish via Electron main-process Node fetch with text/plain (zero CORS & ntfy.sh raw payload!)
    try {
      if (window.scDesktop?.jamPublish) {
        await window.scDesktop.jamPublish(url, bodyText);
        return;
      }
      await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          Firebase: 'no',
          Priority: '1'
        },
        body: bodyText
      });
    } catch {}
  }

  async handleRawFrame(text) {
    let env;
    try { env = JSON.parse(text); } catch { return; }
    if (env.id) this.lastNtfyId = env.id;
    if (env.event !== 'message' || !env.message) return;

    let ev;
    try { ev = JSON.parse(env.message); } catch { return; }
    if (!ev || ev.senderId === this.clientId) return;

    if (ev.type !== 'leave' && ev.type !== 'ended') {
      const now = Date.now() / 1000;
      const idx = this.participants.findIndex((p) => p.id === ev.senderId);
      const entry = {
        id: ev.senderId,
        name: ev.senderName || 'Listener',
        avatarUrl: ev.senderAvatar || null,
        isHost: Boolean(ev.isHost),
        lastSeen: now
      };
      if (idx >= 0) this.participants[idx] = entry;
      else this.participants.push(entry);
    }

    switch (ev.type) {
      case 'join':
        this.hooks.onToast(`${ev.senderName} joined the Jam`);
        if (this.isHost) this.broadcastHostState();
        break;
      case 'leave':
        this.participants = this.participants.filter((p) => p.id !== ev.senderId);
        this.hooks.onToast(`${ev.senderName} left the Jam`);
        break;
      case 'ended':
        if (!this.isHost) {
          this.hooks.onToast(`${ev.senderName} ended the Jam`);
          await this.leaveJam(true);
          return;
        }
        break;
      case 'sync_request':
        if (this.isHost) this.broadcastHostState();
        break;
      case 'reaction':
        if (ev.emoji) this.hooks.onReaction({ emoji: ev.emoji, senderName: ev.senderName });
        break;
      case 'queue_add':
        if (this.isHost && ev.track) {
          this.hooks.onHostAppendQueue(DesktopJamManager.refToTrack(ev.track));
          this.syncQueueFromPlayer();
          this.hooks.onToast(`${ev.senderName} queued "${ev.track.title}"`);
          this.broadcastHostState();
        }
        break;
      case 'control':
        if (this.isHost && this.allowGuestControl && ev.action) {
          this.hooks.onApplyGuestControl(ev.action, ev.track, ev.seekSec);
        }
        break;
      case 'game_chess':
        if (ev.gameData) {
          this.hooks.onChessRemote?.(ev.gameData, ev.senderName, ev.senderId);
        }
        break;
      case 'game_connect4':
        if (ev.gameData) {
          this.hooks.onConnect4Remote?.(ev.gameData, ev.senderName, ev.senderId);
        }
        break;
      case 'game_blackjack':
        if (ev.gameData) {
          try {
            const parsed = JSON.parse(ev.gameData);
            const summary = parsed?.summary ? `${ev.senderName}: ${parsed.summary}` : `${ev.senderName} played a hand`;
            this.blackjackFeed.unshift({ text: summary, time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) });
            this.blackjackFeed = this.blackjackFeed.slice(0, 8);
            this.hooks.onBlackjackRemote?.(summary, parsed);
          } catch {}
        }
        break;
      case 'state':
        if (!this.isHost) {
          if (typeof ev.allowGuestControl === 'boolean') {
            this.allowGuestControl = ev.allowGuestControl;
          }
          if (Array.isArray(ev.queue)) {
            this.sharedQueue = ev.queue;
          }
          if (ev.track) {
            const lag = Math.max(0, Math.min(15, Date.now() / 1000 - (ev.sentAt || Date.now() / 1000)));
            const playing = ev.isPlaying !== false;
            const basePos = Number(ev.positionSec || 0);
            const targetPos = playing ? basePos + lag : basePos;
            const scTrack = DesktopJamManager.refToTrack(ev.track);
            const scQueue = (ev.queue || [ev.track]).map((r) => DesktopJamManager.refToTrack(r));
            this.statusNote = `Synced with ${ev.senderName}`;
            await this.hooks.onApplyRemoteState(scTrack, scQueue, playing, targetPos);
          }
        }
        break;
    }

    this.hooks.onUpdate();
  }
}

window.DesktopJamManager = DesktopJamManager;
