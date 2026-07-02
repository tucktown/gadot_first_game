extends SceneTree

var failures := 0
var _save_backup: Variant = null


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_backup_save()
	_test_gold_awarded_by_node_type()
	_test_spend_gold_semantics()
	_test_gold_round_trips()
	_test_upgrade_card()
	_test_purchase_removal()
	_test_buy_card_and_relic()
	if failures == 0:
		print("Economy tests passed.")
	_restore_save()
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _rs() -> Node:
	return root.get_node("RunState")


# Enter an available (row-0) node, then rewrite it to the wanted type/enemy so the
# node-type branches of complete_combat can be exercised deterministically.
func _enter_type(rs: Node, type: MapNode.Type, enemy_id: StringName) -> void:
	var start_id: int = rs.map.get_available_node_ids()[0]
	var node: MapNode = rs.map.get_node_by_id(start_id)
	node.type = type
	node.enemy_id = enemy_id
	rs.begin_node(start_id)


func _test_gold_awarded_by_node_type() -> void:
	var rs := _rs()
	rs.start_new_run()
	var before: int = rs.gold
	_enter_type(rs, MapNode.Type.COMBAT, &"cinder_hound")
	rs.complete_combat(30)
	var normal_gain: int = rs.gold - before
	_expect(normal_gain >= 9 and normal_gain <= 15, "Normal win gold in [9,15], got %d." % normal_gain)

	rs.start_new_run()
	before = rs.gold
	_enter_type(rs, MapNode.Type.ELITE, &"dread_sentinel")
	rs.complete_combat(30)
	var elite_gain: int = rs.gold - before
	_expect(elite_gain >= 25 and elite_gain <= 30, "Elite win gold in [25,30], got %d." % elite_gain)

	rs.start_new_run()
	before = rs.gold
	_enter_type(rs, MapNode.Type.BOSS, &"gravemaw")
	rs.complete_combat(30)
	_expect(rs.gold - before == 0, "Boss win should give no gold.")


func _test_spend_gold_semantics() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	_expect(rs.spend_gold(30) and rs.gold == 70, "spend_gold deducts on success.")
	_expect(not rs.spend_gold(1000) and rs.gold == 70, "Insufficient gold: no deduction.")
	_expect(not rs.spend_gold(-5) and rs.gold == 70, "Negative amount rejected.")


func _test_gold_round_trips() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 42
	rs.save_run()
	rs.gold = 0
	_expect(rs.load_saved_run() and rs.gold == 42, "Gold should survive save/load.")


func _test_upgrade_card() -> void:
	var rs := _rs()
	rs.start_new_run()   # deck: strike, strike, defend, defend, heavy_strike
	_expect(rs.upgrade_card(0), "Upgrading an upgradable card should succeed.")
	_expect(rs.deck[0].id == &"strike_plus", "Slot 0 should now hold strike_plus.")
	rs.save_run()
	var empty_deck: Array[CardData] = []
	rs.deck = empty_deck
	_expect(rs.load_saved_run() and rs.deck[0].id == &"strike_plus",
		"Upgraded card should round-trip through save/load by id.")
	_expect(not rs.upgrade_card(999), "Out-of-range upgrade should fail.")
	rs.deck.append(CardData.new())   # runtime card, upgrade_id defaults &""
	_expect(not rs.upgrade_card(rs.deck.size() - 1), "Non-upgradable card can't be upgraded.")


func _test_purchase_removal() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	var size_before: int = rs.deck.size()
	_expect(rs.purchase_removal(0), "Removal with funds + room should succeed.")
	_expect(rs.deck.size() == size_before - 1, "Removal should drop one card.")
	_expect(rs.gold == 25, "Removal should cost 75.")
	rs.gold = 10
	_expect(not rs.purchase_removal(0), "Removal without funds should fail.")
	var one_card: Array[CardData] = [RunState.STRIKE_CARD]
	rs.deck = one_card
	rs.gold = 100
	_expect(not rs.purchase_removal(0), "Can't remove the last card.")
	_expect(rs.deck.size() == 1 and rs.gold == 100, "Failed removal changes nothing.")


func _test_buy_card_and_relic() -> void:
	var rs := _rs()
	rs.start_new_run()
	rs.gold = 100
	var deck_before: int = rs.deck.size()
	_expect(rs.buy_card(RunState.RALLY_CARD) and rs.deck.size() == deck_before + 1 and rs.gold == 50,
		"buy_card appends and costs 50.")
	rs.gold = 10
	_expect(not rs.buy_card(RunState.RALLY_CARD), "buy_card fails when short; no change.")
	rs.gold = 200
	var relics_before: int = rs.relics.size()
	_expect(rs.buy_relic(RunState.STONE_HEART) and rs.relics.size() == relics_before + 1 and rs.gold == 60,
		"buy_relic appends and costs 140.")
	rs.gold = 10
	_expect(not rs.buy_relic(RunState.STONE_HEART), "buy_relic fails when short.")


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
