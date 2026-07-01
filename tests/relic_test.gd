extends SceneTree

var failures := 0
var _save_backup: Variant = null  # bytes of user://run.json, or null if none


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_backup_save()
	_test_relic_defaults()
	_test_combat_start_block_relic()
	_test_combat_start_strength_relic()
	_test_turn_start_energy_relic()
	_test_turn_start_draw_relic()
	_test_relics_stack()
	if failures == 0:
		print("Relic tests passed.")
	_restore_save()
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_relic_defaults() -> void:
	var relic := RelicData.new()
	_expect(relic.magnitude == 0, "Relic magnitude should default to 0.")
	_expect(relic.trigger == RelicData.Trigger.COMBAT_START, "Relic trigger should default to COMBAT_START.")
	_expect(relic.effect == RelicData.Effect.GAIN_BLOCK, "Relic effect should default to GAIN_BLOCK.")


func _test_combat_start_block_relic() -> void:
	var state := CombatState.new()
	state.begin(_deck(), 30, 50, 50, 5, null, [_relic(RelicData.Trigger.COMBAT_START, RelicData.Effect.GAIN_BLOCK, 6)])
	_expect(state.player_block == 6, "COMBAT_START GAIN_BLOCK relic should grant starting block.")


func _test_combat_start_strength_relic() -> void:
	var state := CombatState.new()
	state.begin(_deck(), 30, 50, 50, 5, null, [_relic(RelicData.Trigger.COMBAT_START, RelicData.Effect.GAIN_STRENGTH, 1)])
	_expect(state.player_status.amount(StatusSet.Type.STRENGTH) == 1, "COMBAT_START GAIN_STRENGTH relic should grant Strength.")


func _test_turn_start_energy_relic() -> void:
	var state := CombatState.new()
	state.begin(_deck(), 30, 50, 50, 5, null, [_relic(RelicData.Trigger.TURN_START, RelicData.Effect.GAIN_ENERGY, 1)])
	_expect(state.energy == state.max_energy + 1, "TURN_START GAIN_ENERGY relic should add energy on turn 1.")
	# And again after a full turn cycle.
	state.planned_move = EnemyMoveData.new()  # 0-damage no-op
	state.end_player_turn(5)
	_expect(state.energy == state.max_energy + 1, "Energy relic should re-apply each turn.")


func _test_turn_start_draw_relic() -> void:
	var state := CombatState.new()
	state.begin(_deck(), 30, 50, 50, 2, null, [_relic(RelicData.Trigger.TURN_START, RelicData.Effect.DRAW_CARD, 1)])
	# Opening hand size 2 + 1 relic draw = 3 (deck has enough cards).
	_expect(state.hand.size() == 3, "TURN_START DRAW_CARD relic should draw an extra card.")


func _test_relics_stack() -> void:
	var state := CombatState.new()
	state.begin(_deck(), 30, 50, 50, 5, null, [
		_relic(RelicData.Trigger.COMBAT_START, RelicData.Effect.GAIN_BLOCK, 6),
		_relic(RelicData.Trigger.COMBAT_START, RelicData.Effect.GAIN_STRENGTH, 2),
	])
	_expect(state.player_block == 6, "Stacked relics: block applied.")
	_expect(state.player_status.amount(StatusSet.Type.STRENGTH) == 2, "Stacked relics: strength applied.")


func _relic(trigger: RelicData.Trigger, effect: RelicData.Effect, magnitude: int) -> RelicData:
	var relic := RelicData.new()
	relic.trigger = trigger
	relic.effect = effect
	relic.magnitude = magnitude
	return relic


func _deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	for i in 10:
		var card := CardData.new()
		card.id = &"filler"
		card.energy_cost = 1
		cards.append(card)
	return cards


func _backup_save() -> void:
	if FileAccess.file_exists("user://run.json"):
		_save_backup = FileAccess.get_file_as_bytes("user://run.json")


func _restore_save() -> void:
	if _save_backup != null:
		var file := FileAccess.open("user://run.json", FileAccess.WRITE)
		file.store_buffer(_save_backup)
	elif FileAccess.file_exists("user://run.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://run.json"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
