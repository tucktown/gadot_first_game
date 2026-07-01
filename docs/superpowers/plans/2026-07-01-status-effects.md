# Status Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a combat status-effect system (Vulnerable, Weak, Strength, Poison) with text badges, applied by a starter batch of cards and enemy moves.

**Architecture:** A self-contained `StatusSet` (RefCounted) holds each combatant's status stacks and all status behavior (multipliers, ticking). `CombatState` owns one per side and routes attack damage through a shared formula. Cards and enemy moves gain data fields that apply statuses. `combat_screen` shows badges and floating text. Statuses are combat-scoped and never serialized.

**Tech Stack:** Godot 4.7, typed GDScript. Tests are a headless `SceneTree` script; art via the Python `tools/gen_asset.py` pipeline.

## Global Constraints

- Engine: Godot 4.7. All GDScript is typed (annotate vars, params, returns).
- Repo lives at `FirstGame/first-game/`; the Godot executable and `tools/` live one level up at the repo-root working directory. Run all commands from that working directory.
- Run tests headless: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd` — prints `Combat state tests passed.` and exits 0 on success; failures `push_error` and exit non-zero.
- Card art is 1254x1254 RGB PNG generated via `python tools/gen_asset.py "<prompt>" <out.png> --resize 1254x1254`, then imported with `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import`.
- Every new card id MUST be registered in `RunState.CARD_CATALOG` or saves referencing it break.
- Statuses are combat-scoped: never added to the `RunState` save format.
- Damage formula (single source of truth): `dmg = max(0, floor(floor((base + attacker.strength) * weak_mult) * vuln_mult))`, `weak_mult = 0.75 if attacker Weak else 1.0`, `vuln_mult = 1.25 if defender Vulnerable else 1.0`. Only applies when `base > 0`.
- Commit to `main` from within `FirstGame/first-game`. End commit messages with the Co-Authored-By trailer used in this repo.

---

### Task 1: StatusSet class and unit tests

**Files:**
- Create: `FirstGame/first-game/systems/status_set.gd`
- Test: `FirstGame/first-game/tests/combat_state_test.gd`

**Interfaces:**
- Produces: `class_name StatusSet extends RefCounted` with `enum Type { VULNERABLE, WEAK, STRENGTH, POISON }`, `var stacks: Dictionary`, and methods `amount(type: Type) -> int`, `add(type: Type, amount_to_add: int) -> void`, `attack_bonus() -> int`, `outgoing_multiplier() -> float`, `incoming_multiplier() -> float`, `tick_turn_start() -> int`, `tick_turn_end() -> void`, `describe() -> Array` (entries `{"label": String, "amount": int, "kind": String}`).

- [ ] **Step 1: Write the failing test**

Add to `tests/combat_state_test.gd`: register the test in `_run_tests()` (add the call line after the existing calls) and add the function.

In `_run_tests()`, after `_test_uncapped_energy_exceeds_maximum()`:
```gdscript
	_test_status_set_basics()
```

New function (add above `_fresh_state()`):
```gdscript
func _test_status_set_basics() -> void:
	var s := StatusSet.new()
	s.add(StatusSet.Type.STRENGTH, 2)
	_expect(s.attack_bonus() == 2, "Strength should report as attack bonus.")
	s.add(StatusSet.Type.WEAK, 1)
	_expect(is_equal_approx(s.outgoing_multiplier(), 0.75), "Weak should reduce outgoing damage.")
	s.add(StatusSet.Type.VULNERABLE, 1)
	_expect(is_equal_approx(s.incoming_multiplier(), 1.25), "Vulnerable should raise incoming damage.")

	s.add(StatusSet.Type.POISON, 3)
	var ticked := s.tick_turn_start()
	_expect(ticked == 3, "Poison tick should return current poison.")
	_expect(s.amount(StatusSet.Type.POISON) == 2, "Poison should decrement after ticking.")

	s.tick_turn_end()
	_expect(s.amount(StatusSet.Type.VULNERABLE) == 0, "Vulnerable should decrement at turn end.")
	_expect(s.amount(StatusSet.Type.WEAK) == 0, "Weak should decrement at turn end.")

	var badges := s.describe()
	_expect(badges.size() == 2, "Only remaining statuses (Strength, Poison) should describe.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: FAIL — parse/identifier error, `StatusSet` not declared.

- [ ] **Step 3: Write minimal implementation**

Create `systems/status_set.gd`:
```gdscript
class_name StatusSet
extends RefCounted

enum Type { VULNERABLE, WEAK, STRENGTH, POISON }

const _DISPLAY_ORDER := [Type.VULNERABLE, Type.WEAK, Type.STRENGTH, Type.POISON]
const _LABELS := {
	Type.VULNERABLE: "Vuln",
	Type.WEAK: "Weak",
	Type.STRENGTH: "Str",
	Type.POISON: "Poison",
}
const _KINDS := {
	Type.VULNERABLE: "debuff",
	Type.WEAK: "debuff",
	Type.STRENGTH: "buff",
	Type.POISON: "poison",
}

var stacks := {}


func amount(type: Type) -> int:
	return int(stacks.get(type, 0))


func add(type: Type, amount_to_add: int) -> void:
	if amount_to_add == 0:
		return
	var total := amount(type) + amount_to_add
	if total <= 0:
		stacks.erase(type)
	else:
		stacks[type] = total


func attack_bonus() -> int:
	return amount(Type.STRENGTH)


func outgoing_multiplier() -> float:
	return 0.75 if amount(Type.WEAK) > 0 else 1.0


func incoming_multiplier() -> float:
	return 1.25 if amount(Type.VULNERABLE) > 0 else 1.0


func tick_turn_start() -> int:
	var poison := amount(Type.POISON)
	if poison > 0:
		add(Type.POISON, -1)
	return poison


func tick_turn_end() -> void:
	add(Type.VULNERABLE, -1)
	add(Type.WEAK, -1)


func describe() -> Array:
	var out := []
	for type in _DISPLAY_ORDER:
		var n := amount(type)
		if n > 0:
			out.append({"label": _LABELS[type], "amount": n, "kind": _KINDS[type]})
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS — `Combat state tests passed.`, exit 0.

- [ ] **Step 5: Commit**

```bash
cd FirstGame/first-game && git add systems/status_set.gd systems/status_set.gd.uid tests/combat_state_test.gd && git commit -m "Add StatusSet with status stacks, multipliers, and ticking

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(The `.gd.uid` is generated on first load; include it if present.)

---

### Task 2: Attack damage formula, card status application, CardData fields

**Files:**
- Modify: `FirstGame/first-game/cards/card_data.gd`
- Modify: `FirstGame/first-game/combat/combat_state.gd`
- Test: `FirstGame/first-game/tests/combat_state_test.gd`

**Interfaces:**
- Consumes: `StatusSet` (Task 1).
- Produces: `CombatState.player_status: StatusSet`, `CombatState.enemy_status: StatusSet`, `CombatState._attack_damage(base: int, attacker: StatusSet, defender: StatusSet) -> int`. `play_card` result dict gains keys `vulnerable_applied`, `weak_applied`, `poison_applied`, `strength_gained` (ints). `CardData` gains `vulnerable_applied`, `weak_applied`, `poison_applied`, `strength_gained` (int, default 0).

- [ ] **Step 1: Write the failing tests**

In `_run_tests()`, after `_test_status_set_basics()`:
```gdscript
	_test_strength_adds_flat_damage()
	_test_vulnerable_increases_damage_taken()
	_test_weak_reduces_damage_dealt()
	_test_combined_status_damage_formula()
	_test_card_applies_statuses_to_enemy()
```

New functions (above `_fresh_state()`):
```gdscript
func _test_strength_adds_flat_damage() -> void:
	var state := _fresh_state()
	state.player_status.add(StatusSet.Type.STRENGTH, 3)
	var strike := _card(&"strike")
	strike.damage = 6
	state.hand.append(CardInstance.new(strike))
	var result := state.play_card(state.hand[0])
	_expect(result.damage_dealt == 9, "Strength should add flat damage to attacks.")


func _test_vulnerable_increases_damage_taken() -> void:
	var state := _fresh_state()
	state.enemy_status.add(StatusSet.Type.VULNERABLE, 1)
	var strike := _card(&"strike")
	strike.damage = 6
	state.hand.append(CardInstance.new(strike))
	var result := state.play_card(state.hand[0])
	_expect(result.damage_dealt == 7, "Vulnerable should raise damage: floor(6*1.25)=7.")


func _test_weak_reduces_damage_dealt() -> void:
	var state := _fresh_state()
	state.player_status.add(StatusSet.Type.WEAK, 1)
	var strike := _card(&"strike")
	strike.damage = 6
	state.hand.append(CardInstance.new(strike))
	var result := state.play_card(state.hand[0])
	_expect(result.damage_dealt == 4, "Weak should reduce damage: floor(6*0.75)=4.")


func _test_combined_status_damage_formula() -> void:
	var state := _fresh_state()
	state.player_status.add(StatusSet.Type.STRENGTH, 2)
	state.player_status.add(StatusSet.Type.WEAK, 1)
	state.enemy_status.add(StatusSet.Type.VULNERABLE, 1)
	var strike := _card(&"strike")
	strike.damage = 6
	state.hand.append(CardInstance.new(strike))
	var result := state.play_card(state.hand[0])
	_expect(result.damage_dealt == 7, "Combined: floor(floor((6+2)*0.75)*1.25)=7.")


func _test_card_applies_statuses_to_enemy() -> void:
	var state := _fresh_state()
	var hex := _card(&"hex")
	hex.vulnerable_applied = 2
	hex.poison_applied = 3
	state.hand.append(CardInstance.new(hex))
	state.play_card(state.hand[0])
	_expect(state.enemy_status.amount(StatusSet.Type.VULNERABLE) == 2, "Card should apply Vulnerable to the enemy.")
	_expect(state.enemy_status.amount(StatusSet.Type.POISON) == 3, "Card should apply Poison to the enemy.")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: FAIL — `player_status`/`enemy_status`/`vulnerable_applied` not found.

- [ ] **Step 3a: Add CardData fields**

In `cards/card_data.gd`, after `@export var energy_uncapped: bool = false`:
```gdscript
@export_range(0, 99) var vulnerable_applied: int = 0
@export_range(0, 99) var weak_applied: int = 0
@export_range(0, 99) var poison_applied: int = 0
@export_range(0, 99) var strength_gained: int = 0
```

- [ ] **Step 3b: Add status sets to CombatState**

In `combat/combat_state.gd`, after `var deck := Deck.new()`:
```gdscript
var player_status: StatusSet = StatusSet.new()
var enemy_status: StatusSet = StatusSet.new()
```

In `begin()`, after `retain_block_this_turn = false`:
```gdscript
	player_status.stacks.clear()
	enemy_status.stacks.clear()
```

- [ ] **Step 3c: Add the damage helper**

In `combat/combat_state.gd`, add a new function (place it just before `func end_player_turn`):
```gdscript
func _attack_damage(base: int, attacker: StatusSet, defender: StatusSet) -> int:
	if base <= 0:
		return 0
	var raw := base + attacker.attack_bonus()
	var weakened := floori(raw * attacker.outgoing_multiplier())
	var result := floori(weakened * defender.incoming_multiplier())
	return maxi(0, result)
```

- [ ] **Step 3d: Route play_card through the formula and apply card statuses**

In `play_card`, replace this block:
```gdscript
	energy -= card.get_energy_cost()
	player_block += card.definition.block
	var damage_blocked := mini(enemy_block, card.definition.damage)
	var damage_dealt := maxi(0, card.definition.damage - enemy_block)
	enemy_block = maxi(0, enemy_block - card.definition.damage)
	enemy_health = maxi(0, enemy_health - damage_dealt)
	hand.erase(card)
```
with:
```gdscript
	energy -= card.get_energy_cost()
	player_block += card.definition.block
	var raw_damage := _attack_damage(card.definition.damage, player_status, enemy_status)
	var damage_blocked := mini(enemy_block, raw_damage)
	var damage_dealt := maxi(0, raw_damage - enemy_block)
	enemy_block = maxi(0, enemy_block - raw_damage)
	enemy_health = maxi(0, enemy_health - damage_dealt)
	hand.erase(card)

	enemy_status.add(StatusSet.Type.VULNERABLE, card.definition.vulnerable_applied)
	enemy_status.add(StatusSet.Type.WEAK, card.definition.weak_applied)
	enemy_status.add(StatusSet.Type.POISON, card.definition.poison_applied)
	player_status.add(StatusSet.Type.STRENGTH, card.definition.strength_gained)
```

Then in the `play_card` return dictionary, add these keys before the closing brace (after `"healed": healed,`):
```gdscript
		"vulnerable_applied": card.definition.vulnerable_applied,
		"weak_applied": card.definition.weak_applied,
		"poison_applied": card.definition.poison_applied,
		"strength_gained": card.definition.strength_gained,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS — `Combat state tests passed.`, exit 0. (Existing heal/lifesteal tests still pass because lifesteal reads the same `damage_dealt`.)

- [ ] **Step 5: Commit**

```bash
cd FirstGame/first-game && git add cards/card_data.gd combat/combat_state.gd tests/combat_state_test.gd && git commit -m "Route attacks through status formula and apply card statuses

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Enemy-turn timing, poison, EnemyMoveData fields

**Files:**
- Modify: `FirstGame/first-game/enemies/enemy_move_data.gd`
- Modify: `FirstGame/first-game/combat/combat_state.gd` (`end_player_turn`)
- Test: `FirstGame/first-game/tests/combat_state_test.gd`

**Interfaces:**
- Consumes: `StatusSet`, `CombatState._attack_damage` (Task 2).
- Produces: `EnemyMoveData` gains `weak_applied`, `vulnerable_applied`, `poison_applied`, `strength_gained` (int, default 0). `end_player_turn` result dict gains keys `enemy_poison_damage`, `player_poison_damage`, `weak_applied`, `vulnerable_applied`, `poison_applied` (ints).

- [ ] **Step 1: Write the failing tests**

In `_run_tests()`, after `_test_card_applies_statuses_to_enemy()`:
```gdscript
	_test_enemy_poison_triggers_and_decrements()
	_test_player_poison_ignores_block()
	_test_duration_status_expires_at_turn_end()
	_test_enemy_move_applies_weak_to_player()
```

New functions (above `_fresh_state()`):
```gdscript
func _test_enemy_poison_triggers_and_decrements() -> void:
	var state := _fresh_state()
	state.enemy_status.add(StatusSet.Type.POISON, 4)
	var move := EnemyMoveData.new()
	var result := state.end_player_turn(move, 0)
	_expect(result.enemy_poison_damage == 4, "Enemy poison should trigger at enemy turn start.")
	_expect(state.enemy_health == 46, "Poison should reduce enemy health by its amount.")
	_expect(state.enemy_status.amount(StatusSet.Type.POISON) == 3, "Poison should decrement after firing.")


func _test_player_poison_ignores_block() -> void:
	var state := _fresh_state()
	state.player_block = 20
	state.player_status.add(StatusSet.Type.POISON, 5)
	var move := EnemyMoveData.new()
	var result := state.end_player_turn(move, 0)
	_expect(result.player_poison_damage == 5, "Player poison should trigger when regaining control.")
	_expect(state.player_health == 45, "Poison should ignore block and reduce health.")


func _test_duration_status_expires_at_turn_end() -> void:
	var state := _fresh_state()
	state.player_status.add(StatusSet.Type.VULNERABLE, 1)
	var move := EnemyMoveData.new()
	state.end_player_turn(move, 0)
	_expect(state.player_status.amount(StatusSet.Type.VULNERABLE) == 0, "Player Vulnerable should expire after one turn end.")


func _test_enemy_move_applies_weak_to_player() -> void:
	var state := _fresh_state()
	var move := EnemyMoveData.new()
	move.damage = 5
	move.weak_applied = 2
	state.end_player_turn(move, 0)
	_expect(state.player_status.amount(StatusSet.Type.WEAK) == 2, "Enemy move should apply Weak to the player.")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: FAIL — `enemy_poison_damage` key missing / `move.weak_applied` not found.

- [ ] **Step 3a: Add EnemyMoveData fields**

In `enemies/enemy_move_data.gd`, after `@export_range(0, 999) var block: int = 0`:
```gdscript
@export_range(0, 99) var weak_applied: int = 0
@export_range(0, 99) var vulnerable_applied: int = 0
@export_range(0, 99) var poison_applied: int = 0
@export_range(0, 99) var strength_gained: int = 0
```

- [ ] **Step 3b: Rewrite end_player_turn**

Replace the entire `end_player_turn` function in `combat/combat_state.gd` with:
```gdscript
func end_player_turn(enemy_move: EnemyMoveData, new_hand_size: int = 5) -> Dictionary:
	if phase != Phase.PLAYER_TURN:
		return {}

	for card in hand:
		deck.discard(card)
	hand.clear()
	energy = 0
	phase = Phase.ENEMY_TURN

	# Player's turn ends: their duration debuffs count down.
	player_status.tick_turn_end()

	# Enemy turn begins with poison (ignores block).
	var enemy_poison := enemy_status.tick_turn_start()
	enemy_health = maxi(0, enemy_health - enemy_poison)

	var result := {
		"move_name": enemy_move.display_name,
		"attack": 0,
		"blocked": 0,
		"damage_taken": 0,
		"enemy_block_gained": 0,
		"retained_block": 0,
		"enemy_poison_damage": enemy_poison,
		"player_poison_damage": 0,
		"weak_applied": enemy_move.weak_applied,
		"vulnerable_applied": enemy_move.vulnerable_applied,
		"poison_applied": enemy_move.poison_applied,
	}

	if enemy_health == 0:
		phase = Phase.WON
		return result

	# Enemy attacks; its Strength/Weak and the player's Vulnerable adjust damage.
	enemy_block = 0
	var attack_damage := _attack_damage(enemy_move.damage, enemy_status, player_status)
	var blocked_damage := mini(player_block, attack_damage)
	var damage_taken := maxi(0, attack_damage - player_block)
	player_health = maxi(0, player_health - damage_taken)
	var remaining_block := maxi(0, player_block - attack_damage)
	var retained_block := remaining_block if retain_block_this_turn else 0
	player_block = retained_block
	retain_block_this_turn = false
	enemy_block += enemy_move.block
	enemy_turn_index += 1

	result.attack = attack_damage
	result.blocked = blocked_damage
	result.damage_taken = damage_taken
	result.enemy_block_gained = enemy_move.block
	result.retained_block = retained_block

	# The move applies statuses to the player and can buff the enemy.
	player_status.add(StatusSet.Type.WEAK, enemy_move.weak_applied)
	player_status.add(StatusSet.Type.VULNERABLE, enemy_move.vulnerable_applied)
	player_status.add(StatusSet.Type.POISON, enemy_move.poison_applied)
	enemy_status.add(StatusSet.Type.STRENGTH, enemy_move.strength_gained)

	# Enemy's turn ends: its duration debuffs count down.
	enemy_status.tick_turn_end()

	if player_health == 0:
		phase = Phase.LOST
		return result

	# Player regains control: their poison ticks before the new turn.
	var player_poison := player_status.tick_turn_start()
	player_health = maxi(0, player_health - player_poison)
	result.player_poison_damage = player_poison
	if player_health == 0:
		phase = Phase.LOST
		return result

	phase = Phase.PLAYER_TURN
	energy = max_energy
	draw_cards(new_hand_size)
	return result
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS — `Combat state tests passed.`, exit 0. (The existing `_test_fortify_retains_block_once` still passes: block retention math is unchanged.)

- [ ] **Step 5: Commit**

```bash
cd FirstGame/first-game && git add enemies/enemy_move_data.gd combat/combat_state.gd tests/combat_state_test.gd && git commit -m "Add status timing, poison, and enemy move status application

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Combat screen display (badges, floating text, intent)

**Files:**
- Modify: `FirstGame/first-game/combat/combat_screen.gd`

**Interfaces:**
- Consumes: `state.player_status`/`state.enemy_status` (`StatusSet`), and the result-dict keys from Tasks 2-3.
- Produces: none (UI only). No automated test — verified by running the game.

- [ ] **Step 1: Add member vars for the status boxes**

In `combat/combat_screen.gd`, after `var end_turn_prompt_active := false`:
```gdscript
var player_status_box: HBoxContainer
var enemy_status_box: HBoxContainer
```

- [ ] **Step 2: Build the boxes in _ready and add helpers**

Replace `_ready` with:
```gdscript
func _ready() -> void:
	AudioManager.play_game_music()
	_build_status_boxes()
	_start_combat()
```

Add these functions (place after `_start_combat`):
```gdscript
func _build_status_boxes() -> void:
	player_status_box = HBoxContainer.new()
	player_status_box.add_theme_constant_override("separation", 10)
	var layout := status_bar.get_parent()
	layout.add_child(player_status_box)
	layout.move_child(player_status_box, status_bar.get_index() + 1)

	enemy_status_box = HBoxContainer.new()
	enemy_status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_status_box.add_theme_constant_override("separation", 10)
	var enemy_details := enemy_panel.get_node("EnemyMargin/EnemyDetails")
	enemy_details.add_child(enemy_status_box)


func _refresh_status_badges(box: HBoxContainer, status: StatusSet) -> void:
	for child in box.get_children():
		child.queue_free()
	for entry in status.describe():
		var label := Label.new()
		label.text = "%s %d" % [entry.label, entry.amount]
		label.add_theme_color_override("font_color", _status_color(entry.kind))
		box.add_child(label)


func _status_color(kind: String) -> Color:
	match kind:
		"poison":
			return Color(0.5, 0.9, 0.5)
		"buff":
			return Color(1.0, 0.82, 0.3)
		_:
			return Color(1.0, 0.45, 0.4)
```

- [ ] **Step 3: Refresh badges each view update**

In `_refresh_combat_view`, at the very end of the function (after `_refresh_hand()`):
```gdscript
	_refresh_status_badges(player_status_box, state.player_status)
	_refresh_status_badges(enemy_status_box, state.enemy_status)
```

- [ ] **Step 4: Floating text for card-applied statuses**

In `_on_card_selected`, after the `if result.block_retention_armed:` block (the one that spawns `"FORTIFIED"`), add:
```gdscript
	if result.vulnerable_applied > 0:
		_spawn_floating_value("VULN %d" % result.vulnerable_applied, enemy_panel, Color(1.0, 0.45, 0.4))
	if result.weak_applied > 0:
		_spawn_floating_value("WEAK %d" % result.weak_applied, enemy_panel, Color(1.0, 0.45, 0.4))
	if result.poison_applied > 0:
		_spawn_floating_value("POISON %d" % result.poison_applied, enemy_panel, Color(0.5, 0.9, 0.5))
	if result.strength_gained > 0:
		_spawn_floating_value("STR +%d" % result.strength_gained, status_bar, Color(1.0, 0.82, 0.3))
```

- [ ] **Step 5: Floating text for poison and enemy-applied statuses**

In `_on_end_turn_button_pressed`, after the `if result.retained_block > 0:` block (before the `if state.phase == CombatState.Phase.LOST:` check), add:
```gdscript
	if result.enemy_poison_damage > 0:
		_spawn_floating_value("POISON %d" % result.enemy_poison_damage, enemy_panel, Color(0.5, 0.9, 0.5))
	if result.player_poison_damage > 0:
		_spawn_floating_value("POISON %d" % result.player_poison_damage, status_bar, Color(0.5, 0.9, 0.5))
	if result.weak_applied > 0:
		_spawn_floating_value("WEAK %d" % result.weak_applied, status_bar, Color(1.0, 0.45, 0.4))
	if result.vulnerable_applied > 0:
		_spawn_floating_value("VULN %d" % result.vulnerable_applied, status_bar, Color(1.0, 0.45, 0.4))
```

- [ ] **Step 6: Show status application in enemy intent**

Replace `_get_intent_text` with:
```gdscript
func _get_intent_text(move: EnemyMoveData) -> String:
	if move == null:
		return "Intent: Waiting"
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
		return "Intent: %s" % move.display_name
	return "Intent: %s - %s" % [move.display_name, " + ".join(parts)]
```

- [ ] **Step 7: Verify the tests still pass, then manually verify the UI**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS (this task changes no logic).

Manual check — launch `./Godot_v4.7-stable_win64_console.exe --path FirstGame/first-game`, start a run, and confirm: no errors on load; combat screen shows (empty) status rows; playing normal cards still works. (Full status visuals are exercised once Tasks 5-6 add status content.)

- [ ] **Step 8: Commit**

```bash
cd FirstGame/first-game && git add combat/combat_screen.gd && git commit -m "Show status badges, floating status text, and status intents

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Starter status cards (art, definitions, catalog, reward pool)

**Files:**
- Create: `FirstGame/first-game/cards/definitions/expose.tres`, `sap.tres`, `flex.tres`, `venom_cut.tres`
- Create: `FirstGame/first-game/assets/art/cards/expose.png`, `sap.png`, `flex.png`, `venom_cut.png` (+ generated `.import` files)
- Modify: `FirstGame/first-game/systems/run_state.gd`
- Modify: `FirstGame/first-game/screens/card_reward.gd`
- Test: `FirstGame/first-game/tests/combat_state_test.gd`

**Interfaces:**
- Consumes: CardData status fields (Task 2).
- Produces: card ids `expose`, `sap`, `flex`, `venom_cut` in `RunState.CARD_CATALOG` and `card_reward.REWARD_POOL`.

- [ ] **Step 1: Generate the four card arts**

Run from the working directory:
```bash
OUT="FirstGame/first-game/assets/art/cards"
STYLE="Dark-fantasy tarot-style trading card illustration, painterly, muted grim palette, dramatic rim lighting, centered subject, no text, no card border, no frame."
python tools/gen_asset.py "A hooded figure tracing a glowing crimson sigil in the air that clings to a shadowed foe, marking it, exposing weakness. $STYLE" "$OUT/expose.png" --resize 1254x1254
python tools/gen_asset.py "A sickly green haze draining the strength from a snarling warrior's arm, muscles going slack, sapping power. $STYLE" "$OUT/sap.png" --resize 1254x1254
python tools/gen_asset.py "A warrior flexing, veins alight with golden power, muscles surging with newfound strength. $STYLE" "$OUT/flex.png" --resize 1254x1254
python tools/gen_asset.py "A curved dagger dripping luminous green venom, toxic droplets sizzling, poison. $STYLE" "$OUT/venom_cut.png" --resize 1254x1254
```
Expected: four `Wrote ...` lines, each ~2 MB.

- [ ] **Step 2: Import the art**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import`
Expected: reimport lines for the four new PNGs, ending `[ DONE ] reimport`.

- [ ] **Step 3: Create the card definitions**

`cards/definitions/expose.tres`:
```
[gd_resource type="Resource" script_class="CardData" load_steps=3 format=3]

[ext_resource type="Script" path="res://cards/card_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/art/cards/expose.png" id="2"]

[resource]
script = ExtResource("1")
id = &"expose"
display_name = "Expose"
description = "Apply 2 Vulnerable to the enemy."
energy_cost = 1
target = 2
vulnerable_applied = 2
artwork = ExtResource("2")
```

`cards/definitions/sap.tres`:
```
[gd_resource type="Resource" script_class="CardData" load_steps=3 format=3]

[ext_resource type="Script" path="res://cards/card_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/art/cards/sap.png" id="2"]

[resource]
script = ExtResource("1")
id = &"sap"
display_name = "Sap"
description = "Apply 2 Weak to the enemy."
energy_cost = 1
target = 2
weak_applied = 2
artwork = ExtResource("2")
```

`cards/definitions/flex.tres`:
```
[gd_resource type="Resource" script_class="CardData" load_steps=3 format=3]

[ext_resource type="Script" path="res://cards/card_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/art/cards/flex.png" id="2"]

[resource]
script = ExtResource("1")
id = &"flex"
display_name = "Flex"
description = "Gain 2 Strength."
energy_cost = 1
target = 1
strength_gained = 2
artwork = ExtResource("2")
```

`cards/definitions/venom_cut.tres`:
```
[gd_resource type="Resource" script_class="CardData" load_steps=3 format=3]

[ext_resource type="Script" path="res://cards/card_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/art/cards/venom_cut.png" id="2"]

[resource]
script = ExtResource("1")
id = &"venom_cut"
display_name = "Venom Cut"
description = "Deal 4 damage. Apply 3 Poison."
energy_cost = 1
target = 2
damage = 4
poison_applied = 3
artwork = ExtResource("2")
```

- [ ] **Step 4: Register in the catalog**

In `systems/run_state.gd`, after `const RALLY_CARD := preload("res://cards/definitions/rally.tres")`:
```gdscript
const EXPOSE_CARD := preload("res://cards/definitions/expose.tres")
const SAP_CARD := preload("res://cards/definitions/sap.tres")
const FLEX_CARD := preload("res://cards/definitions/flex.tres")
const VENOM_CUT_CARD := preload("res://cards/definitions/venom_cut.tres")
```
And in `CARD_CATALOG`, after `&"rally": RALLY_CARD,`:
```gdscript
	&"expose": EXPOSE_CARD,
	&"sap": SAP_CARD,
	&"flex": FLEX_CARD,
	&"venom_cut": VENOM_CUT_CARD,
```

- [ ] **Step 5: Add to the reward pool**

In `screens/card_reward.gd`, inside the `REWARD_POOL` array, after the `preload(".../rally.tres"),` line:
```gdscript
	preload("res://cards/definitions/expose.tres"),
	preload("res://cards/definitions/sap.tres"),
	preload("res://cards/definitions/flex.tres"),
	preload("res://cards/definitions/venom_cut.tres"),
```

- [ ] **Step 6: Add a catalog test**

In `_run_tests()`, after `_test_enemy_move_applies_weak_to_player()`:
```gdscript
	_test_starter_cards_registered()
```
New function (above `_fresh_state()`):
```gdscript
func _test_starter_cards_registered() -> void:
	for id in [&"expose", &"sap", &"flex", &"venom_cut"]:
		_expect(RunState.CARD_CATALOG.has(id), "Starter card %s should be in the catalog." % id)
```

- [ ] **Step 7: Run tests**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS. (This also proves the new `.tres` + art load cleanly, since `RunState` preloads them.)

- [ ] **Step 8: Commit**

```bash
cd FirstGame/first-game && git add cards/definitions assets/art/cards systems/run_state.gd screens/card_reward.gd tests/combat_state_test.gd && git commit -m "Add starter status cards: Expose, Sap, Flex, Venom Cut

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Starter enemy status moves

**Files:**
- Create: `FirstGame/first-game/enemies/moves/hobbling_slash.tres`, `dread_roar.tres`
- Modify: `FirstGame/first-game/enemies/definitions/raider.tres`, `guardian.tres`
- Test: `FirstGame/first-game/tests/combat_state_test.gd`

**Interfaces:**
- Consumes: EnemyMoveData status fields (Task 3).
- Produces: Road Raider pattern includes a Weak-applying move; Iron Guardian pattern includes a Vulnerable-applying move.

- [ ] **Step 1: Write the failing test**

In `_run_tests()`, after `_test_starter_cards_registered()`:
```gdscript
	_test_enemy_patterns_include_status_moves()
```
New function (above `_fresh_state()`):
```gdscript
func _test_enemy_patterns_include_status_moves() -> void:
	var raider_has_weak := false
	for move in RunState.RAIDER.move_pattern:
		if move.weak_applied > 0:
			raider_has_weak = true
	_expect(raider_has_weak, "Raider should have a move that applies Weak.")
	var guardian_has_vuln := false
	for move in RunState.GUARDIAN.move_pattern:
		if move.vulnerable_applied > 0:
			guardian_has_vuln = true
	_expect(guardian_has_vuln, "Guardian should have a move that applies Vulnerable.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: FAIL — neither pattern has the status move yet.

- [ ] **Step 3: Create the move resources**

`enemies/moves/hobbling_slash.tres`:
```
[gd_resource type="Resource" script_class="EnemyMoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="1"]

[resource]
script = ExtResource("1")
display_name = "Hobbling Slash"
damage = 6
weak_applied = 1
```

`enemies/moves/dread_roar.tres`:
```
[gd_resource type="Resource" script_class="EnemyMoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="1"]

[resource]
script = ExtResource("1")
display_name = "Dread Roar"
vulnerable_applied = 2
```

- [ ] **Step 4: Add the moves to the enemy patterns**

Replace the full contents of `enemies/definitions/raider.tres` with (adds `hobbling_slash` as `id="6"`, `load_steps` 6->7, appends it to `move_pattern`):
```
[gd_resource type="Resource" script_class="EnemyData" load_steps=7 format=3]

[ext_resource type="Script" path="res://enemies/enemy_data.gd" id="1"]
[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="2"]
[ext_resource type="Resource" path="res://enemies/moves/raider_slash.tres" id="3"]
[ext_resource type="Resource" path="res://enemies/moves/raider_guard.tres" id="4"]
[ext_resource type="Resource" path="res://enemies/moves/hobbling_slash.tres" id="6"]
[ext_resource type="Texture2D" path="res://assets/art/enemies/road_raider.png" id="5"]

[resource]
script = ExtResource("1")
id = &"raider"
display_name = "Road Raider"
max_health = 38
move_pattern = Array[ExtResource("2")]([ExtResource("3"), ExtResource("4"), ExtResource("6")])
artwork = ExtResource("5")
```

Replace the full contents of `enemies/definitions/guardian.tres` with (adds `dread_roar` as `id="7"`, `load_steps` 7->8, appends it to `move_pattern`):
```
[gd_resource type="Resource" script_class="EnemyData" load_steps=8 format=3]

[ext_resource type="Script" path="res://enemies/enemy_data.gd" id="1"]
[ext_resource type="Script" path="res://enemies/enemy_move_data.gd" id="2"]
[ext_resource type="Resource" path="res://enemies/moves/guardian_crush.tres" id="3"]
[ext_resource type="Resource" path="res://enemies/moves/guardian_fortify.tres" id="4"]
[ext_resource type="Resource" path="res://enemies/moves/guardian_heavy.tres" id="5"]
[ext_resource type="Resource" path="res://enemies/moves/dread_roar.tres" id="7"]
[ext_resource type="Texture2D" path="res://assets/art/enemies/iron_guardian.png" id="6"]

[resource]
script = ExtResource("1")
id = &"guardian"
display_name = "Iron Guardian"
max_health = 52
move_pattern = Array[ExtResource("2")]([ExtResource("3"), ExtResource("4"), ExtResource("5"), ExtResource("4"), ExtResource("7")])
artwork = ExtResource("6")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS — `Combat state tests passed.`, exit 0.

- [ ] **Step 6: Commit**

```bash
cd FirstGame/first-game && git add enemies/moves enemies/definitions/raider.tres enemies/definitions/guardian.tres tests/combat_state_test.gd && git commit -m "Give Raider a Weak move and Guardian a Vulnerable move

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Full verification and docs

**Files:**
- Modify: `FirstGame/first-game/README.md`

- [ ] **Step 1: Run the full test suite**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd`
Expected: PASS — `Combat state tests passed.`, exit 0.

- [ ] **Step 2: Manual playtest**

Launch `./Godot_v4.7-stable_win64_console.exe --path FirstGame/first-game`. Verify:
- Playing Expose shows `VULN 2` and a `Vuln 2` badge on the enemy; a following Strike hits harder.
- Venom Cut adds a `Poison 3` badge; the enemy loses HP at the start of its turn and the badge counts down.
- Flex adds a gold `Str 2` badge on the player; attacks deal more.
- Reaching the Road Raider, its Hobbling Slash applies `Weak`; the Iron Guardian's Dread Roar intent reads "Vulnerable 2" and applies it.
- Status badges clear when a new combat begins.

- [ ] **Step 3: Update the README**

In `README.md`, under "Roadmap", change the first foundation bullet to mark it done:
```markdown
- **Status effects** - stacking buffs/debuffs (Vulnerable, Weak, Poison,
  Strength, Dexterity). Biggest depth multiplier. Impact: high. Effort: medium.
  DONE: Vulnerable, Weak, Strength, and Poison, with the Expose/Sap/Flex/Venom
  Cut cards and Raider/Guardian debuff moves.
```

- [ ] **Step 4: Commit**

```bash
cd FirstGame/first-game && git add README.md && git commit -m "Mark status-effects milestone complete in the roadmap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
