# Enemy Variety + AI/Intents — Design

Date: 2026-07-01

Milestone 2 of the [roguelike roadmap](2026-07-01-roguelike-roadmap.md). Goal:
make combat encounters feel distinct via more enemies (incl. one elite, one
boss), conditional/weighted move selection, and clearer intent display —
building content the milestone-4 branching map will draw from.

Builds directly on milestone 1 (status effects: Vulnerable, Weak, Strength,
Poison), which are fully wired and ready for enemies to apply and react to.

## Current state (baseline)

- `EnemyData` (`enemies/enemy_data.gd`): `id`, `display_name`, `max_health`,
  `move_pattern: Array[EnemyMoveData]`, `artwork`. `get_move(turn_index)` returns
  `move_pattern[turn_index % size]` — a **fixed cycle**. No conditions, weights,
  or randomness.
- `EnemyMoveData` (`enemies/enemy_move_data.gd`): pure data —
  `damage`, `block`, `weak_applied`, `vulnerable_applied`, `poison_applied`,
  `strength_gained`.
- **Selection lives in the view**: `combat_screen.gd` calls
  `enemy.get_move(state.enemy_turn_index)` (once for the intent label ~line 92,
  once at end-of-turn ~line 189) and passes the move into
  `state.end_player_turn(move)`. `CombatState` never *chooses* — it is told.
- **Intent** is a single text `Label` (`%EnemyIntentLabel`), built by
  `_get_intent_text` → e.g. `"Intent: Overhead Smash - 15 damage"`.
- Run is a linear 3-encounter list: `RunState.ENCOUNTERS = [TRAINING_DUMMY,
  RAIDER, GUARDIAN]`, indexed by `encounter_number`. Save format (v1) serializes
  `encounter_number` (not enemy ids); validated against `ENCOUNTERS.size()`.

## Decisions

- **AI model: declarative rules** (data on `.tres`, one tested selector). Not
  per-enemy scripts. Keeps all enemies data-authored and uniformly testable.
- **Selection model: flat conditional pool.** No fixed sequence. Each turn:
  filter an enemy's moves by their `condition`, then weighted-roll among the
  eligible ones. (Authored openers/telegraphed combos are out of scope; a future
  boss that needs them can get a bespoke condition or drop to a scripted AI.)
- **Behaviors supported:** weighted random pool, HP threshold, react-to-player.
  (No-repeat rule intentionally omitted — weights already reduce repetition.)
- **Roster size: medium** — 3 new normals + 1 elite + 1 boss. Existing raider
  and guardian fold into the normal pool.
- **Intent UI: icon+number chips with hover detail.**
- **Run: author a pool, expand the linear run to end on the boss.** Full pool
  stays available for the milestone-4 map.

## 1. Data model

`EnemyMoveData` gains three fields:

```gdscript
enum Condition { ALWAYS, ENEMY_HP_BELOW, PLAYER_BLOCK_BELOW }

@export_range(1, 99) var weight: int = 1
@export var condition: Condition = Condition.ALWAYS
@export var condition_value: float = 0.0
```

- `ALWAYS` — always eligible. `condition_value` ignored.
- `ENEMY_HP_BELOW` — eligible when `enemy_health / enemy_max_health < condition_value`
  (fraction, e.g. `0.5`). Enables enrage / phase behavior.
- `PLAYER_BLOCK_BELOW` — eligible when `player_block < condition_value`.
  `condition_value = 1` means "player undefended".

`EnemyData`:
- Rename `move_pattern` → `moves` (it is a pool now, not a sequence). Update the
  3 existing definition `.tres` files.
- Delete `get_move(turn_index)` — selection moves to `CombatState`.

**Invariant:** every enemy must have at least one `ALWAYS` move. The selector
falls back to it (or, defensively, `moves[0]`) if no move is eligible, so
selection can never return `null` on a non-empty pool.

## 2. Selection — in the tested core

`CombatState` gains:

```gdscript
var rng := RandomNumberGenerator.new()
var planned_move: EnemyMoveData

func choose_enemy_move(enemy: EnemyData) -> EnemyMoveData
```

- `choose_enemy_move`: build the list of eligible moves (condition passes against
  current combat state), then pick one weighted by `weight` using `rng`. If none
  eligible, fall back to the first `ALWAYS` move (else `moves[0]`).
- **Decide-then-telegraph.** `begin()` seeds `rng` and calls
  `planned_move = choose_enemy_move(enemy)`. The intent displays `planned_move`.
  `end_player_turn()` **no longer takes a move param** — it executes
  `self.planned_move`, then re-plans (`planned_move = choose_enemy_move(enemy)`)
  for the next turn's intent. One roll, locked when shown → reload cannot reroll
  a softer intent, and the displayed intent always matches what executes.
- `begin()` needs the `EnemyData` (or its `moves`) so the state can plan. Pass it
  into `begin()`; `CombatState` holds a reference for re-planning.
- `enemy_turn_index` stays (flavor/telemetry) but no longer drives selection.

RNG + save: combats are never saved mid-fight (saves happen between encounters),
so a fresh per-combat seed is sufficient — no RNG state is serialized. Tests set
`state.rng.seed` for determinism.

## 3. Roster

Dark-fantasy set (matches the existing painterly, muted, rim-lit card/enemy art
style). Existing `raider` and `guardian` convert to the flat pool: their current
fixed moves become `ALWAYS` weight-1, preserving behavior. `training_dummy` stays
as the tutorial-tier normal.

| Enemy | Role | Behavior showcase |
|---|---|---|
| Cinder Hound | fast normal, low HP | weighted attacks; bigger bite via `PLAYER_BLOCK_BELOW` |
| Plague Crawler | normal | enemy Poison offense; weighted poison-spit vs. bite |
| Bone Acolyte | normal | self-Strength + Vulnerable on player; `ENEMY_HP_BELOW` → defends |
| Dread Sentinel | **elite**, high HP + block | applies Vulnerable; `ENEMY_HP_BELOW 0.5` enrage |
| The Gravemaw | **boss**, highest HP | all three: heavy hits + Strength above half; `ENEMY_HP_BELOW 0.5` enrage adds Poison and hits harder on `PLAYER_BLOCK_BELOW` |

Each new enemy (5) needs generated art via `tools/gen_asset.py` (1254×1254 RGB
PNG, dark-fantasy style prompt), then `--import` to create `.png.import`
sidecars.

## 4. Run integration

- `ENCOUNTERS` expands to 5: `normal → normal → elite → normal → boss`, pulling
  from the pool. All enemy definitions remain available for the milestone-4 map.
- **No new save keys** — enemies are indexed by `encounter_number`, not
  serialized by id. But **bump `SAVE_VERSION` to 2** so a stale v1 save doesn't
  resume into the rearranged run (`load_saved_run` already invalidates on version
  mismatch).
- **Balance pass:** 5 fights yield 4 card rewards and carry player HP across.
  Tune enemy HP/damage and the encounter order so the run is neither trivial nor
  brutal. This is playtesting, not a code deliverable — call it out in the plan.

## 5. Intent UI (`combat/combat_screen.tscn` + `combat_screen.gd`)

- Replace the single `%EnemyIntentLabel` with an intent **chip row** (an
  `HBoxContainer`): each effect is a chip — sword icon + damage, shield icon +
  block, and status effects as colored abbreviations (reuse `_status_color` and
  the status color scheme already used for badges).
- **Hover detail** via the built-in `Control.tooltip_text` on the row (move name
  + full breakdown). No custom tooltip node.
- Two small icons to author: sword (attack) and shield (block). Full status-icon
  art is deferred to the polish milestone — statuses stay colored-text chips for
  now.
- `combat_screen.gd`: `_refresh_combat_view` reads `state.planned_move` instead
  of `enemy.get_move(...)`; `_get_intent_text` becomes a chip-builder. The
  end-turn handler calls `state.end_player_turn()` with no move argument.

## 6. Testing

Plain `SceneTree` harness under `tests/` (exit code = failure count).

- Selector correctness:
  - `ENEMY_HP_BELOW` gates a move in/out at the fraction boundary.
  - `PLAYER_BLOCK_BELOW` gates a move based on `player_block`.
  - Seeded `rng` produces a deterministic weighted pick from a mixed pool.
  - `ALWAYS` fallback fires when no conditional move is eligible; selection never
    returns `null` on a non-empty pool.
- `planned_move` is locked once per turn: re-reading the intent does not reroll;
  `end_player_turn()` executes exactly the telegraphed move.
- Layout: the chip row fits within the 720 viewport (SceneTree size-measure
  technique already used for HUD clipping).

## Out of scope / deferred

- No-repeat move rule (add if fights feel repetitive).
- Full per-status intent icon art (polish milestone).
- Per-enemy scripted AI (only if a future boss outgrows the flat pool).
- Branching map wiring (milestone 4) — this milestone only expands the linear
  run and leaves the pool map-ready.
