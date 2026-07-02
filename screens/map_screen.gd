extends Control

const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")

const NODE_SIZE := Vector2(56, 56)
# ponytail: laid out against the fixed 1280x720 design viewport (see CLAUDE.md).
# Switch CENTER_X to the live viewport width if the game ever goes resolution-dynamic.
const CENTER_X := 640.0
const Y0 := 92.0
const X_GAP := 150.0
const Y_GAP := 84.0

const TYPE_LETTER := {
	MapNode.Type.COMBAT: "C",
	MapNode.Type.ELITE: "E",
	MapNode.Type.REST: "R",
	MapNode.Type.BOSS: "B",
	MapNode.Type.SHOP: "S",
}
const TYPE_COLOR := {
	MapNode.Type.COMBAT: Color(0.85, 0.30, 0.28),
	MapNode.Type.ELITE: Color(0.66, 0.40, 0.85),
	MapNode.Type.REST: Color(0.40, 0.80, 0.50),
	MapNode.Type.BOSS: Color(0.96, 0.79, 0.47),
	MapNode.Type.SHOP: Color(0.45, 0.78, 0.85),
}

@onready var health_label: Label = %HealthLabel
@onready var gold_label: Label = %GoldLabel
@onready var legend: VBoxContainer = %Legend

var _node_buttons: Dictionary = {}   # id -> Button
var _row_width: Dictionary = {}       # row -> node count (for centering)


func _ready() -> void:
	RunState.ensure_run_started()
	AudioManager.play_game_music()
	health_label.text = "Health: %d / %d" % [RunState.current_health, RunState.max_health]
	gold_label.text = "Gold: %d" % RunState.gold
	_build_legend()
	_build_map()


func _build_legend() -> void:
	for pair in [
		[MapNode.Type.COMBAT, "Combat"],
		[MapNode.Type.ELITE, "Elite (relic)"],
		[MapNode.Type.REST, "Rest (heal 30%)"],
		[MapNode.Type.BOSS, "Boss"],
		[MapNode.Type.SHOP, "Shop (spend gold)"],
	]:
		var row := Label.new()
		row.text = "%s  —  %s" % [TYPE_LETTER[pair[0]], pair[1]]
		row.add_theme_color_override("font_color", TYPE_COLOR[pair[0]])
		legend.add_child(row)


func _build_map() -> void:
	var map: GameMap = RunState.map
	var available := map.get_available_node_ids()
	var top_row := 0
	_row_width.clear()
	for node in map.nodes:
		top_row = maxi(top_row, node.row)
		_row_width[node.row] = int(_row_width.get(node.row, 0)) + 1

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
		_style_node_button(button, node.type)
		var reachable := available.has(node.id)
		button.disabled = not reachable
		button.modulate = Color(1, 1, 1, 1.0) if reachable else Color(1, 1, 1, 0.45)
		button.pressed.connect(_on_node_pressed.bind(node.id))
		add_child(button)
		_node_buttons[node.id] = button


# A themed node: dark tint of the type's hue for the background, the hue for the
# border, and a brightened hue for the letter — so each node reads as its type.
func _style_node_button(button: Button, type: MapNode.Type) -> void:
	button.add_theme_stylebox_override("normal", _node_stylebox(type, 0.0))
	button.add_theme_stylebox_override("hover", _node_stylebox(type, 0.12))
	button.add_theme_stylebox_override("pressed", _node_stylebox(type, 0.06))
	button.add_theme_stylebox_override("disabled", _node_stylebox(type, 0.0))
	button.add_theme_stylebox_override("focus", _node_stylebox(type, 0.0))
	var letter_color: Color = TYPE_COLOR[type].lightened(0.4)
	button.add_theme_color_override("font_color", letter_color)
	button.add_theme_color_override("font_hover_color", letter_color)
	button.add_theme_color_override("font_pressed_color", letter_color)
	button.add_theme_color_override("font_disabled_color", letter_color)
	button.add_theme_font_size_override("font_size", 22)


func _node_stylebox(type: MapNode.Type, lighten: float) -> StyleBoxFlat:
	var hue: Color = TYPE_COLOR[type]
	var box := StyleBoxFlat.new()
	box.bg_color = hue.darkened(0.55).lightened(lighten)
	box.border_color = hue
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	return box


func _node_pos(node: MapNode, top_row: int) -> Vector2:
	# Center each row around CENTER_X; row 0 sits at the bottom, boss at the top.
	var width: int = int(_row_width.get(node.row, 1))
	var x := CENTER_X + (node.column - (width - 1) / 2.0) * X_GAP - NODE_SIZE.x * 0.5
	var y := Y0 + (top_row - node.row) * Y_GAP
	return Vector2(x, y)


func _tooltip(node: MapNode) -> String:
	match node.type:
		MapNode.Type.REST:
			return "Rest — heal 30% HP"
		MapNode.Type.ELITE:
			return "Elite — %s" % _enemy_name(node)
		MapNode.Type.BOSS:
			return "Boss — %s" % _enemy_name(node)
		MapNode.Type.SHOP:
			return "Shop — buy cards, relics, removal"
		_:
			return "Combat — %s" % _enemy_name(node)


func _enemy_name(node: MapNode) -> String:
	var enemy: EnemyData = RunState.ENEMY_CATALOG.get(node.enemy_id, null)
	return enemy.display_name if enemy != null else "Unknown"


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


func _on_view_deck_button_pressed() -> void:
	if get_node_or_null("DeckViewer"):
		return
	AudioManager.play_ui_click()
	var deck_viewer := DECK_VIEWER_SCENE.instantiate()
	add_child(deck_viewer)


func _on_main_menu_button_pressed() -> void:
	AudioManager.play_ui_click()
	SceneTransition.transition_to("res://screens/title_screen.tscn")
