// Guide: how to read the table, the big trends, glossary, conventions,
// shortcuts and data sources. Static content plus a glossary filter.

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

const GLOSSARY = [
  ["Atomic number (Z)", "Number of protons in the nucleus. Defines the element and its position; Moseley (1913) showed it from X-ray spectra."],
  ["Mass number (A)", "Protons + neutrons in one nucleus. Isotopes of an element differ in A."],
  ["Standard atomic weight", "Abundance-weighted mean mass of an element's natural isotopes, in unified atomic mass units (u = 1/12 of ¹²C). Varies slightly between natural sources, hence the ± uncertainty."],
  ["Bracketed weight [ ]", "For elements with no stable isotopes, the mass number of the longest-lived isotope stands in for a weight."],
  ["Mole", "6.022 140 76 × 10²³ entities (Avogadro's number). The mass of one mole in grams equals the formula weight in u."],
  ["Isotope", "Atoms with the same Z but different neutron counts. Chemically almost identical; physically distinct (mass, nuclear stability)."],
  ["Nuclide", "A specific nucleus defined by Z and N (and energy state). ~3,400 are known; ~250 are stable."],
  ["Half-life (t½)", "Time for half of a radioactive sample to decay. Spans from ~10⁻²² s (unbound resonances) to >10²⁴ years (¹²⁸Te)."],
  ["Decay modes", "α: emits ⁴He (Z−2, A−4). β⁻: n→p (Z+1). β⁺/EC: p→n (Z−1). SF: the nucleus splits. IT: an excited state relaxes."],
  ["Magic numbers", "2, 8, 20, 28, 50, 82, 126 protons or neutrons close nuclear shells, giving extra stability (doubly magic: ⁴He, ¹⁶O, ⁴⁰Ca, ²⁰⁸Pb)."],
  ["Binding energy per nucleon", "Energy holding the nucleus together divided by A. Peaks near iron/nickel (~8.8 MeV), which is why both fusion of light and fission of heavy nuclei release energy."],
  ["Electron configuration", "Distribution of electrons into subshells (1s² 2s² 2p⁶…), filled roughly by the Aufbau (n+ℓ) rule, with exceptions near half/full d and f subshells."],
  ["Shell / subshell", "Shell n = 1, 2, 3… (K, L, M…); subshells s, p, d, f hold 2, 6, 10, 14 electrons."],
  ["Valence electrons", "Outer electrons that participate in bonding; main-group elements tend to reach 8 (octet) or 2 (duet)."],
  ["Term symbol", "²ˢ⁺¹L_J — compact quantum state of an atom: multiplicity from unpaired spins, total orbital angular momentum (S, P, D, F…), and J. Used in spectroscopy and magnetism."],
  ["Hund's rules", "Electrons fill degenerate orbitals singly with parallel spins before pairing — the origin of most atomic magnetism."],
  ["Ionisation energy", "Energy to remove an electron from a gaseous atom or ion. Large jumps between successive values reveal shell boundaries."],
  ["Electron affinity", "Energy released when a gaseous atom gains an electron. Positive for halogens; ~0 or negative for noble gases."],
  ["Electronegativity (χ)", "Tendency of a bonded atom to attract electrons. Pauling's scale (thermochemical) is standard; Allen's is spectroscopic. Δχ predicts bond polarity."],
  ["Oxidation state", "Hypothetical charge if all bonds were ionic. Ranges from −4 (C) to +9 (Ir in IrO₄⁺). Governs formulas and redox chemistry."],
  ["Bond character", "Continuum from nonpolar covalent (Δχ < 0.4) through polar covalent to ionic (Δχ > 1.7); metallic bonding between metals."],
  ["Atomic radii", "Empirical: from bond lengths in compounds. Covalent: half a homonuclear single bond. Metallic: half the metal's interatomic spacing (CN 12). Van der Waals: non-bonded contact."],
  ["Shannon ionic radius", "Radius of an ion in crystals, tabulated by charge, coordination number (CN) and spin state. The basis of ionic-substitution and perovskite tolerance-factor reasoning."],
  ["Coordination number (CN)", "Number of nearest neighbours around an atom or ion (written in Roman numerals in Shannon's table)."],
  ["Lanthanide contraction", "Poor shielding by 4f electrons shrinks atoms after La — so Hf ≈ Zr and Ta ≈ Nb in size, making them hard to separate."],
  ["Inert pair effect", "Heavy p-block elements (Tl, Pb, Bi) prefer oxidation states two below the group maximum because relativistic 6s² electrons hold on."],
  ["Diagonal relationship", "Li–Mg, Be–Al and B–Si resemble each other because size and charge density trends run diagonally."],
  ["Crystal structures", "FCC (ccp) and HCP pack spheres at 74% efficiency; BCC at 68%. Slip systems decide ductility: FCC 12 easy systems, HCP few, BCC many but temperature-sensitive."],
  ["Allotropes", "Different structural forms of one element: diamond/graphite/fullerene (C), white/red/black (P), α/β/γ/δ iron, grey/white tin."],
  ["Phase transitions", "Melting, boiling and sublimation points at 1 atm; the triple point is where solid, liquid and gas coexist; above the critical point liquid and gas merge."],
  ["Specific heat & Dulong–Petit", "Most solids hold ~3R ≈ 25 J/(mol·K); per gram this falls as atoms get heavier."],
  ["Elastic moduli", "Young's (tension), shear and bulk moduli in GPa; Poisson's ratio relates lateral to axial strain. Pugh ratio G/B < 0.57 suggests ductility."],
  ["Hardness scales", "Mohs (scratch, 1–10), Vickers and Brinell (indentation, MPa). Values are for pure elements; alloys and processing change them greatly."],
  ["Superconductivity", "Zero resistance below Tc. Nb has the highest elemental Tc (9.25 K); compounds reach 133 K at ambient pressure (cuprates)."],
  ["Magnetic ordering", "Dia- (repelled), para- (weakly attracted), ferro- (spontaneous alignment below Curie T) and antiferromagnetic (antiparallel below Néel T)."],
  ["Goldschmidt classes", "Lithophile (rock), siderophile (iron/core), chalcophile (sulfide/ore), atmophile (volatile) — explains where elements concentrate in Earth."],
  ["Hume-Rothery rules", "Extensive solid solubility needs <15% size difference, same crystal structure, similar χ and suitable valence."],
  ["High-entropy alloy", "≥ 5 principal elements near-equiatomic; ΔS_mix ≥ 1.5R. Phase screening uses VEC (FCC ≥ 8, BCC < 6.87) and size mismatch δ ≤ 6.6%."],
  ["Hill notation", "Formula ordering convention for indexing: C first, H second, then alphabetical (no C: all alphabetical)."],
  ["Empirical vs molecular formula", "Empirical is the simplest whole-number ratio (CH₂O); molecular is the actual count (C₆H₁₂O₆)."],
  ["Limiting reagent", "The reactant consumed first; it sets the maximum (theoretical) yield."],
  ["CAS number", "Chemical Abstracts Service registry identifier — unique, used in safety data sheets and procurement."],
  ["Supply risk index", "RSC/BGS 1–10 composite of scarcity, production concentration, political stability, recycling and substitutability."]
]

const TRENDS = [
  ["Atomic radius", "↙ grows down and to the left", "Each period adds a shell (down); across a period nuclear charge rises with no new shell (left is larger)."],
  ["Ionisation energy", "↗ rises up and to the right", "Smaller atoms with higher effective nuclear charge hold electrons tighter; peaks at He."],
  ["Electronegativity", "↗ rises up and to the right", "Fluorine is the maximum (3.98); caesium/francium the minimum. Noble gases are usually unassigned."],
  ["Metallic character", "↙ rises down and to the left", "Loosely held electrons delocalise into a metallic sea."],
  ["Electron affinity", "↗ broadly up and right", "Halogens highest; irregular because of subshell stability (N, Be, Mg, noble gases)."],
  ["Melting point", "∩ peaks mid-transition series", "Half-filled d bands bond most strongly; tungsten melts at 3695 K."],
  ["Density", "↓ rises down, peaks at Os/Ir", "Heavy nuclei plus lanthanide contraction pack the most mass per volume."],
  ["Reactivity (metals)", "↙ increases down a group", "Cs explodes in water; Li merely fizzes."],
  ["Reactivity (nonmetals)", "↗ increases up a group", "F₂ is the strongest elemental oxidiser; I₂ is mild."]
]

export function mountGuide(panel, ctx) {
  const sources = []
  import("lib/periodic_table/elements").then(({ SOURCES }) => {
    sources.push(...SOURCES)
    const list = panel.querySelector('[data-out="sources"]')
    if (list) list.innerHTML = sources.map((s) => `<li><b>${esc(s.name)}</b> — <span>${esc(s.license)}</span>${/^https?:/.test(s.url) ? ` · <a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.url.replace(/^https?:\/\//, ""))}</a>` : ` · <code>${esc(s.url)}</code>`}</li>`).join("")
  })

  const trendSvg = `
    <svg viewBox="0 0 360 170" class="pb-guide-svg" role="img" aria-label="Diagram of periodic trends: radius and metallic character grow to the lower left; ionisation energy and electronegativity grow to the upper right">
      <defs><marker id="pbArrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" class="pb-guide-arrowhead"/></marker></defs>
      ${Array.from({ length: 7 }, (_, r) => Array.from({ length: 18 }, (_, c) => {
        const show = r === 0 ? c === 0 || c === 17 : r < 3 ? c < 2 || c > 11 : true
        return show ? `<rect x="${12 + c * 18.5}" y="${12 + r * 18.5}" width="16" height="16" rx="2" class="pb-guide-cell"/>` : ""
      }).join("")).join("")}
      <line x1="70" y1="146" x2="326" y2="26" class="pb-guide-arrow pb-guide-arrow--ie" marker-end="url(#pbArrow)"/>
      <text x="348" y="10" text-anchor="end" class="pb-guide-label">ionisation energy · electronegativity increase ↗</text>
      <line x1="300" y1="22" x2="44" y2="142" class="pb-guide-arrow pb-guide-arrow--r" marker-end="url(#pbArrow)"/>
      <text x="12" y="164" class="pb-guide-label">↙ atomic radius · metallic character increase</text>
    </svg>`

  panel.innerHTML = `
    <div class="pb-guide">
      <section class="pb-guide-intro">
        <h3 class="pb-guide-title">The periodic law</h3>
        <p>Order the elements by atomic number and their properties repeat. Mendeleev (1869) saw the pattern in chemistry, left gaps and predicted gallium, scandium and germanium before they were found. Quantum mechanics later explained why: the table's shape <em>is</em> the order in which electron subshells fill — 2 columns of s, 6 of p, 10 of d, 14 of f.</p>
        <ul class="pb-guide-facts">
          <li><b>Period</b> (row) — the outermost shell being filled. Period lengths 2, 8, 8, 18, 18, 32, 32 follow from 2n² electrons per shell.</li>
          <li><b>Group</b> (column, IUPAC 1–18) — same valence-electron arrangement, so similar chemistry: alkali metals, halogens, noble gases.</li>
          <li><b>Block</b> — s, p, d or f, named for the subshell that the last electron enters.</li>
          <li>The f-block (lanthanides, actinides) is drawn below the table to keep it printable; switch to the 32-column layout to see it in place.</li>
        </ul>
      </section>

      <section class="pb-card">
        <h3 class="pb-title">The big trends</h3>
        ${trendSvg}
        <dl class="pb-guide-trends">${TRENDS.map(([k, dir, why]) => `<div><dt>${esc(k)}</dt><dd><b>${esc(dir)}</b> — ${esc(why)}</dd></div>`).join("")}</dl>
        <button type="button" class="pb-btn pb-btn--ghost" data-trend="electronegativity">See electronegativity on the table →</button>
      </section>

      <section class="pb-card">
        <header class="pb-card-head"><h3 class="pb-title">Glossary <small>${GLOSSARY.length}</small></h3>
          <input type="search" class="pb-guide-filter" data-in="filter" placeholder="Filter terms…" aria-label="Filter glossary"></header>
        <dl class="pb-glossary" data-out="glossary">${GLOSSARY.map(([t, d]) => `<div data-term="${esc((t + " " + d).toLowerCase())}"><dt>${esc(t)}</dt><dd>${esc(d)}</dd></div>`).join("")}</dl>
      </section>

      <section class="pb-card">
        <h3 class="pb-title">Conventions & caveats</h3>
        <ul class="pb-guide-list">
          <li>Temperatures in kelvin unless switched; phases are at 1 atm. Gas densities in g/L, solids and liquids in g/cm³.</li>
          <li>Atomic weights are IUPAC standard (conventional abridged values for H, Li, B, C, N, O, Mg, Si, S, Cl, Br, Tl).</li>
          <li>Bulk properties (hardness, moduli, conductivity) are for the pure, polycrystalline element at room temperature; real materials vary with purity, grain size and processing.</li>
          <li>Superheavy-element values (Z ≥ 104) are largely predicted; their chemistry has been probed a few atoms at a time.</li>
          <li>Predicted compounds come from oxidation-state bookkeeping, not thermodynamics — use them as hypotheses.</li>
        </ul>
      </section>

      <section class="pb-card">
        <h3 class="pb-title">Keyboard</h3>
        <dl class="pb-kv pb-kv--keys">
          <div><dt><kbd>/</kbd></dt><dd>Search elements (name, symbol, Z or CAS)</dd></div>
          <div><dt><kbd>←↑→↓</kbd></dt><dd>Move between tiles</dd></div>
          <div><dt><kbd>Enter</kbd></dt><dd>Open the focused element</dd></div>
          <div><dt><kbd>+</kbd> / shift-click</dt><dd>Add to or remove from the tray</dd></div>
          <div><dt><kbd>Esc</kbd></dt><dd>Close the detail panel</dd></div>
        </dl>
      </section>

      <section class="pb-card pb-card--wide">
        <h3 class="pb-title">Data sources</h3>
        <ul class="pb-sources" data-out="sources"><li>Loading…</li></ul>
      </section>
    </div>`

  const onInput = (e) => {
    if (e.target.dataset.in !== "filter") return
    const q = e.target.value.trim().toLowerCase()
    panel.querySelectorAll("[data-term]").forEach((row) => { row.hidden = !!q && !row.dataset.term.includes(q) })
  }
  const onClick = (e) => {
    const b = e.target.closest("[data-trend]")
    if (b) ctx.emit("periodic-table:set-mode", { mode: "trends", property: b.dataset.trend })
  }
  panel.addEventListener("input", onInput)
  panel.addEventListener("click", onClick)
  return {
    update() {},
    destroy() {
      panel.removeEventListener("input", onInput)
      panel.removeEventListener("click", onClick)
    }
  }
}
