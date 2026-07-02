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
