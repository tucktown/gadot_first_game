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
