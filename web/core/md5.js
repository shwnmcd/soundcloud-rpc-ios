// Pure-JS RFC 1321 MD5 (UTF-8 aware) for Last.fm API signatures with zero external dependencies.
export function md5(str) {
  const bytes = new TextEncoder().encode(str);
  const len = bytes.length;
  const wordCount = (((len + 8) >> 6) + 1) * 16;
  const words = new Uint32Array(wordCount);

  for (let i = 0; i < len; i++) {
    words[i >> 2] |= bytes[i] << ((i % 4) * 8);
  }
  words[len >> 2] |= 0x80 << ((len % 4) * 8);
  words[wordCount - 2] = (len * 8) >>> 0;
  words[wordCount - 1] = Math.floor((len * 8) / 0x100000000) >>> 0;

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  const s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const K = new Uint32Array(64);
  for (let i = 0; i < 64; i++) {
    K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000) >>> 0;
  }

  for (let i = 0; i < wordCount; i += 16) {
    let A = a0, B = b0, C = c0, D = d0;
    for (let j = 0; j < 64; j++) {
      let F, g;
      if (j < 16) {
        F = (B & C) | (~B & D);
        g = j;
      } else if (j < 32) {
        F = (D & B) | (~D & C);
        g = (5 * j + 1) % 16;
      } else if (j < 48) {
        F = B ^ C ^ D;
        g = (3 * j + 5) % 16;
      } else {
        F = C ^ (B | ~D);
        g = (7 * j) % 16;
      }
      const sum = (A + F + K[j] + words[i + g]) >>> 0;
      const rot = ((sum << s[j]) | (sum >>> (32 - s[j]))) >>> 0;
      A = D;
      D = C;
      C = B;
      B = (B + rot) >>> 0;
    }
    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  const toHex = (n) => {
    let hex = '';
    for (let i = 0; i < 4; i++) {
      hex += ((n >>> (i * 8)) & 0xff).toString(16).padStart(2, '0');
    }
    return hex;
  };
  return toHex(a0) + toHex(b0) + toHex(c0) + toHex(d0);
}
