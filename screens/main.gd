extends Control

@onready var continue_button: Button = %ContinueButton
@onready var status_label: Label = %StatusLabel
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider


func _ready() -> void:
	continue_button.visible = RunState.has_saved_run()
	music_slider.value = AudioManager.get_music_volume() * 100.0
	sfx_slider.value = AudioManager.get_sfx_volume() * 100.0


func _on_start_pressed() -> void:
	RunState.start_new_run()
	SceneTransition.transition_to("res://combat/combat_screen.tscn")


func _on_continue_pressed() -> void:
	if RunState.load_saved_run():
		SceneTransition.transition_to(RunState.get_resume_scene())
		return
	status_label.text = "The saved run could not be loaded and was removed."
	continue_button.visible = false


func _on_music_slider_value_changed(value: float) -> void:
	AudioManager.set_music_volume(value / 100.0)


func _on_sfx_slider_value_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
