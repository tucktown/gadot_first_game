extends CanvasLayer

var overlay: ColorRect
var transitioning := false


func _ready() -> void:
	layer = 100
	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.025, 0.04, 1.0)
	overlay.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)


func transition_to(scene_path: String) -> void:
	if transitioning:
		return
	transitioning = true
	overlay.visible = true

	var fade_out := create_tween()
	fade_out.tween_property(overlay, "modulate:a", 1.0, 0.2)
	await fade_out.finished

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not change scene to %s (error %d)." % [scene_path, error])
		overlay.visible = false
		transitioning = false
		return

	await get_tree().process_frame
	var fade_in := create_tween()
	fade_in.tween_property(overlay, "modulate:a", 0.0, 0.2)
	await fade_in.finished
	overlay.visible = false
	transitioning = false
