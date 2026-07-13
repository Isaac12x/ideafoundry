# VISION.md for ideafoundry

```
The CRM+planner for ideas.
The solveforintelligence.com of ideas ip.
The default sw for working on ideas (research, experiments).
The default sw to triage/plan/develop/categorize/score ideas.
The default sw to sell ideas (marketplace).
The default sw to provenance ideas.
The default sw for the legacy of ideas.
The default sw for collaborating on ideas at any stage.
```

The above captures how ideafoundry treats ideas. Ideas are paramount and so is all things related to them.

This means ideas can come in any form: text, voice, video, images, drawings, etc. And this app allows them to be captured in all and any of these formats from anywhere: in app, mobile, email, chrome extension, etc.

**Capture promise:** an idea is captured in seconds, in any format, from wherever you are, and is never lost. Friction at capture kills ideas; this is the one SLO the whole ecosystem serves.

## Who it's for

Anyone. MIT licensed — anyone can run it, own it, extend it.

Collaboration is per idea, between *objects* (an object = a user or a team): 1-to-1, 1-to-many, many-to-many. A team counts as one object regardless of size.

## Platform parts

One application, distinct parts:

- **Ideas workbench** — capture, triage, develop, score, plan (the core).
- **Notes** — in service of ideas.
- **KB/research** — the user's research substrate.
- **Execution PM** — building out ideas that graduate to execution.
- **Internal CRM** — the user's own contacts/relationships.
- **IP platform** — legal side: provenance, protection, licensing.
- **Marketplace** — selling ideas, communicates with the webapp.
- **Legacy** — succession of ideas and research.

## Idea lifecycle

Canonical stages every feature hangs off:

```
capture → score → triage → develop (research/experiments) → decide
                                                            ├─ build
                                                            ├─ license/sell
                                                            ├─ park/archive
                                                            └─ legacy
```

Full provenance at every step: every transition, edit, and contribution is recorded. An idea can loop (capture↔decide) but never loses history.

## Trust & provenance promise

Ideas here are pre-patent IP. The promises:

- **Local and encrypted.** The db is encrypted at rest, keys set by the user in /settings. Your machine is the vault and source of truth. Nothing leaves without an explicit action, and everything that leaves (sync via zephyrus/oracle/noder) is encrypted to the user's encryption set — satellites only ever see ciphertext.
- **Full provenance at every step.** Who had what idea when: full version history, activity log, authorship signals (typing/voice fingerprints). The story of an idea is reconstructable end to end.
- **Agents on a leash.** Agents are local to the app (not a 3rd-party LLM) and act only through scoped, revocable tokens. Outward-facing actions (email, publish, sell) require human approval.
- **No lock-in.** Everything exports to open formats at any time. Required for legacy, honest everywhere else.

## Scoring

Scoring is defined per user — each user builds their own scoring scheme and applies it to their ideas. The IP platform uses its own separate scoring. Scores are versioned like everything else — how your judgement of an idea changed is itself provenance.

## Marketplace

A distinct part of the application that communicates with the marketplace webapp — a company-hosted service separate from the ideafoundry app. The user decides an idea is up for grabs; bidders/buyers then access it via the webapp. Mechanics contained here: sale, royalties, NDAs, escrow, valuation. A marketed idea gets a curated public face (pitch, selected artifacts) — the webapp only ever holds what the user chose to publish; the vault stays private.

## Legacy

An idea outlives its author, with fine-grain control over succession. The user designates who receives what: all of it to one person, or partitioned — certain ideas to one successor, others to another, research likewise — each partition encrypted with its own key.

Transition mechanics: the noder delivers the encrypted db (or partition) to the successor; the cryptographic key reaches them by a separate, untraceable channel. Whoever holds the db and its key holds the rights to those ideas.

Publication-as-prior-art is in scope: the user can choose to publish ideas defensively. This falls within the IP platform.

## Agents

Agents are local to the app — not a 3rd-party LLM. The local agent has access to the whole context and loads different parts as needed. It helps the user organically: shape ideas, score them, organize, enrich. It can do web search for enrichment, but without any disclosure of the user's ideas. In the IP platform the agent becomes an expert IP/corporate lawyer and helps with all legal matters. All agent activity is attributed and logged as provenance (human vs agent contribution is always distinguishable).

## Knowledge base

Key component of the system. Users can add anything here — including their own research — to consult, use as reference, and connect to ideas as evidence: support, prior art, contradiction, inspiration. An idea with a KB trail is a developed idea; the trail is part of its provenance and its sale value.

## Ecosystem

- **ideafoundry** (this app): source of truth, the vault, the workbench.
- **zephyrus**: mobile app; encrypts media and sends it to the paired ideafoundry instance. If that node is offline, the encrypted media goes to the oracle instead.
- **oracle**: encrypted store-and-forward; holds media until the paired ideafoundry instance is online, then delivers it via the intake flow.
- **noder**: resilience — produces encrypted backup copies on the 3-2-1 principle, and executes the legacy transition mechanism.
- **relay**: service/worker carrying collaboration traffic between objects. Users launch their own or use the company-owned ones, chosen in /settings/collaborations.
- **marketplace webapp**: company-hosted, separate from the ideafoundry app; where bidders/buyers meet published ideas.
- plus other associated ways of interacting with the app+agents while not directly in the app.

Contract: ideafoundry owns the data; satellites capture, relay, and back up — always ciphertext, never plaintext.

## Non-goals

- Not a social network. Sharing is deliberate, scoped, per-idea.
- Not a cloud service. No central server ever holds plaintext.

## Development strategy

1. Max functionality.
2. Max versatility
3. Max customizability (how you work, how you collaborate, how you like looking at this)

Steps:
1.1 Gather all functionality in the backlog
1.2 Iterate on the functionality until it is all implemented
1.3 Verify
1.4 Add deterministic tests
2.1 Add multiple views, templates, layers, etc.
2.2 Add multiple ways of working.
2.3 Add multiple ways to accomplish anything and track them
2.4 Verify
3.1 Add skins/, preferred_views/, and other ways to modify the appearence, layout, background, etc.
3.2 Add ways for the user to modify the look and feel too. Skins mixed with their own patterns (e.g. noise on the background, shades with coloring, etc.) like 2000 software used to do.
3.3 Other customizations like preferred agents, preferred services, preferred way of interacting, etc.
3.4 Verify

## Open questions

- Collaboration: relay carries the traffic, but merge/reconciliation semantics for concurrent many-to-many edits still to define.
