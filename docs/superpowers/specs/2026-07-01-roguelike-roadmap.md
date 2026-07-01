# Roguelike Depth Roadmap

Date: 2026-07-01

Goal: reach a **branching map** that improves content and replayability, built on
combat and progression foundations so the map is not a hollow graph. Each
milestone below is its own spec -> plan -> implementation cycle. This document
locks the sequence and sketches the map's target data model up front so earlier
milestones are built "map-aware".

## Milestone sequence

1. **Status effects** - Vulnerable, Weak, Strength, Poison. Combat depth;
   prerequisite for interesting elites and a boss. (First milestone; see
   `2026-07-01-status-effects-design.md`.)
2. **Enemy variety + AI/intents** - more enemies, one elite, one boss;
   conditional/weighted move selection; clearer intent display. Makes map nodes
   feel distinct.
3. **Relics** - persistent run-modifying artifacts. The reward that makes a
   branch worth choosing (risk the elite for a relic).
4. **Branching map** - the headline feature. Node types: combat / elite /
   rest(heal) / boss. Generation, navigation, save integration.
5. **Gold + shop + card upgrades/removal** - enrich the existing map with an
   economy node and deck-sculpting (rest gains "upgrade").
6. **Polish** - events, card keywords (Exhaust/Retain/Innate/X-cost), potions,
   ascension.

Rationale: 1-3 give the map content and stakes; 4 assembles them; 5-6 deepen it.

## Backlog / future enhancements (unscheduled)

Captured during playtesting; slot into a milestone (mostly Polish) when convenient.

- **Run Complete screen revamp** — current screen is bare; make it a proper
  end-of-run summary/celebration.
- **Status hover tooltips** — hovering a status badge (player or enemy) explains
  what it does (Vulnerable/Weak/Strength/Poison). Combat legibility.
- **Victory SFX** — play a win sound when a combat is won (`AudioManager` already
  has an SFX bus; add a cue in the WON branch).
- **Balance: Strength may be too strong** — enemies (esp. The Gravemaw) can stack
  Strength high, snowballing attack damage. Possibly fine as boss threat, but
  revisit tuning; consider a per-turn cap or diminishing returns if it dominates.
- **Run telemetry** — persist per-combat/per-run history for data-driven
  balancing (see the run-telemetry note in memory). Nothing is logged today.
- **Dynamic card values (status-aware previews)** — show a card's *effective*
  numbers given current statuses, not the base definition. E.g. Strike's "Deal 5
  damage" reads "Deal 7 damage" when the player has Strength 2 (and reflects
  Weak/Vulnerable too). Highlight the changed number: green when it's better for
  the player (buffed damage/block), red when worse (Weak-reduced). Needs the
  combat `player_status`/`enemy_status` piped into `CardView.display` and the
  effective value computed with the same formula as `CombatState._attack_damage`
  so preview and outcome always agree.

## Provisional map data model (finalized in milestone 4)

Sketch only, to keep milestones 1-3 compatible. Subject to change.

- A **run** is a generated directed graph of nodes with a current position, held
  in `RunState` (replacing the linear `encounter_number`).
- A **node** has: `id`, `type` (COMBAT/ELITE/REST/SHOP/BOSS/EVENT), `row`,
  `edges` (ids of reachable next nodes), and type-specific payload (e.g. which
  `EnemyData` for combat/elite).
- **Navigation**: the player picks one of the current node's `edges` to advance.
- **Save shape**: serialize the graph (nodes + edges), current position, and the
  existing run fields (health, deck ids). Node payloads reference definitions by
  id, matching the existing card-id save approach.

Design implications for earlier milestones:
- Keep run progression decisions (which enemy, is-final) funneled through
  `RunState` accessors, not scattered, so swapping the linear model for a graph
  is localized.
- Statuses (milestone 1) are combat-scoped and never serialized, so they do not
  affect the run/map save shape.
- Relics (milestone 3) are run-scoped and WILL be serialized alongside the run;
  their save keys should coexist with the map fields added in milestone 4.
