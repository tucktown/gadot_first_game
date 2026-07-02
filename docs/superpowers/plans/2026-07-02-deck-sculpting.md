# Gold, Shop & Deck Sculpting (Milestone 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gold economy, a SHOP map node, card upgrades (at rest) and card removal (at shop) — the run's deck-sculpting layer.

**Architecture:** Gold is a new `RunState` field (save v5). Upgrades are separate `+` card definitions swapped into the deck by id (no per-instance state, no save-schema change beyond gold). A new `SHOP` node type + shop/rest screens spend gold and sculpt the deck. Non-combat nodes commit on entry; combat still commits on win.

**Tech Stack:** Godot 4.7, typed GDScript. Tests are plain `extends SceneTree` scripts under `tests/`, `quit(failures)` (exit 0 == pass).

## Global Constraints

- Typed GDScript throughout — annotations on all vars, params, returns.
- Never mutate `.tres` definitions at runtime; they are shared immutable data.
- Never call `change_scene_to_file` directly — use `SceneTransition.transition_to(path)`.
- Combat logic stays pure in `CombatState`; screens only route/animate.
- `SAVE_VERSION` bumps to **5**. Save keeps the aggressive fail-safe: any mismatch (bad version, malformed map, unknown card/relic/enemy id, health ≤ 0) → `clear_saved_run()` + return false.
- New `class_name` / new `.tres` / new scenes require an `--import` run before headless `--script` tests resolve them. Steps include `--import` where needed.
- `extends SceneTree` tests call autoload **instance** members via `root.get_node("RunState")`; class consts (`RunState.SAVE_VERSION`, `RunState.SHOP_CARD_PRICE`, etc.) resolve bare.
- Adding a card requires registering its id in `CARD_CATALOG`; an upgraded card is a normal cataloged card.
- Run the editor from repo root: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game ...`
- Prices (authoritative): card 50, remove 75, relic 140. Gold: normal combat `randi_range(9,15)`, elite `randi_range(25,30)`, boss 0.
- Map: 7 rows (rows 0–5 choice + row 6 boss). Row 0 all COMBAT, row 5 all REST, ELITE only rows 2–4, SHOP only rows 1–4, ≥1 SHOP guaranteed per act.

---

### Task 1: Gold field + economy + save v5

**Files:**
- Modify: `systems/run_state.gd` (version, `gold`, `add_gold`/`spend_gold`, `complete_combat`, `start_new_run`, `save_run`, `load_saved_run`)
- Modify: `tests/relic_test.gd` (version assertion), `tests/enemy_ai_test.gd` (version assertion)
- Test: `tests/economy_test.gd` (new)

**Interfaces:**
- Produces: `RunState.gold: int`, `RunState.add_gold(amount: int) -> void`, `RunState.spend_gold(amount: int) -> bool` (false + no deduction if `amount < 0` or `gold < amount`). `SAVE_VERSION == 5`. Gold awarded in `complete_combat` by node type.

- [ ] **Step 1: Write the failing economy test**

Create `tests/economy_test.gd`:

```gdscript
extends SceneTree

var failures := 0
var _save_backup: Variant = null


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_backup_save()
	_test_gold_awarded_by_node_type()
	_test_spend_gold_semantics()
	_test_gold_round_trips()
	if failures == 0:
		print("Economy tests passed.")
	_restore_save()
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _rs() -> Node:
	return root.get_node("RunState")


# Enter an available (row-0) node, then rewrite it to the wanted type/enemy so the
# node-type branches of complete_combat can be exercised deterministically.
func _enter_type(rs: Node, type: MapNode.Type, enemy_id: StringName) -> void:
	var start_id: int = rs.map.get_available_node_ids()[0]
	var node: MapNode = rs.map.get_node_by_id(start_id)
	node.type = type
	node.enemy_id = enemy_id
	rs.begin_node(start_id)


func _test_gold_awarded_by_node_type() -> void:
	var rs := _rs()
	rs.start_new_run()
	var before: int = rs.gold
	_enter_type(rs, MapNode.Type.COMBAT, &"cinder_hound")
	rs.complete_combat(30)
	var normal_gain: int = rs.gold - before
	_expect(normal_gain >= 9 and normal_gain <= 15, "Normal win gold in [9,15], got %d." % normal_gain)

	rs.start_new_run()
	before = rs.gold
	_enter_type(rs, MapNode.Type.ELITE, &"dread_sentinel")
	rs.complete_combat(30)
	var elite_gain: int = rs.gold - before
	_expect(elite_gain >= 25 and elite_gain <= 30, "Elite win gold in [25,30], got %d." % elite_gain)

	rs.start_new_run()
	before = rs.gold
	_enter_type(rs, MapNode.Type.BOSS, &"gravemaw")
	rs.complete_combat(30)
	_expect(rs.gold - before == 0, "Boss win should give no gold.")


func _test_spend_gold_semantics() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	_expect(rs.spend_gold(30) and rs.gold == 70, "spend_gold deducts on success.")
	_expect(not rs.spend_gold(1000) and rs.gold == 70, "Insufficient gold: no deduction.")
	_expect(not rs.spend_gold(-5) and rs.gold == 70, "Negative amount rejected.")


func _test_gold_round_trips() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 42
	rs.save_run()
	rs.gold = 0
	_expect(rs.load_saved_run() and rs.gold == 42, "Gold should survive save/load.")


func _backup_save() -> void:
	if FileAccess.file_exists("user://run.json"):
		_save_backup = FileAccess.get_file_as_bytes("user://run.json")


func _restore_save() -> void:
	if _save_backup != null:
		var file := FileAccess.open("user://run.json", FileAccess.WRITE)
		file.store_buffer(_save_backup)
	elif FileAccess.file_exists("user://run.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://run.json"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import`
then: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/economy_test.gd`
Expected: FAIL — `rs.gold` / `spend_gold` don't exist.

- [ ] **Step 3: Add gold to `RunState`**

In `systems/run_state.gd`:

(a) Bump version (line 3): `const SAVE_VERSION := 5`

(b) Add the field after `var current_health` (line 68):
```gdscript
var gold: int = 0
```

(c) In `start_new_run()`, add before `map = _generate_map()`:
```gdscript
	gold = 0
```

(d) Replace `complete_combat` (lines 113–123) with a version that awards gold by node type:
```gdscript
func complete_combat(remaining_health: int) -> void:
	var node := map.get_node_by_id(_pending_node_id) if map != null else null
	if node == null or not map.enter(_pending_node_id):
		push_error("complete_combat: no committable pending node (%d)." % _pending_node_id)
		return
	current_health = clampi(remaining_health, 0, max_health)
	match node.type:
		MapNode.Type.ELITE:
			awaiting_relic = true
			add_gold(randi_range(25, 30))
		MapNode.Type.BOSS:
			awaiting_relic = true
		_:
			awaiting_reward = true
			add_gold(randi_range(9, 15))
	save_run()
```

(e) Add the two methods (e.g. after `add_relic`):
```gdscript
func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	return true
```

(f) In `save_run()`'s `save_data` dict, add:
```gdscript
		"gold": gold,
```

(g) In `load_saved_run()`, after `current_health = clampi(...)` (line 263), add:
```gdscript
	gold = maxi(0, int(save_data.get("gold", 0)))
```

- [ ] **Step 4: Update the two version-assertion tests**

In `tests/relic_test.gd` `_test_relic_catalog_complete`, change the version line to:
```gdscript
	_expect(RunState.SAVE_VERSION == 5, "SAVE_VERSION should be 5.")
```
In `tests/enemy_ai_test.gd` `_test_run_ends_on_boss`, change the version line to:
```gdscript
	_expect(RunState.SAVE_VERSION == 5, "Save version should be bumped to 5.")
```

- [ ] **Step 5: Run tests to verify pass**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/economy_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/relic_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: all PASS (exit 0).

- [ ] **Step 6: Commit**

```bash
git -C FirstGame/first-game add systems/run_state.gd tests/economy_test.gd tests/relic_test.gd tests/enemy_ai_test.gd
git -C FirstGame/first-game commit -m "feat: gold economy + save v5"
```

---

### Task 2: `upgrade_id` on CardData + upgraded card definitions

**Files:**
- Modify: `cards/card_data.gd` (add `upgrade_id`)
- Create: `cards/definitions/<id>_plus.tres` for all 16 cards
- Modify: each `cards/definitions/<id>.tres` (set `upgrade_id`)
- Modify: `systems/run_state.gd` (preload + `CARD_CATALOG` entries for the 16 `+` cards)
- Test: `tests/upgrade_catalog_test.gd` (new)

**Interfaces:**
- Produces: `CardData.upgrade_id: StringName` (`&""` = not upgradable). Each base card's `upgrade_id` points to its `<id>_plus`; every `<id>_plus` is registered in `CARD_CATALOG` with `upgrade_id == &""` (one-level).

- [ ] **Step 1: Add the field to `CardData`**

In `cards/card_data.gd`, under `@export_category("Rules")` (after `strength_gained`, line 29):
```gdscript
@export var upgrade_id: StringName    # this card's + version; &"" = not upgradable
```

- [ ] **Step 2: Write the failing catalog test**

Create `tests/upgrade_catalog_test.gd`:

```gdscript
extends SceneTree

var failures := 0

# base id -> expected + id
const UPGRADES := {
	&"strike": &"strike_plus", &"defend": &"defend_plus",
	&"heavy_strike": &"heavy_strike_plus", &"guarded_strike": &"guarded_strike_plus",
	&"power_blow": &"power_blow_plus", &"quick_guard": &"quick_guard_plus",
	&"fortify": &"fortify_plus", &"second_wind": &"second_wind_plus",
	&"devour": &"devour_plus", &"mend": &"mend_plus",
	&"bulwark": &"bulwark_plus", &"rally": &"rally_plus",
	&"expose": &"expose_plus", &"sap": &"sap_plus",
	&"flex": &"flex_plus", &"venom_cut": &"venom_cut_plus",
}


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var catalog: Dictionary = RunState.CARD_CATALOG
	for base_id in UPGRADES:
		var plus_id: StringName = UPGRADES[base_id]
		_expect(catalog.has(base_id), "Base card %s should be catalogued." % base_id)
		_expect(catalog.has(plus_id), "Upgraded card %s should be catalogued." % plus_id)
		if catalog.has(base_id) and catalog.has(plus_id):
			var base: CardData = catalog[base_id]
			var plus: CardData = catalog[plus_id]
			_expect(base.upgrade_id == plus_id, "%s.upgrade_id should point to %s." % [base_id, plus_id])
			_expect(plus.upgrade_id == &"", "%s should not be further upgradable." % plus_id)
			_expect(_stats_improved(base, plus), "%s should improve on %s." % [plus_id, base_id])
	if failures == 0:
		print("Upgrade catalog tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _stats_improved(base: CardData, plus: CardData) -> bool:
	# At least one meaningful stat is strictly better.
	return (plus.damage > base.damage or plus.block > base.block or plus.heal > base.heal
		or plus.vulnerable_applied > base.vulnerable_applied or plus.weak_applied > base.weak_applied
		or plus.poison_applied > base.poison_applied or plus.strength_gained > base.strength_gained
		or plus.cards_drawn > base.cards_drawn or plus.energy_gained > base.energy_gained)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 3: Run to verify it fails**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import`
then the test — Expected: FAIL (`_plus` ids not in catalog).

- [ ] **Step 4: Author the 16 `+` definitions**

For each card, create `cards/definitions/<id>_plus.tres`. **Method:** copy the base `<id>.tres` verbatim, then change only `id`, `display_name`, `description`, and the stat line(s) listed below; **keep every other line identical** (same `target`, `energy_cost`, flags, `artwork` ExtResource, `load_steps`). The `+` file does NOT set `upgrade_id` (defaults to `&""`).

Full template (strike_plus.tres) as the pattern:
```
[gd_resource type="Resource" script_class="CardData" load_steps=3 format=3]

[ext_resource type="Script" path="res://cards/card_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/art/cards/strike.png" id="2"]

[resource]
script = ExtResource("1")
id = &"strike_plus"
display_name = "Strike+"
description = "Deal 9 damage."
energy_cost = 1
target = 2
damage = 9
artwork = ExtResource("2")
```

Exact per-card values (everything else copied from the base file):

| + file | id | display_name | description | changed stat lines |
|--------|----|--------------|-------------|--------------------|
| strike_plus | `strike_plus` | `Strike+` | `Deal 9 damage.` | `damage = 9` |
| defend_plus | `defend_plus` | `Defend+` | `Gain 8 block.` | `block = 8` |
| heavy_strike_plus | `heavy_strike_plus` | `Heavy Strike+` | `Deal 14 damage.` | `damage = 14` |
| guarded_strike_plus | `guarded_strike_plus` | `Guarded Strike+` | `Deal 5 damage. Gain 5 block. Draw 1 card.` | `damage = 5`, `block = 5` |
| power_blow_plus | `power_blow_plus` | `Power Blow+` | `Deal 18 damage. Gain 1 energy.` | `damage = 18` |
| quick_guard_plus | `quick_guard_plus` | `Quick Guard+` | `Gain 6 block.` | `block = 6` |
| fortify_plus | `fortify_plus` | `Fortify+` | `Gain 7 block. Retain unspent block next turn.` | `block = 7` |
| second_wind_plus | `second_wind_plus` | `Second Wind+` | `Gain 3 energy. Can exceed your maximum.` | `energy_gained = 3` |
| devour_plus | `devour_plus` | `Devour+` | `Deal 16 damage. Heal health equal to damage dealt.` | `damage = 16` |
| mend_plus | `mend_plus` | `Mend+` | `Restore 8 health.` | `heal = 8` |
| bulwark_plus | `bulwark_plus` | `Bulwark+` | `Gain 16 block. Retain unspent block next turn.` | `block = 16` |
| rally_plus | `rally_plus` | `Rally+` | `Deal 8 damage. Draw 1 card. Gain 1 energy.` | `damage = 8` |
| expose_plus | `expose_plus` | `Expose+` | `Apply 3 Vulnerable to the enemy.` | `vulnerable_applied = 3` |
| sap_plus | `sap_plus` | `Sap+` | `Apply 3 Weak to the enemy.` | `weak_applied = 3` |
| flex_plus | `flex_plus` | `Flex+` | `Gain 3 Strength.` | `strength_gained = 3` |
| venom_cut_plus | `venom_cut_plus` | `Venom Cut+` | `Deal 6 damage. Apply 4 Poison.` | `damage = 6`, `poison_applied = 4` |

> Note on `expose`/`sap`/`venom_cut`: their base files omit `energy_cost` (defaults 1) and `expose`/`sap`/`venom_cut` omit `target` (defaults 2). Copy the base file exactly, so those defaults carry over — do not add lines the base omits.

- [ ] **Step 5: Set `upgrade_id` on each base card**

In each `cards/definitions/<id>.tres`, add one line in the `[resource]` block:
```
upgrade_id = &"<id>_plus"
```
(e.g. `strike.tres` gets `upgrade_id = &"strike_plus"`).

- [ ] **Step 6: Register the `+` cards in `CARD_CATALOG`**

In `systems/run_state.gd`, add preload consts after `VENOM_CUT_CARD` (line 19):
```gdscript
const STRIKE_PLUS_CARD := preload("res://cards/definitions/strike_plus.tres")
const DEFEND_PLUS_CARD := preload("res://cards/definitions/defend_plus.tres")
const HEAVY_STRIKE_PLUS_CARD := preload("res://cards/definitions/heavy_strike_plus.tres")
const GUARDED_STRIKE_PLUS_CARD := preload("res://cards/definitions/guarded_strike_plus.tres")
const POWER_BLOW_PLUS_CARD := preload("res://cards/definitions/power_blow_plus.tres")
const QUICK_GUARD_PLUS_CARD := preload("res://cards/definitions/quick_guard_plus.tres")
const FORTIFY_PLUS_CARD := preload("res://cards/definitions/fortify_plus.tres")
const SECOND_WIND_PLUS_CARD := preload("res://cards/definitions/second_wind_plus.tres")
const DEVOUR_PLUS_CARD := preload("res://cards/definitions/devour_plus.tres")
const MEND_PLUS_CARD := preload("res://cards/definitions/mend_plus.tres")
const BULWARK_PLUS_CARD := preload("res://cards/definitions/bulwark_plus.tres")
const RALLY_PLUS_CARD := preload("res://cards/definitions/rally_plus.tres")
const EXPOSE_PLUS_CARD := preload("res://cards/definitions/expose_plus.tres")
const SAP_PLUS_CARD := preload("res://cards/definitions/sap_plus.tres")
const FLEX_PLUS_CARD := preload("res://cards/definitions/flex_plus.tres")
const VENOM_CUT_PLUS_CARD := preload("res://cards/definitions/venom_cut_plus.tres")
```
And add these entries inside the `CARD_CATALOG` dict (before its closing brace):
```gdscript
	&"strike_plus": STRIKE_PLUS_CARD,
	&"defend_plus": DEFEND_PLUS_CARD,
	&"heavy_strike_plus": HEAVY_STRIKE_PLUS_CARD,
	&"guarded_strike_plus": GUARDED_STRIKE_PLUS_CARD,
	&"power_blow_plus": POWER_BLOW_PLUS_CARD,
	&"quick_guard_plus": QUICK_GUARD_PLUS_CARD,
	&"fortify_plus": FORTIFY_PLUS_CARD,
	&"second_wind_plus": SECOND_WIND_PLUS_CARD,
	&"devour_plus": DEVOUR_PLUS_CARD,
	&"mend_plus": MEND_PLUS_CARD,
	&"bulwark_plus": BULWARK_PLUS_CARD,
	&"rally_plus": RALLY_PLUS_CARD,
	&"expose_plus": EXPOSE_PLUS_CARD,
	&"sap_plus": SAP_PLUS_CARD,
	&"flex_plus": FLEX_PLUS_CARD,
	&"venom_cut_plus": VENOM_CUT_PLUS_CARD,
```

- [ ] **Step 7: Import + run the catalog test**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/upgrade_catalog_test.gd
```
Expected: PASS — "Upgrade catalog tests passed." Also re-run `combat_state_test.gd` (unaffected) — PASS.

- [ ] **Step 8: Commit**

```bash
git -C FirstGame/first-game add cards/card_data.gd cards/definitions/ systems/run_state.gd tests/upgrade_catalog_test.gd
git -C FirstGame/first-game commit -m "feat: upgraded (+) card definitions and upgrade_id"
```

---

### Task 3: Deck-sculpt + node-commit `RunState` methods

**Files:**
- Modify: `systems/run_state.gd`
- Modify: `tests/economy_test.gd`

**Interfaces:**
- Consumes: `spend_gold` (Task 1), `upgrade_id`/`CARD_CATALOG` `+` cards (Task 2).
- Produces:
  - `const SHOP_CARD_PRICE := 50`, `SHOP_REMOVE_PRICE := 75`, `SHOP_RELIC_PRICE := 140`
  - `upgrade_card(deck_index: int) -> bool` — swaps the slot to its `+` card; false if index invalid or card not upgradable.
  - `purchase_removal(deck_index: int) -> bool` — false if `deck.size() <= 1`, index invalid, or gold < 75; else spends 75 and removes.
  - `buy_card(def: CardData) -> bool`, `buy_relic(relic: RelicData) -> bool` — spend the price, append; false if short.
  - `heal_rest() -> void` — heal `ceil(max_health*0.30)` + save (no commit).
  - `commit_pending_node() -> bool` — guarded `map.enter(_pending_node_id)` + save.
  - `apply_rest` is left intact for now (map_screen still calls it until Task 8).

- [ ] **Step 1: Add the failing deck-sculpt tests**

In `tests/economy_test.gd`, add these calls in `_run_tests()` before the `if failures == 0` line:
```gdscript
	_test_upgrade_card()
	_test_purchase_removal()
	_test_buy_card_and_relic()
```
Add these methods:
```gdscript
func _test_upgrade_card() -> void:
	var rs := _rs()
	rs.start_new_run()   # deck: strike, strike, defend, defend, heavy_strike
	_expect(rs.upgrade_card(0), "Upgrading an upgradable card should succeed.")
	_expect(rs.deck[0].id == &"strike_plus", "Slot 0 should now hold strike_plus.")
	rs.save_run()
	rs.deck = []
	_expect(rs.load_saved_run() and rs.deck[0].id == &"strike_plus",
		"Upgraded card should round-trip through save/load by id.")
	_expect(not rs.upgrade_card(999), "Out-of-range upgrade should fail.")
	rs.deck.append(CardData.new())   # runtime card, upgrade_id defaults &""
	_expect(not rs.upgrade_card(rs.deck.size() - 1), "Non-upgradable card can't be upgraded.")


func _test_purchase_removal() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	var size_before: int = rs.deck.size()
	_expect(rs.purchase_removal(0), "Removal with funds + room should succeed.")
	_expect(rs.deck.size() == size_before - 1, "Removal should drop one card.")
	_expect(rs.gold == 25, "Removal should cost 75.")
	rs.gold = 10
	_expect(not rs.purchase_removal(0), "Removal without funds should fail.")
	var one_card: Array[CardData] = [RunState.STRIKE_CARD]
	rs.deck = one_card
	rs.gold = 100
	_expect(not rs.purchase_removal(0), "Can't remove the last card.")
	_expect(rs.deck.size() == 1 and rs.gold == 100, "Failed removal changes nothing.")


func _test_buy_card_and_relic() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	var deck_before: int = rs.deck.size()
	_expect(rs.buy_card(RunState.RALLY_CARD) and rs.deck.size() == deck_before + 1 and rs.gold == 50,
		"buy_card appends and costs 50.")
	rs.gold = 10
	_expect(not rs.buy_card(RunState.RALLY_CARD), "buy_card fails when short; no change.")
	rs.gold = 200
	var relics_before: int = rs.relics.size()
	_expect(rs.buy_relic(RunState.STONE_HEART) and rs.relics.size() == relics_before + 1 and rs.gold == 60,
		"buy_relic appends and costs 140.")
	rs.gold = 10
	_expect(not rs.buy_relic(RunState.STONE_HEART), "buy_relic fails when short.")
```

- [ ] **Step 2: Run to verify failure**

Run economy_test — Expected: FAIL (methods/consts undefined).

- [ ] **Step 3: Implement the methods**

In `systems/run_state.gd`, add price consts after `CARD_CATALOG` (line 65):
```gdscript
const SHOP_CARD_PRICE := 50
const SHOP_REMOVE_PRICE := 75
const SHOP_RELIC_PRICE := 140
```
Add methods (e.g. after `add_relic`):
```gdscript
func upgrade_card(deck_index: int) -> bool:
	if deck_index < 0 or deck_index >= deck.size():
		return false
	var card := deck[deck_index]
	if card.upgrade_id == &"" or not CARD_CATALOG.has(card.upgrade_id):
		return false
	deck[deck_index] = CARD_CATALOG[card.upgrade_id]
	save_run()
	return true


func purchase_removal(deck_index: int) -> bool:
	if deck.size() <= 1 or deck_index < 0 or deck_index >= deck.size():
		return false
	if not spend_gold(SHOP_REMOVE_PRICE):
		return false
	deck.remove_at(deck_index)
	save_run()
	return true


func buy_card(def: CardData) -> bool:
	if not spend_gold(SHOP_CARD_PRICE):
		return false
	deck.append(def)
	save_run()
	return true


func buy_relic(relic: RelicData) -> bool:
	if not spend_gold(SHOP_RELIC_PRICE):
		return false
	relics.append(relic)
	save_run()
	return true


func heal_rest() -> void:
	var heal := int(ceil(max_health * 0.30))
	current_health = clampi(current_health + heal, 0, max_health)
	save_run()


func commit_pending_node() -> bool:
	if map == null:
		return false
	var node := map.get_node_by_id(_pending_node_id)
	if node == null or not map.enter(_pending_node_id):
		push_error("commit_pending_node: no committable pending node (%d)." % _pending_node_id)
		return false
	save_run()
	return true
```

- [ ] **Step 4: Run to verify pass**

Run economy_test — Expected: PASS ("Economy tests passed.").

- [ ] **Step 5: Commit**

```bash
git -C FirstGame/first-game add systems/run_state.gd tests/economy_test.gd
git -C FirstGame/first-game commit -m "feat: deck-sculpt + node-commit RunState methods"
```

---

### Task 4: SHOP node type + generation (+ guaranteed shop) + map display support

**Files:**
- Modify: `systems/map_node.gd` (enum)
- Modify: `systems/game_map.gd` (`_roll_type`, `_ensure_shop`, `generate`, `from_dict`)
- Modify: `screens/map_screen.gd` (SHOP letter/color/tooltip/legend so any map renders)
- Modify: `tests/map_generation_test.gd`

**Interfaces:**
- Produces: `MapNode.Type.SHOP` (value 4, appended after BOSS). SHOP nodes appear only on rows 1–4, carry empty `enemy_id`, and every generated map has ≥ 1 SHOP.

- [ ] **Step 1: Add SHOP to the enum**

In `systems/map_node.gd`, append `SHOP` (keep existing order/values stable):
```gdscript
enum Type { COMBAT, ELITE, REST, BOSS, SHOP }
```

- [ ] **Step 2: Add the failing generation assertions**

In `tests/map_generation_test.gd`:

In `_test_type_placement_rules`, add inside the per-node loop:
```gdscript
		if node.type == MapNode.Type.SHOP:
			_expect(node.row >= 1 and node.row <= 4, "Shops only on rows 1-4.")
```
In `_test_enemy_ids_assigned`, add a SHOP case to the `match`:
```gdscript
			MapNode.Type.SHOP:
				_expect(node.enemy_id == &"", "Shop node must have no enemy id.")
```
Register a new test in `_run_tests()`:
```gdscript
	_test_every_map_has_a_shop()
```
Add the method:
```gdscript
func _test_every_map_has_a_shop() -> void:
	for seed_value in range(1, 31):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var map := GameMap.generate(rng, NORMALS, ELITES, BOSS_ID)
		var shops := 0
		for node in map.nodes:
			if node.type == MapNode.Type.SHOP:
				shops += 1
		_expect(shops >= 1, "Seed %d: every act must have at least one shop." % seed_value)
```

- [ ] **Step 3: Run to verify failure**

Run map_generation_test — Expected: FAIL (no SHOP generated / enum value).

- [ ] **Step 4: Implement SHOP generation**

In `systems/game_map.gd`:

Replace `_roll_type` (lines 67–77):
```gdscript
static func _roll_type(rng: RandomNumberGenerator, row: int) -> MapNode.Type:
	if row == 0:
		return MapNode.Type.COMBAT
	if row == CHOICE_ROWS - 1:
		return MapNode.Type.REST
	var roll := rng.randf()
	if roll < 0.15:
		return MapNode.Type.REST
	if roll < 0.27:
		return MapNode.Type.SHOP
	if roll < 0.52 and row >= 2:
		return MapNode.Type.ELITE
	return MapNode.Type.COMBAT
```

In `generate`, add the guaranteed-shop pass right after the choice-row + boss rows are built and **before** the enemy-assignment loop (i.e. after the `rows.append([boss] ...)` line, before `# Assign enemies`):
```gdscript
	GameMap._ensure_shop(rng, rows)
```
Add the helper (e.g. after `_roll_type`):
```gdscript
static func _ensure_shop(rng: RandomNumberGenerator, rows: Array) -> void:
	# Rows 1..CHOICE_ROWS-2 are the shop-eligible mid rows (row 0 combat, row 5 rest).
	for r in range(1, CHOICE_ROWS - 1):
		for node in rows[r]:
			if node.type == MapNode.Type.SHOP:
				return
	var candidates: Array[MapNode] = []
	for r in range(1, CHOICE_ROWS - 1):
		for node in rows[r]:
			candidates.append(node)
	if candidates.is_empty():
		return
	candidates[rng.randi_range(0, candidates.size() - 1)].type = MapNode.Type.SHOP
```
(The enemy-assignment loop's `_:` branch already sets `enemy_id = &""` for SHOP.)

In `from_dict`, widen the type bound (line 165):
```gdscript
		if type_value < 0 or type_value > int(MapNode.Type.SHOP):
```

- [ ] **Step 5: Add SHOP display support to the map screen**

In `screens/map_screen.gd`, add SHOP to the dictionaries so any generated map renders:

`TYPE_LETTER` gains:
```gdscript
	MapNode.Type.SHOP: "S",
```
`TYPE_COLOR` gains:
```gdscript
	MapNode.Type.SHOP: Color(0.45, 0.78, 0.85),
```
In `_build_legend`, add to the list literal:
```gdscript
		[MapNode.Type.SHOP, "Shop (spend gold)"],
```
In `_tooltip`, add a case:
```gdscript
		MapNode.Type.SHOP:
			return "Shop — buy cards, relics, removal"
```

- [ ] **Step 6: Import + run tests**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_screen_test.gd
```
Expected: both PASS (map_screen_test still builds a button per node — SHOP nodes now have a letter/color).

- [ ] **Step 7: Commit**

```bash
git -C FirstGame/first-game add systems/map_node.gd systems/game_map.gd screens/map_screen.gd tests/map_generation_test.gd
git -C FirstGame/first-game commit -m "feat: SHOP map node + generation with guaranteed shop per act"
```

---

### Task 5: Selectable card picker (extend `deck_viewer`)

**Files:**
- Modify: `screens/deck_viewer.gd`, `screens/deck_viewer.tscn`
- Test: `tests/card_picker_test.gd` (new)

**Interfaces:**
- Produces: `DeckViewer.set_picker(title: String, eligible: Callable) -> void` (call before `add_child`; `eligible` is `func(index: int, card: CardData) -> bool`) and signal `card_selected(deck_index: int)`. Default (no `set_picker`) stays read-only preview mode — existing callers unaffected.

- [ ] **Step 1: Add `unique_name_in_owner` to the title label**

In `screens/deck_viewer.tscn`, on the `Title` node (under `Center/Panel/Margin/Content/Header`), add:
```
unique_name_in_owner = true
```

- [ ] **Step 2: Write the failing picker test**

Create `tests/card_picker_test.gd`:
```gdscript
extends SceneTree

var failures := 0
var _viewer_scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_viewer_scene = load("res://screens/deck_viewer.tscn")
	await _test_picker_eligibility()
	if failures == 0:
		print("Card picker tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_picker_eligibility() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()   # 5-card deck
	root.size = Vector2i(1280, 720)
	var picker := _viewer_scene.instantiate()
	# Only even indices eligible.
	picker.set_picker("Pick", func(index, _card): return index % 2 == 0)
	root.add_child(picker)
	await process_frame
	await process_frame
	var grid := picker.get_node("%CardGrid")
	_expect(grid.get_child_count() == rs.deck.size(),
		"Picker should show one card per deck card (%d)." % rs.deck.size())
	for i in grid.get_child_count():
		var card_view = grid.get_child(i)
		var enabled := not card_view.select_button.disabled
		_expect(enabled == (i % 2 == 0),
			"Card %d eligibility should match the predicate." % i)
	picker.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 3: Run to verify failure**

Import + run card_picker_test — Expected: FAIL (`set_picker` undefined).

- [ ] **Step 4: Implement the picker mode**

Replace the body of `screens/deck_viewer.gd` with:
```gdscript
class_name DeckViewer
extends Control

signal card_selected(deck_index: int)

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")

@onready var card_grid: GridContainer = %CardGrid
@onready var count_label: Label = %CountLabel
@onready var title_label: Label = %Title

var _selectable := false
var _title := "YOUR DECK"
var _eligible := func(_index: int, _card: CardData) -> bool: return true


func set_picker(title: String, eligible: Callable) -> void:
	_selectable = true
	_title = title
	_eligible = eligible


func _ready() -> void:
	title_label.text = _title
	count_label.text = "%d cards" % RunState.deck.size()
	for i in RunState.deck.size():
		var definition: CardData = RunState.deck[i]
		var card_view: CardView = CARD_VIEW_SCENE.instantiate()
		card_grid.add_child(card_view)
		card_view.display(CardInstance.new(definition))
		if _selectable:
			var ok: bool = _eligible.call(i, definition)
			card_view.set_playable(ok)
			if ok:
				card_view.selected.connect(func(_card): card_selected.emit(i))
		else:
			card_view.set_preview_mode()


func _on_close_button_pressed() -> void:
	queue_free()
```

- [ ] **Step 5: Import + run test**

Import + run card_picker_test — Expected: PASS. Also re-run `map_screen_test.gd` and `relic_test.gd` (both instantiate `deck_viewer` in preview mode via "View Deck") — PASS.

- [ ] **Step 6: Commit**

```bash
git -C FirstGame/first-game add screens/deck_viewer.gd screens/deck_viewer.tscn tests/card_picker_test.gd
git -C FirstGame/first-game commit -m "feat: selectable card picker mode for deck viewer"
```

---

### Task 6: Rest screen

**Files:**
- Create: `screens/rest_screen.tscn`, `screens/rest_screen.gd`
- Test: `tests/rest_screen_test.gd` (new)

**Interfaces:**
- Consumes: `RunState.heal_rest()`, `RunState.upgrade_card(index)` (Task 3); `DeckViewer.set_picker`/`card_selected` (Task 5).
- Produces: `res://screens/rest_screen.tscn` (routed to from the map in Task 8).

- [ ] **Step 1: Create the scene**

Create `screens/rest_screen.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://screens/rest_screen.gd" id="1"]

[node name="RestScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
color = Color(0.055, 0.071, 0.11, 1)

[node name="Center" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Content" type="VBoxContainer" parent="Center"]
custom_minimum_size = Vector2(420, 0)
layout_mode = 2
theme_override_constants/separation = 20
alignment = 1

[node name="Title" type="Label" parent="Center/Content"]
layout_mode = 2
theme_override_font_sizes/font_size = 40
text = "Rest Site"
horizontal_alignment = 1

[node name="RestButton" type="Button" parent="Center/Content"]
custom_minimum_size = Vector2(300, 54)
layout_mode = 2
mouse_default_cursor_shape = 2
text = "Rest — heal 30% HP"

[node name="UpgradeButton" type="Button" parent="Center/Content"]
custom_minimum_size = Vector2(300, 54)
layout_mode = 2
mouse_default_cursor_shape = 2
text = "Upgrade a card"

[connection signal="pressed" from="Center/Content/RestButton" to="." method="_on_rest_button_pressed"]
[connection signal="pressed" from="Center/Content/UpgradeButton" to="." method="_on_upgrade_button_pressed"]
```

- [ ] **Step 2: Write the script**

Create `screens/rest_screen.gd`:
```gdscript
extends Control

const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")


func _ready() -> void:
	RunState.ensure_run_started()
	AudioManager.play_game_music()


func _on_rest_button_pressed() -> void:
	AudioManager.play_ui_click()
	RunState.heal_rest()
	SceneTransition.transition_to("res://screens/map_screen.tscn")


func _on_upgrade_button_pressed() -> void:
	if get_node_or_null("Picker"):
		return
	AudioManager.play_ui_click()
	var picker := DECK_VIEWER_SCENE.instantiate()
	picker.name = "Picker"
	picker.set_picker("Upgrade a card", func(_index, card): return card.upgrade_id != &"")
	picker.card_selected.connect(_on_card_to_upgrade)
	add_child(picker)


func _on_card_to_upgrade(deck_index: int) -> void:
	RunState.upgrade_card(deck_index)
	SceneTransition.transition_to("res://screens/map_screen.tscn")
```

- [ ] **Step 3: Write the smoke test**

Create `tests/rest_screen_test.gd`:
```gdscript
extends SceneTree

var failures := 0
var _scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_scene = load("res://screens/rest_screen.tscn")
	await _test_builds_and_upgrade_picker_filters()
	if failures == 0:
		print("Rest screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_builds_and_upgrade_picker_filters() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()
	root.size = Vector2i(1280, 720)
	var screen := _scene.instantiate()
	root.add_child(screen)
	await process_frame
	_expect(screen.get_node_or_null("Center/Content/RestButton") != null, "Rest button present.")
	_expect(screen.get_node_or_null("Center/Content/UpgradeButton") != null, "Upgrade button present.")
	# Opening the upgrade picker builds a picker whose cards are all upgradable (starters are).
	screen._on_upgrade_button_pressed()
	await process_frame
	await process_frame
	var picker := screen.get_node_or_null("Picker")
	_expect(picker != null, "Upgrade opens a picker.")
	if picker != null:
		var grid := picker.get_node("%CardGrid")
		for card_view in grid.get_children():
			_expect(not card_view.select_button.disabled, "Starter deck cards are all upgradable.")
	screen.queue_free()
	var audio_manager := root.get_node("AudioManager")
	audio_manager.music_player.stop()
	audio_manager.music_player.stream = null
	OS.delay_msec(150)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 4: Import + run (verify fail then pass)**

Run before the scene/script exist → FAIL; after creating them + `--import` → PASS ("Rest screen tests passed.").
```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/rest_screen_test.gd
```

- [ ] **Step 5: Commit**

```bash
git -C FirstGame/first-game add screens/rest_screen.tscn screens/rest_screen.gd tests/rest_screen_test.gd
git -C FirstGame/first-game commit -m "feat: rest screen (heal or upgrade)"
```

---

### Task 7: Shop screen

**Files:**
- Create: `screens/shop_screen.tscn`, `screens/shop_screen.gd`
- Test: `tests/shop_screen_test.gd` (new)

**Interfaces:**
- Consumes: `RunState.buy_card`/`buy_relic`/`purchase_removal`/`gold`, price consts (Task 3); `DeckViewer.set_picker`/`card_selected` (Task 5).
- Produces: `res://screens/shop_screen.tscn` (routed to from the map in Task 8).

- [ ] **Step 1: Create the scene**

Create `screens/shop_screen.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://screens/shop_screen.gd" id="1"]

[node name="ShopScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
color = Color(0.055, 0.071, 0.11, 1)

[node name="Margin" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 40
theme_override_constants/margin_top = 28
theme_override_constants/margin_right = 40
theme_override_constants/margin_bottom = 28

[node name="Content" type="VBoxContainer" parent="Margin"]
layout_mode = 2
theme_override_constants/separation = 18

[node name="Header" type="HBoxContainer" parent="Margin/Content"]
layout_mode = 2

[node name="Title" type="Label" parent="Margin/Content/Header"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_font_sizes/font_size = 36
text = "Shop"

[node name="GoldLabel" type="Label" parent="Margin/Content/Header"]
unique_name_in_owner = true
layout_mode = 2
theme_override_colors/font_color = Color(0.95, 0.85, 0.35, 1)
theme_override_font_sizes/font_size = 28
text = "Gold: 0"

[node name="CardsLabel" type="Label" parent="Margin/Content"]
layout_mode = 2
text = "Cards"

[node name="CardRow" type="HBoxContainer" parent="Margin/Content"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 20

[node name="RelicsLabel" type="Label" parent="Margin/Content"]
layout_mode = 2
text = "Relics"

[node name="RelicRow" type="HBoxContainer" parent="Margin/Content"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 20

[node name="Footer" type="HBoxContainer" parent="Margin/Content"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="RemoveButton" type="Button" parent="Margin/Content/Footer"]
unique_name_in_owner = true
custom_minimum_size = Vector2(240, 48)
layout_mode = 2
mouse_default_cursor_shape = 2
text = "Remove a card (75)"

[node name="LeaveButton" type="Button" parent="Margin/Content/Footer"]
custom_minimum_size = Vector2(180, 48)
layout_mode = 2
mouse_default_cursor_shape = 2
text = "Leave"

[connection signal="pressed" from="Margin/Content/Footer/RemoveButton" to="." method="_on_remove_button_pressed"]
[connection signal="pressed" from="Margin/Content/Footer/LeaveButton" to="." method="_on_leave_button_pressed"]
```

- [ ] **Step 2: Write the script**

Create `screens/shop_screen.gd`:
```gdscript
extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")
const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")
const CARD_STOCK := 3
const RELIC_STOCK := 2
const CARD_POOL: Array[CardData] = [
	preload("res://cards/definitions/guarded_strike.tres"),
	preload("res://cards/definitions/power_blow.tres"),
	preload("res://cards/definitions/quick_guard.tres"),
	preload("res://cards/definitions/fortify.tres"),
	preload("res://cards/definitions/second_wind.tres"),
	preload("res://cards/definitions/devour.tres"),
	preload("res://cards/definitions/mend.tres"),
	preload("res://cards/definitions/bulwark.tres"),
	preload("res://cards/definitions/rally.tres"),
	preload("res://cards/definitions/expose.tres"),
	preload("res://cards/definitions/sap.tres"),
	preload("res://cards/definitions/flex.tres"),
	preload("res://cards/definitions/venom_cut.tres"),
]
const RELIC_POOL: Array[RelicData] = [
	preload("res://relics/definitions/stone_heart.tres"),
	preload("res://relics/definitions/battle_fervor.tres"),
	preload("res://relics/definitions/everflow_battery.tres"),
	preload("res://relics/definitions/scrying_lens.tres"),
]

@onready var gold_label: Label = %GoldLabel
@onready var card_row: HBoxContainer = %CardRow
@onready var relic_row: HBoxContainer = %RelicRow
@onready var remove_button: Button = %RemoveButton

var _card_buttons: Array[Button] = []
var _relic_buttons: Array[Button] = []


func _ready() -> void:
	RunState.ensure_run_started()
	AudioManager.play_game_music()
	_build_cards()
	_build_relics()
	_refresh_affordability()


func _build_cards() -> void:
	var pool := CARD_POOL.duplicate()
	pool.shuffle()
	for definition in pool.slice(0, CARD_STOCK):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var view: CardView = CARD_VIEW_SCENE.instantiate()
		box.add_child(view)
		view.display(CardInstance.new(definition))
		view.set_preview_mode()
		var buy := Button.new()
		buy.text = "Buy (%d)" % RunState.SHOP_CARD_PRICE
		buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		buy.pressed.connect(_on_buy_card.bind(definition, buy))
		box.add_child(buy)
		card_row.add_child(box)
		_card_buttons.append(buy)


func _build_relics() -> void:
	var pool := RELIC_POOL.duplicate()
	pool.shuffle()
	for relic in pool.slice(0, RELIC_STOCK):
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(200, 0)
		box.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = relic.display_name
		name_label.add_theme_color_override("font_color", Color(0.96, 0.79, 0.47))
		box.add_child(name_label)
		var desc := Label.new()
		desc.text = relic.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.custom_minimum_size = Vector2(200, 0)
		box.add_child(desc)
		var buy := Button.new()
		buy.text = "Buy (%d)" % RunState.SHOP_RELIC_PRICE
		buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		buy.pressed.connect(_on_buy_relic.bind(relic, buy))
		box.add_child(buy)
		relic_row.add_child(box)
		_relic_buttons.append(buy)


func _on_buy_card(definition: CardData, button: Button) -> void:
	if RunState.buy_card(definition):
		AudioManager.play_card()
		button.text = "Sold"
		button.disabled = true
		_refresh_affordability()


func _on_buy_relic(relic: RelicData, button: Button) -> void:
	if RunState.buy_relic(relic):
		AudioManager.play_card()
		button.text = "Sold"
		button.disabled = true
		_refresh_affordability()


func _on_remove_button_pressed() -> void:
	if get_node_or_null("Picker") or RunState.gold < RunState.SHOP_REMOVE_PRICE or RunState.deck.size() <= 1:
		return
	AudioManager.play_ui_click()
	var picker := DECK_VIEWER_SCENE.instantiate()
	picker.name = "Picker"
	picker.set_picker("Remove a card (%d gold)" % RunState.SHOP_REMOVE_PRICE,
		func(_index, _card): return true)
	picker.card_selected.connect(_on_card_to_remove)
	add_child(picker)


func _on_card_to_remove(deck_index: int) -> void:
	if RunState.purchase_removal(deck_index):
		AudioManager.play_card()
	var picker := get_node_or_null("Picker")
	if picker != null:
		picker.queue_free()
	_refresh_affordability()


func _on_leave_button_pressed() -> void:
	AudioManager.play_ui_click()
	SceneTransition.transition_to("res://screens/map_screen.tscn")


func _refresh_affordability() -> void:
	gold_label.text = "Gold: %d" % RunState.gold
	for button in _card_buttons:
		if button.text != "Sold":
			button.disabled = RunState.gold < RunState.SHOP_CARD_PRICE
	for button in _relic_buttons:
		if button.text != "Sold":
			button.disabled = RunState.gold < RunState.SHOP_RELIC_PRICE
	remove_button.disabled = RunState.gold < RunState.SHOP_REMOVE_PRICE or RunState.deck.size() <= 1
```

- [ ] **Step 3: Write the smoke test**

Create `tests/shop_screen_test.gd`:
```gdscript
extends SceneTree

var failures := 0
var _scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_scene = load("res://screens/shop_screen.tscn")
	await _test_buy_and_affordability()
	if failures == 0:
		print("Shop screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_buy_and_affordability() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()
	rs.gold = 50   # affords exactly one card, no relic
	root.size = Vector2i(1280, 720)
	var screen := _scene.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	_expect(screen._card_buttons.size() == 3, "Shop stocks 3 cards.")
	_expect(not screen._card_buttons[0].disabled, "Card affordable at 50 gold.")
	_expect(screen._relic_buttons[0].disabled, "Relic (140) unaffordable at 50 gold.")
	var deck_before: int = rs.deck.size()
	screen._on_buy_card(RunState.RALLY_CARD, screen._card_buttons[0])
	await process_frame
	_expect(rs.deck.size() == deck_before + 1, "Buying a card adds it to the deck.")
	_expect(rs.gold == 0, "Buying spent the gold.")
	_expect(screen._card_buttons[1].disabled, "Other cards now unaffordable at 0 gold.")
	screen.queue_free()
	var audio_manager := root.get_node("AudioManager")
	audio_manager.music_player.stop()
	audio_manager.music_player.stream = null
	OS.delay_msec(150)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 4: Import + run (fail then pass)**

Import + run shop_screen_test — Expected: PASS ("Shop screen tests passed.").

- [ ] **Step 5: Commit**

```bash
git -C FirstGame/first-game add screens/shop_screen.tscn screens/shop_screen.gd tests/shop_screen_test.gd
git -C FirstGame/first-game commit -m "feat: shop screen (buy cards/relics, remove a card)"
```

---

### Task 8: Wire the map to shop/rest + gold displays

**Files:**
- Modify: `screens/map_screen.gd` (routing, gold label), `screens/map_screen.tscn` (gold label node)
- Modify: `systems/run_state.gd` (remove now-dead `apply_rest`)
- Modify: `combat/combat_screen.gd:102` (gold in HUD line)

**Interfaces:**
- Consumes: `RunState.commit_pending_node`, `RunState.gold`, `rest_screen.tscn`, `shop_screen.tscn`.

- [ ] **Step 1: Route rest/shop from the map (commit on entry)**

In `screens/map_screen.gd`, replace `_on_node_pressed` (lines 107–114):
```gdscript
func _on_node_pressed(id: int) -> void:
	AudioManager.play_ui_click()
	var node := RunState.begin_node(id)
	match node.type:
		MapNode.Type.REST:
			RunState.commit_pending_node()
			SceneTransition.transition_to("res://screens/rest_screen.tscn")
		MapNode.Type.SHOP:
			RunState.commit_pending_node()
			SceneTransition.transition_to("res://screens/shop_screen.tscn")
		_:
			SceneTransition.transition_to("res://combat/combat_screen.tscn")
```

- [ ] **Step 2: Add a gold label to the map screen**

In `screens/map_screen.tscn`, add a node after `HealthLabel` (sibling, same left column):
```
[node name="GoldLabel" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 24.0
offset_top = 78.0
offset_right = 400.0
offset_bottom = 100.0
theme_override_colors/font_color = Color(0.95, 0.85, 0.35, 1)
```
And nudge the `Legend` node down so it doesn't overlap: change its `offset_top` from `100.0` to `112.0` and `offset_bottom` from `264.0` to `276.0`.

In `screens/map_screen.gd`, add the onready var (after `health_label`):
```gdscript
@onready var gold_label: Label = %GoldLabel
```
And set it in `_ready()` after the health line:
```gdscript
	gold_label.text = "Gold: %d" % RunState.gold
```

- [ ] **Step 3: Remove the dead `apply_rest`**

In `systems/run_state.gd`, delete the entire `apply_rest()` function (it is no longer called — rest now commits on entry via `commit_pending_node` and heals via `heal_rest`).

- [ ] **Step 4: Show gold in the combat HUD**

In `combat/combat_screen.gd`, replace line 102:
```gdscript
	encounter_label.text = "Gold: %d  |  Deck: %d cards" % [RunState.gold, RunState.deck.size()]
```

- [ ] **Step 5: Import + run the full suite**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
for t in combat_state enemy_ai relic map_generation map_screen economy upgrade_catalog card_picker rest_screen shop_screen; do
  ./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script "res://tests/${t}_test.gd"
done
```
Expected: every script prints its "... passed." line and exits 0. (Some test files are named `<name>_test.gd`; confirm each ran.)

- [ ] **Step 6: Static check for dead references**

Confirm no remaining `apply_rest` references:
Run: `grep -rn "apply_rest" FirstGame/first-game --include=*.gd`
Expected: no matches.

- [ ] **Step 7: Manual playthrough (human — headless can't cover it)**

Run: `./Godot_v4.7-stable_win64_console.exe --path FirstGame/first-game`
Verify: gold shows on map/combat/shop and rises after wins; a SHOP node exists each run and is reachable; buying a card/relic deducts gold and disables when broke; "Remove a card" (75) removes a chosen card and can't remove your last; a REST node offers Heal or Upgrade, upgrade swaps a card to its `+`; entering shop/rest then leaving returns to the map on the next row; quitting mid-shop/rest and resuming lands on the map (node already spent). Note anything off.

- [ ] **Step 8: Commit**

```bash
git -C FirstGame/first-game add screens/map_screen.gd screens/map_screen.tscn systems/run_state.gd combat/combat_screen.gd
git -C FirstGame/first-game commit -m "feat: wire map to shop/rest screens + gold displays"
```

---

## Self-Review

**Spec coverage:**
- Gold field + sources + save v5 → Task 1. ✓
- Upgrade representation (separate `+` defs, `upgrade_id`, one-level) → Task 2. ✓
- Deck-sculpt mechanics (upgrade/remove/buy) + commit model → Task 3. ✓
- SHOP node + gen + guaranteed shop + `from_dict` → Task 4. ✓
- Card picker (selectable deck viewer) → Task 5. ✓
- Rest choice screen (heal/upgrade) → Task 6. ✓
- Shop screen (cards/relics/removal, prices, disable states) → Task 7. ✓
- Map routing (commit-on-entry) + gold displays (map/combat/shop) → Task 8 (+ Task 7 shop gold). ✓
- Save v5 fail-safe + gold round-trip → Task 1 (+ upgraded-card id round-trip in Task 3). ✓
- Deferred (potions, escalating removal, `++`, boss gold, events) → not implemented. ✓

**Placeholder scan:** none — every code/`.tres` step gives full content or exact field-level values; commands include expected output. The 16 `+` files use one full template + an exact per-file value table (every changed field specified).

**Type consistency:** `upgrade_card(deck_index)`, `purchase_removal(deck_index)`, `buy_card(def)`, `buy_relic(relic)`, `heal_rest()`, `commit_pending_node()`, `add_gold`/`spend_gold`, `SHOP_CARD_PRICE`/`SHOP_REMOVE_PRICE`/`SHOP_RELIC_PRICE`, `DeckViewer.set_picker(title, eligible)` + `card_selected(deck_index)`, `MapNode.Type.SHOP` — all names/signatures consistent across tasks. Rest/shop screens consume exactly the RunState API defined in Tasks 1/3 and the picker API from Task 5.
