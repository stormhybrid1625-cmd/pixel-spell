// Pixel Spell — vignettes d'écran texturées par élément (procédural, aucune IA).
// Une vignette = image plein écran basse résolution (320x180), affichée étirée avec ResampleMode = Pixelated :
// le CENTRE est toujours transparent, la matière de l'élément envahit les BORDS. Palette limitée + tramage
// ordonné (Bayer 4x4), pixels pleins ou vides (aucune transparence partielle) = vrai pixel art.
// Feu et Foudre : 2 images (A/B) alternées en jeu pour l'animation.
// Usage : node gen_vignettes.js [dossierSortie]
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const OUT = process.argv[2] || path.join(__dirname, "..", "sprites", "vignettes");
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG ----------
const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc32 = (b) => { let c = -1; for (const x of b) c = CRC[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([l, td, c]); };
function png(file, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

// ---------- utilitaires ----------
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);
const dither = (x, y) => BAYER[(y & 3) * 4 + (x & 3)];
let SEED = 1;
const H = (x, y) => { const s = Math.sin(x * 127.1 + y * 311.7 + SEED * 17.3) * 43758.5453; return s - Math.floor(s); };
const vn = (x, y) => { const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  return (H(xi, yi) * (1 - u) + H(xi + 1, yi) * u) * (1 - v) + (H(xi, yi + 1) * (1 - u) + H(xi + 1, yi + 1) * u) * v; };
const fbm = (x, y) => vn(x, y) * 0.55 + vn(x * 2.1, y * 2.1) * 0.3 + vn(x * 4.3, y * 4.3) * 0.15;
const ridge = (x, y) => 1 - Math.abs(2 * fbm(x, y) - 1);

const W = 320, Hh = 180;
// distance normalisée au bord le plus proche (0 = bord, 1 = centre), en tenant compte du format 16:9
function edgeDist(x, y) {
  const dx = Math.min(x, W - 1 - x) / (W / 2), dy = Math.min(y, Hh - 1 - y) / (Hh / 2);
  return Math.min(dx * 1.0, dy * 1.0);
}

// valeur 0..1 par pixel (null = vide) -> rampe de couleurs + tramage ; densité = présence (tramée)
function paint(name, ramp, fn) {
  const pal = ramp.map(hex), buf = Buffer.alloc(W * Hh * 4);
  for (let y = 0; y < Hh; y++) for (let x = 0; x < W; x++) {
    const r = fn(x + 0.5, y + 0.5); if (!r) continue;
    const [density, value] = r; const d = dither(x, y);
    if (density <= 0 || d > density) continue; // bord tramé : de plus en plus clairsemé vers le centre
    const pos = clamp(value) * (pal.length - 1) + (d - 0.5) * 0.8;
    const c = pal[clamp(Math.round(pos), 0, pal.length - 1)];
    const i = (y * W + x) * 4; buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255;
  }
  // contour sombre 1 px vers l'intérieur (lisibilité pixel art)
  const src = Buffer.from(buf), dark = pal[0];
  for (let y = 1; y < Hh - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = (y * W + x) * 4; if (src[i + 3]) continue;
    if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => src[((y + b) * W + x + a) * 4 + 3])) { buf[i] = dark[0]; buf[i + 1] = dark[1]; buf[i + 2] = dark[2]; buf[i + 3] = 255; }
  }
  png(path.join(OUT, name + ".png"), W, Hh, buf);
  console.log("vignette", name);
}

// ── GIVRE : cristaux en veines (bruit en crête) qui partent des bords, plus denses dans les coins ──
SEED = 3;
paint("vignette_frost", ["#4f9be8", "#8fe3ff", "#c4f1ff", "#e8fbff", "#ffffff"], (x, y) => {
  const e = edgeDist(x, y);
  const cx = Math.min(x, W - x) / W, cy = Math.min(y, Hh - y) / Hh, corner = Math.hypot(cx, cy * 0.6);
  const reach = 0.06 + fbm(x * 0.03, y * 0.03) * 0.1 + smooth(0.38, 0, corner) * 0.3;
  const vein = ridge(x * 0.045, y * 0.045);
  const density = smooth(reach, reach * 0.35, e) * (0.55 + 0.6 * Math.pow(vein, 3));
  if (density < 0.05) return null;
  return [density, 0.35 + 0.65 * (1 - e / reach) * vein];
});

// ── FEU : langues de flammes qui montent du bas, lèchent les côtés (2 images) ──
for (const [frameName, seed] of [["vignette_fire_a", 5], ["vignette_fire_b", 9]]) {
  SEED = seed;
  paint(frameName, ["#b8401c", "#ff7a26", "#ffad3a", "#ffdc5a", "#fff6c4"], (x, y) => {
    const fromBottom = (Hh - y) / Hh;
    const side = Math.min(x, W - x) / W;
    // hauteur de la flamme par colonne (bruit) + turbulence verticale
    const tongue = 0.06 + fbm(x * 0.045, seed) * 0.12 + Math.pow(vn(x * 0.11, seed * 3), 3) * 0.16;
    const turb = (fbm(x * 0.06, y * 0.05 - seed) - 0.5) * 0.08;
    const bottom = smooth(tongue, tongue * 0.25, fromBottom + turb);
    // côtés : flammes plus fines, surtout dans la moitié basse
    const sideReach = (0.025 + fbm(y * 0.05, seed + 2) * 0.04) * smooth(0.1, 0.75, 1 - fromBottom * 0.9) ;
    const sides = smooth(sideReach, sideReach * 0.2, side + turb * 0.5) * smooth(0.95, 0.3, 1 - fromBottom);
    const density = Math.max(bottom, sides * 0.85);
    if (density < 0.05) return null;
    return [density, Math.max(bottom * (1 - fromBottom / Math.max(tongue, 0.01)) , sides * 0.6) * 1.1];
  });
}

// ── FOUDRE : vrais ÉCLAIRS fractals qui partent des coins / bords et se ramifient (cœur blanc, halo électrique
//    tramé), légère charge bleutée dans les coins ; aucun cadre sombre. 2 images (éclairs différents) ──
for (const [frameName, seed] of [["vignette_lightning_a", 11], ["vignette_lightning_b", 23]]) {
  SEED = seed;
  const core = new Float32Array(W * Hh), glow = new Float32Array(W * Hh);
  let rs = seed * 7919 + 5;
  const rnd = () => { rs = (rs * 16807) % 2147483647; return (rs - 1) / 2147483646; };
  const plot = (x, y, w) => {
    const ix = Math.round(x), iy = Math.round(y);
    for (let oy = -3; oy <= 3; oy++) for (let ox = -3; ox <= 3; ox++) {
      const qx = ix + ox, qy = iy + oy; if (qx < 0 || qy < 0 || qx >= W || qy >= Hh) continue;
      const d = Math.hypot(ox, oy), k = qy * W + qx;
      if (d <= w) core[k] = 1;
      glow[k] = Math.max(glow[k], 1 - d / 3.5);
    }
  };
  // segment en zigzag (déplacement du point milieu) + ramifications
  function bolt(x, y, ang, len, w, depth) {
    let px = x, py = y;
    const steps = Math.max(4, Math.floor(len / 3));
    for (let s = 0; s < steps; s++) {
      ang += (rnd() - 0.5) * 0.9;
      const nx = px + Math.cos(ang) * 3, ny = py + Math.sin(ang) * 3;
      if (edgeDist(nx, ny) > 0.42) return; // le centre de l'écran reste dégagé
      for (let t = 0; t <= 1; t += 0.34) plot(px + (nx - px) * t, py + (ny - py) * t, w);
      px = nx; py = ny;
      if (depth < 2 && rnd() < 0.22) bolt(px, py, ang + (rnd() < 0.5 ? 1 : -1) * (0.5 + rnd() * 0.6), len * 0.45, 0, depth + 1);
    }
  }
  const starts = [[0, 0, 0.6], [W, 0, Math.PI - 0.6], [0, Hh, -0.6], [W, Hh, Math.PI + 0.6]];
  for (const [x, y, a] of starts) bolt(x, y, a + (rnd() - 0.5) * 0.5, 70 + rnd() * 40, 1, 0);
  for (let i = 0; i < 6; i++) { // éclairs depuis les bords
    const side = Math.floor(rnd() * 4);
    const x = side === 0 ? 0 : side === 1 ? W - 1 : 20 + rnd() * (W - 40);
    const y = side === 2 ? 0 : side === 3 ? Hh - 1 : 15 + rnd() * (Hh - 30);
    const a = side === 0 ? 0 : side === 1 ? Math.PI : side === 2 ? Math.PI / 2 : -Math.PI / 2;
    bolt(x, y, a + (rnd() - 0.5) * 0.8, 35 + rnd() * 35, rnd() < 0.5 ? 1 : 0, 0);
  }
  paint(frameName, ["#5a8cff", "#8fb8ff", "#c8dcff", "#fff27a", "#ffffff"], (x, y) => {
    const k = Math.floor(y) * W + Math.floor(x);
    if (core[k]) return [1, 0.95];
    const cx = Math.min(x, W - x) / W, cy = Math.min(y, Hh - y) / Hh, corner = Math.hypot(cx, cy * 0.6);
    const charge = smooth(0.12, 0, corner) * 0.35; // légère charge électrique dans les coins
    const g = glow[k] * 0.75;
    const density = Math.max(g, charge);
    if (density < 0.05) return null;
    return [density, g > charge ? 0.35 + g * 0.45 : 0.15];
  });
}
// ── TOXIQUE : bave qui coule du haut (gouttes à bout rond) + flaque visqueuse en bas ──
SEED = 13;
paint("vignette_toxic", ["#3f8a2a", "#6cc436", "#9bee4a", "#c8ff7a", "#f2ffd0"], (x, y) => {
  const col = Math.floor(x / 6);
  const dripLen = (0.04 + Math.pow(H(col, 7), 3) * 0.2) * Hh; // quelques coulures plus longues
  const dripW = 1.6 + H(col, 3) * 1.1;
  const cxCol = col * 6 + 3, dx = Math.abs(x - cxCol);
  const topBand = 0.05 + fbm(x * 0.05, 1) * 0.05;
  let density = 0, value = 0;
  if (y / Hh < topBand) { density = 1; value = 0.45; }
  if (dx < dripW && y < dripLen) { density = 1; value = 0.6 + (1 - y / dripLen) * 0.2; }
  if (Math.hypot(dx, y - dripLen) < dripW + 1) { density = 1; value = 0.9; } // goutte au bout
  const bottom = (Hh - y) / Hh, pool = 0.07 + fbm(x * 0.04, 9) * 0.07;
  if (bottom < pool) { density = Math.max(density, smooth(pool, pool * 0.4, bottom)); value = 0.5 + fbm(x * 0.2, y * 0.2) * 0.4; }
  const e = edgeDist(x, y), side = smooth(0.05, 0.0, e) * 0.8;
  if (side > density) { density = side; value = 0.35; }
  // bulles claires dans la bave
  if (density > 0.5 && H(Math.floor(x / 3), Math.floor(y / 3)) > 0.93) value = 1;
  return density > 0.05 ? [density, value] : null;
});

// ── NATURE : ronces, épines et feuilles qui envahissent les coins et les bords ──
SEED = 17;
paint("vignette_nature", ["#6b4a2a", "#8a6238", "#5aa83a", "#8fd94a", "#d8ff9a"], (x, y) => {
  const cx = Math.min(x, W - x) / W, cy = Math.min(y, Hh - y) / Hh, corner = Math.hypot(cx, cy * 0.7);
  const e = edgeDist(x, y);
  const reach = 0.035 + fbm(x * 0.04, y * 0.04) * 0.07 + smooth(0.36, 0, corner) * 0.3;
  const mass = smooth(reach, reach * 0.4, e);
  if (mass < 0.05) return null;
  // tiges / ronces : veines en crête, en brun
  const vine = Math.pow(ridge(x * 0.06, y * 0.06), 6);
  // feuilles : cellules arrondies vertes
  const cell = vn(x * 0.18, y * 0.18), leaf = cell > 0.62 ? 1 : 0;
  // épines : petits pics clairsemés le long des tiges
  const thorn = vine > 0.55 && H(Math.floor(x), Math.floor(y)) > 0.9 ? 1 : 0;
  let value = 0.2 + leaf * 0.55 + (cell > 0.8 ? 0.25 : 0);
  if (vine > 0.5) value = 0.18;
  if (thorn) value = 0.05;
  return [mass * (0.65 + 0.5 * Math.max(vine, leaf)), value];
});
