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
