extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_move_defaults()
	_test_hp_threshold_gates_move()
	_test_player_block_gates_move()
	_test_weighted_pick_is_deterministic_with_seed()
	_test_always_fallback_when_none_eligible()
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


func _test_hp_threshold_gates_move() -> void:
	var state := _combat_with_moves([
		_move("Slam", 10, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Enrage", 20, EnemyMoveData.Condition.ENEMY_HP_BELOW, 0.5, 1),
	])
	state.enemy_max_health = 100
	state.enemy_health = 80  # 80% > 50%, Enrage ineligible
	var eligible_high := _eligible_names(state)
	_expect(not eligible_high.has("Enrage"), "Enrage should be ineligible above the HP threshold.")
	state.enemy_health = 40  # 40% < 50%, Enrage eligible
	var eligible_low := _eligible_names(state)
	_expect(eligible_low.has("Enrage"), "Enrage should be eligible below the HP threshold.")


func _test_player_block_gates_move() -> void:
	var state := _combat_with_moves([
		_move("Bite", 6, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Lunge", 11, EnemyMoveData.Condition.PLAYER_BLOCK_BELOW, 1.0, 1),
	])
	state.player_block = 5  # defended, Lunge ineligible
	_expect(not _eligible_names(state).has("Lunge"), "Lunge should be ineligible while player has block.")
	state.player_block = 0  # undefended, Lunge eligible
	_expect(_eligible_names(state).has("Lunge"), "Lunge should be eligible when player has no block.")


func _test_weighted_pick_is_deterministic_with_seed() -> void:
	var state := _combat_with_moves([
		_move("A", 5, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("B", 5, EnemyMoveData.Condition.ALWAYS, 0.0, 9),
	])
	state.rng.seed = 12345
	var first := state.choose_enemy_move(state.enemy)
	state.rng.seed = 12345
	var second := state.choose_enemy_move(state.enemy)
	_expect(first == second, "Same seed should pick the same move.")
	_expect(first != null, "A non-empty pool should never pick null.")


func _test_always_fallback_when_none_eligible() -> void:
	var state := _combat_with_moves([
		_move("Guard", 0, EnemyMoveData.Condition.ALWAYS, 0.0, 1),
		_move("Enrage", 20, EnemyMoveData.Condition.ENEMY_HP_BELOW, 0.5, 5),
	])
	state.enemy_max_health = 100
	state.enemy_health = 100  # Enrage ineligible; only Guard (ALWAYS) remains
	var picked := state.choose_enemy_move(state.enemy)
	_expect(picked != null and picked.display_name == "Guard", "Should fall back to the ALWAYS move.")


func _move(name: String, damage: int, condition: EnemyMoveData.Condition, value: float, weight: int) -> EnemyMoveData:
	var move := EnemyMoveData.new()
	move.display_name = name
	move.damage = damage
	move.condition = condition
	move.condition_value = value
	move.weight = weight
	return move


func _combat_with_moves(moves: Array) -> CombatState:
	var enemy := EnemyData.new()
	var typed: Array[EnemyMoveData] = []
	for m in moves:
		typed.append(m)
	enemy.moves = typed
	enemy.max_health = 50
	var state := CombatState.new()
	state.enemy = enemy
	state.enemy_max_health = 50
	state.enemy_health = 50
	state.player_block = 0
	return state


func _eligible_names(state: CombatState) -> Array:
	var names: Array = []
	for m in state.enemy.moves:
		if state._move_eligible(m):
			names.append(m.display_name)
	return names


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
