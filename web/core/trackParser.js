// Ported from richardhbtz/soundcloud-rpc (MIT License)

const SEPARATOR_REGEX = /(\s+[\u002D\u2013\u2014\u2015]+\s+|[\u002D\u2013\u2014\u2015]{2,})/;
const INVALID_PATTERNS = [
  /^\s*$/,
  /^[\u002D\u2013\u2014\u2015]/,
  /[\u002D\u2013\u2014\u2015]$/,
  /(.)\1{4,}/,
  /[\u002D\u2013\u2014\u2015]{2,}/,
];

const hasInvalidPatterns = (text) => INVALID_PATTERNS.some((p) => p.test(text));

export function parseSoundCloudTitle(title) {
  if (!title || typeof title !== 'string') {
    return { artist: null, track: '' };
  }
  const cleanTitle = title.split('\n')[0].trim();
  const match = cleanTitle.match(SEPARATOR_REGEX);
  if (match && match.index && match.index > 0) {
    const artist = cleanTitle.substring(0, match.index).trim();
    const track = cleanTitle.substring(match.index + match[0].length).trim();
    if (artist.length > 0 && track.length > 0 && !hasInvalidPatterns(artist) && !hasInvalidPatterns(track)) {
      return { artist, track };
    }
  }
  return { artist: null, track: cleanTitle };
}

export function normalizeTrackInfo(titleFromPage, authorFromPage, useTrackParser = true) {
  if (!useTrackParser || !titleFromPage) {
    return {
      artist: (authorFromPage || '').trim() || 'Unknown Artist',
      track: (titleFromPage || '').split('\n')[0].trim() || 'Unknown Track',
    };
  }
  const parsed = parseSoundCloudTitle(titleFromPage);
  return {
    artist: parsed.artist || (authorFromPage || '').trim() || 'Unknown Artist',
    track: parsed.track || 'Unknown Track',
  };
}

export function formatSeconds(sec) {
  const s = Math.max(0, Math.floor(sec || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const rem = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(rem).padStart(2, '0')}`;
  return `${m}:${String(rem).padStart(2, '0')}`;
}
