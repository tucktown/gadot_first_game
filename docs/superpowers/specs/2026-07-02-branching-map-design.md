# Branching Map — Milestone 4 Design

Status: approved (2026-07-02). Supersedes the linear `encounter_number` progression
sketched provisionally in `2026-07-01-roguelike-roadmap.md` ("Provisional map data model").

## Goal

Replace the run's linear 5-encounter sequence with a **generated branching map** the
player navigates node by node. This is the roadmap's headline feature (milestone 4):
it turns the earlier milestones' content (status effects, enemy variety, relics) into a
route the player chooses — "risk the elite for a relic, or take the safe rest?"

Scale target: a small Slay-the-Spire-style map (7 rows). Big enough for real route
choices, small enough to build the pattern once and expand later (more rows / acts).

## Scope

**In:** map generation, a map-screen hub, four node types (combat / elite / rest / boss),
save integration, `RunState` refactor from linear index to graph.

**Out (deferred):**
- Shop / gold / events — milestone 5 (economy + deck sculpting).
- Row-scaled enemy difficulty (weaker early, tougher late) — **backlog**; enemies rolled
  flat from a pool for now.
- Art-heavy map presentation (custom node art, animated paths) — later polish pass.
- Multiple acts — future; boss win ends the run for now, but the boss still grants a relic
  so the hook pays off when acts land.

## Node types

| Type    | Behavior |
|---------|----------|
| `COMBAT`| Normal fight, enemy rolled from the normal pool. Win → card reward. |
| `ELITE` | Tougher fight (`is_elite` enemy). Win → relic reward (existing `relic_reward.tscn`). |
| `REST`  | No fight. Heal **30% of max HP** (`ceil(max_health * 0.30)`, clamped to max). |
| `BOSS`  | Single node, top row. Win → relic reward → run-complete. |

Rest is heal-only this milestone; the StS "rest OR upgrade a card" choice waits for
milestone 5 deck sculpting.

## Data model

Two new `RefCounted` runtime classes under `systems/`, matching the existing pattern
(`CombatState`, `Deck` are `RefCounted`; `.tres` definitions stay immutable).

### `MapNode` (`systems/map_node.gd`)

```
class_name MapNode extends RefCounted

enum Type { COMBAT, ELITE, REST, BOSS }

var id: int
var type: Type
var row: int
var column: int
var edges: Array[int]          # ids of reachable nodes in the next row
var enemy_id: StringName        # set for COMBAT/ELITE/BOSS; &"" for REST
```

One node = one map position. No engine nodes involved — pure data, testable in isolation.

### `GameMap` (`systems/game_map.gd`)

```
class_name GameMap extends RefCounted

var nodes: Array[MapNode]
var current_node_id: int = -1   # -1 = run not yet entered (choose a row-0 node)

func get_available_node_ids() -> Array[int]   # edges of current node, or all row-0 nodes if current == -1
func get_node_by_id(id: int) -> MapNode
func enter(id: int) -> void                    # sets current_node_id (must be in get_available_node_ids())
func is_boss(node: MapNode) -> bool
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> GameMap   # returns null on malformed data
static func generate(rng: RandomNumberGenerator) -> GameMap
```

`GameMap` owns the graph, the current position, generation, and serialization. `MapNode`
is the small unit it holds. Both understandable and testable without the scene tree.

## Generation — `GameMap.generate(rng)`, seeded

1. **7 rows** (0–6). Row 6 = a single `BOSS` node. Rows 0–5 are "choice" rows.
2. **Width:** each choice row rolls 2–4 nodes.
3. **Edges (bottom-up):** each node in row `r` links to 1–2 nodes in row `r+1`. Connect to
   the nearest columns and keep edges **sorted by column so paths never cross**. Guarantee:
   every node in `r+1` has ≥1 incoming edge (reachable) and every node in `r` has ≥1
   outgoing edge (no dead ends). All row-5 nodes connect to the single boss.
4. **Type assignment:**
   - Row 0 → all `COMBAT` (fair start).
   - Row 5 (pre-boss) → all `REST` (guaranteed heal before the boss).
   - Rows 1–4 → weighted roll: `COMBAT` common, `ELITE` uncommon (**rows 2–4 only**),
     `REST` rare.
5. **Enemy assignment:** `COMBAT` → random from `NORMAL_POOL`; `ELITE` → from `ELITE_POOL`;
   `BOSS` → Gravemaw. Repeats allowed (genre-normal). All rolls use the passed `rng`.

Seeded: a fresh run seed is drawn at `start_new_run()` and fed to `generate`, so the map
is reproducible and generation is deterministically testable.

**`ponytail:` deliberate simplification** — no "no two rests reachable back-to-back" check.
Worst case is a wasted heal, low harm. Upgrade path: add a path-walk constraint during
type assignment if playtest shows it matters.

## Navigation & screen flow

New `screens/map_screen.tscn` + `screens/map_screen.gd`. The map screen is the hub between
nodes.

```
Title → start run → GENERATE MAP → [Map screen]
  pick node → COMBAT → card reward  → back to [Map screen] (next row unlocked)
            → ELITE  → relic reward  → back to [Map screen]
            → REST   → heal 30%       → back to [Map screen]
            → BOSS   → relic reward   → Run-complete
```

**Presentation (functional, not art-heavy):** nodes positioned by row (y) and column (x),
a `Button` per node with `Line2D` edges between connected nodes.

**Each node must clearly read as its type** without the player guessing — via three
redundant cues (no asset generation; built-in font glyph + themed color):

| Type    | Glyph | Color  | Tooltip |
|---------|-------|--------|---------|
| `COMBAT`| ⚔     | red    | "Combat — <enemy name>" |
| `ELITE` | ☠     | purple | "Elite — <enemy name>" |
| `REST`  | ✚     | green  | "Rest — heal 30% HP" |
| `BOSS`  | ♛     | gold   | "Boss — <enemy name>" |

Cue 1 = glyph on the button, cue 2 = the button's color (themed `StyleBox`), cue 3 = a
hover tooltip naming the type (and the enemy for fights). A small always-visible **legend**
(glyph → meaning) sits in a map-screen corner. Tooltips reuse the relic-bar pattern
(`mouse_filter = STOP` so hovers register — the milestone-3 gotcha).

Reachable nodes (`get_available_node_ids()`) are enabled + glow; unreachable are
disabled/greyed (dimmed, but glyph/color still legible so the player can plan a route
ahead). Clicking a reachable node calls into `RunState` to enter it and route:
- `COMBAT`/`ELITE`/`BOSS` → set current node, transition to `combat_screen` (combat reads
  the current node's enemy).
- `REST` → heal, save, reload the map screen.

## `RunState` refactor

- **Remove:** `encounter_number`, `ENCOUNTERS`, and the linear `get_current_enemy` /
  `is_final_encounter` logic.
- **Add:**
  - `var map: GameMap`
  - `NORMAL_POOL: Array[EnemyData]` (Cinder Hound, Plague Crawler, Bone Acolyte),
    `ELITE_POOL: Array[EnemyData]` (Dread Sentinel), boss const (Gravemaw).
  - `ENEMY_CATALOG` — `{ id: EnemyData }`, mirroring `CARD_CATALOG` / `RELIC_CATALOG`, for
    per-node enemy serialization. (`EnemyData.id` already exists and is set in each `.tres`.)
  - `get_current_enemy()` resolves the current node's `enemy_id` through `ENEMY_CATALOG`.
- `start_new_run()` → draw a run seed, `map = GameMap.generate(rng)`.
- Player advances by **picking the next node on the map**, not by incrementing an index.
- `complete_combat(remaining_health)` → if the current node is the boss, `run_complete` +
  `clear_saved_run()`; otherwise set `awaiting_reward` (combat) or `awaiting_relic` (elite)
  by the current node's type, then `save_run()`. The map's `current_node_id` stays on the
  just-cleared node; the player re-enters the map and picks from its `edges`.
- `get_resume_scene()` → returns the map screen when between nodes (reward flags still take
  precedence so an unclaimed reward resumes correctly).

## Save format — `SAVE_VERSION = 4`

Serialize the **full graph** (not seed-only — robust if generation logic changes mid-run):

```
{
  "version": 4,
  "current_health": int,
  "awaiting_reward": bool,
  "awaiting_relic": bool,
  "deck": [card_id, ...],
  "relics": [relic_id, ...],
  "map": {
    "current_node_id": int,
    "nodes": [
      { "id": int, "type": int, "row": int, "column": int,
        "edges": [int, ...], "enemy_id": String }, ...
    ]
  }
}
```

Same aggressive fail-safe as the existing deck/relic loading: on any mismatch — bad version,
unknown `enemy_id` (not in `ENEMY_CATALOG`), malformed node, out-of-range health, invalid
`current_node_id` — `load_saved_run()` calls `clear_saved_run()` and returns false. Old v3
saves are cleared on load (expected; the linear field `encounter_number` is gone).

## Testing — `tests/map_generation_test.gd`

`GameMap` is pure (no scene tree), so it's headless-testable like `CombatState`. Assert:

- 7 rows; exactly one `BOSS` node, alone on the top row.
- Row 0 is all `COMBAT`; row 5 is all `REST`.
- No `ELITE` outside rows 2–4.
- Every node is reachable from some row-0 node; every non-boss node has ≥1 outgoing edge.
- Edges never cross (columns sorted per node).
- Determinism: the same seed produces an identical map.
- `to_dict()` → `from_dict()` round-trips to an equivalent map.

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd`

## Adding content later

- New enemy still registers in `ENEMY_CATALOG` (like `CARD_CATALOG`), and joins
  `NORMAL_POOL` or `ELITE_POOL` as intended — no more editing a fixed `ENCOUNTERS` list.
- Row-scaled difficulty (backlog): tag enemies with a tier and pick from a row-appropriate
  slice of the pool inside `generate`.
