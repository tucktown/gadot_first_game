extends SceneTree

var failures := 0
var _scene: PackedScene


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_scene = load("res://screens/shop_screen.tscn")
	await _test_buy_and_affordability()
	if failures == 0:
		print("Shop screen tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_buy_and_affordability() -> void:
	var rs := root.get_node("RunState")
	rs.start_new_run()
	rs.gold = 50   # affords exactly one card, no relic
	root.size = Vector2i(1280, 720)
	var screen := _scene.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	_expect(screen._card_buttons.size() == 3, "Shop stocks 3 cards.")
	_expect(not screen._card_buttons[0].disabled, "Card affordable at 50 gold.")
	_expect(screen._relic_buttons[0].disabled, "Relic (140) unaffordable at 50 gold.")
	var deck_before: int = rs.deck.size()
	screen._on_buy_card(RunState.RALLY_CARD, screen._card_buttons[0])
	await process_frame
	_expect(rs.deck.size() == deck_before + 1, "Buying a card adds it to the deck.")
	_expect(rs.gold == 0, "Buying spent the gold.")
	_expect(screen._card_buttons[1].disabled, "Other cards now unaffordable at 0 gold.")
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
