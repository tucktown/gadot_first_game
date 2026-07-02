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
	_test_relic_catalog_complete()
	_test_relic_save_load_round_trip()
	_test_unknown_relic_id_invalidates_save()
	_test_unknown_enemy_id_invalidates_save()
	_test_elite_win_awaits_relic()
	_test_normal_win_awaits_card()
	_test_boss_committed_resumes_to_run_complete()
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


func _test_relic_catalog_complete() -> void:
	for id in [&"stone_heart", &"battle_fervor", &"everflow_battery", &"scrying_lens"]:
		_expect(RunState.RELIC_CATALOG.has(id), "RELIC_CATALOG should contain %s." % id)
	_expect(RunState.SAVE_VERSION == 4, "SAVE_VERSION should be 4.")


func _test_relic_save_load_round_trip() -> void:
	# NOTE: bare `RunState.foo()` doesn't resolve here — this test script `extends SceneTree`,
	# not Node, so GDScript can't do its usual autoload-lookup-via-get_node for instance
	# members/methods (constants like RunState.EVERFLOW_BATTERY still resolve fine, since those
	# are read straight off the script's class, no instance needed). Fetch the live singleton
	# through the scene tree instead.
	var run_state := _run_state()
	run_state.start_new_run()
	# `relics` on RunState is `Array[RelicData]`; going through `run_state` (typed `Node` here,
	# for the get_node-workaround reason above) makes the assignment dynamic, so the RHS must
	# already carry the matching typed-array shape rather than a bare untyped `[...]` literal.
	var relics_with_battery: Array[RelicData] = [RunState.EVERFLOW_BATTERY]
	run_state.relics = relics_with_battery
	run_state.save_run()
	var empty_relics: Array[RelicData] = []
	run_state.relics = empty_relics  # clobber in memory
	var ok: bool = run_state.load_saved_run()
	_expect(ok, "Saved run with a relic should load.")
	_expect(run_state.relics.size() == 1 and run_state.relics[0] == RunState.EVERFLOW_BATTERY,
		"Relic should round-trip by id through the catalog.")


func _test_unknown_relic_id_invalidates_save() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	var data := {
		"version": RunState.SAVE_VERSION,
		"current_health": 40,
		"awaiting_reward": false,
		"awaiting_relic": false,
		"deck": ["strike", "strike", "defend", "defend", "heavy_strike"],
		"relics": ["not_a_real_relic"],
		"map": _run_state().map.to_dict(),
	}
	SaveManager.save_run(data)
	var ok: bool = run_state.load_saved_run()
	_expect(not ok, "An unknown relic id must invalidate the save.")
	_expect(not SaveManager.has_run(), "Invalid save should be cleared.")


func _test_unknown_enemy_id_invalidates_save() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	var map_dict: Dictionary = run_state.map.to_dict()
	# Corrupt the first node that carries an enemy id (row-0 nodes are combat).
	for node_dict in map_dict["nodes"]:
		if node_dict["enemy_id"] != "":
			node_dict["enemy_id"] = "not_a_real_enemy"
			break
	var data := {
		"version": RunState.SAVE_VERSION,
		"current_health": 40,
		"awaiting_reward": false,
		"awaiting_relic": false,
		"deck": ["strike", "strike", "defend", "defend", "heavy_strike"],
		"relics": [],
		"map": map_dict,
	}
	SaveManager.save_run(data)
	var ok: bool = run_state.load_saved_run()
	_expect(not ok, "An unknown enemy id in the map must invalidate the save.")
	_expect(not SaveManager.has_run(), "Invalid save should be cleared.")


func _test_elite_win_awaits_relic() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	# Elite nodes only exist on rows 2-4; a fresh map may or may not roll one.
	# Force a deterministic elite by entering a hand-built pending node instead.
	_enter_type(run_state, MapNode.Type.ELITE, &"dread_sentinel")
	_expect(run_state.get_current_enemy().is_elite, "Dread Sentinel should be flagged as elite.")
	run_state.complete_combat(30)
	_expect(run_state.awaiting_relic, "Beating the elite should set awaiting_relic.")
	_expect(not run_state.awaiting_reward, "Elite win should not set the card-reward flag.")
	_expect(run_state.get_resume_scene() == "res://screens/relic_reward.tscn",
		"awaiting_relic should resume to the relic-reward scene.")


func _test_normal_win_awaits_card() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	_enter_type(run_state, MapNode.Type.COMBAT, &"cinder_hound")
	run_state.complete_combat(30)
	_expect(run_state.awaiting_reward, "Beating a normal enemy should set awaiting_reward.")
	_expect(not run_state.awaiting_relic, "Normal win should not set the relic flag.")
	_expect(run_state.get_resume_scene() == "res://screens/card_reward.tscn",
		"A pending card reward must resume into the card-reward screen (not skip to the map).")


func _test_boss_committed_resumes_to_run_complete() -> void:
	var run_state := _run_state()
	run_state.start_new_run()
	# Simulate having beaten the boss and claimed its relic: commit the boss node
	# with no pending reward flags.
	var boss_id := -1
	for node in run_state.map.nodes:
		if node.type == MapNode.Type.BOSS:
			boss_id = node.id
	run_state.map.current_node_id = boss_id
	run_state.awaiting_reward = false
	run_state.awaiting_relic = false
	_expect(run_state.is_current_node_boss(), "Boss node should be the committed current node.")
	_expect(run_state.get_resume_scene() == "res://screens/run_complete.tscn",
		"A committed boss with no pending reward must resume to run-complete, not a dead map.")


# Enters an available node, then rewrites it to the wanted type/enemy so the
# win-routing branches can be exercised without depending on random layout.
func _enter_type(run_state: Node, type: MapNode.Type, enemy_id: StringName) -> void:
	var start_id: int = run_state.map.get_available_node_ids()[0]
	var node: MapNode = run_state.map.get_node_by_id(start_id)
	node.type = type
	node.enemy_id = enemy_id
	run_state.begin_node(start_id)


func _run_state() -> Node:
	# The RunState autoload, fetched through the tree since this SceneTree script has no
	# Node `self` for GDScript's normal autoload-name-to-get_node sugar to hook into.
	return root.get_node("RunState")


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
