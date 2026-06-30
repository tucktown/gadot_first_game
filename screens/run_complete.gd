extends Control

@onready var summary_label: Label = %SummaryLabel


func _ready() -> void:
	RunState.ensure_run_started()
	summary_label.text = "You defeated all three encounters with %d health and a %d-card deck." % [
		RunState.current_health,
		RunState.deck.size(),
	]


func _on_new_run_button_pressed() -> void:
	RunState.start_new_run()
	get_tree().change_scene_to_file("res://combat/combat_screen.tscn")


func _on_title_button_pressed() -> void:
	get_tree().change_scene_to_file("res://screens/main.tscn")
