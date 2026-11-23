// Pixel Spell — generateur de sprites pixel art animes (procedural, aucune IA).
// Chaque effet = planche horizontale de N images carrees (S x S px), palette limitee,
// tramage ordonne (Bayer 4x4), bords nets. Rendu en jeu via ImageLabel ResampleMode = Pixelated.
// Usage : node gen_sprites.js [dossierSortie]
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const OUT = process.argv[2] || path.join(__dirname, "..", "sprites");
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
const H = (x, y) => { const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - Math.floor(s); };
const vn = (x, y) => { const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  return (H(xi, yi) * (1 - u) + H(xi + 1, yi) * u) * (1 - v) + (H(xi, yi + 1) * (1 - u) + H(xi + 1, yi + 1) * u) * v; };
const fbm = (x, y) => vn(x, y) * 0.55 + vn(x * 2.1, y * 2.1) * 0.3 + vn(x * 4.3, y * 4.3) * 0.15;
const TAU = Math.PI * 2;

// Une image = grille de "valeurs" 0..1 (-1 = vide), convertie en couleurs de la rampe au rendu.
function frame(S, fn) {
  const v = new Float32Array(S * S).fill(-1);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) { const val = fn(x + 0.5, y + 0.5); if (val !== null && val > 0) v[y * S + x] = val; }
  return v;
}
// valeur -> couleur de rampe avec tramage ; valeurs < cut = transparent (bord trame)
function render(frames, S, ramp, cut = 0.08) {
  const N = frames.length, W = S * N, buf = Buffer.alloc(W * S * 4), pal = ramp.map(hex);
  frames.forEach((f, k) => {
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const val = f[y * S + x]; if (val < 0) continue;
      const d = dither(x, y);
      if (val < cut && d > val / cut) continue;
      const pos = clamp(val) * (pal.length - 1) + (d - 0.5) * 0.9;
      const c = pal[clamp(Math.round(pos), 0, pal.length - 1)];
      const i = (y * W + k * S + x) * 4; buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255;
    }
  });
  return { W, H: S, buf, N, S };
}
// contour 1 px avec la couleur la plus sombre (lisibilite pixel art)
function outline(sheet, col) {
  const { W, H: Hh, S, buf } = sheet, c = hex(col), src = Buffer.from(buf);
  for (let y = 0; y < Hh; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4; if (src[i + 3]) continue;
    const nb = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= W || ny >= Hh || Math.floor(nx / S) !== Math.floor(x / S)) return false;
      return src[(ny * W + nx) * 4 + 3] > 0;
    });
    if (nb) { buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255; }
  }
  return sheet;
}
const sheets = [];
function save(name, sheet, meta) {
  png(path.join(OUT, name + ".png"), sheet.W, sheet.H, sheet.buf);
  sheets.push({ name, sheet, meta });
}

// ---------- 1. Vortex de trou noir (boucle, 3 bras -> 1/3 de tour sur 8 images) ----------
{
  const S = 64, N = 8, frames = [];
  for (let k = 0; k < N; k++) {
    const phase = (k / N) * (TAU / 3);
    frames.push(frame(S, (x, y) => {
      const dx = (x - S / 2) / (S / 2), dy = (y - S / 2) / (S / 2), r = Math.hypot(dx, dy), a = Math.atan2(dy, dx);
      if (r > 1) return null;
      if (r < 0.2) return 0.1; // coeur noir
      if (r < 0.28) return 1 - (r - 0.2) * 3; // horizon lumineux
      const arm = 0.5 + 0.5 * Math.cos(3 * a - 7 * Math.log(r) + phase * 3);
      const fall = smooth(1, 0.3, r);
      return clamp(Math.pow(arm, 2.2) * fall * 1.15 + fall * 0.08);
    }));
  }
  save("vortex", outline(render(frames, S, ["#08030f", "#26093f", "#521a8f", "#9442f0", "#d98bff", "#fff0ff"], 0.1), "#08030f"), { frames: N, size: S, loop: true, fps: 12 });
}

// ---------- 2. Nuage de gaz toxique (boucle : bruit echantillonne sur un cercle) ----------
{
  const S = 64, N = 8, frames = [];
  for (let k = 0; k < N; k++) {
    const t = (k / N) * TAU;
    frames.push(frame(S, (x, y) => {
      const dx = (x - S / 2) / (S / 2), dy = (y - S / 2) / (S / 2), r = Math.hypot(dx, dy * 1.15);
      const n = fbm(x / 13 + Math.cos(t) * 0.9, y / 13 + Math.sin(t) * 0.9);
      return clamp(n * 1.45 - r * 0.95 - 0.12);
    }));
  }
  save("gas", outline(render(frames, S, ["#0b2410", "#1d5419", "#3a9126", "#86cf38", "#d6ff78"], 0.12), "#0b2410"), { frames: N, size: S, loop: true, fps: 8 });
}

// ---------- 3. Disque-scie (boucle : 8 dents -> 1/8 de tour sur 4 images) ----------
{
  const S = 32, N = 4, frames = [];
  for (let k = 0; k < N; k++) {
    const rot = (k / N) * (TAU / 8);
    frames.push(frame(S, (x, y) => {
      const dx = x - S / 2, dy = y - S / 2, r = Math.hypot(dx, dy), a = Math.atan2(dy, dx) - rot;
      const tooth = ((a / TAU) * 8 % 1 + 1) % 1; // dent en dents de scie
      const edge = 11 + tooth * 4;
      if (r > edge) return null;
      if (r < 2.5) return 0.95; // moyeu
      if (r < 4) return 0.3;
      const ring = Math.abs(r - 8) < 0.8 ? 0.85 : 0;
      const slot = Math.abs(((a / TAU) * 4 % 1 + 1) % 1 - 0.5) < 0.06 && r < 10 ? 0.25 : 0;
      return slot || ring || (r > 10.5 ? 0.7 : 0.5);
    }));
  }
  save("saw", outline(render(frames, S, ["#15161f", "#363c52", "#626c8a", "#a3adc7", "#eef2ff"], 0.05), "#15161f"), { frames: N, size: S, loop: true, fps: 20 });
}

// ---------- 4. Bouffee de teleportation (une fois : anneau qui s'etend + etincelles) ----------
{
  const S = 64, N = 8, frames = [];
  for (let k = 0; k < N; k++) {
    const p = k / (N - 1), R = 0.12 + p * 0.82, w = 0.16 * (1 - p) + 0.04;
    frames.push(frame(S, (x, y) => {
      const dx = (x - S / 2) / (S / 2), dy = (y - S / 2) / (S / 2), r = Math.hypot(dx, dy), a = Math.atan2(dy, dx);
      if (r > 1) return null;
      const ring = clamp(1 - Math.abs(r - R) / w) * (1 - p * 0.7);
      const core = p < 0.35 ? clamp(1 - r / (0.35 - p)) : 0;
      const spark = H(Math.floor(x / 2), Math.floor(y / 2) + k * 7) > 0.985 - p * 0.02 && r < R ? 0.9 * (1 - p) : 0;
      const rays = p < 0.5 ? clamp(Math.pow(0.5 + 0.5 * Math.cos(a * 8), 8) * (1 - r / (R + 0.1))) * (1 - p * 2) : 0;
      return Math.max(ring, core, spark, rays);
    }));
  }
  save("teleport", render(frames, S, ["#1a0a3a", "#4a2a9e", "#5f8bff", "#9ff3ff", "#ffffff"], 0.15), { frames: N, size: S, loop: false, fps: 16 });
}

// ---------- 5. Bouclier hexagonal (boucle : reflet qui tourne) ----------
{
  const S = 64, N = 6, frames = [];
  const hexDist = (dx, dy) => { const qx = Math.abs(dx), qy = Math.abs(dy); return Math.max(qx * 0.866 + qy * 0.5, qy); };
  for (let k = 0; k < N; k++) {
    const phase = (k / N) * TAU;
    frames.push(frame(S, (x, y) => {
      // hexagone mis a l'echelle pour que ses pointes restent DANS l'image
      const dx = (x - S / 2) / (S / 2) * 1.2, dy = (y - S / 2) / (S / 2) * 1.2, h = hexDist(dx, dy), a = Math.atan2(dy, dx);
      if (h > 0.97) return null;
      const border = h > 0.86 ? 0.55 + 0.45 * Math.pow(0.5 + 0.5 * Math.cos(a - phase), 6) : 0;
      const cells = h < 0.86 && (Math.abs(((dx * 3 + dy * 1.75) % 1 + 1) % 1 - 0.5) < 0.035 || Math.abs(((dx * 3 - dy * 1.75) % 1 + 1) % 1 - 0.5) < 0.035) ? 0.3 : 0;
      const fill = h < 0.86 ? 0.06 : 0;
      return Math.max(border, cells, fill);
    }));
  }
  save("shield", render(frames, S, ["#08202c", "#1b5d78", "#38b6da", "#a8f4ff", "#ffffff"], 0.09), { frames: N, size: S, loop: true, fps: 10 });
}

// ---------- 6. Cercle de feu vu de dessus (boucle) ----------
{
  const S = 64, N = 6, frames = [];
  for (let k = 0; k < N; k++) {
    const t = (k / N) * TAU;
    frames.push(frame(S, (x, y) => {
      const dx = (x - S / 2) / (S / 2), dy = (y - S / 2) / (S / 2), r = Math.hypot(dx, dy), a = Math.atan2(dy, dx);
      const n = fbm(Math.cos(a) * 2.2 + Math.cos(t) * 0.7, Math.sin(a) * 2.2 + r * 3 + Math.sin(t) * 0.7);
      const band = clamp(1 - Math.abs(r - 0.72) / (0.12 + n * 0.16));
      return clamp(band * (0.55 + n * 0.8));
    }));
  }
  save("firering", render(frames, S, ["#3a0a05", "#8a1f0a", "#d8481a", "#ff9a2e", "#ffe680", "#ffffff"], 0.12), { frames: N, size: S, loop: true, fps: 10 });
}

// ---------- 7. Mine (2 images : voyant eteint / allume) ----------
{
  const S = 16, N = 2, frames = [];
  for (let k = 0; k < N; k++) {
    frames.push(frame(S, (x, y) => {
      const dx = x - S / 2, dy = y - S / 2, r = Math.hypot(dx, dy);
      if (r > 6.5) return null;
      if (r < 2.2) return k === 1 ? 0.95 : 0.62;
      const spike = Math.abs(dx) < 1 || Math.abs(dy) < 1 ? 0.5 : 0.3;
      return spike;
    }));
  }
  save("mine", outline(render(frames, S, ["#141018", "#3a3344", "#6b6280", "#ff3030", "#ffd0d0"], 0.05), "#141018"), { frames: N, size: S, loop: true, fps: 4 });
}

// ---------- 8. Flamme (boucle : bruit qui MONTE, bouclage par fondu de deux phases) ----------
// Posee sur les personnages en feu (billboards) : base large, pointe qui ondule, coeur blanc-jaune.
{
  const S = 32, N = 8, frames = [], L = 2.2;
  const F = (x, y, off) => fbm(x / 5.5, y / 5.5 + off);
  for (let k = 0; k < N; k++) {
    const p = k / N;
    frames.push(frame(S, (x, y) => {
      const yn = 1 - y / S; // 0 = bas, 1 = haut
      const dx = (x - S / 2) / (S / 2);
      // la flamme est decoupee par le bruit : (1-p) * phase A + p * phase B -> boucle parfaite
      const n = (1 - p) * F(x, y, p * L) + p * F(x, y, (p - 1) * L);
      const n2 = (1 - p) * fbm(x / 3, y / 3 + p * L * 2) + p * fbm(x / 3, y / 3 + (p - 1) * L * 2);
      // goutte : ventre rond en bas, langues qui se detachent en haut
      const sway = (n - 0.5) * 0.9 * yn * yn;
      const cy = 0.27, belly = Math.hypot((dx - sway) / 0.62, (yn - cy) / 0.3);
      const width = 0.6 * Math.pow(clamp(1 - (yn - cy) / (1 - cy)), 0.9);
      const tongue = yn > cy ? Math.abs(dx - sway) / Math.max(width, 0.01) : belly;
      const body = 1 - Math.min(belly, tongue);
      const heat = body * 1.15 + (n2 - 0.5) * 1.1 * (0.4 + yn) - yn * 0.25;
      if (yn < 0.02) return null;
      return clamp(heat);
    }));
  }
  save("flame", outline(render(frames, S, ["#3a0a05", "#8a1f0a", "#d8481a", "#ff9a2e", "#ffe680", "#fffbe0"], 0.1), "#3a0a05"), { frames: N, size: S, loop: true, fps: 12 });
}

// ---------- 8b. Electrocution (boucle : arcs brises qui changent a chaque image, coeur blanc, halo bleu) ----------
// Pose sur les cibles touchees par la foudre (billboards), comme la flamme pour les cibles en feu.
{
  const S = 32, N = 8, frames = [];
  for (let k = 0; k < N; k++) {
    const v = new Float32Array(S * S).fill(-1);
    const plot = (x, y, val) => {
      x = Math.round(x); y = Math.round(y);
      if (x < 0 || y < 0 || x >= S || y >= S) return;
      const i = y * S + x; v[i] = Math.max(v[i], val);
    };
    const arcs = 3 + Math.floor(H(k, 1.3) * 2);
    const turn = H(k, 4.4) * TAU;
    for (let a = 0; a < arcs; a++) {
      // un arc part pres du centre et file vers le bord en ZIGZAG franc : segments droits de 2-3 px,
      // puis cassure brusque d'un cote ou de l'autre (comme un vrai eclair)
      const ang = turn + (a / arcs) * TAU + (H(k * 7 + a, 2.1) - 0.5) * 0.9;
      let x = S / 2 + (H(a, k + 0.5) - 0.5) * 4, y = S / 2 + (H(a + 3, k) - 0.5) * 6;
      const len = 10 + H(a, k * 3) * 5;
      let side = 0;
      for (let s = 0; s < len; s++) {
        if (s % 3 === 0) side = (H(k * 13 + a * 5, s) - 0.5) * 2.4;
        x += Math.cos(ang) + Math.cos(ang + Math.PI / 2) * side * 0.6;
        y += Math.sin(ang) + Math.sin(ang + Math.PI / 2) * side * 0.6;
        plot(x, y, 1);                                   // coeur de l'arc (1 px)
        plot(x + 1, y, 0.35);                            // halo fin d'un seul cote
        if (s < 3) plot(x, y + 1, 0.55);                 // plus epais pres de la source
        // petite branche de temps en temps
        if (H(s + a, k * 9) > 0.86) {
          let bx = x, by = y;
          const bang = ang + (H(s, a + k) > 0.5 ? 0.9 : -0.9);
          for (let b = 0; b < 4; b++) { bx += Math.cos(bang); by += Math.sin(bang); plot(bx, by, 0.75); plot(bx + 1, by, 0.3); }
        }
      }
    }
    // etincelles isolees
    for (let p = 0; p < 6; p++) plot(H(p, k * 2.7) * S, H(p + 9, k) * S, 0.85);
    frames.push(v);
  }
  save("shock", outline(render(frames, S, ["#0d1a4a", "#2a4fd6", "#5f9bff", "#ffe94f", "#fffbe0", "#ffffff"], 0.05), "#0d1a4a"), { frames: N, size: S, loop: true, fps: 16 });
}

// ---------- 9. Ecorce (texture TUILABLE 32x32, isotrope : marche dans tous les sens sur les troncs) ----------
// Plaques d'ecorce (Voronoi periodique) separees par des fissures sombres, grain fin, tons neutres chauds
// -> teintee par element en jeu (ImageColor3). Affichee en SurfaceGui non eclaire (lisible dans le noir).
{
  const S = 32, pts = [];
  // grille 4 x 3 perturbee : plaques de taille reguliere, sans grand vide
  // grille 2 x 6 perturbee : plaques LONGUES le long de l'axe X de l'image (= le long du tronc)
  for (let gx = 0; gx < 2; gx++) for (let gy = 0; gy < 6; gy++)
    pts.push([(gx + 0.1 + H(gx, gy + 9.3) * 0.8) * S / 2, (gy + 0.25 + H(gx + 4.7, gy) * 0.5) * S / 6]);
  const wrap = (d) => { d = Math.abs(d); return Math.min(d, S - d); };
  const f = frame(S, (x, y) => {
    let d1 = 1e9, d2 = 1e9;
    for (const [px, py] of pts) {
      const dx = wrap(x - px) * 0.35, dy = wrap(y - py); // plaques allongees en X (distance bouclee = tuilable)
      const d = Math.hypot(dx, dy);
      if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d;
    }
    const crack = d2 - d1; // 0 sur la frontiere entre deux plaques
    if (crack < 0.9) return 0.12;
    const grain = vn((x % S) * 0.3, y * 1.1) * 0.25; // fibres le long de X
    return clamp(0.45 + grain + Math.min(crack, 6) * 0.05 + (H(Math.floor(x), Math.floor(y)) - 0.5) * 0.12);
  });
  save("bark", render([f], S, ["#2a2420", "#4a4038", "#6b5d50", "#8f7f6c", "#b3a38c"], 0.0), { frames: 1, size: S, loop: false, fps: 1 });
}

// ---------- manifeste + apercu agrandi (x4, plus proche voisin) pour inspection ----------
const manifest = {};
for (const s of sheets) manifest[s.name] = s.meta;
fs.writeFileSync(path.join(OUT, "manifest.json"), JSON.stringify(manifest, null, 2));
{
  const Z = 4, PAD = 8;
  const W = Math.max(...sheets.map((s) => s.sheet.W)) * Z + PAD * 2;
  const Ht = sheets.reduce((h, s) => h + s.sheet.H * Z + PAD, PAD);
  const buf = Buffer.alloc(W * Ht * 4);
  for (let i = 0; i < W * Ht; i++) { const c = ((i % W >> 4) + (Math.floor(i / W) >> 4)) & 1 ? 40 : 52; buf[i * 4] = c; buf[i * 4 + 1] = c; buf[i * 4 + 2] = c + 6; buf[i * 4 + 3] = 255; }
  let oy = PAD;
  for (const { sheet } of sheets) {
    for (let y = 0; y < sheet.H * Z; y++) for (let x = 0; x < sheet.W * Z; x++) {
      const si = (Math.floor(y / Z) * sheet.W + Math.floor(x / Z)) * 4; if (!sheet.buf[si + 3]) continue;
      const di = ((oy + y) * W + PAD + x) * 4; sheet.buf.copy(buf, di, si, si + 4);
    }
    oy += sheet.H * Z + PAD;
  }
  png(path.join(OUT, "_preview.png"), W, Ht, buf);
}
console.log("ok", sheets.map((s) => `${s.name}:${s.sheet.W}x${s.sheet.H}`).join(" "));
