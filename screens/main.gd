extends Control


func _on_start_pressed() -> void:
	RunState.start_new_run()
	SceneTransition.transition_to("res://combat/combat_screen.tscn")
