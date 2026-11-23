// Pixel Spell — icones de cartes 16x16 dessinees PIXEL PAR PIXEL (grilles) + quelques aides de trace.
// Palette commune, contour sombre, lumiere venant d'en haut a gauche.
// Usage : node gen_icons.js  -> sprites/icons/*.png + sprites/icons/_sheet.png (apercu agrandi)
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const OUT = path.join(__dirname, "..", "sprites", "icons");
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

// ---- palette (une lettre = une couleur ; '.' = transparent) ----
const PAL = {
  K: "#1a1426", // contour
  W: "#fff6e0", // blanc chaud (reflets)
  Y: "#ffe680", O: "#ff9a2e", R: "#d8481a", D: "#7a1c0c", // feu
  w: "#f0fdff", c: "#8fe3ff", b: "#3f9fd6", n: "#1f4f8a", // glace
  L: "#bfe0ff", B: "#5a9ae6", N: "#2f5aa6",               // modificateur (bleu)
  g: "#c9c9d2", G: "#8a8a96", h: "#55555f", H: "#34343c", // metal / neutre
  r: "#ff4a3a", p: "#ffd0c8",                              // voyant rouge
  E: "#a8e85a", e: "#6fbf3a", f: "#3f7f22",               // feuillage
  T: "#8a5a32", t: "#5c3a21", u: "#3b2614",               // bois
  M: "#ff5ad0", m: "#c56bff",                              // accents magiques
};
const hex = (s) => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];

// grille 16x16 a partir de lignes (completees a droite par du transparent)
function grid(rows) { return rows.map((r) => (r + "................").slice(0, 16)); }

const ICONS = {};

// 1. BOULE DE FEU : boule qui file vers le bas-gauche, trainee de flammes vers le haut-droite
ICONS.fireball = grid([
  "............R...",
  "..........R.OR..",
  "...........ROR..",
  ".........RROYR..",
  "........ROYYOR..",
  ".......ROYYOR...",
  "....KKKOYYOR....",
  "...KOOYYYYOK....",
  "..KOYYWWYYOK....",
  ".KOYWWWWYYORK...",
  ".KOYWWWYYYORK...",
  ".KOYYWYYYOORK...",
  ".KROYYYYOORRK...",
  "..KRROOOORRK....",
  "...KKRRRRKK.....",
  ".....KKKK.......",
]);

// 2. ECLAT DE GLACE : cristal en diagonale, facette claire / facette sombre, petite etincelle
// (cristal principal + petit cristal secondaire : on lit "glace" et pas "baton lumineux")
ICONS.ice = grid([
  "............K...",
  "...........KwK..",
  "..........KwwcK.",
  "....w....KwwccK.",
  "...www..KwwccbK.",
  "....w..KwwccbnK.",
  "......KwwccbnK..",
  ".....KwwccbnK...",
  "....KwwccbnK....",
  "...KwccbbnK.K...",
  "...KccbbnK.KwK..",
  "..KccbbnK.KwcbK.",
  "..KcbbnK..KcbnK.",
  "..KbbnK....KnK..",
  "..KbnK......K...",
  "...KK...........",
]);

// 3. GIGANTISME : le MEME bloc, en petit puis en grand (x2) -> on lit directement "ca grossit"
ICONS.giant = grid([
  "......KKKKKKKKKK",
  "......KLLLLLLLBK",
  "......KLWWBBBBNK",
  "......KLWBBBBBNK",
  "......KLBBBBBBNK",
  "......KLBBBBBBNK",
  "......KLBBBBBBNK",
  "......KLBBBBBBNK",
  "......KBNNNNNNNK",
  "......KKKKKKKKKK",
  "KKKKKK.....WWWW.",
  "KLLLBK......WWW.",
  "KLWBNK.....WW.W.",
  "KLBBNK....WW....",
  "KBNNNK...WW.....",
  "KKKKKK..WW......",
]);

// 4. TETE CHERCHEUSE : reticule + trajectoire courbe en pointilles qui file vers le centre
ICONS.homing = grid([
  ".....KKKKKK.....",
  "...KKBBLLBBKK...",
  "..KBBK.LL.KBBK..",
  ".KBK...LL...KBK.",
  ".KBK...LL...KBK.",
  "KBK.........KBK.",
  "KBK...KrrK...BK.",
  "KLLLL.KrpK.LLLLK",
  "KBK...KrrK...BK.",
  "KBK.........KBK.",
  ".KBK...LL...KBK.",
  ".KBK...LL..WKBK.",
  "..KBBK.LL.W.BK..",
  "...KKBBLWBBKK...",
  ".....KKWKKK.....",
  "W.WW..W.........",
]);

// 5. MINE : dome metallique pose au sol, voyant rouge, pointes, paillettes
ICONS.mine = grid([
  "..g.........g...",
  "........p.......",
  "....g..KrK......",
  ".......KrK...g..",
  "...KG.KprrK.GK..",
  "....KGKKKKKGK...",
  "...KKgggGGGhKK..",
  "..KgWWggGGGGhhK.",
  ".KGgWgggGGGGhhHK",
  "KGKgggGGGGGhhHKGK",
  ".KKggGGGGGhhhHHK",
  "..KhhhhhhhhhHHK.",
  "...KKKKKKKKKKK..",
  ".g..HHHHHHHHH..g",
  "..HHHHHHHHHHHHH.",
  "................",
]);

// 6. RAMURE : tronc qui jaillit du sol, deux bras, feuillage
ICONS.branch = grid([
  "....KKK...KKKK..",
  "...KEEeK.KEEEeK.",
  "..KEEEeeKEEeeefK",
  "..KEEeeKfKEeeffK",
  "...KeffKTK.KfffK",
  "....KKKTtK..KKK.",
  "......KTtK..KT..",
  "..KK..KTtK.KTt..",
  ".KEeK.KTtKKTtK..",
  ".KEefKKTttTtK...",
  "..KfKTTTttK.....",
  "...KKTTtttK.....",
  ".....KTttuK.....",
  "....KKTtuuKK....",
  "..KKuuTtuuuuKK..",
  ".KhhhhhhhhhhhhK.",
]);

// ---- rendu ----
function render(rows) {
  const buf = Buffer.alloc(16 * 16 * 4);
  rows.forEach((row, y) => [...row].forEach((ch, x) => {
    if (ch === "." || !PAL[ch]) return;
    const c = hex(PAL[ch]), i = (y * 16 + x) * 4;
    buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255;
  }));
  return buf;
}

// planche d'apercu : chaque icone en x12 sur une "carte" sombre, puis en taille reelle x3 (comme en jeu)
const names = Object.keys(ICONS);
const Z = 12, PAD = 16, CARD = 16 * Z + 24;
const W = PAD + names.length * (CARD + PAD), Hh = PAD + CARD + PAD + 16 * 3 + 16 + PAD;
const sheet = Buffer.alloc(W * Hh * 4);
const put = (x, y, c) => { if (x < 0 || y < 0 || x >= W || y >= Hh) return; const i = (y * W + x) * 4; sheet[i] = c[0]; sheet[i + 1] = c[1]; sheet[i + 2] = c[2]; sheet[i + 3] = 255; };
for (let y = 0; y < Hh; y++) for (let x = 0; x < W; x++) put(x, y, [14, 12, 22]);
names.forEach((name, k) => {
  const px = render(ICONS[name]);
  png(path.join(OUT, name + ".png"), 16, 16, px);
  const ox = PAD + k * (CARD + PAD), oy = PAD;
  // carte : fond + bordure (comme les tuiles du jeu)
  for (let y = 0; y < CARD; y++) for (let x = 0; x < CARD; x++) {
    const border = x < 4 || y < 4 || x >= CARD - 4 || y >= CARD - 4;
    put(ox + x, oy + y, border ? [58, 52, 84] : [32, 28, 46]);
  }
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const i = (y * 16 + x) * 4; if (!px[i + 3]) continue;
    for (let dy = 0; dy < Z; dy++) for (let dx = 0; dx < Z; dx++) put(ox + 12 + x * Z + dx, oy + 12 + y * Z + dy, [px[i], px[i + 1], px[i + 2]]);
  }
  // taille "en jeu" (x3) sous la grande
  const sy = oy + CARD + PAD, sx = ox + CARD / 2 - 24;
  for (let y = 0; y < 48 + 8; y++) for (let x = 0; x < 48 + 8; x++) put(sx - 4 + x, sy - 4 + y, [32, 28, 46]);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const i = (y * 16 + x) * 4; if (!px[i + 3]) continue;
    for (let dy = 0; dy < 3; dy++) for (let dx = 0; dx < 3; dx++) put(sx + x * 3 + dx, sy + y * 3 + dy, [px[i], px[i + 1], px[i + 2]]);
  }
});
png(path.join(OUT, "_sheet.png"), W, Hh, sheet);
console.log("ok", names.join(" "));
