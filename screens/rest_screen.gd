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
