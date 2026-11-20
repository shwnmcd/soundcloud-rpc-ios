const net = require('net');
const crypto = require('crypto');

const OP_HANDSHAKE = 0;
const OP_FRAME = 1;
const OP_CLOSE = 2;
const OP_PING = 3;
const OP_PONG = 4;

/**
 * Zero-dependency Windows/macOS/Linux Discord IPC Rich Presence Client.
 * Connects directly to Discord's local IPC pipe (\\.\pipe\discord-ipc-0..9)
 * with zero native node-gyp dependencies!
 */
class DiscordRPCClient {
  constructor(defaultClientId = '1090770350251458592') {
    this.clientId = defaultClientId;
    this.socket = null;
    this.connected = false;
    this.ready = false;
    this.buffer = Buffer.alloc(0);
    this.reconnectTimer = null;
    this.lastActivity = null;
    this.statusListeners = new Set();
  }

  onStatusChange(fn) {
    this.statusListeners.add(fn);
    return () => this.statusListeners.delete(fn);
  }

  emitStatus() {
    const status = { connected: this.ready, clientId: this.clientId };
    for (const fn of this.statusListeners) {
      try { fn(status); } catch {}
    }
  }

  setClientId(id) {
    const clean = String(id || '').trim() || '1090770350251458592';
    if (clean !== this.clientId) {
      this.clientId = clean;
      this.disconnect();
      this.connect();
    }
  }

  getPipePath(index) {
    if (process.platform === 'win32') {
      return `\\\\?\\pipe\\discord-ipc-${index}`;
    }
    const base = process.env.XDG_RUNTIME_DIR || process.env.TMPDIR || process.env.TMP || '/tmp';
    return `${base}/discord-ipc-${index}`;
  }

  connect(pipeIndex = 0) {
    if (this.connected || this.socket) return;
    if (pipeIndex > 9) {
      this.scheduleReconnect();
      return;
    }

    const pipePath = this.getPipePath(pipeIndex);
    const sock = net.createConnection(pipePath);

    const onError = () => {
      sock.removeAllListeners();
      try { sock.destroy(); } catch {}
      if (this.socket === sock) this.socket = null;
      this.connected = false;
      this.ready = false;
      this.connect(pipeIndex + 1);
    };

    sock.once('error', onError);

    sock.once('connect', () => {
      sock.removeListener('error', onError);
      this.socket = sock;
      this.connected = true;
      this.buffer = Buffer.alloc(0);

      sock.on('data', (chunk) => this.handleData(chunk));
      sock.on('close', () => {
        this.socket = null;
        this.connected = false;
        this.ready = false;
        this.emitStatus();
        this.scheduleReconnect();
      });
      sock.on('error', () => {
        try { sock.destroy(); } catch {}
      });

      this.sendPacket(OP_HANDSHAKE, { v: 1, client_id: this.clientId });
    });
  }

  scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.connected) this.connect(0);
    }, 10000);
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket) {
      try { this.socket.end(); } catch {}
      try { this.socket.destroy(); } catch {}
      this.socket = null;
    }
    this.connected = false;
    this.ready = false;
    this.emitStatus();
  }

  sendPacket(op, data) {
    if (!this.socket || !this.connected) return;
    try {
      const payload = Buffer.from(JSON.stringify(data), 'utf8');
      const header = Buffer.alloc(8);
      header.writeInt32LE(op, 0);
      header.writeInt32LE(payload.length, 4);
      this.socket.write(Buffer.concat([header, payload]));
    } catch {}
  }

  handleData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 8) {
      const op = this.buffer.readInt32LE(0);
      const len = this.buffer.readInt32LE(4);
      if (this.buffer.length < 8 + len) break;
      const bodyBuf = this.buffer.subarray(8, 8 + len);
      this.buffer = this.buffer.subarray(8 + len);

      if (op === OP_PING) {
        this.sendPacket(OP_PONG, {});
        continue;
      }
      if (op === OP_CLOSE) {
        this.disconnect();
        this.scheduleReconnect();
        return;
      }

      try {
        const msg = JSON.parse(bodyBuf.toString('utf8'));
        if (msg.cmd === 'DISPATCH' && msg.evt === 'READY') {
          this.ready = true;
          this.emitStatus();
          if (this.lastActivity) {
            this.setActivity(this.lastActivity);
          }
        }
      } catch {}
    }
  }

  setActivity(activity) {
    this.lastActivity = activity;
    if (!this.ready) {
      if (!this.connected) this.connect(0);
      return;
    }
    this.sendPacket(OP_FRAME, {
      cmd: 'SET_ACTIVITY',
      args: {
        pid: process.pid,
        activity
      },
      nonce: crypto.randomUUID()
    });
  }

  clearActivity() {
    this.lastActivity = null;
    if (!this.ready) return;
    this.sendPacket(OP_FRAME, {
      cmd: 'SET_ACTIVITY',
      args: {
        pid: process.pid,
        activity: null
      },
      nonce: crypto.randomUUID()
    });
  }

  updateFromPlayback(payload, settings) {
    if (!settings.discordRichPresence) {
      this.clearActivity();
      return;
    }
    if (!payload || !payload.title) {
      this.clearActivity();
      return;
    }
    if (!payload.isPlaying && !settings.displayWhenPaused) {
      this.clearActivity();
      return;
    }

    const nowSec = Math.floor(Date.now() / 1000);
    const elapsed = Math.max(0, Math.floor(payload.elapsedSec || 0));
    const duration = Math.max(1, Math.floor(payload.durationSec || 0));

    const activity = {
      type: 2, // Listening to SoundCloud
      details: String(payload.title).slice(0, 128),
      state: payload.isPlaying
        ? String(payload.artist || 'SoundCloud').slice(0, 128)
        : `Paused · ${String(payload.artist || 'SoundCloud')}`.slice(0, 128),
      assets: {
        large_image: payload.artwork || 'soundcloud-logo',
        large_text: String(payload.title).slice(0, 128)
      }
    };

    if (settings.displaySmallIcon) {
      activity.assets.small_image = 'soundcloud-logo';
      activity.assets.small_text = payload.jamCode
        ? `SoundCloud S · Jam ${payload.jamCode}`
        : 'SoundCloud S';
    }

    if (payload.isPlaying && duration > 0) {
      activity.timestamps = {
        start: nowSec - elapsed,
        end: nowSec - elapsed + duration
      };
    }

    if (settings.displayButtons && payload.url && payload.url.startsWith('http')) {
      activity.buttons = [
        { label: 'Listen on SoundCloud', url: payload.url }
      ];
    }

    this.setActivity(activity);
  }
}

module.exports = { DiscordRPCClient };
