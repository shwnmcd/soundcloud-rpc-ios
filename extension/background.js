const SEPARATOR_REGEX = /(\s+[\u002D\u2013\u2014\u2015]+\s+|[\u002D\u2013\u2014\u2015]{2,})/;
const INVALID_PATTERNS = [/^\s*$/, /^[\u002D\u2013\u2014\u2015]/, /[\u002D\u2013\u2014\u2015]$/, /(.)\1{4,}/, /[\u002D\u2013\u2014\u2015]{2,}/];

function normalizeTrackInfo(title, author, useParser = true) {
  if (!useParser || !title) {
    return { artist: author || 'Unknown Artist', track: (title || '').split('\n')[0].trim() || 'Unknown Track' };
  }
  const clean = title.split('\n')[0].trim();
  const match = clean.match(SEPARATOR_REGEX);
  if (match && match.index > 0) {
    const a = clean.substring(0, match.index).trim();
    const t = clean.substring(match.index + match[0].length).trim();
    if (a && t && !INVALID_PATTERNS.some((p) => p.test(a) || p.test(t))) {
      return { artist: a, track: t };
    }
  }
  return { artist: author || 'Unknown Artist', track: clean || 'Unknown Track' };
}

function timeToSec(str) {
  if (!str) return 0;
  const raw = str.trim().replace(/^-/, '');
  return raw.split(':').reduce((acc, part) => acc * 60 + (parseInt(part, 10) || 0), 0);
}

let lastWebhookKey = '';

async function handleTrackUpdate(track) {
  const cfg = await chrome.storage.local.get([
    'trackParser',
    'webhookEnabled',
    'webhookUrl',
    'webhookPercent',
    'webhookDiscord',
  ]);

  const parsed = normalizeTrackInfo(track.title, track.author, cfg.trackParser !== false);
  await chrome.storage.local.set({
    currentTrack: { ...track, parsedArtist: parsed.artist, parsedTrack: parsed.track },
  });

  if (cfg.webhookEnabled && cfg.webhookUrl && track.isPlaying && track.title) {
    const elapsed = timeToSec(track.elapsed);
    const total = timeToSec(track.duration);
    const pct = total > 0 ? (elapsed / total) * 100 : 0;
    const key = `${parsed.artist}::${parsed.track}`;
    if (pct >= (cfg.webhookPercent ?? 50) && key !== lastWebhookKey) {
      lastWebhookKey = key;
      const isDiscord = cfg.webhookDiscord || cfg.webhookUrl.includes('discord.com/api/webhooks');
      const body = isDiscord
        ? {
            username: 'SoundCloud RPC',
            embeds: [
              {
                title: parsed.track,
                description: `by **${parsed.artist}**`,
                url: track.url || 'https://soundcloud.com',
                color: 0xff5500,
                thumbnail: track.artwork ? { url: track.artwork } : undefined,
                timestamp: new Date().toISOString(),
              },
            ],
          }
        : {
            timestamp: new Date().toISOString(),
            artist: parsed.artist,
            track: parsed.track,
            duration: total,
            originUrl: track.url,
            trackArt: track.artwork,
          };

      fetch(cfg.webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }).catch(() => {});
    }
  }
}

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'TRACK_UPDATE') {
    handleTrackUpdate(msg.payload);
  } else if (msg.type === 'SET_ADBLOCK') {
    chrome.declarativeNetRequest.updateEnabledRulesets(
      msg.enabled ? { enableRulesetIds: ['sc_adblock_rules'] } : { disableRulesetIds: ['sc_adblock_rules'] }
    );
  }
});
