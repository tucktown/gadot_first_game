extends Control


func _on_start_pressed() -> void:
	RunState.start_new_run()
	get_tree().change_scene_to_file("res://combat/combat_screen.tscn")
