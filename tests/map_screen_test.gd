extends SceneTree

var failures := 0
var _map_screen: PackedScene   # loaded lazily -- see note in _run_tests()


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# NOTE: loaded here (not as a top-level `const ... := preload(...)`). A top-level
	# preload of a scene is resolved while this script itself is still compiling, which
	# happens before the engine has registered autoload singletons as global identifiers
	# -- map_screen.gd's bare `RunState` reference would then fail with a compile error
	# ("Identifier not found: RunState"). Deferring the load until `_run_tests()` (which
	# only runs once the SceneTree has finished starting up, via `call_deferred` above)
	# gives autoloads time to register first.
	_map_screen = load("res://screens/map_screen.tscn")
	await _test_builds_a_button_per_node()
	if failures == 0:
		print("Map screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_builds_a_button_per_node() -> void:
	var run_state := root.get_node("RunState")
	run_state.start_new_run()
	root.size = Vector2i(1280, 720)
	var screen := _map_screen.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var expected: int = run_state.map.nodes.size()
	_expect(screen._node_buttons.size() == expected,
		"Map screen should build one button per node (%d)." % expected)
	# Row-0 nodes are the only enabled buttons at the start.
	var enabled := 0
	for id in screen._node_buttons:
		if not screen._node_buttons[id].disabled:
			enabled += 1
	_expect(enabled == run_state.map.get_available_node_ids().size(),
		"Only the currently-available nodes should be enabled.")
	screen.queue_free()
	# _ready() started looping music via AudioManager.play_game_music(); stop it and drop
	# the stream reference so the headless run doesn't report leaked Ogg decoder objects.
	# The Ogg decoder's playback objects are released on the audio mix thread, which runs
	# on wall-clock time independent of headless (fast-forwarded) engine frames, so a
	# frame-count wait is not reliable here -- a short real-time delay is.
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
