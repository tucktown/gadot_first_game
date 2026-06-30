extends Control

@onready var continue_button: Button = %ContinueButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	continue_button.visible = RunState.has_saved_run()


func _on_start_pressed() -> void:
	RunState.start_new_run()
	SceneTransition.transition_to("res://combat/combat_screen.tscn")


func _on_continue_pressed() -> void:
	if RunState.load_saved_run():
		SceneTransition.transition_to(RunState.get_resume_scene())
		return
	status_label.text = "The saved run could not be loaded and was removed."
	continue_button.visible = false
