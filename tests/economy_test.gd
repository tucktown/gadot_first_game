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
