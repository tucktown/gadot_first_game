extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_move_defaults()
	if failures == 0:
		print("Enemy AI tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_move_defaults() -> void:
	var move := EnemyMoveData.new()
	_expect(move.weight == 1, "Move weight should default to 1.")
	_expect(move.condition == EnemyMoveData.Condition.ALWAYS, "Move condition should default to ALWAYS.")
	_expect(move.condition_value == 0.0, "Move condition_value should default to 0.0.")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
