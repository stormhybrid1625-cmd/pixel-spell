// Pixel Spell — textures de GIVRE au sol (plaques posées sur les surfaces), pixel art procédural.
// Plusieurs variantes 64x64 : dendrites de cristaux (branches à 60°, comme un flocon qui pousse à plat),
// voile givré tramé autour, centre plus dense. Fond transparent, pixels pleins (aucune transparence partielle).
// Usage : node gen_frost.js [dossierSortie]
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const OUT = process.argv[2] || path.join(__dirname, "..", "sprites", "frost");
fs.mkdirSync(OUT, { recursive: true });

const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc32 = (b) => { let c = -1; for (const x of b) c = CRC[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([l, td, c]); };
function png(file, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);
const dither = (x, y) => BAYER[(y & 3) * 4 + (x & 3)];
const PAL = ["#2f7fd6", "#8fe3ff", "#d8f8ff", "#ffffff"].map(hex);
const S = 64;

function make(name, seed) {
  let rs = seed * 7919 + 13;
  const rnd = () => { rs = (rs * 16807) % 2147483647; return (rs - 1) / 2147483646; };
  const val = new Float32Array(S * S); // 0..1 intensité cristal
  const c = S / 2;
  // dendrites : 6 branches principales (60°) + sous-branches, légèrement déviées
  const arms = 6, rot = rnd() * Math.PI;
  function branch(x, y, ang, len, w, depth) {
    for (let s = 0; s < len; s++) {
      x += Math.cos(ang); y += Math.sin(ang);
      ang += (rnd() - 0.5) * 0.12;
      const ix = Math.round(x), iy = Math.round(y);
      if (ix < 1 || iy < 1 || ix >= S - 1 || iy >= S - 1) return;
      const v = 1 - (s / len) * 0.55;
      for (let oy = -w; oy <= w; oy++) for (let ox = -w; ox <= w; ox++) {
        const k = (iy + oy) * S + ix + ox; val[k] = Math.max(val[k], v * (ox === 0 && oy === 0 ? 1 : 0.75));
      }
      if (depth < 2 && s > 2 && s % (3 + depth) === 0 && rnd() < 0.85) {
        const side = rnd() < 0.5 ? 1 : -1;
        branch(x, y, ang + side * Math.PI / 3, len * (0.35 + rnd() * 0.2), 0, depth + 1);
      }
    }
  }
  for (let a = 0; a < arms; a++) branch(c, c, rot + a * Math.PI / 3, 20 + rnd() * 9, a % 2 === 0 ? 1 : 0, 0);
  // voile givré : halo tramé autour des cristaux, plus dense au centre
  const buf = Buffer.alloc(S * S * 4);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const k = y * S + x, d = Math.hypot(x - c, y - c) / c;
    let v = val[k];
    let haze = 0;
    for (let oy = -2; oy <= 2; oy++) for (let ox = -2; ox <= 2; ox++) {
      const xx = x + ox, yy = y + oy; if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue;
      haze = Math.max(haze, val[yy * S + xx] * (1 - Math.hypot(ox, oy) / 3));
    }
    const centre = Math.max(0, 0.55 - d) * 0.9;
    const density = Math.max(v > 0 ? 1 : 0, haze * 0.6, centre);
    const dd = dither(x, y);
    if (density <= 0 || dd > density) continue;
    const level = v > 0 ? 2 + (v > 0.8 ? 1 : 0) : (haze > 0.35 ? 1 : 0);
    const col = PAL[level];
    const i = k * 4; buf[i] = col[0]; buf[i + 1] = col[1]; buf[i + 2] = col[2]; buf[i + 3] = 255;
  }
  png(path.join(OUT, name + ".png"), S, S, buf);
  console.log("frost", name);
}
make("frost_a", 3); make("frost_b", 11); make("frost_c", 29);
