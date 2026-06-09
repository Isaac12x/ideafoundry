# Graph Report - idea-app  (2026-06-09)

## Corpus Check
- 367 files · ~544,643 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 215 nodes · 299 edges · 27 communities (23 shown, 4 thin omitted)
- Extraction: 79% EXTRACTED · 21% INFERRED · 0% AMBIGUOUS · INFERRED: 64 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2821398e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 20|Community 20]]

## God Nodes (most connected - your core abstractions)
1. `User` - 94 edges
2. `SettingsController` - 67 edges
3. `Update Workflow` - 9 edges
4. `Update Excalidraw Package` - 7 edges
5. `Changelog` - 7 edges
6. `[Unreleased]` - 5 edges
7. `SettingsControllerTest` - 5 edges
8. `[1.4.0] - 2026-05-12` - 4 edges
9. `[1.1.0] - 2026-03-16` - 4 edges
10. `[1.2.0] - 2026-03-24` - 3 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities (27 total, 4 thin omitted)

### Community 2 - "Community 2"
Cohesion: 0.09
Nodes (21): [1.0.0] - 2026-02-24, [1.1.0] - 2026-03-16, [1.2.0] - 2026-03-24, [1.3.0] - 2026-03-28, [1.4.0] - 2026-05-12, Added, Added, Added (+13 more)

### Community 3 - "Community 3"
Cohesion: 0.12
Nodes (15): code:bash (cd /home/devuser/ideafoundry), code:bash (npm view @excalidraw/excalidraw version dist-tags --json), code:bash (npm install @excalidraw/excalidraw@latest), code:bash (corepack yarn add @excalidraw/excalidraw@latest), code:tsx (import { Excalidraw, exportToBlob } from "@excalidraw/excali), code:bash (npm run build), code:bash (npm run verify:excalidraw-local-only), code:bash (git diff -- package.json package-lock.json yarn.lock esbuild) (+7 more)

### Community 4 - "Community 4"
Cohesion: 0.16
Nodes (4): install_url(), MobileUplink, pairing_payload(), qr_svg()

## Knowledge Gaps
- **28 isolated node(s):** `Overview`, `When to Use`, `code:bash (cd /home/devuser/ideafoundry)`, `code:bash (npm view @excalidraw/excalidraw version dist-tags --json)`, `code:bash (npm install @excalidraw/excalidraw@latest)` (+23 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `User` connect `Community 0` to `Community 4`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 10`, `Community 11`, `Community 12`, `Community 13`, `Community 15`, `Community 16`, `Community 17`, `Community 18`, `Community 19`, `Community 22`, `Community 23`, `Community 24`, `Community 25`, `Community 26`?**
  _High betweenness centrality (0.364) - this node is a cross-community bridge._
- **Why does `SettingsController` connect `Community 1` to `Community 4`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 10`, `Community 11`, `Community 12`, `Community 13`, `Community 14`, `Community 16`, `Community 17`, `Community 18`, `Community 19`, `Community 21`, `Community 22`, `Community 23`, `Community 24`?**
  _High betweenness centrality (0.290) - this node is a cross-community bridge._
- **What connects `Overview`, `When to Use`, `code:bash (cd /home/devuser/ideafoundry)` to the rest of the system?**
  _28 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.06451612903225806 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.06896551724137931 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._