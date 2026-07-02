extends SceneTree

var failures := 0
var _scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_scene = load("res://screens/rest_screen.tscn")
	await _test_builds_and_upgrade_picker_filters()
	if failures == 0:
		print("Rest screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_builds_and_upgrade_picker_filters() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()
	root.size = Vector2i(1280, 720)
	var screen := _scene.instantiate()
	root.add_child(screen)
	await process_frame
	_expect(screen.get_node_or_null("Center/Content/RestButton") != null, "Rest button present.")
	_expect(screen.get_node_or_null("Center/Content/UpgradeButton") != null, "Upgrade button present.")
	# Opening the upgrade picker builds a picker whose cards are all upgradable (starters are).
	screen._on_upgrade_button_pressed()
	await process_frame
	await process_frame
	var picker := screen.get_node_or_null("Picker")
	_expect(picker != null, "Upgrade opens a picker.")
	if picker != null:
		var grid := picker.get_node("%CardGrid")
		for card_view in grid.get_children():
			_expect(not card_view.select_button.disabled, "Starter deck cards are all upgradable.")
	screen.queue_free()
	var audio_manager := root.get_node("AudioManager")
	audio_manager.music_player.stop()
	audio_manager.music_player.stream = null
	OS.delay_msec(150)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
