export async function sendWebhookPayload({ url, discordFormat, artist, track, duration, originUrl, trackArt }) {
  const iso = new Date().toISOString();
  const isDiscord = discordFormat || url.includes('discord.com/api/webhooks');
  const payload = isDiscord
    ? {
        username: 'SoundCloud RPC',
        embeds: [
          {
            title: track,
            description: `by **${artist}**`,
            url: originUrl || 'https://soundcloud.com',
            color: 0xff5500,
            thumbnail: trackArt ? { url: trackArt } : undefined,
            footer: { text: `SoundCloud RPC Web • ${Math.round(duration || 0)}s` },
            timestamp: iso,
          },
        ],
      }
    : {
        timestamp: iso,
        artist,
        track,
        duration: Math.round(duration || 0),
        originUrl,
        trackArt,
      };

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return { ok: res.ok, status: res.status };
}
