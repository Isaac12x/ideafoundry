// Pure electron-configuration math for the periodic table detail panel.
// No imports, so this module is directly node-testable (see
// test/javascript/periodic_table_electrons_test.mjs) and safe to import from
// both the browser (via importmap) and detail.mjs.

const CORES = {
  He: "1s2",
  Ne: "1s2 2s2 2p6",
  Ar: "1s2 2s2 2p6 3s2 3p6",
  Kr: "1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6",
  Xe: "1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6 4d10 5s2 5p6",
  Rn: "1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6 4d10 4f14 5d10 5s2 5p6 6s2 6p6",
};

const CORE_RE = /^\[(He|Ne|Ar|Kr|Xe|Rn)\]\s*/;

/** Expand a semantic noble-gas-core config ("[Ar] 3d6 4s2") to its full form. */
export function expandConfig(semantic) {
  if (!semantic) return "";
  const match = semantic.match(CORE_RE);
  if (!match) return semantic.trim().replace(/\s+/g, " ");
  const core = CORES[match[1]];
  const rest = semantic.slice(match[0].length).trim();
  return rest ? `${core} ${rest}` : core;
}

const SUBSHELL_RE = /(\d+)([spdf])(\d+)/g;

/** Parse a full config string into [{n, l, electrons}] in the order written. */
export function parseConfig(full) {
  const out = [];
  if (!full) return out;
  for (const m of full.matchAll(SUBSHELL_RE)) {
    out.push({ n: Number(m[1]), l: m[2], electrons: Number(m[3]) });
  }
  return out;
}

const BOX_COUNTS = { s: 1, p: 3, d: 5, f: 7 };

/**
 * Per-subshell orbital boxes with Hund's rule applied: every box gets one
 * up-spin electron first, then boxes are re-visited in order for pairing
 * (down-spin). Matches the conventional left-to-right filling diagram.
 */
export function orbitalBoxes(parsed) {
  return parsed.map(({ n, l, electrons }) => {
    const boxCount = BOX_COUNTS[l] ?? 1;
    const boxes = Array.from({ length: boxCount }, () => ({ up: false, down: false }));
    const firstPass = Math.min(electrons, boxCount);
    for (let i = 0; i < firstPass; i++) boxes[i].up = true;
    const remaining = electrons - boxCount;
    if (remaining > 0) {
      for (let i = 0; i < remaining; i++) boxes[i].down = true;
    }
    return { n, l, label: `${n}${l}`, electrons, boxes };
  });
}

/** Sum electrons per principal shell: [K, L, M, ...] indexed by n-1. */
export function shellsFromConfig(parsed) {
  const maxN = parsed.reduce((m, s) => Math.max(m, s.n), 0);
  const shells = new Array(maxN).fill(0);
  for (const { n, electrons } of parsed) shells[n - 1] += electrons;
  return shells;
}

/**
 * Valence ("free") electron count. Prefers the data record; when absent,
 * derives it as the electrons in the highest-n subshells of the full config
 * (covers s/p valence electrons; inner d/f electrons of the same outer
 * shell are intentionally excluded — good enough for main-group display,
 * transition-metal edge cases should supply `valence` explicitly).
 */
export function valenceFromRecord(el) {
  if (el.valence != null) return el.valence;
  const parsed = parseConfig(expandConfig(el.electronConfigFull || el.electronConfig || ""));
  if (!parsed.length) return null;
  const maxN = parsed.reduce((m, s) => Math.max(m, s.n), 0);
  return parsed.filter((s) => s.n === maxN).reduce((sum, s) => sum + s.electrons, 0);
}

export function escapeHtml(str) {
  return String(str ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

export const SHELL_LETTERS = "KLMNOPQ";

/**
 * Deterministic Bohr-model SVG string: nucleus + one <g class="ptd-shell">
 * per shell (style="--i:N" lets CSS vary rotation speed per shell — outer
 * shells get a larger --i so a longer animation-duration reads as slower).
 * Electron dots are placed at evenly-spaced angles with a small per-shell
 * rotational offset (deterministic, not random) purely so shells don't all
 * start with a dot at the same angle.
 */
export function bohrSVG(shells, { symbol = "", size = 260 } = {}) {
  const c = size / 2;
  const nucR = Math.max(14, size * 0.09);
  const shellGap = (c - nucR - 8) / Math.max(shells.length, 1);
  const valenceIdx = shells.length - 1;
  const dotR = Math.max(2.5, size * 0.016);

  const shellsSvg = shells
    .map((count, idx) => {
      const r = nucR + shellGap * (idx + 1);
      const isValence = idx === valenceIdx;
      const offset = idx * 17; // deterministic stagger, not random
      const dots = Array.from({ length: count }, (_, i) => {
        const angle = ((360 / count) * i + offset) * (Math.PI / 180);
        const ex = (c + r * Math.cos(angle)).toFixed(2);
        const ey = (c + r * Math.sin(angle)).toFixed(2);
        return `<circle class="ptd-electron${isValence ? " is-valence" : ""}" cx="${ex}" cy="${ey}" r="${dotR}" />`;
      }).join("");
      return `<g class="ptd-shell" style="--i:${idx + 1}"><circle class="ptd-orbit" cx="${c}" cy="${c}" r="${r.toFixed(2)}" />${dots}</g>`;
    })
    .join("");

  return (
    `<svg class="ptd-bohr" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" role="img" aria-label="Bohr model of ${escapeHtml(symbol)}">` +
    `<circle class="ptd-nucleus" cx="${c}" cy="${c}" r="${nucR.toFixed(2)}" />` +
    `<text class="ptd-nucleus-label" x="${c}" y="${c}" text-anchor="middle" dominant-baseline="central">${escapeHtml(symbol)}</text>` +
    shellsSvg +
    `</svg>`
  );
}

/**
 * Orbital-box diagram HTML: rows grouped by principal shell n (ascending),
 * each subshell rendered as boxes with ↑/↓ per orbitalBoxes(). Subshells in
 * the highest-n row are marked .is-valence for emphasis.
 */
export function orbitalDiagramHTML(parsed) {
  if (!parsed.length) return "";
  const boxes = orbitalBoxes(parsed);
  const maxN = parsed.reduce((m, s) => Math.max(m, s.n), 0);
  const byN = new Map();
  for (const sub of boxes) {
    if (!byN.has(sub.n)) byN.set(sub.n, []);
    byN.get(sub.n).push(sub);
  }
  const rows = Array.from(byN.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([n, subs]) => {
      const subsHtml = subs
        .map((sub) => {
          const isValence = sub.n === maxN;
          const boxesHtml = sub.boxes
            .map(
              (b) =>
                `<span class="ptd-box"><span class="ptd-arrow-up">${b.up ? "↑" : ""}</span><span class="ptd-arrow-down">${b.down ? "↓" : ""}</span></span>`
            )
            .join("");
          return `<div class="ptd-subshell${isValence ? " is-valence" : ""}"><span class="ptd-subshell-label">${escapeHtml(sub.label)}</span><span class="ptd-boxes">${boxesHtml}</span></div>`;
        })
        .join("");
      return `<div class="ptd-orbital-row"><span class="ptd-orbital-row-label">n=${n}</span><div class="ptd-orbital-group">${subsHtml}</div></div>`;
    });
  return `<div class="ptd-orbital-diagram">${rows.join("")}</div>`;
}
