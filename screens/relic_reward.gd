extends Control

const REWARD_CHOICES := 3
const RELIC_POOL: Array[RelicData] = [
	preload("res://relics/definitions/stone_heart.tres"),
	preload("res://relics/definitions/battle_fervor.tres"),
	preload("res://relics/definitions/everflow_battery.tres"),
	preload("res://relics/definitions/scrying_lens.tres"),
]

@onready var relic_container: HBoxContainer = %RelicContainer
@onready var message_label: Label = %MessageLabel
@onready var continue_button: Button = %ContinueButton

var reward_chosen := false


func _ready() -> void:
	RunState.ensure_run_started()
	var pool := RELIC_POOL.duplicate()
	pool.shuffle()
	pool = pool.slice(0, REWARD_CHOICES)
	for relic in pool:
		relic_container.add_child(_build_choice(relic))


func _build_choice(relic: RelicData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var name_label := Label.new()
	name_label.text = relic.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color(0.96, 0.79, 0.47))
	name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = relic.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size = Vector2(200, 0)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc_label)
	var button := Button.new()
	button.text = "Choose"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_relic_chosen.bind(relic))
	box.add_child(button)
	return panel


func _on_relic_chosen(relic: RelicData) -> void:
	if reward_chosen:
		return
	reward_chosen = true
	AudioManager.play_card()
	RunState.add_relic(relic)
	message_label.text = "%s claimed." % relic.display_name
	continue_button.disabled = false
	for panel in relic_container.get_children():
		for node in panel.get_children()[0].get_children():
			if node is Button:
				node.disabled = true


func _on_continue_button_pressed() -> void:
	if not reward_chosen:
		return
	if RunState.is_current_node_boss():
		RunState.clear_saved_run()
		SceneTransition.transition_to("res://screens/run_complete.tscn")
	else:
		SceneTransition.transition_to("res://screens/map_screen.tscn")


func _on_main_menu_button_pressed() -> void:
	SceneTransition.transition_to("res://screens/title_screen.tscn")
