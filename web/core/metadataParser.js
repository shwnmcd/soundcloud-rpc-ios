// Ported from richardhbtz/soundcloud-rpc (MIT License)

const DEFAULTS = {
  name: '',
  author: 'Unknown',
  version: '0.0.0',
  description: '',
  license: '',
  homepage: '',
};

export function parseMetadata(source, style = 'css') {
  if (!source) return { ...DEFAULTS };
  const pattern = style === 'js' ? /^[\s\S]*?\/\*\*([\s\S]*?)\*\// : /^[\s\S]*?\/\*([\s\S]*?)\*\//;
  const match = source.match(pattern);
  if (!match) return { ...DEFAULTS };

  const fields = {};
  for (const line of match[1].split('\n')) {
    const cleaned = line.replace(/^\s*\*?\s*/, '').trim();
    const m = cleaned.match(/^@(\w+)\s+(.*)/);
    if (m) fields[m[1].toLowerCase()] = m[2].trim();
  }
  return { ...DEFAULTS, ...fields };
}
