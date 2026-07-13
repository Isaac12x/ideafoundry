# VISION GAPS

## First pass analysis
Missing entirely
  1. Trust/privacy/security posture — app holds pre-patent IP. Nothing on encryption, local-first vs cloud, who sees what, agent access limits. For "sell/provenance ideas" this IS the product promise. Biggest gap.
  2. Provenance definition — named but undefined. What guarantee: tamper-evident "who had what idea when"? Timestamping, cryptographic proof, defensive publication? App already has versions + activity logs + voice fingerprints pointing this way; vision should state the actual claim.
  3. Idea lifecycle model — verbs listed (triage/plan/develop/score/sell/legacy) but no canonical state machine. Everything (views, agents, marketplace) hangs off this; should be spec'd once.
  4. Who it's for — no personas. Solo inventor vs team vs licensing agent changes collab model, pricing, marketplace design.

Named but hollow:
  5. Scoring — no criteria (novelty/feasibility/market/effort),no method (manual, agent-assisted, comparative).
  6. Marketplace mechanics — sell how? License (CRM exists), outright sale, royalties? NDAs, escrow, valuation?
  7. Legacy — estate/inheritance? Archival guarantee? Implies an export/no-lock-in promise (open formats, data longevity) not stated anywhere.
  8. Ecosystem contract — zephyrus/oracle/noder named, responsibilities undefined. Sync/conflict model, offline-first or not, source of truth.

Underweighted vs reality of thecodebase:
9. Agents — app is agent-heavy (local_agent toolbox, agent runs/recommendations, tokens) yetvision barely mentions them. Define what agents may do autonomously to your ideas.
10. KB/research — major subsystem, absent from vision. How captured knowledge relates to ideas (evidence? enrichment? prior art?)

Doc hygiene:
11. Non-goals — not a note app, not an execution PM tool. But contains all of this as it is needed for idea lifecycles.
12. Capture SLO — "from anywhere" listed but no principle like "idea captured in <5s, never lost." That's the retention hook.

## Not found on the first pass
1. Agents 
2. Missing review flow
3. Ideas are pre-IP, not necessirily.

## Addressed
1. The db is encrypted, read again. Local. The synching via Zephyrus, the Oracle and the Noder is all encrypted to each users encryption set in the app via /settings.
2. Full provenance at every step.
3. Agreed.
4. This is for anyone. It's MIT licensed so anyone can use it. Collaboration can be between 1 to 1, 1 to many and many to many on a per idea basis. 1 to 1 meaning here the object so user or team (despite the team meaning more than 1 person). The marketplace is a different part of this application as are the internal user CRM, the IP part of the platform, the notes, the execution PM tool, the legacy, etc.
5. Scoring is defined per user. So each user can do their scoring. The ip part of the platform uses a separate scoring.
6. Marketplace mechanics — sell via sale, royalties, NDAs, escrow, valuation. Everything contained in this part of the application communicating with the webapp for it. The user decides X is up for grabs. Bidders/Buyers can then access it via the webapp.
7. Transition to the next person and fine-grain control. So when an inventor dies this then can go to the next person they have set. Transition happens via the noder (receives the encrypted db) and the person will receive the cryptographic key in another way that is not traceable. Whomever holds that apps db has the rights to the ideas. The user can also set up that certain ideas go to one person, certain go to another and the same with his research, then it works as described above except the database is partitioned and encrypted with different keys.
8. Zephyrus; mobile app that encrypts media to send to the app (ideafoundry). If ideafoundry node is offline, the encrypted media is sent to the Oracle. The oracle then waits until that ideafoundry instace (paired) is online to send the information via the intake flow. The noder is for resilience, it produces copies as backup using the 3-2-1 principle and also functions for the legacy mechanism.
9. Agents work in different areas but agents are local to the app not a 3rd party LLM. They can use do web search for enrichment but without any disclosure and help the user shape ideas, score them, etc. The local agent has access to the whole context and can load different parts as needed. The idea is the agent helps organically the user. For IP the agent becomes an expert IP/corporate lawyer and helps with all the legal matters.
10. KB/research - key component of the system, users can add anything here including their own research to consult, use as reference, etc.