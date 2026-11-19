import { md5 } from './md5.js';

function signParams(params, secret) {
  const base =
    Object.keys(params)
      .sort()
      .map((k) => `${k}${params[k]}`)
      .join('') + secret;
  return md5(base);
}

export async function getLastFmSession(apiKey, apiSecret, token) {
  const params = { method: 'auth.getSession', api_key: apiKey, token };
  const api_sig = signParams(params, apiSecret);
  const url = `https://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=${encodeURIComponent(apiKey)}&token=${encodeURIComponent(token)}&api_sig=${api_sig}&format=json`;
  const res = await fetch(url);
  return res.json();
}

export async function updateLastFmNowPlaying({ apiKey, apiSecret, sessionKey, artist, track }) {
  const params = {
    method: 'track.updateNowPlaying',
    api_key: apiKey,
    sk: sessionKey,
    artist,
    track,
  };
  const api_sig = signParams(params, apiSecret);
  const body = new URLSearchParams({ ...params, api_sig, format: 'json' });
  const res = await fetch('https://ws.audioscrobbler.com/2.0/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  return res.json();
}

export async function scrobbleLastFmTrack({ apiKey, apiSecret, sessionKey, artist, track }) {
  const params = {
    method: 'track.scrobble',
    api_key: apiKey,
    sk: sessionKey,
    artist,
    track,
    timestamp: String(Math.floor(Date.now() / 1000)),
  };
  const api_sig = signParams(params, apiSecret);
  const body = new URLSearchParams({ ...params, api_sig, format: 'json' });
  const res = await fetch('https://ws.audioscrobbler.com/2.0/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  return res.json();
}
