const crypto = require('crypto');

/**
 * Last.fm Scrobbling & Custom / Discord Webhooks Service for Desktop
 */
class IntegrationsService {
  constructor() {
    this.scrobbledKey = '';
    this.webhookKey = '';
    this.nowPlayingKey = '';
    this.scrobbleCount = 0;
  }

  md5(str) {
    return crypto.createHash('md5').update(str, 'utf8').digest('hex');
  }

  async onPlaybackProgress(track, settings) {
    if (!track || !track.title || !track.isPlaying) return;
    const trackKey = `${track.id}-${track.title}`;
    const elapsed = Number(track.elapsedSec || 0);
    const duration = Math.max(1, Number(track.durationSec || 0));
    const pct = (elapsed / duration) * 100;

    // 1. Last.fm Now Playing + Scrobble (50% or 4 mins)
    if (settings.lastFmEnabled && settings.lastFmApiKey && settings.lastFmApiSecret && settings.lastFmSessionKey) {
      if (this.nowPlayingKey !== trackKey) {
        this.nowPlayingKey = trackKey;
        this.sendLastFm('track.updateNowPlaying', track, settings).catch(() => {});
      }
      if (this.scrobbledKey !== trackKey && duration >= 30 && (elapsed >= duration * 0.5 || elapsed >= 240)) {
        this.scrobbledKey = trackKey;
        this.sendLastFm('track.scrobble', track, settings)
          .then((ok) => { if (ok) this.scrobbleCount++; })
          .catch(() => {});
      }
    }

    // 2. Webhooks (JSON or Discord Embed)
    if (settings.webhookEnabled && settings.webhookUrl && this.webhookKey !== trackKey) {
      const trigger = Number(settings.webhookTriggerPercent ?? 50);
      if (pct >= trigger) {
        this.webhookKey = trackKey;
        this.sendWebhook(track, settings).catch(() => {});
      }
    }
  }

  async sendLastFm(method, track, settings) {
    const params = {
      method,
      api_key: settings.lastFmApiKey.trim(),
      sk: settings.lastFmSessionKey.trim(),
      artist: track.artist || 'Unknown Artist',
      track: track.title || 'Unknown Track'
    };
    if (method === 'track.scrobble') {
      params.timestamp = String(Math.floor(Date.now() / 1000));
    }
    const keys = Object.keys(params).sort();
    const sigBase = keys.map((k) => `${k}${params[k]}`).join('') + settings.lastFmApiSecret.trim();
    params.api_sig = this.md5(sigBase);
    params.format = 'json';

    const body = new URLSearchParams(params);
    const resp = await fetch('https://ws.audioscrobbler.com/2.0/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });
    return resp.ok;
  }

  async sendWebhook(track, settings) {
    const url = (settings.webhookUrl || '').trim();
    if (!url) return 'No webhook URL configured';

    const body = settings.webhookDiscordFormat
      ? {
          embeds: [
            {
              title: track.title,
              description: `By **${track.artist}**`,
              url: track.url || undefined,
              color: 0xff5500,
              thumbnail: track.artwork ? { url: track.artwork } : undefined,
              footer: { text: 'SoundCloud RPC Desktop' },
              timestamp: new Date().toISOString()
            }
          ]
        }
      : {
          timestamp: new Date().toISOString(),
          artist: track.artist,
          track: track.title,
          duration: Math.round(track.durationSec || 0),
          originUrl: track.url || '',
          trackArt: track.artwork || ''
        };

    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    return resp.ok ? `Sent (HTTP ${resp.status})` : `Failed (HTTP ${resp.status})`;
  }

  async sendTestWebhook(settings) {
    return this.sendWebhook(
      {
        title: 'Test Track (SoundCloud RPC Desktop)',
        artist: 'SoundCloud RPC',
        durationSec: 215,
        url: 'https://soundcloud.com',
        artwork: 'https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8fe7.png'
      },
      settings
    );
  }
}

module.exports = { IntegrationsService };
