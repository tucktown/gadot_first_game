# Relics — Design

Date: 2026-07-01

Milestone 3 of the [roguelike roadmap](2026-07-01-roguelike-roadmap.md). Goal:
introduce **relics** — persistent, run-modifying artifacts — as the reward that
makes risking the elite worthwhile. This is the first system that is both
**run-scoped + serialized** and reaches *into* combat, so it establishes the
pattern the branching map (milestone 4) will lean on.

Builds on milestone 1 (status effects: Strength) and milestone 2 (the elite,
Dread Sentinel). Relics affect only the player.

## Current state (baseline)

- `RunState` (`systems/run_state.gd`) is the run's source of truth: `max_health`,
  `current_health`, `encounter_number`, `deck: Array[CardData]`, `awaiting_reward`,
  `run_complete`. It serializes the run to `user://run.json` (`SAVE_VERSION`, deck
  saved as **card-id strings** resolved via `CARD_CATALOG`; `load_saved_run`
  invalidates the save on any mismatch). Currently `SAVE_VERSION == 2`.
- Reward flow: `complete_combat(remaining_health)` — for a non-final win, increments
  `encounter_number`, sets `awaiting_reward`, saves; for the final win, sets
  `run_complete` and clears the save. `get_resume_scene()` returns `card_reward.tscn`
  when `awaiting_reward`, else the combat scene.
- `card_reward.gd` shows 3 random cards from a `REWARD_POOL`, `RunState.add_card(...)`
  on pick, continue to combat.
- `CombatState` (`combat/combat_state.gd`) is pure/headless. `begin(...)` sets up
  combat and draws the opening hand; `end_player_turn()` runs the enemy turn and,
  on the return-to-player path, resets energy and draws the next hand.
- `EnemyData` has `is_elite`? **No** — needs adding. The run is
  `ENCOUNTERS = [CINDER_HOUND, PLAGUE_CRAWLER, DREAD_SENTINEL, BONE_ACOLYTE, GRAVEMAW]`;
  Dread Sentinel (index 2) is the elite, Gravemaw (index 4) the boss/final.

## Decisions

- **Effect model: declarative typed effects** (`.tres`-authored `trigger` + `effect`
  + `magnitude`), applied by one tested applier in `CombatState`. Not per-relic
  scripts. Same reasoning as the milestone-2 enemy-AI decision: smallest fully
  testable, data-authored change; the pure core stays pure.
- **Acquisition: elite grants a relic** (used in the two fights after it). The boss
  currently ends the run, so **boss relics are deferred to the map milestone**; the
  reward hook is built generically so the map can grant relics without rework.
- **No starter relic** — first relic is the elite reward.
- **Pool of 4 relics; elite reward offers a choice of 3** (mirrors the card reward).
- **Display: text badges + hover tooltip** — no art, no API spend, consistent with
  the label-based intent from milestone 2.

## 1. Data model

`RelicData` (`relics/relic_data.gd`, `Resource` subclass):

```gdscript
class_name RelicData
extends Resource

enum Trigger { COMBAT_START, TURN_START }
enum Effect { GAIN_BLOCK, GAIN_ENERGY, GAIN_STRENGTH, DRAW_CARD }

@export var id: StringName
@export var display_name: String = "New Relic"
@export var description: String = ""
@export var trigger: Trigger = Trigger.COMBAT_START
@export var effect: Effect = Effect.GAIN_BLOCK
@export_range(0, 99) var magnitude: int = 0
```

Definitions authored as `.tres` under `relics/definitions/`.

`RunState`:
- `var relics: Array[RelicData] = []` — run-scoped held relics.
- `RELIC_CATALOG := { &"stone_heart": ..., ... }` (id → preloaded `RelicData`), the
  relic analogue of `CARD_CATALOG`.
- `func add_relic(relic: RelicData) -> void` — append, clear `awaiting_relic`, save.

## 2. Effect system

`CombatState`:
- `begin(...)` gains a trailing `relics: Array[RelicData] = []` param; stored as
  `self.relics`.
- `func _apply_relics(trigger: RelicData.Trigger) -> void`: for each relic whose
  `trigger` matches, apply its `effect`:
  - `GAIN_BLOCK` → `player_block += magnitude`
  - `GAIN_ENERGY` → `energy += magnitude` (uncapped; intentional)
  - `GAIN_STRENGTH` → `player_status.add(StatusSet.Type.STRENGTH, magnitude)`
  - `DRAW_CARD` → `draw_cards(magnitude)`

**Hook points:**
- In `begin()`, after the opening hand is drawn and energy set: call
  `_apply_relics(COMBAT_START)` then `_apply_relics(TURN_START)` (combat start and
  turn 1 both begin here).
- In `end_player_turn()`, on the return-to-player path (right where energy is reset
  and the new hand is drawn), call `_apply_relics(TURN_START)`.

Effects mutate the same state the view already renders (`player_block`, `energy`,
hand, `player_status`), so no result-dict plumbing is required — a start-of-combat
block or a per-turn extra card simply appears on the next `_refresh_combat_view`.
`GAIN_ENERGY` may push energy above `max_energy` (label reads e.g. `4 / 3`);
acceptable and expected for an energy relic.

## 3. The 4 relics

Authored under `relics/definitions/`, dark-fantasy flavored:

| id | display_name | trigger | effect | magnitude | description |
|---|---|---|---|---|---|
| `stone_heart` | Stone Heart | COMBAT_START | GAIN_BLOCK | 6 | "Start each combat with 6 Block." |
| `battle_fervor` | Battle Fervor | COMBAT_START | GAIN_STRENGTH | 1 | "Start each combat with 1 Strength." |
| `everflow_battery` | Everflow Battery | TURN_START | GAIN_ENERGY | 1 | "Gain 1 extra Energy at the start of each turn." |
| `scrying_lens` | Scrying Lens | TURN_START | DRAW_CARD | 1 | "Draw 1 additional card at the start of each turn." |

Together these exercise both triggers and all four effects.

## 4. Acquisition

- `EnemyData` gains `@export var is_elite: bool = false`. Dread Sentinel's `.tres`
  sets it true.
- `RunState` gains `var awaiting_relic := false` (serialized alongside
  `awaiting_reward`).
- `complete_combat(remaining_health)` — determine the beaten enemy
  (`ENCOUNTERS[encounter_number - 1]`, before incrementing). For a non-final win:
  increment, then set `awaiting_relic = true` if that enemy `is_elite`, else
  `awaiting_reward = true`; save. Final win unchanged (run complete). An elite grants
  **only** a relic (no card that fight).
- `get_resume_scene()` returns `relic_reward.tscn` when `awaiting_relic`, else the
  existing card-reward / combat routing.
- `combat_screen._on_result_action_button_pressed()` (the post-win "continue" path)
  routes to `relic_reward.tscn` when `RunState.awaiting_relic`, else the current
  card-reward / run-complete logic. (Its VICTORY button label should read
  "Choose Relic" for an elite win.)
- New `relic_reward.tscn` + `relic_reward.gd`, mirroring `card_reward`: shows 3
  random relics from `RELIC_POOL` (the 4 definitions), player picks one →
  `RunState.add_relic(...)` → continue to `combat_screen.tscn`.

`RELIC_POOL` lives in `relic_reward.gd` (as `REWARD_POOL` does for cards).

## 5. UI (text badges, no art)

- **Combat** (`combat/combat_screen.tscn` + `.gd`): a new relic bar
  (`HBoxContainer`, `%RelicBar`) near the player HUD overlay. `_refresh_combat_view`
  rebuilds it from `RunState.relics` — one badge (a `Label`, or small
  `PanelContainer`+`Label`) per relic, `tooltip_text` set to the relic description.
  `_start_combat` passes `RunState.relics` into `state.begin(...)`.
- **Relic reward screen**: 3 selectable panels, each a name `Label` + description
  `Label` (no artwork), following the card-reward screen's layout, selection
  feedback, deck/continue affordances.

## 6. Testing (`tests/`, plain `SceneTree`)

Add relic cases (new `tests/relic_test.gd`, or extend an existing suite):
- `RelicData` defaults (magnitude 0, trigger COMBAT_START, effect GAIN_BLOCK).
- `CombatState.begin` with a `stone_heart`-like relic → `player_block == 6`.
- `begin` with a `battle_fervor`-like relic → player Strength == 1 and it boosts the
  first attack's damage.
- TURN_START energy relic → after `end_player_turn`, `energy == max_energy + magnitude`.
- TURN_START draw relic → hand grows by `magnitude` on the new turn.
- Multiple relics stack.
- `RunState`: `RELIC_CATALOG` contains all 4 ids; relic save/load round-trips by id;
  `load_saved_run` invalidates on an unknown relic id; `awaiting_relic` and
  `SAVE_VERSION == 3` serialize/restore; a beaten `is_elite` enemy sets
  `awaiting_relic` (not `awaiting_reward`) and `get_resume_scene()` returns the
  relic-reward scene.

## Out of scope / deferred

- Boss and other relic sources (branching map, milestone 4).
- Relic art (text badges for now).
- Scripted/complex relics and additional triggers (on-attack, on-damage, on-block,
  end-of-turn) — only COMBAT_START and TURN_START now; add when a relic needs them.
- Relic removal/selling, negative/curse relics, relic synergies.
