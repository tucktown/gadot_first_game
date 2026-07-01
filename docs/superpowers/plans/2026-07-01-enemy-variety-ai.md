# Enemy Variety + AI/Intents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add more enemies (3 normals + 1 elite + 1 boss), conditional/weighted move selection in the tested combat core, and an icon-based intent display with hover detail.

**Architecture:** Move selection moves out of the view and into `CombatState`. Each enemy is a flat pool of `EnemyMoveData`, each move carrying a `weight` and a `condition`. Each turn the state filters moves by condition, weighted-rolls one via a seeded RNG, stores it as `planned_move` (telegraphed as the intent), and executes exactly that move on end-of-turn. The linear run expands to 5 encounters ending on the boss; the full enemy set stays available for the milestone-4 map.

**Tech Stack:** Godot 4.7, typed GDScript, `.tres` Resource definitions, plain `SceneTree` test scripts (no framework).

## Global Constraints

- Godot 4.7; run everything with the bundled editor. All `res://` paths are relative to `FirstGame/first-game/`.
- Typed GDScript throughout — type annotations on all vars, params, returns.
- Never mutate `.tres` definitions at runtime; they are shared immutable data (definition vs. instance vs. runtime-state pattern).
- Tests are `extends SceneTree` scripts under `tests/`; exit code == failure count (0 == pass). Run headless via the console exe.
- Enemies are referenced in saves by `encounter_number` index into `ENCOUNTERS`, **not** by id — no per-enemy catalog needed for saves, but bumping `SAVE_VERSION` invalidates stale saves.
- The git repo is `FirstGame/first-game/` (nested). All `git` commands run from there; Godot/python commands run from the repo root `C:/Users/tucke/Documents/Gadot`.

**Command reference:**
```sh
# From repo root — run the combat-core test suite:
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
# Run the new AI test suite:
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
# Re-import assets after generating art (creates .import sidecars):
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
```

---

### Task 1: Add weight/condition fields to EnemyMoveData

**Files:**
- Modify: `enemies/enemy_move_data.gd`
- Test: `tests/enemy_ai_test.gd` (create)

**Interfaces:**
- Produces: `EnemyMoveData.Condition` enum (`ALWAYS=0`, `ENEMY_HP_BELOW=1`, `PLAYER_BLOCK_BELOW=2`); `EnemyMoveData.weight: int` (default 1), `EnemyMoveData.condition: Condition` (default ALWAYS), `EnemyMoveData.condition_value: float` (default 0.0).

- [ ] **Step 1: Write the failing test**

Create `tests/enemy_ai_test.gd`:

```gdscript
extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_move_defaults()
	if failures == 0:
		print("Enemy AI tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_move_defaults() -> void:
	var move := EnemyMoveData.new()
	_expect(move.weight == 1, "Move weight should default to 1.")
	_expect(move.condition == EnemyMoveData.Condition.ALWAYS, "Move condition should default to ALWAYS.")
	_expect(move.condition_value == 0.0, "Move condition_value should default to 0.0.")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 2: Run test to verify it fails**

From repo root:
```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: non-zero exit / errors — `Condition` and the new properties don't exist yet.

- [ ] **Step 3: Implement the fields**

Replace `enemies/enemy_move_data.gd` with:

```gdscript
class_name EnemyMoveData
extends Resource

enum Condition {
	ALWAYS,
	ENEMY_HP_BELOW,
	PLAYER_BLOCK_BELOW,
}

@export var display_name: String = "Enemy Move"
@export_range(0, 999) var damage: int = 0
@export_range(0, 999) var block: int = 0
@export_range(0, 99) var weak_applied: int = 0
@export_range(0, 99) var vulnerable_applied: int = 0
@export_range(0, 99) var poison_applied: int = 0
@export_range(0, 99) var strength_gained: int = 0
@export_range(1, 99) var weight: int = 1
@export var condition: Condition = Condition.ALWAYS
@export var condition_value: float = 0.0
```

- [ ] **Step 4: Run test to verify it passes**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: exit 0, prints `Enemy AI tests passed.`

- [ ] **Step 5: Commit**

```sh
cd FirstGame/first-game
git add enemies/enemy_move_data.gd tests/enemy_ai_test.gd
git commit -m "feat: add weight/condition fields to EnemyMoveData"
```

---

### Task 2: Rename EnemyData.move_pattern → moves

Mechanical rename. `get_move` stays (still used by the view until Task 4) but reads the renamed field. Everything compiles and existing tests stay green.

**Files:**
- Modify: `enemies/enemy_data.gd`
- Modify: `enemies/definitions/training_dummy.tres`, `enemies/definitions/raider.tres`, `enemies/definitions/guardian.tres`
- Modify: `tests/combat_state_test.gd` (references `.move_pattern`)

**Interfaces:**
- Produces: `EnemyData.moves: Array[EnemyMoveData]` (was `move_pattern`).

- [ ] **Step 1: Rename the field in `enemies/enemy_data.gd`**

Replace with:

```gdscript
class_name EnemyData
extends Resource

@export var id: StringName
@export var display_name: String = "New Enemy"
@export_range(1, 9999) var max_health: int = 20
@export var moves: Array[EnemyMoveData] = []
@export var artwork: Texture2D


func get_move(turn_index: int) -> EnemyMoveData:
	if moves.is_empty():
		return null
	return moves[turn_index % moves.size()]
```

- [ ] **Step 2: Update the three definition `.tres` files**

In each of `training_dummy.tres`, `raider.tres`, `guardian.tres`, change the property line `move_pattern = Array[...]([...])` to `moves = Array[...]([...])` — only the property name changes, the value is untouched. Example for `raider.tres` line 15:

```
moves = Array[ExtResource("2")]([ExtResource("3"), ExtResource("4"), ExtResource("6")])
```

- [ ] **Step 3: Update the test reference in `tests/combat_state_test.gd`**

In `_test_enemy_patterns_include_status_moves` (lines ~236 and ~241), change `RunState.RAIDER.move_pattern` → `RunState.RAIDER.moves` and `RunState.GUARDIAN.move_pattern` → `RunState.GUARDIAN.moves`.

- [ ] **Step 4: Run both test suites to verify still green**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: both exit 0.

- [ ] **Step 5: Commit**

```sh
cd FirstGame/first-game
git add enemies/enemy_data.gd enemies/definitions/*.tres tests/combat_state_test.gd
git commit -m "refactor: rename EnemyData.move_pattern to moves (now a pool)"
```

---

### Task 3: Weighted/conditional move selection in CombatState

Add selection logic to the tested core. Does not yet wire into `end_player_turn` or the view — that is Task 4 — so existing behavior is unchanged.

**Files:**
- Modify: `combat/combat_state.gd`
- Test: `tests/enemy_ai_test.gd`

**Interfaces:**
- Consumes: `EnemyData.moves`, `EnemyMoveData.{weight, condition, condition_value}` (Task 1, 2).
- Produces on `CombatState`:
  - `var rng: RandomNumberGenerator`
  - `var enemy: EnemyData`
  - `var planned_move: EnemyMoveData`
  - `func choose_enemy_move(target: EnemyData) -> EnemyMoveData`
  - `func plan_enemy_move() -> void` (sets `planned_move` from `enemy`; no-op if `enemy` is null)

- [ ] **Step 1: Write the failing tests**

Add these to `tests/enemy_ai_test.gd`. Register them in `_run_tests` (call each after `_test_move_defaults()`):

```gdscript
func _test_hp_threshold_gates_move() -> void:
	var state := _combat_with_moves([
		_move("Slam", 10, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Enrage", 20, EnemyMoveData.Condition.ENEMY_HP_BELOW, 0.5, 1),
	])
	state.enemy_max_health = 100
	state.enemy_health = 80  # 80% > 50%, Enrage ineligible
	var eligible_high := _eligible_names(state)
	_expect(not eligible_high.has("Enrage"), "Enrage should be ineligible above the HP threshold.")
	state.enemy_health = 40  # 40% < 50%, Enrage eligible
	var eligible_low := _eligible_names(state)
	_expect(eligible_low.has("Enrage"), "Enrage should be eligible below the HP threshold.")


func _test_player_block_gates_move() -> void:
	var state := _combat_with_moves([
		_move("Bite", 6, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Lunge", 11, EnemyMoveData.Condition.PLAYER_BLOCK_BELOW, 1.0, 1),
	])
	state.player_block = 5  # defended, Lunge ineligible
	_expect(not _eligible_names(state).has("Lunge"), "Lunge should be ineligible while player has block.")
	state.player_block = 0  # undefended, Lunge eligible
	_expect(_eligible_names(state).has("Lunge"), "Lunge should be eligible when player has no block.")


func _test_weighted_pick_is_deterministic_with_seed() -> void:
	var state := _combat_with_moves([
		_move("A", 5, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("B", 5, EnemyMoveData.Condition.ALWAYS, 0.0, 9),
	])
	state.rng.seed = 12345
	var first := state.choose_enemy_move(state.enemy)
	state.rng.seed = 12345
	var second := state.choose_enemy_move(state.enemy)
	_expect(first == second, "Same seed should pick the same move.")
	_expect(first != null, "A non-empty pool should never pick null.")


func _test_always_fallback_when_none_eligible() -> void:
	var state := _combat_with_moves([
		_move("Guard", 0, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Enrage", 20, EnemyMoveData.Condition.ENEMY_HP_BELOW, 0.5, 5),
	])
	state.enemy_max_health = 100
	state.enemy_health = 100  # Enrage ineligible; only Guard (ALWAYS) remains
	var picked := state.choose_enemy_move(state.enemy)
	_expect(picked != null and picked.display_name == "Guard", "Should fall back to the ALWAYS move.")
```

And add these helpers to `tests/enemy_ai_test.gd`:

```gdscript
func _move(name: String, damage: int, condition: EnemyMoveData.Condition, value: float, weight: int) -> EnemyMoveData:
	var move := EnemyMoveData.new()
	move.display_name = name
	move.damage = damage
	move.condition = condition
	move.condition_value = value
	move.weight = weight
	return move


func _combat_with_moves(moves: Array) -> CombatState:
	var enemy := EnemyData.new()
	var typed: Array[EnemyMoveData] = []
	for m in moves:
		typed.append(m)
	enemy.moves = typed
	enemy.max_health = 50
	var state := CombatState.new()
	state.enemy = enemy
	state.enemy_max_health = 50
	state.enemy_health = 50
	state.player_block = 0
	return state


func _eligible_names(state: CombatState) -> Array:
	var names: Array = []
	for m in state.enemy.moves:
		if state._move_eligible(m):
			names.append(m.display_name)
	return names
```

- [ ] **Step 2: Run to verify failure**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: fails — `rng`, `choose_enemy_move`, `_move_eligible` don't exist.

- [ ] **Step 3: Implement selection in `combat/combat_state.gd`**

Add the new vars near the other state vars (after `var enemy_status: StatusSet = StatusSet.new()`):

```gdscript
var enemy: EnemyData
var planned_move: EnemyMoveData
var rng := RandomNumberGenerator.new()
```

Add these methods (place them after `_attack_damage`):

```gdscript
func _move_eligible(move: EnemyMoveData) -> bool:
	match move.condition:
		EnemyMoveData.Condition.ENEMY_HP_BELOW:
			var fraction := float(enemy_health) / float(maxi(1, enemy_max_health))
			return fraction < move.condition_value
		EnemyMoveData.Condition.PLAYER_BLOCK_BELOW:
			return float(player_block) < move.condition_value
		_:
			return true


func choose_enemy_move(target: EnemyData) -> EnemyMoveData:
	if target == null or target.moves.is_empty():
		return null
	var eligible: Array[EnemyMoveData] = []
	for move in target.moves:
		if _move_eligible(move):
			eligible.append(move)
	if eligible.is_empty():
		for move in target.moves:
			if move.condition == EnemyMoveData.Condition.ALWAYS:
				return move
		return target.moves[0]
	var total_weight := 0
	for move in eligible:
		total_weight += move.weight
	var roll := rng.randi_range(1, total_weight)
	var accumulated := 0
	for move in eligible:
		accumulated += move.weight
		if roll <= accumulated:
			return move
	return eligible[eligible.size() - 1]


func plan_enemy_move() -> void:
	if enemy == null:
		return
	planned_move = choose_enemy_move(enemy)
```

- [ ] **Step 4: Run to verify pass**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
```
Expected: both exit 0 (combat_state suite still green — nothing wired yet).

- [ ] **Step 5: Commit**

```sh
cd FirstGame/first-game
git add combat/combat_state.gd tests/enemy_ai_test.gd
git commit -m "feat: weighted/conditional enemy move selection in CombatState"
```

---

### Task 4: Decide-then-telegraph — wire selection into the turn flow

`begin()` takes the enemy and plans the first move; `end_player_turn()` drops its move param, executes `planned_move`, and re-plans for the next turn. The view reads `state.planned_move`. `EnemyData.get_move` is removed. Existing `combat_state_test.gd` call sites migrate to set `planned_move` directly.

**Files:**
- Modify: `combat/combat_state.gd`
- Modify: `enemies/enemy_data.gd` (remove `get_move`)
- Modify: `combat/combat_screen.gd`
- Modify: `tests/combat_state_test.gd`
- Test: `tests/enemy_ai_test.gd`

**Interfaces:**
- Consumes: `plan_enemy_move`, `planned_move`, `choose_enemy_move` (Task 3).
- Produces:
  - `func begin(card_definitions: Array[CardData], starting_enemy_health: int, starting_player_health: int = 50, starting_player_max_health: int = 50, opening_hand_size: int = 5, enemy_data: EnemyData = null) -> void`
  - `func end_player_turn(new_hand_size: int = 5) -> Dictionary` (move param removed; uses `planned_move`)

- [ ] **Step 1: Write the failing test (telegraph lock + re-plan)**

Add to `tests/enemy_ai_test.gd` and register in `_run_tests`:

```gdscript
func _test_end_turn_executes_planned_move_and_replans() -> void:
	var state := _combat_with_moves([
		_move("Hit", 8, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
	])
	state.phase = CombatState.Phase.PLAYER_TURN
	state.player_health = 50
	state.player_max_health = 50
	state.energy = 3
	state.max_energy = 3
	state.plan_enemy_move()
	var planned := state.planned_move
	_expect(planned != null, "A move should be planned.")
	var result := state.end_player_turn(0)
	_expect(result.attack == 8, "end_player_turn should execute the planned move's damage.")
	_expect(state.planned_move != null, "A new move should be planned for the next turn.")
```

- [ ] **Step 2: Run to verify failure**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: fails — `end_player_turn` still requires a move argument.

- [ ] **Step 3: Update `begin()` in `combat/combat_state.gd`**

Change the signature and body. Replace the `begin` header line and add the two closing lines:

```gdscript
func begin(
	card_definitions: Array[CardData],
	starting_enemy_health: int,
	starting_player_health: int = 50,
	starting_player_max_health: int = 50,
	opening_hand_size: int = 5,
	enemy_data: EnemyData = null,
) -> void:
	phase = Phase.PLAYER_TURN
	player_max_health = starting_player_max_health
	player_health = clampi(starting_player_health, 1, player_max_health)
	player_block = 0
	energy = max_energy
	enemy_max_health = starting_enemy_health
	enemy_health = starting_enemy_health
	enemy_block = 0
	enemy_turn_index = 0
	retain_block_this_turn = false
	player_status.stacks.clear()
	enemy_status.stacks.clear()
	hand.clear()
	deck.initialize(card_definitions)
	draw_cards(opening_hand_size)
	enemy = enemy_data
	rng.randomize()
	plan_enemy_move()
```

- [ ] **Step 4: Change `end_player_turn` signature and body in `combat/combat_state.gd`**

Replace the function header and the first lines so it no longer takes a move param and reads `planned_move`:

```gdscript
func end_player_turn(new_hand_size: int = 5) -> Dictionary:
	if phase != Phase.PLAYER_TURN:
		return {}

	var enemy_move := planned_move
	if enemy_move == null:
		enemy_move = EnemyMoveData.new()
```

Leave the rest of the function body unchanged (it already refers to `enemy_move`). Then add a re-plan call immediately before the final `phase = Phase.PLAYER_TURN` block at the end:

```gdscript
	plan_enemy_move()
	phase = Phase.PLAYER_TURN
	energy = max_energy
	draw_cards(new_hand_size)
	return result
```

- [ ] **Step 5: Remove `get_move` from `enemies/enemy_data.gd`**

Delete the `get_move` function entirely, leaving:

```gdscript
class_name EnemyData
extends Resource

@export var id: StringName
@export var display_name: String = "New Enemy"
@export_range(1, 9999) var max_health: int = 20
@export var moves: Array[EnemyMoveData] = []
@export var artwork: Texture2D
```

- [ ] **Step 6: Migrate `combat/combat_screen.gd`**

Change `_start_combat` (the `state.begin(...)` call) to pass the enemy:

```gdscript
	state.begin(
		RunState.deck,
		enemy.max_health,
		RunState.current_health,
		RunState.max_health,
		5,
		enemy,
	)
```

In `_refresh_combat_view`, change the intent line (was line ~92):

```gdscript
	enemy_intent_label.text = _get_intent_text(state.planned_move)
```

In `_on_end_turn_button_pressed` (was lines ~189-192), replace the move lookup and call:

```gdscript
	_set_input_locked(true)
	var enemy_move := state.planned_move
	message_label.text = "%s prepares %s..." % [enemy.display_name, enemy_move.display_name]
	await get_tree().create_timer(0.4).timeout
	var result := state.end_player_turn()
```

- [ ] **Step 7: Migrate `tests/combat_state_test.gd` call sites**

Every call of the form `state.end_player_turn(move, N)` becomes `state.planned_move = move; state.end_player_turn(N)`. Apply to all sites:

- `_test_fortify_retains_block_once`: before each of the two `end_player_turn(attack, 0)` calls, add `state.planned_move = attack`, then call `state.end_player_turn(0)`.
- `_test_enemy_poison_triggers_and_decrements`, `_test_player_poison_ignores_block`, `_test_duration_status_expires_at_turn_end`, `_test_enemy_move_applies_weak_to_player`: before each `end_player_turn(move, 0)`, add `state.planned_move = move`, then call `state.end_player_turn(0)`.

Example (fortify test):
```gdscript
	var attack := EnemyMoveData.new()
	attack.damage = 1
	state.planned_move = attack
	var first_result := state.end_player_turn(0)
	_expect(first_result.retained_block == 3, "Fortify should retain block left after damage.")
	_expect(state.player_block == 3, "Retained block should remain for the next turn.")

	state.planned_move = attack
	var second_result := state.end_player_turn(0)
	_expect(second_result.retained_block == 0, "Fortify should expire after one enemy action.")
	_expect(state.player_block == 0, "Block should reset normally after Fortify expires.")
```
(In `_fresh_state` `enemy` is null, so the re-plan at the end of `end_player_turn` is a no-op and `planned_move` stays as set.)

- [ ] **Step 8: Run all tests**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: both exit 0.

- [ ] **Step 9: Smoke-test the game boots**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --quit-after 2
```
Expected: no script/parse errors in output (headless boot loads all autoloads and scripts).

- [ ] **Step 10: Commit**

```sh
cd FirstGame/first-game
git add combat/combat_state.gd enemies/enemy_data.gd combat/combat_screen.gd tests/combat_state_test.gd tests/enemy_ai_test.gd
git commit -m "feat: decide-then-telegraph enemy moves through CombatState"
```

---

### Task 5: Author the enemy roster (data)

Create the move and enemy `.tres` definitions, register them, expand the run, and bump the save version. Art comes in Task 6 — leave `artwork` unset for now (renders blank, harmless).

**Files:**
- Create move `.tres` under `enemies/moves/` (see table)
- Create enemy `.tres` under `enemies/definitions/`: `cinder_hound.tres`, `plague_crawler.tres`, `bone_acolyte.tres`, `dread_sentinel.tres`, `gravemaw.tres`
- Modify: `systems/run_state.gd`
- Test: `tests/enemy_ai_test.gd`

**Interfaces:**
- Consumes: `EnemyMoveData` fields (Task 1), `EnemyData.moves` (Task 2).
- Produces: `RunState.CINDER_HOUND`, `RunState.PLAGUE_CRAWLER`, `RunState.BONE_ACOLYTE`, `RunState.DREAD_SENTINEL`, `RunState.GRAVEMAW` consts; `ENCOUNTERS` of length 5; `SAVE_VERSION == 2`.

- [ ] **Step 1: Write the failing test**

Add to `tests/enemy_ai_test.gd`, register in `_run_tests`:

```gdscript
func _test_roster_loads_and_is_valid() -> void:
	var roster := [
		RunState.CINDER_HOUND, RunState.PLAGUE_CRAWLER, RunState.BONE_ACOLYTE,
		RunState.DREAD_SENTINEL, RunState.GRAVEMAW,
	]
	for enemy in roster:
		_expect(enemy != null, "Roster enemy should load.")
		_expect(not enemy.moves.is_empty(), "%s should have moves." % enemy.display_name)
		var has_always := false
		for move in enemy.moves:
			if move.condition == EnemyMoveData.Condition.ALWAYS:
				has_always = true
		_expect(has_always, "%s must have at least one ALWAYS move (selector fallback)." % enemy.display_name)


func _test_run_ends_on_boss() -> void:
	_expect(RunState.ENCOUNTERS.size() == 5, "Run should have 5 encounters.")
	_expect(RunState.ENCOUNTERS[4] == RunState.GRAVEMAW, "Final encounter should be the boss.")
	_expect(RunState.SAVE_VERSION == 2, "Save version should be bumped to 2.")
```

- [ ] **Step 2: Run to verify failure**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: fails — the new consts don't exist.

- [ ] **Step 3: Create the move `.tres` files**

Each file uses this template (`enemies/moves/<file>.tres`), filling values from the table. Omit any field whose value is the default (`damage/block/*_applied/strength_gained = 0`, `weight = 1`, `condition = 0`, `condition_value = 0.0`) — write only the non-default lines. `condition` integers: `ALWAYS=0`, `ENEMY_HP_BELOW=1`, `PLAYER_BLOCK_BELOW=2`.

Template:
```
[gd_resource type="Resource" script_class="EnemyMoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="1"]

[resource]
script = ExtResource("1")
display_name = "<name>"
damage = <d>
block = <b>
weak_applied = <w>
vulnerable_applied = <v>
poison_applied = <p>
strength_gained = <s>
weight = <weight>
condition = <cond>
condition_value = <cv>
```

Values (file → display_name, damage, block, weak, vuln, poison, str, weight, condition, condition_value):

| file | name | dmg | blk | weak | vuln | psn | str | wt | cond | cv |
|---|---|---|---|---|---|---|---|---|---|---|
| `cinder_bite.tres` | Bite | 7 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `cinder_lunge.tres` | Lunge | 11 | 0 | 0 | 0 | 0 | 0 | 3 | 2 | 1.0 |
| `cinder_snarl.tres` | Snarl | 4 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0.0 |
| `crawler_bite.tres` | Gnaw | 6 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `crawler_spit.tres` | Venom Spit | 2 | 0 | 0 | 0 | 4 | 0 | 3 | 0 | 0.0 |
| `crawler_writhe.tres` | Writhe | 0 | 6 | 0 | 0 | 0 | 0 | 2 | 1 | 0.5 |
| `acolyte_bolt.tres` | Dark Bolt | 7 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `acolyte_curse.tres` | Curse | 0 | 0 | 0 | 2 | 0 | 0 | 2 | 0 | 0.0 |
| `acolyte_channel.tres` | Channel | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 0 | 0.0 |
| `acolyte_ward.tres` | Bone Ward | 0 | 8 | 0 | 0 | 0 | 0 | 3 | 1 | 0.5 |
| `sentinel_slam.tres` | Slam | 13 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `sentinel_bulwark.tres` | Bulwark | 0 | 12 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `sentinel_break.tres` | Sunder | 9 | 0 | 0 | 2 | 0 | 0 | 2 | 0 | 0.0 |
| `sentinel_enrage.tres` | Devastate | 20 | 0 | 0 | 0 | 0 | 0 | 4 | 1 | 0.5 |
| `gravemaw_maul.tres` | Maul | 16 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0.0 |
| `gravemaw_gather.tres` | Gather Dread | 0 | 8 | 0 | 0 | 0 | 3 | 2 | 0 | 0.0 |
| `gravemaw_devour.tres` | Devour | 12 | 0 | 0 | 0 | 0 | 0 | 3 | 2 | 1.0 |
| `gravemaw_plague.tres` | Plague Breath | 8 | 0 | 0 | 0 | 5 | 0 | 3 | 1 | 0.5 |
| `gravemaw_rampage.tres` | Rampage | 24 | 0 | 0 | 0 | 0 | 0 | 4 | 1 | 0.5 |

- [ ] **Step 4: Create the enemy `.tres` files**

Each enemy file follows the existing `raider.tres` shape: one `ext_resource` for the `EnemyData` script (id "1"), one for the `EnemyMoveData` script (id "2"), one per move (ids "3"+), and a `moves = Array[ExtResource("2")]([...])` line listing the move resources in order. Leave out the `artwork` line (Task 6 adds it). Set `load_steps` = 2 + number of moves.

`enemies/definitions/cinder_hound.tres` (3 moves):
```
[gd_resource type="Resource" script_class="EnemyData" load_steps=5 format=3]

[ext_resource type="Script" path="res://enemies/enemy_data.gd" id="1"]
[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="2"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_bite.tres" id="3"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_lunge.tres" id="4"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_snarl.tres" id="5"]

[resource]
script = ExtResource("1")
id = &"cinder_hound"
display_name = "Cinder Hound"
max_health = 28
moves = Array[ExtResource("2")]([ExtResource("3"), ExtResource("4"), ExtResource("5")])
```

`enemies/definitions/plague_crawler.tres` (3 moves: crawler_bite, crawler_spit, crawler_writhe), `id = &"plague_crawler"`, `display_name = "Plague Crawler"`, `max_health = 34`, `load_steps=5`.

`enemies/definitions/bone_acolyte.tres` (4 moves: acolyte_bolt, acolyte_curse, acolyte_channel, acolyte_ward), `id = &"bone_acolyte"`, `display_name = "Bone Acolyte"`, `max_health = 30`, `load_steps=6`.

`enemies/definitions/dread_sentinel.tres` (4 moves: sentinel_slam, sentinel_bulwark, sentinel_break, sentinel_enrage), `id = &"dread_sentinel"`, `display_name = "Dread Sentinel"`, `max_health = 70`, `load_steps=6`.

`enemies/definitions/gravemaw.tres` (5 moves: gravemaw_maul, gravemaw_gather, gravemaw_devour, gravemaw_plague, gravemaw_rampage), `id = &"gravemaw"`, `display_name = "The Gravemaw"`, `max_health = 110`, `load_steps=7`.

- [ ] **Step 5: Register in `systems/run_state.gd`**

Add preload consts after the existing enemy consts (after line 22, `GUARDIAN`):

```gdscript
const CINDER_HOUND := preload("res://enemies/definitions/cinder_hound.tres")
const PLAGUE_CRAWLER := preload("res://enemies/definitions/plague_crawler.tres")
const BONE_ACOLYTE := preload("res://enemies/definitions/bone_acolyte.tres")
const DREAD_SENTINEL := preload("res://enemies/definitions/dread_sentinel.tres")
const GRAVEMAW := preload("res://enemies/definitions/gravemaw.tres")
```

Replace the `ENCOUNTERS` line (normal → normal → elite → normal → boss):

```gdscript
const ENCOUNTERS: Array[EnemyData] = [CINDER_HOUND, PLAGUE_CRAWLER, DREAD_SENTINEL, BONE_ACOLYTE, GRAVEMAW]
```

Bump the save version (line 3):

```gdscript
const SAVE_VERSION := 2
```

- [ ] **Step 6: Run tests**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
```
Expected: both exit 0.

- [ ] **Step 7: Commit**

```sh
cd FirstGame/first-game
git add enemies/moves/*.tres enemies/definitions/*.tres systems/run_state.gd tests/enemy_ai_test.gd
git commit -m "feat: author enemy roster (3 normals, elite, boss); expand run to 5, bump save v2"
```

---

### Task 6: Generate enemy art + intent icons

Uses the build-time asset tool (`tools/gen_asset.py`, reads `OPENAI_API_KEY` from repo-root `.env`). Run from the repo root. Card/enemy art convention: 1254×1254 RGB PNG, dark-fantasy painterly style. Intent icons are small UI glyphs.

**Files:**
- Create: `assets/art/enemies/{cinder_hound,plague_crawler,bone_acolyte,dread_sentinel,gravemaw}.png`
- Create: `assets/art/ui/{intent_attack,intent_block}.png`
- Modify: the 5 new enemy `.tres` (add `artwork` ext_resource + line)

**Interfaces:**
- Produces: enemy `artwork` textures; `res://assets/art/ui/intent_attack.png`, `res://assets/art/ui/intent_block.png` (consumed by Task 7).

- [ ] **Step 1: Generate the five enemy images**

From repo root (dark-fantasy style suffix matches the existing set):
```sh
python tools/gen_asset.py "a lean burning hound wreathed in embers, glowing cracks, painterly, muted grim palette, dramatic rim lighting, centered subject, no text/border/frame" FirstGame/first-game/assets/art/enemies/cinder_hound.png --resize 1254x1254
python tools/gen_asset.py "a bloated plague crawler insect dripping venom, sickly green, painterly, muted grim palette, dramatic rim lighting, centered subject, no text/border/frame" FirstGame/first-game/assets/art/enemies/plague_crawler.png --resize 1254x1254
python tools/gen_asset.py "a robed skeletal acolyte channeling dark magic, bone mask, painterly, muted grim palette, dramatic rim lighting, centered subject, no text/border/frame" FirstGame/first-game/assets/art/enemies/bone_acolyte.png --resize 1254x1254
python tools/gen_asset.py "a towering armored dread sentinel with a massive shield, iron and rust, painterly, muted grim palette, dramatic rim lighting, centered subject, no text/border/frame" FirstGame/first-game/assets/art/enemies/dread_sentinel.png --resize 1254x1254
python tools/gen_asset.py "a colossal grave maw monster of bone and rotting flesh, gaping toothed maw, painterly, muted grim palette, dramatic rim lighting, centered subject, no text/border/frame" FirstGame/first-game/assets/art/enemies/gravemaw.png --resize 1254x1254
```

- [ ] **Step 2: Generate the two intent icons**

```sh
python tools/gen_asset.py "minimalist flat game UI icon of a sword, solid warm-orange silhouette, transparent background, no text" FirstGame/first-game/assets/art/ui/intent_attack.png --resize 96x96
python tools/gen_asset.py "minimalist flat game UI icon of a shield, solid cool-blue silhouette, transparent background, no text" FirstGame/first-game/assets/art/ui/intent_block.png --resize 96x96
```

- [ ] **Step 3: Import so Godot creates `.png.import` sidecars**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
```
Expected: `.png.import` files created next to each new PNG. (A `.tres` referencing un-imported art fails to load.)

- [ ] **Step 4: Attach `artwork` to each enemy `.tres`**

For each enemy definition, add an `ext_resource` for its texture and an `artwork = ExtResource(...)` line (mirroring `raider.tres`). Bump `load_steps` by 1. Example for `cinder_hound.tres`:

```
[gd_resource type="Resource" script_class="EnemyData" load_steps=6 format=3]

[ext_resource type="Script" path="res://enemies/enemy_data.gd" id="1"]
[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="2"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_bite.tres" id="3"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_lunge.tres" id="4"]
[ext_resource type="Resource" path="res://enemies/moves/cinder_snarl.tres" id="5"]
[ext_resource type="Texture2D" path="res://assets/art/enemies/cinder_hound.png" id="6"]

[resource]
script = ExtResource("1")
id = &"cinder_hound"
display_name = "Cinder Hound"
max_health = 28
moves = Array[ExtResource("2")]([ExtResource("3"), ExtResource("4"), ExtResource("5")])
artwork = ExtResource("6")
```
Do the same for the other four (the texture ext_resource id is the next integer after the last move).

- [ ] **Step 5: Verify the game boots with art loaded**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --quit-after 2
```
Expected: no "failed to load" errors for the enemy `.tres`.

- [ ] **Step 6: Commit**

```sh
cd FirstGame/first-game
git add assets/art/enemies/ assets/art/ui/ enemies/definitions/*.tres
git commit -m "assets: enemy art for new roster + attack/block intent icons"
```

Provenance note: these are AI-generated (OpenAI image API), not third-party CC0 — no `SOURCES.md` entry needed (that file tracks CC0 audio).

---

### Task 7: Icon-based intent display with hover detail

Replace the single intent `Label` with an `HBoxContainer` whose chips are built in code (mirroring how `_refresh_status_badges` builds status labels dynamically). Sword/shield icons for damage/block; colored text chips for statuses; the row's `tooltip_text` carries the full breakdown for hover.

**Files:**
- Modify: `combat/combat_screen.tscn`
- Modify: `combat/combat_screen.gd`

**Interfaces:**
- Consumes: `state.planned_move` (Task 4); `res://assets/art/ui/intent_attack.png`, `intent_block.png` (Task 6); `_status_color` (existing).

- [ ] **Step 1: Swap the intent node in `combat/combat_screen.tscn`**

Replace the `EnemyIntentLabel` node block (currently lines ~108-113) with an `HBoxContainer` named `EnemyIntent`, centered:

```
[node name="EnemyIntent" type="HBoxContainer" parent="PageMargin/Layout/EnemyArea/EnemyPanel/EnemyMargin/EnemyDetails"]
unique_name_in_owner = true
layout_mode = 2
alignment = 1
theme_override_constants/separation = 8
```
(`alignment = 1` centers the chips, matching the old label's `horizontal_alignment = 1`.)

- [ ] **Step 2: Update the `@onready` reference in `combat/combat_screen.gd`**

Change line 21:
```gdscript
@onready var enemy_intent: HBoxContainer = %EnemyIntent
```

- [ ] **Step 3: Add the icon preloads**

Near the top consts (after `DECK_VIEWER_SCENE`):
```gdscript
const INTENT_ATTACK_ICON := preload("res://assets/art/ui/intent_attack.png")
const INTENT_BLOCK_ICON := preload("res://assets/art/ui/intent_block.png")
```

- [ ] **Step 4: Replace `_get_intent_text` with a chip builder**

Replace the intent line in `_refresh_combat_view` (was `enemy_intent_label.text = _get_intent_text(...)`) with:
```gdscript
	_refresh_intent(state.planned_move)
```

Replace the `_get_intent_text` function with:
```gdscript
func _refresh_intent(move: EnemyMoveData) -> void:
	for child in enemy_intent.get_children():
		child.queue_free()
	if move == null:
		enemy_intent.tooltip_text = ""
		_add_intent_text_chip("Waiting", Color(0.7, 0.7, 0.7))
		return
	if move.damage > 0:
		_add_intent_icon_chip(INTENT_ATTACK_ICON, str(move.damage))
	if move.block > 0:
		_add_intent_icon_chip(INTENT_BLOCK_ICON, str(move.block))
	if move.weak_applied > 0:
		_add_intent_text_chip("Weak %d" % move.weak_applied, _status_color("debuff"))
	if move.vulnerable_applied > 0:
		_add_intent_text_chip("Vuln %d" % move.vulnerable_applied, _status_color("debuff"))
	if move.poison_applied > 0:
		_add_intent_text_chip("Psn %d" % move.poison_applied, _status_color("poison"))
	if move.strength_gained > 0:
		_add_intent_text_chip("Str %d" % move.strength_gained, _status_color("buff"))
	if enemy_intent.get_child_count() == 0:
		_add_intent_text_chip(move.display_name, Color(0.7, 0.7, 0.7))
	enemy_intent.tooltip_text = _intent_tooltip(move)


func _add_intent_icon_chip(icon: Texture2D, value: String) -> void:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	var texture := TextureRect.new()
	texture.texture = icon
	texture.custom_minimum_size = Vector2(22, 22)
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.add_child(texture)
	var label := Label.new()
	label.text = value
	chip.add_child(label)
	enemy_intent.add_child(chip)


func _add_intent_text_chip(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	enemy_intent.add_child(label)


func _intent_tooltip(move: EnemyMoveData) -> String:
	var parts: Array[String] = []
	if move.damage > 0:
		parts.append("%d damage" % move.damage)
	if move.block > 0:
		parts.append("%d block" % move.block)
	if move.weak_applied > 0:
		parts.append("Weak %d" % move.weak_applied)
	if move.vulnerable_applied > 0:
		parts.append("Vulnerable %d" % move.vulnerable_applied)
	if move.poison_applied > 0:
		parts.append("Poison %d" % move.poison_applied)
	if move.strength_gained > 0:
		parts.append("Strength %d" % move.strength_gained)
	if parts.is_empty():
		return move.display_name
	return "%s — %s" % [move.display_name, ", ".join(parts)]
```
Note: `_status_color` already maps `"debuff"`/anything not `poison`/`buff` to the red debuff color, so passing `"debuff"` is fine.

- [ ] **Step 5: Verify the game boots (no parse/scene errors)**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --quit-after 2
```
Expected: no errors; `%EnemyIntent` resolves.

- [ ] **Step 6: Manual visual check**

Run the game windowed and start a combat:
```sh
./Godot_v4.7-stable_win64.exe --path FirstGame/first-game
```
Confirm: the intent shows sword+number / shield+number chips and status chips; hovering the row shows the move name + full breakdown tooltip; nothing clips off the enemy panel. (UI layout can't be asserted headlessly here without the autoload stack; this is the intended verification per the combat-UI note in CLAUDE.md.)

- [ ] **Step 7: Commit**

```sh
cd FirstGame/first-game
git add combat/combat_screen.tscn combat/combat_screen.gd
git commit -m "feat: icon-based enemy intent chips with hover breakdown"
```

---

### Task 8: Balance pass + full-run verification

No new code by default — a playtest tuning pass over the numbers authored in Task 5. Adjust `.tres` values only if the run plays poorly.

**Files:**
- Possibly modify: `enemies/moves/*.tres`, `enemies/definitions/*.tres` (HP/damage tuning)

- [ ] **Step 1: Play a full run**

```sh
./Godot_v4.7-stable_win64.exe --path FirstGame/first-game
```
Play all 5 encounters start to finish with a fresh run.

- [ ] **Step 2: Assess and note**

Check: does the run curve feel fair (not trivial, not unwinnable)? Do conditions visibly fire — Bone Acolyte/Plague Crawler defending below half HP, Cinder Hound/Gravemaw hitting harder when you have no block, elite/boss enrage below 50%? Does the intent always match what the enemy actually does?

- [ ] **Step 3: Tune if needed**

Adjust enemy `max_health` and move `damage`/`weight` in the `.tres` files. Re-run. Repeat until the run feels right. Common levers: boss HP (110) vs. player's ~4-reward deck; elite `Devastate` (20) and boss `Rampage` (24) enrage damage.

- [ ] **Step 4: Full regression**

```sh
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: both exit 0.

- [ ] **Step 5: Commit (only if values changed)**

```sh
cd FirstGame/first-game
git add enemies/
git commit -m "balance: tune enemy roster after full-run playtest"
```

---

## Self-review notes

- **Spec coverage:** declarative fields (T1), pool rename (T2), selector w/ weighted+HP+player-block conditions and ALWAYS fallback (T3), decide-then-telegraph incl. RNG + no-reroll (T4), 3 normals+elite+boss + expanded run + SAVE_VERSION bump (T5), art + icons (T6), icon intent chips + hover (T7), balance pass (T8). All spec sections mapped.
- **Deferred (per spec):** no-repeat rule, full status-icon art, per-enemy scripted AI, map wiring — none in this plan, by design.
- **Type consistency:** `moves` (not `move_pattern`), `planned_move`, `choose_enemy_move`, `plan_enemy_move`, `_move_eligible`, `end_player_turn(new_hand_size)`, `begin(..., enemy_data)` used consistently across tasks.
