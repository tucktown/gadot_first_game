extends SceneTree

var failures := 0
var _viewer_scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_viewer_scene = load("res://screens/deck_viewer.tscn")
	await _test_picker_eligibility()
	if failures == 0:
		print("Card picker tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_picker_eligibility() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()   # 5-card deck
	root.size = Vector2i(1280, 720)
	var picker := _viewer_scene.instantiate()
	# Only even indices eligible.
	picker.set_picker("Pick", func(index, _card): return index % 2 == 0)
	root.add_child(picker)
	await process_frame
	await process_frame
	var grid := picker.get_node("%CardGrid")
	_expect(grid.get_child_count() == rs.deck.size(),
		"Picker should show one card per deck card (%d)." % rs.deck.size())
	for i in grid.get_child_count():
		var card_view: CardView = grid.get_child(i)
		var enabled := not card_view.select_button.disabled
		_expect(enabled == (i % 2 == 0),
			"Card %d eligibility should match the predicate." % i)
	picker.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
