# Branching Map (Milestone 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the linear 5-encounter run with a seeded, navigable branching map (7 rows; combat / elite / rest / boss nodes).

**Architecture:** Two pure `RefCounted` classes (`MapNode`, `GameMap`) hold the graph + generation + serialization, mirroring `CombatState`/`Deck`. `RunState` swaps its linear `encounter_number`/`ENCOUNTERS` for a `GameMap` plus enemy pools and an `ENEMY_CATALOG`. A new `map_screen` scene is the hub the player returns to between nodes.

**Tech Stack:** Godot 4.7, typed GDScript. Tests are plain `extends SceneTree` scripts under `tests/` (no framework); `quit(failures)`.

## Global Constraints

- Typed GDScript throughout — type annotations on all vars, params, returns.
- Never mutate `.tres` definitions; they are shared immutable data.
- Never call `change_scene_to_file` directly — use `SceneTransition.transition_to(path)`.
- Combat logic stays pure/headless in `CombatState`; screens only animate/route.
- New `class_name` globals (`MapNode`, `GameMap`) do NOT resolve in headless `--script` tests until an `--import` run registers them. Run `--import` before running tests that reference them.
- `extends SceneTree` tests cannot call autoload **instance** methods bare — fetch the singleton via `root.get_node("RunState")`. Class consts (`RunState.SAVE_VERSION`, etc.) resolve fine.
- Adding a new enemy requires registering its id in `ENEMY_CATALOG`, matching the existing `CARD_CATALOG`/`RELIC_CATALOG` pattern.
- Run the editor from the repo root: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game ...`

---

### Task 1: `MapNode` + seeded `GameMap.generate()`

**Files:**
- Create: `FirstGame/first-game/systems/map_node.gd`
- Create: `FirstGame/first-game/systems/game_map.gd`
- Test: `FirstGame/first-game/tests/map_generation_test.gd`

**Interfaces:**
- Produces:
  - `class_name MapNode extends RefCounted` with `enum Type { COMBAT, ELITE, REST, BOSS }` and vars `id: int`, `type: Type`, `row: int`, `column: int`, `edges: Array[int]`, `enemy_id: StringName`.
  - `class_name GameMap extends RefCounted` with `var nodes: Array[MapNode]`, `var current_node_id: int` and `static func generate(rng: RandomNumberGenerator, normal_ids: Array[StringName], elite_ids: Array[StringName], boss_id: StringName) -> GameMap`.
  - `GameMap` constants: `CHOICE_ROWS := 6` (rows 0–5), so the boss occupies row 6 and the map has 7 rows total.

- [ ] **Step 1: Create `MapNode`**

```gdscript
# systems/map_node.gd
class_name MapNode
extends RefCounted

enum Type { COMBAT, ELITE, REST, BOSS }

var id: int = -1
var type: Type = Type.COMBAT
var row: int = 0
var column: int = 0
var edges: Array[int] = []       # ids of reachable nodes in the next row
var enemy_id: StringName = &""    # set for COMBAT/ELITE/BOSS; &"" for REST
```

- [ ] **Step 2: Write the failing generation test**

```gdscript
# tests/map_generation_test.gd
extends SceneTree

var failures := 0

const NORMALS: Array[StringName] = [&"n_a", &"n_b", &"n_c"]
const ELITES: Array[StringName] = [&"e_a"]
const BOSS_ID: StringName = &"boss"


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_structure()
	_test_type_placement_rules()
	_test_reachability_and_no_dead_ends()
	_test_no_crossing_edges()
	_test_enemy_ids_assigned()
	_test_seed_is_deterministic()
	if failures == 0:
		print("Map generation tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _map(seed_value: int = 1) -> GameMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GameMap.generate(rng, NORMALS, ELITES, BOSS_ID)


func _test_structure() -> void:
	var map := _map()
	var max_row := 0
	var boss_nodes := 0
	for node in map.nodes:
		max_row = maxi(max_row, node.row)
		if node.type == MapNode.Type.BOSS:
			boss_nodes += 1
	_expect(max_row == 6, "Map should have 7 rows (top row index 6).")
	_expect(boss_nodes == 1, "Map should have exactly one boss node.")
	for node in map.nodes:
		if node.type == MapNode.Type.BOSS:
			_expect(node.row == 6, "Boss must be on the top row.")
	_expect(map.current_node_id == -1, "A fresh map starts before any node.")


func _test_type_placement_rules() -> void:
	var map := _map()
	for node in map.nodes:
		if node.row == 0:
			_expect(node.type == MapNode.Type.COMBAT, "Row 0 must be all combat.")
		if node.row == 5:
			_expect(node.type == MapNode.Type.REST, "Row 5 (pre-boss) must be all rest.")
		if node.type == MapNode.Type.ELITE:
			_expect(node.row >= 2 and node.row <= 4, "Elites only on rows 2-4.")


func _test_reachability_and_no_dead_ends() -> void:
	var map := _map()
	# BFS from all row-0 nodes; every node must be visited.
	var frontier: Array[int] = []
	for node in map.nodes:
		if node.row == 0:
			frontier.append(node.id)
	var seen := {}
	while not frontier.is_empty():
		var id: int = frontier.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for e in map.get_node_by_id(id).edges:
			frontier.append(e)
	for node in map.nodes:
		_expect(seen.has(node.id), "Every node must be reachable from row 0.")
		if node.type != MapNode.Type.BOSS:
			_expect(not node.edges.is_empty(), "Non-boss nodes must have an outgoing edge.")


func _test_no_crossing_edges() -> void:
	# Each node's edge targets, in id order, must be non-decreasing in column,
	# and later siblings must not point to earlier columns (monotone => no crossing).
	var map := _map()
	var by_row := {}
	for node in map.nodes:
		by_row.get_or_add(node.row, []).append(node)
	for row_value in by_row:
		var row_nodes: Array = by_row[row_value]
		row_nodes.sort_custom(func(a, b): return a.column < b.column)
		var last_max := -1
		for node in row_nodes:
			var cols: Array[int] = []
			for e in node.edges:
				cols.append(map.get_node_by_id(e).column)
			cols.sort()
			if not cols.is_empty():
				_expect(cols[0] >= last_max, "Edges must not cross between siblings.")
				last_max = cols[cols.size() - 1]


func _test_enemy_ids_assigned() -> void:
	var map := _map()
	for node in map.nodes:
		match node.type:
			MapNode.Type.COMBAT:
				_expect(NORMALS.has(node.enemy_id), "Combat node needs a normal enemy id.")
			MapNode.Type.ELITE:
				_expect(ELITES.has(node.enemy_id), "Elite node needs an elite enemy id.")
			MapNode.Type.BOSS:
				_expect(node.enemy_id == BOSS_ID, "Boss node needs the boss enemy id.")
			MapNode.Type.REST:
				_expect(node.enemy_id == &"", "Rest node must have no enemy id.")


func _test_seed_is_deterministic() -> void:
	_expect(_map(42).to_dict() == _map(42).to_dict(), "Same seed must produce the same map.")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd`
Expected: FAIL — `GameMap` not found / parse errors (class not yet defined).

- [ ] **Step 4: Implement `GameMap` generation**

```gdscript
# systems/game_map.gd
class_name GameMap
extends RefCounted

const CHOICE_ROWS := 6   # rows 0..5; boss occupies row 6 -> 7 rows total

var nodes: Array[MapNode] = []
var current_node_id: int = -1


static func generate(
	rng: RandomNumberGenerator,
	normal_ids: Array[StringName],
	elite_ids: Array[StringName],
	boss_id: StringName,
) -> GameMap:
	var map := GameMap.new()
	var rows: Array = []          # rows[r] = Array[MapNode]
	var next_id := 0

	# Choice rows 0..CHOICE_ROWS-1
	for r in CHOICE_ROWS:
		var width := rng.randi_range(2, 4)
		var row_nodes: Array[MapNode] = []
		for c in width:
			var node := MapNode.new()
			node.id = next_id
			next_id += 1
			node.row = r
			node.column = c
			node.type = GameMap._roll_type(rng, r)
			row_nodes.append(node)
		rows.append(row_nodes)

	# Boss row
	var boss := MapNode.new()
	boss.id = next_id
	next_id += 1
	boss.row = CHOICE_ROWS
	boss.column = 0
	boss.type = MapNode.Type.BOSS
	boss.enemy_id = boss_id
	rows.append([boss] as Array[MapNode])

	# Assign enemies to choice-row nodes
	for r in CHOICE_ROWS:
		for node in rows[r]:
			match node.type:
				MapNode.Type.COMBAT:
					node.enemy_id = normal_ids[rng.randi_range(0, normal_ids.size() - 1)]
				MapNode.Type.ELITE:
					node.enemy_id = elite_ids[rng.randi_range(0, elite_ids.size() - 1)]
				_:
					node.enemy_id = &""

	# Connect adjacent rows (monotone staircase => no crossing, full coverage)
	for r in range(rows.size() - 1):
		GameMap._connect_rows(rows[r], rows[r + 1])

	for r in rows:
		for node in r:
			map.nodes.append(node)
	map.current_node_id = -1
	return map


static func _roll_type(rng: RandomNumberGenerator, row: int) -> MapNode.Type:
	if row == 0:
		return MapNode.Type.COMBAT
	if row == CHOICE_ROWS - 1:
		return MapNode.Type.REST
	var roll := rng.randf()
	if roll < 0.15:
		return MapNode.Type.REST
	if roll < 0.40 and row >= 2:
		return MapNode.Type.ELITE
	return MapNode.Type.COMBAT


static func _connect_rows(upper: Array, lower: Array) -> void:
	var u := upper.size()
	var l := lower.size()
	var i := 0
	var j := 0
	while i < u and j < l:
		GameMap._add_edge(upper[i], lower[j])
		var up_ratio := float(i + 1) / u
		var low_ratio := float(j + 1) / l
		if up_ratio < low_ratio:
			i += 1
		elif up_ratio > low_ratio:
			j += 1
		else:
			i += 1
			j += 1
	while i < u:
		GameMap._add_edge(upper[i], lower[l - 1])
		i += 1
	while j < l:
		GameMap._add_edge(upper[u - 1], lower[j])
		j += 1
	for node in upper:
		node.edges.sort()   # ids increase with column within a row -> column order


static func _add_edge(from_node: MapNode, to_node: MapNode) -> void:
	if not from_node.edges.has(to_node.id):
		from_node.edges.append(to_node.id)


func get_node_by_id(id: int) -> MapNode:
	for node in nodes:
		if node.id == id:
			return node
	return null


func to_dict() -> Dictionary:
	var node_dicts: Array = []
	for node in nodes:
		node_dicts.append({
			"id": node.id,
			"type": int(node.type),
			"row": node.row,
			"column": node.column,
			"edges": node.edges.duplicate(),
			"enemy_id": String(node.enemy_id),
		})
	return {"current_node_id": current_node_id, "nodes": node_dicts}
```

> Note: `to_dict()` is used by the determinism test now; `from_dict()` and navigation land in Task 2.

- [ ] **Step 5: Register the new class_name globals**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import`
Expected: exits cleanly; `MapNode`/`GameMap` now resolve bare in `--script` tests.

- [ ] **Step 6: Run the test to verify it passes**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd`
Expected: PASS — prints "Map generation tests passed.", exit code 0.

- [ ] **Step 7: Commit**

```bash
git -C FirstGame/first-game add systems/map_node.gd systems/game_map.gd tests/map_generation_test.gd
git -C FirstGame/first-game commit -m "feat: MapNode + seeded GameMap.generate with structure tests"
```

---

### Task 2: `GameMap` navigation + serialization

**Files:**
- Modify: `FirstGame/first-game/systems/game_map.gd`
- Test: `FirstGame/first-game/tests/map_generation_test.gd`

**Interfaces:**
- Consumes: `GameMap`, `MapNode` from Task 1.
- Produces:
  - `func get_available_node_ids() -> Array[int]` — row-0 ids when `current_node_id == -1`, else the current node's `edges`.
  - `func enter(id: int) -> bool` — commits `current_node_id = id` iff `id` is currently available; returns success.
  - `static func from_dict(data: Dictionary) -> GameMap` — rebuilds a map; returns `null` on malformed data (does NOT validate enemy ids against a catalog — that is `RunState`'s job in Task 3).

- [ ] **Step 1: Add the failing navigation + round-trip tests**

Add these calls inside `_run_tests()` (before the `if failures == 0` line):

```gdscript
	_test_navigation()
	_test_serialization_round_trip()
	_test_from_dict_rejects_malformed()
```

Add these methods to `tests/map_generation_test.gd`:

```gdscript
func _test_navigation() -> void:
	var map := _map()
	var start := map.get_available_node_ids()
	_expect(not start.is_empty(), "Start options should be the row-0 nodes.")
	for id in start:
		_expect(map.get_node_by_id(id).row == 0, "Start options must be on row 0.")
	var first: int = start[0]
	_expect(map.enter(first), "Entering an available node should succeed.")
	_expect(map.current_node_id == first, "Entering sets the current node.")
	_expect(map.get_available_node_ids() == map.get_node_by_id(first).edges,
		"After entering, options are that node's edges.")
	_expect(not map.enter(9999), "Entering an unreachable node must fail.")


func _test_serialization_round_trip() -> void:
	var map := _map(7)
	map.enter(map.get_available_node_ids()[0])
	var restored := GameMap.from_dict(map.to_dict())
	_expect(restored != null, "from_dict should rebuild a valid map.")
	_expect(restored.to_dict() == map.to_dict(), "Round-trip must preserve the map.")


func _test_from_dict_rejects_malformed() -> void:
	_expect(GameMap.from_dict({}) == null, "Empty dict is not a map.")
	_expect(GameMap.from_dict({"nodes": []}) == null, "A map needs nodes.")
	_expect(GameMap.from_dict({"nodes": [{"id": 0, "type": 99, "row": 0,
		"column": 0, "edges": [], "enemy_id": ""}], "current_node_id": -1}) == null,
		"An out-of-range node type must be rejected.")
```

- [ ] **Step 2: Run to verify failure**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd`
Expected: FAIL — `get_available_node_ids`/`enter`/`from_dict` not defined.

- [ ] **Step 3: Implement navigation + `from_dict`**

Append to `systems/game_map.gd`:

```gdscript
func get_available_node_ids() -> Array[int]:
	var ids: Array[int] = []
	if current_node_id == -1:
		for node in nodes:
			if node.row == 0:
				ids.append(node.id)
	else:
		var current := get_node_by_id(current_node_id)
		if current != null:
			ids = current.edges.duplicate()
	return ids


func enter(id: int) -> bool:
	if not get_available_node_ids().has(id):
		return false
	current_node_id = id
	return true


static func from_dict(data: Dictionary) -> GameMap:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var raw_nodes: Variant = data.get("nodes", [])
	if typeof(raw_nodes) != TYPE_ARRAY or raw_nodes.is_empty():
		return null
	var map := GameMap.new()
	for raw in raw_nodes:
		if typeof(raw) != TYPE_DICTIONARY:
			return null
		var node := MapNode.new()
		node.id = int(raw.get("id", -1))
		var type_value := int(raw.get("type", -1))
		if type_value < 0 or type_value > int(MapNode.Type.BOSS):
			return null
		node.type = type_value as MapNode.Type
		node.row = int(raw.get("row", 0))
		node.column = int(raw.get("column", 0))
		var raw_edges: Variant = raw.get("edges", [])
		if typeof(raw_edges) != TYPE_ARRAY:
			return null
		var edges: Array[int] = []
		for e in raw_edges:
			edges.append(int(e))
		node.edges = edges
		node.enemy_id = StringName(str(raw.get("enemy_id", "")))
		map.nodes.append(node)
	map.current_node_id = int(data.get("current_node_id", -1))
	if map.current_node_id != -1 and map.get_node_by_id(map.current_node_id) == null:
		return null
	return map
```

- [ ] **Step 4: Run to verify pass**

Run: `./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd`
Expected: PASS — "Map generation tests passed.", exit code 0.

- [ ] **Step 5: Commit**

```bash
git -C FirstGame/first-game add systems/game_map.gd tests/map_generation_test.gd
git -C FirstGame/first-game commit -m "feat: GameMap navigation + serialization"
```

---

### Task 3: `RunState` refactor to the map model

**Files:**
- Modify: `FirstGame/first-game/systems/run_state.gd`
- Modify: `FirstGame/first-game/tests/relic_test.gd`
- Modify: `FirstGame/first-game/tests/enemy_ai_test.gd:116-119`

**Interfaces:**
- Consumes: `GameMap`, `MapNode` (Tasks 1–2).
- Produces (new/changed `RunState` API relied on by combat + screens in Tasks 4–5):
  - `var map: GameMap`
  - `const ENEMY_CATALOG: Dictionary` (`StringName -> EnemyData`), `NORMAL_POOL`, `ELITE_POOL`, `BOSS_ENEMY`
  - `func begin_node(id: int) -> MapNode` — sets the transient `_pending_node_id`, returns the node.
  - `func apply_rest() -> void` — commits the pending rest node and heals 30% of max HP.
  - `func get_current_enemy() -> EnemyData` — resolves the pending node's `enemy_id`.
  - `func is_pending_boss() -> bool`, `func is_current_node_boss() -> bool`
  - `complete_combat`, `get_resume_scene`, `save_run`, `load_saved_run` updated; `SAVE_VERSION = 4`.
  - Removed: `encounter_number`, `ENCOUNTERS`, `is_final_encounter`.

- [ ] **Step 1: Update the failing `RunState` tests first (relic_test.gd)**

In `tests/relic_test.gd`, replace the version assertion in `_test_relic_catalog_complete` (line ~83):

```gdscript
	_expect(RunState.SAVE_VERSION == 4, "SAVE_VERSION should be 4.")
```

In `_test_unknown_relic_id_invalidates_save` (the `data` dict, ~line 111) drop the `encounter_number` key so the save shape matches v4:

```gdscript
	var data := {
		"version": RunState.SAVE_VERSION,
		"current_health": 40,
		"awaiting_reward": false,
		"awaiting_relic": false,
		"deck": ["strike", "strike", "defend", "defend", "heavy_strike"],
		"relics": ["not_a_real_relic"],
		"map": _run_state().map.to_dict(),
	}
```

> `start_new_run()` (called just above) generates `map`, so `_run_state().map` is valid here.

Replace `_test_elite_win_awaits_relic` and `_test_normal_win_awaits_card` entirely — they used `encounter_number`. Drive the map by id via a helper that finds a node of a given type:

```gdscript
func _test_elite_win_awaits_relic() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	# Elite nodes only exist on rows 2-4; a fresh map may or may not roll one.
	# Force a deterministic elite by entering a hand-built pending node instead.
	_enter_type(run_state, MapNode.Type.ELITE, &"dread_sentinel")
	_expect(run_state.get_current_enemy().is_elite, "Dread Sentinel should be flagged as elite.")
	run_state.complete_combat(30)
	_expect(run_state.awaiting_relic, "Beating the elite should set awaiting_relic.")
	_expect(not run_state.awaiting_reward, "Elite win should not set the card-reward flag.")
	_expect(run_state.get_resume_scene() == "res://screens/relic_reward.tscn",
		"awaiting_relic should resume to the relic-reward scene.")


func _test_normal_win_awaits_card() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	_enter_type(run_state, MapNode.Type.COMBAT, &"cinder_hound")
	run_state.complete_combat(30)
	_expect(run_state.awaiting_reward, "Beating a normal enemy should set awaiting_reward.")
	_expect(not run_state.awaiting_relic, "Normal win should not set the relic flag.")
	_expect(run_state.get_resume_scene() == "res://screens/map_screen.tscn",
		"After a card reward is pending, resume goes through the reward then the map.")


# Enters an available node, then rewrites it to the wanted type/enemy so the
# win-routing branches can be exercised without depending on random layout.
func _enter_type(run_state: Node, type: MapNode.Type, enemy_id: StringName) -> void:
	var start_id: int = run_state.map.get_available_node_ids()[0]
	var node: MapNode = run_state.map.get_node_by_id(start_id)
	node.type = type
	node.enemy_id = enemy_id
	run_state.begin_node(start_id)
```

- [ ] **Step 2: Update the failing `enemy_ai_test.gd` roster test**

Replace `_test_run_ends_on_boss` (lines 116–119) with a map-aware version:

```gdscript
func _test_run_ends_on_boss() -> void:
	_expect(RunState.NORMAL_POOL.size() == 3, "Normal pool should have three enemies.")
	_expect(RunState.BOSS_ENEMY == RunState.GRAVEMAW, "Boss enemy should be the Gravemaw.")
	_expect(RunState.SAVE_VERSION == 4, "Save version should be bumped to 4.")
```

- [ ] **Step 3: Run both tests to confirm they now fail against the old RunState**

Run:
```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/relic_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
```
Expected: FAIL — `SAVE_VERSION` still 3, `NORMAL_POOL`/`begin_node`/`map` undefined.

- [ ] **Step 4: Rewrite `RunState`**

Apply these edits to `systems/run_state.gd`.

(a) Bump the version and add the enemy catalog + pools. Replace line 3 and the `ENCOUNTERS` const (line 38):

```gdscript
const SAVE_VERSION := 4
```

Replace:
```gdscript
const ENCOUNTERS: Array[EnemyData] = [CINDER_HOUND, PLAGUE_CRAWLER, DREAD_SENTINEL, BONE_ACOLYTE, GRAVEMAW]
```
with:
```gdscript
const ENEMY_CATALOG := {
	&"cinder_hound": CINDER_HOUND,
	&"plague_crawler": PLAGUE_CRAWLER,
	&"bone_acolyte": BONE_ACOLYTE,
	&"dread_sentinel": DREAD_SENTINEL,
	&"gravemaw": GRAVEMAW,
}
const NORMAL_POOL: Array[EnemyData] = [CINDER_HOUND, PLAGUE_CRAWLER, BONE_ACOLYTE]
const ELITE_POOL: Array[EnemyData] = [DREAD_SENTINEL]
const BOSS_ENEMY := GRAVEMAW
```

(b) Replace the run-state vars (lines 58–65). Replace:
```gdscript
var encounter_number: int = 1
```
with:
```gdscript
var map: GameMap = null
var _pending_node_id: int = -1   # node being fought/rested; transient, not serialized
```

(c) Rewrite `start_new_run()` (lines 68–82). Replace the `encounter_number = 1` line and add map generation before `save_run()`:

```gdscript
func start_new_run() -> void:
	current_health = max_health
	run_complete = false
	awaiting_reward = false
	awaiting_relic = false
	relics = []
	deck = [
		STRIKE_CARD,
		STRIKE_CARD,
		DEFEND_CARD,
		DEFEND_CARD,
		HEAVY_STRIKE_CARD,
	]
	map = _generate_map()
	_pending_node_id = -1
	save_run()


func _generate_map() -> GameMap:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var normal_ids: Array[StringName] = []
	for enemy in NORMAL_POOL:
		normal_ids.append(enemy.id)
	var elite_ids: Array[StringName] = []
	for enemy in ELITE_POOL:
		elite_ids.append(enemy.id)
	return GameMap.generate(rng, normal_ids, elite_ids, BOSS_ENEMY.id)
```

(d) Rewrite `complete_combat` (lines 90–102):

```gdscript
func complete_combat(remaining_health: int) -> void:
	current_health = clampi(remaining_health, 0, max_health)
	map.enter(_pending_node_id)   # commit the fought node as the new position
	var node := map.get_node_by_id(_pending_node_id)
	if node.type == MapNode.Type.ELITE or node.type == MapNode.Type.BOSS:
		awaiting_relic = true
	else:
		awaiting_reward = true
	save_run()
```

(e) Add `begin_node` / `apply_rest` and rewrite `get_current_enemy`; delete `is_final_encounter`. Replace lines 117–123:

```gdscript
func begin_node(id: int) -> MapNode:
	_pending_node_id = id
	return map.get_node_by_id(id)


func apply_rest() -> void:
	map.enter(_pending_node_id)
	var heal := int(ceil(max_health * 0.30))
	current_health = clampi(current_health + heal, 0, max_health)
	save_run()


func get_current_enemy() -> EnemyData:
	var node := map.get_node_by_id(_pending_node_id)
	return ENEMY_CATALOG.get(node.enemy_id, null)


func is_pending_boss() -> bool:
	if map == null or _pending_node_id == -1:
		return false
	var node := map.get_node_by_id(_pending_node_id)
	return node != null and node.type == MapNode.Type.BOSS


func is_current_node_boss() -> bool:
	if map == null or map.current_node_id == -1:
		return false
	var node := map.get_node_by_id(map.current_node_id)
	return node != null and node.type == MapNode.Type.BOSS
```

(f) Rewrite `get_resume_scene()` (lines 130–135):

```gdscript
func get_resume_scene() -> String:
	if awaiting_relic:
		return "res://screens/relic_reward.tscn"
	if awaiting_reward:
		return "res://screens/card_reward.tscn"
	return "res://screens/map_screen.tscn"
```

(g) Update `save_run()` — drop `encounter_number`, add `map`. Replace the `save_data` dict (lines 147–155):

```gdscript
	var save_data := {
		"version": SAVE_VERSION,
		"current_health": current_health,
		"awaiting_reward": awaiting_reward,
		"awaiting_relic": awaiting_relic,
		"deck": card_ids,
		"relics": relic_ids,
		"map": map.to_dict() if map != null else {},
	}
```

(h) Update `load_saved_run()` — replace the encounter validation (lines 194–205) with map parsing + enemy-id validation. Replace:

```gdscript
	var saved_health := int(save_data.get("current_health", 0))
	var saved_encounter := int(save_data.get("encounter_number", 0))
	if saved_health <= 0 or saved_encounter < 1 or saved_encounter > ENCOUNTERS.size():
		clear_saved_run()
		return false

	current_health = clampi(saved_health, 1, max_health)
	encounter_number = saved_encounter
	awaiting_reward = bool(save_data.get("awaiting_reward", false))
	deck = loaded_deck
	relics = loaded_relics
	awaiting_relic = bool(save_data.get("awaiting_relic", false))
	run_complete = false
	return true
```

with:

```gdscript
	var saved_health := int(save_data.get("current_health", 0))
	if saved_health <= 0:
		clear_saved_run()
		return false

	var raw_map: Variant = save_data.get("map", {})
	if typeof(raw_map) != TYPE_DICTIONARY:
		clear_saved_run()
		return false
	var loaded_map := GameMap.from_dict(raw_map)
	if loaded_map == null:
		clear_saved_run()
		return false
	for node in loaded_map.nodes:
		if node.enemy_id != &"" and not ENEMY_CATALOG.has(node.enemy_id):
			clear_saved_run()
			return false

	current_health = clampi(saved_health, 1, max_health)
	map = loaded_map
	_pending_node_id = -1
	awaiting_reward = bool(save_data.get("awaiting_reward", false))
	deck = loaded_deck
	relics = loaded_relics
	awaiting_relic = bool(save_data.get("awaiting_relic", false))
	run_complete = false
	return true
```

- [ ] **Step 5: Import (new API on autoload) and run the tests**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/relic_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd
```
Expected: all three PASS (exit code 0). Also re-run `combat_state_test.gd` — expected PASS (untouched by this task).

- [ ] **Step 6: Commit**

```bash
git -C FirstGame/first-game add systems/run_state.gd tests/relic_test.gd tests/enemy_ai_test.gd
git -C FirstGame/first-game commit -m "feat: RunState uses GameMap instead of linear encounters (save v4)"
```

---

### Task 4: Map screen (hub scene)

**Files:**
- Create: `FirstGame/first-game/screens/map_screen.tscn`
- Create: `FirstGame/first-game/screens/map_screen.gd`
- Test: `FirstGame/first-game/tests/map_screen_test.gd`

**Interfaces:**
- Consumes: `RunState.map`, `RunState.begin_node`, `RunState.apply_rest`, `RunState.ENEMY_CATALOG`, `RunState.current_health/max_health` (Task 3).
- Produces: a scene at `res://screens/map_screen.tscn` that combat/reward/start flows (Task 5) transition to. Node buttons are stored in `_node_buttons: Dictionary` (id -> Button) for the smoke test.

> **Presentation note (deliberate):** the spec lists decorative glyphs (⚔ ☠ ✚ ♛). Godot's default font may not carry those code points (they would render as boxes), so this implementation uses **letters** `C / E / R / B` as the type glyph — the same three-cue design (letter + color + tooltip) with guaranteed rendering. Swapping in an icon font/art is a later polish task. `# ponytail:` letters over glyphs for font-safety; upgrade to icons when art lands.

- [ ] **Step 1: Create the scene**

Create `screens/map_screen.tscn` (minimal — the graph is built in code):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://screens/map_screen.gd" id="1"]

[node name="MapScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Title" type="Label" parent="."]
layout_mode = 0
offset_left = 24.0
offset_top = 16.0
offset_right = 400.0
offset_bottom = 44.0
text = "Choose your path"

[node name="HealthLabel" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 24.0
offset_top = 48.0
offset_right = 400.0
offset_bottom = 76.0

[node name="Legend" type="VBoxContainer" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_left = 24.0
offset_top = 96.0
offset_right = 220.0
offset_bottom = 260.0
```

- [ ] **Step 2: Write the map screen script**

Create `screens/map_screen.gd`:

```gdscript
extends Control

const NODE_SIZE := Vector2(56, 56)
const X0 := 220.0
const Y0 := 60.0
const X_GAP := 150.0
const Y_GAP := 84.0

const TYPE_LETTER := {
	MapNode.Type.COMBAT: "C",
	MapNode.Type.ELITE: "E",
	MapNode.Type.REST: "R",
	MapNode.Type.BOSS: "B",
}
const TYPE_COLOR := {
	MapNode.Type.COMBAT: Color(0.85, 0.30, 0.28),
	MapNode.Type.ELITE: Color(0.66, 0.40, 0.85),
	MapNode.Type.REST: Color(0.40, 0.80, 0.50),
	MapNode.Type.BOSS: Color(0.96, 0.79, 0.47),
}

@onready var health_label: Label = %HealthLabel
@onready var legend: VBoxContainer = %Legend

var _node_buttons: Dictionary = {}   # id -> Button


func _ready() -> void:
	RunState.ensure_run_started()
	AudioManager.play_game_music()
	health_label.text = "Health: %d / %d" % [RunState.current_health, RunState.max_health]
	_build_legend()
	_build_map()


func _build_legend() -> void:
	for pair in [
		[MapNode.Type.COMBAT, "Combat"],
		[MapNode.Type.ELITE, "Elite (relic)"],
		[MapNode.Type.REST, "Rest (heal 30%)"],
		[MapNode.Type.BOSS, "Boss"],
	]:
		var row := Label.new()
		row.text = "%s  —  %s" % [TYPE_LETTER[pair[0]], pair[1]]
		row.add_theme_color_override("font_color", TYPE_COLOR[pair[0]])
		legend.add_child(row)


func _build_map() -> void:
	var map: GameMap = RunState.map
	var available := map.get_available_node_ids()
	var top_row := 0
	for node in map.nodes:
		top_row = maxi(top_row, node.row)

	# Edges first, so buttons draw on top.
	for node in map.nodes:
		for target_id in node.edges:
			var target := map.get_node_by_id(target_id)
			var line := Line2D.new()
			line.width = 3.0
			line.default_color = Color(1, 1, 1, 0.22)
			line.add_point(_node_pos(node, top_row) + NODE_SIZE * 0.5)
			line.add_point(_node_pos(target, top_row) + NODE_SIZE * 0.5)
			add_child(line)

	for node in map.nodes:
		var button := Button.new()
		button.text = TYPE_LETTER[node.type]
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.position = _node_pos(node, top_row)
		button.tooltip_text = _tooltip(node)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_color_override("font_color", TYPE_COLOR[node.type])
		var reachable := available.has(node.id)
		button.disabled = not reachable
		button.modulate = Color(1, 1, 1, 1.0) if reachable else Color(1, 1, 1, 0.45)
		button.pressed.connect(_on_node_pressed.bind(node.id))
		add_child(button)
		_node_buttons[node.id] = button


func _node_pos(node: MapNode, top_row: int) -> Vector2:
	# Row 0 sits at the bottom; the boss (top_row) at the top.
	return Vector2(X0 + node.column * X_GAP, Y0 + (top_row - node.row) * Y_GAP)


func _tooltip(node: MapNode) -> String:
	match node.type:
		MapNode.Type.REST:
			return "Rest — heal 30% HP"
		MapNode.Type.ELITE:
			return "Elite — %s" % _enemy_name(node)
		MapNode.Type.BOSS:
			return "Boss — %s" % _enemy_name(node)
		_:
			return "Combat — %s" % _enemy_name(node)


func _enemy_name(node: MapNode) -> String:
	var enemy: EnemyData = RunState.ENEMY_CATALOG.get(node.enemy_id, null)
	return enemy.display_name if enemy != null else "Unknown"


func _on_node_pressed(id: int) -> void:
	AudioManager.play_ui_click()
	var node := RunState.begin_node(id)
	if node.type == MapNode.Type.REST:
		RunState.apply_rest()
		SceneTransition.transition_to("res://screens/map_screen.tscn")   # reload to refresh
	else:
		SceneTransition.transition_to("res://combat/combat_screen.tscn")
```

- [ ] **Step 3: Write the smoke test**

Create `tests/map_screen_test.gd`:

```gdscript
extends SceneTree

var failures := 0
const MAP_SCREEN := preload("res://screens/map_screen.tscn")


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_builds_a_button_per_node()
	if failures == 0:
		print("Map screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_builds_a_button_per_node() -> void:
	var run_state := root.get_node("RunState")
	run_state.start_new_run()
	root.size = Vector2i(1280, 720)
	var screen := MAP_SCREEN.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var expected: int = run_state.map.nodes.size()
	_expect(screen._node_buttons.size() == expected,
		"Map screen should build one button per node (%d)." % expected)
	# Row-0 nodes are the only enabled buttons at the start.
	var enabled := 0
	for id in screen._node_buttons:
		if not screen._node_buttons[id].disabled:
			enabled += 1
	_expect(enabled == run_state.map.get_available_node_ids().size(),
		"Only the currently-available nodes should be enabled.")
	screen.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
```

- [ ] **Step 4: Import and run the smoke test**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_screen_test.gd
```
Expected: PASS — "Map screen tests passed.", exit code 0.

- [ ] **Step 5: Commit**

```bash
git -C FirstGame/first-game add screens/map_screen.tscn screens/map_screen.gd tests/map_screen_test.gd
git -C FirstGame/first-game commit -m "feat: branching map hub screen"
```

---

### Task 5: Wire combat, rewards, and run start/end to the map

**Files:**
- Modify: `FirstGame/first-game/combat/combat_screen.gd:102,115-125,270-281`
- Modify: `FirstGame/first-game/screens/card_reward.gd:58-61`
- Modify: `FirstGame/first-game/screens/relic_reward.gd:67-69`
- Modify: `FirstGame/first-game/screens/main.gd:16-19`
- Modify: `FirstGame/first-game/screens/run_complete.gd:16-18`

**Interfaces:**
- Consumes: `RunState.get_resume_scene`, `RunState.is_pending_boss`, `RunState.is_current_node_boss`, `RunState.complete_combat`, `RunState.start_new_run` (Task 3); `res://screens/map_screen.tscn` (Task 4).

- [ ] **Step 1: Combat screen — drop the encounter counter label**

In `combat/combat_screen.gd`, replace line 102:

```gdscript
	encounter_label.text = "Deck: %d cards" % RunState.deck.size()
```

- [ ] **Step 2: Combat screen — victory button text by node type**

Replace lines 115–122 (the `if state.phase == CombatState.Phase.WON` block up to the `elif state.phase == LOST`):

```gdscript
	if state.phase == CombatState.Phase.WON:
		result_title.text = "VICTORY"
		if RunState.is_pending_boss() or enemy.is_elite:
			result_action_button.text = "Choose Relic"
		else:
			result_action_button.text = "Choose Card Reward"
```

- [ ] **Step 3: Combat screen — route win to the reward/map, loss to a fresh map**

Replace `_on_result_action_button_pressed()` (lines 270–281):

```gdscript
func _on_result_action_button_pressed() -> void:
	if state.phase == CombatState.Phase.WON:
		RunState.complete_combat(state.player_health)
		SceneTransition.transition_to(RunState.get_resume_scene())
	elif state.phase == CombatState.Phase.LOST:
		RunState.start_new_run()
		SceneTransition.transition_to("res://screens/map_screen.tscn")
```

> `get_resume_scene()` returns `relic_reward` (elite/boss), `card_reward` (normal), else the map. Loss regenerates the run and drops the player on a fresh map instead of re-entering combat with no pending node.

- [ ] **Step 4: Card reward — continue to the map**

In `screens/card_reward.gd`, replace `_on_continue_button_pressed` (lines 58–61):

```gdscript
func _on_continue_button_pressed() -> void:
	if reward_chosen:
		SceneTransition.transition_to("res://screens/map_screen.tscn")
```

- [ ] **Step 5: Relic reward — map, or run-complete after the boss**

In `screens/relic_reward.gd`, replace `_on_continue_button_pressed` (lines 67–69):

```gdscript
func _on_continue_button_pressed() -> void:
	if not reward_chosen:
		return
	if RunState.is_current_node_boss():
		RunState.clear_saved_run()
		SceneTransition.transition_to("res://screens/run_complete.tscn")
	else:
		SceneTransition.transition_to("res://screens/map_screen.tscn")
```

> `is_current_node_boss()` reads the committed `current_node_id`, so it survives a save/reload during the boss-relic claim.

- [ ] **Step 6: Title screen — start a new run on the map**

In `screens/main.gd`, replace `_on_start_pressed` (lines 16–19):

```gdscript
func _on_start_pressed() -> void:
	AudioManager.play_ui_click()
	RunState.start_new_run()
	SceneTransition.transition_to("res://screens/map_screen.tscn")
```

- [ ] **Step 7: Run-complete — "new run" goes to the map; fix stale copy**

In `screens/run_complete.gd`, replace the summary text (lines 10–13) and `_on_new_run_button_pressed` (lines 16–18):

```gdscript
	summary_label.text = "You conquered the map with %d health and a %d-card deck." % [
		RunState.current_health,
		RunState.deck.size(),
	]
```

```gdscript
func _on_new_run_button_pressed() -> void:
	RunState.start_new_run()
	SceneTransition.transition_to("res://screens/map_screen.tscn")
```

- [ ] **Step 8: Import, then verify the whole suite passes**

```
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --import
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/combat_state_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/enemy_ai_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/relic_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_generation_test.gd
./Godot_v4.7-stable_win64_console.exe --headless --path FirstGame/first-game --script res://tests/map_screen_test.gd
```
Expected: every script exits 0 ("... tests passed.").

- [ ] **Step 9: Manual playthrough (the one thing headless can't cover)**

Run: `./Godot_v4.7-stable_win64_console.exe --path FirstGame/first-game`
Verify: title → Start opens the map; row-0 nodes are the only clickable ones and are color/letter-coded; entering a combat node fights, wins route to a reward then back to the map with the next row unlocked; a rest node heals ~30% and returns to the map; reaching the boss fights, awards a relic, then shows run-complete; quitting mid-run and using Continue resumes on the map (or the pending reward). Confirm no node clips off-screen at 1280×720.

- [ ] **Step 10: Commit**

```bash
git -C FirstGame/first-game add combat/combat_screen.gd screens/card_reward.gd screens/relic_reward.gd screens/main.gd screens/run_complete.gd
git -C FirstGame/first-game commit -m "feat: wire combat/rewards/run flow through the branching map"
```

---

## Self-Review

**Spec coverage:**
- Node types (combat/elite/rest/boss) → Task 1 `_roll_type` + Task 3 routing + Task 4 presentation. ✓
- Rest heals 30% → Task 3 `apply_rest`. ✓
- Boss → relic → run-complete → Task 3 (`complete_combat` sets `awaiting_relic`) + Task 5 Step 5 (`is_current_node_boss`). ✓
- 7-row seeded StS-lite w/ placement rules → Task 1 `generate`/`_roll_type`/`_connect_rows`; determinism test. ✓
- Enemy pools + `ENEMY_CATALOG`, drop `ENCOUNTERS` → Task 3. ✓
- Map hub screen w/ three-cue node visuals + legend → Task 4 (letters substitute for glyphs, noted). ✓
- Save v4 (full graph), fail-safe validation → Task 3 (g)/(h). ✓
- Pure gen test suite → Tasks 1–2. ✓
- Deferred (shop/gold/events, row-scaled difficulty, art) → out of scope, not implemented. ✓

**Placeholder scan:** none — every code step carries full code; commands include expected output.

**Type consistency:** `begin_node`/`apply_rest`/`get_current_enemy`/`is_pending_boss`/`is_current_node_boss` names match across Tasks 3–5. `_pending_node_id` (RunState, transient) vs `current_node_id` (GameMap, committed) used consistently. `GameMap.generate(rng, normal_ids, elite_ids, boss_id)` signature matches its callers in Task 1 test and Task 3 `_generate_map`. `_node_buttons` referenced by the Task 4 test matches the script field.
