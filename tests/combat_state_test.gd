extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_draw_and_energy_effects()
	_test_fortify_retains_block_once()
	_test_heal_effect_and_cap()
	_test_lifesteal_heals_for_damage_dealt()
	_test_uncapped_energy_exceeds_maximum()
	_test_status_set_basics()
	if failures == 0:
		print("Combat state tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_draw_and_energy_effects() -> void:
	var state := _fresh_state()
	var filler := _card(&"filler")
	var tactical := _card(&"tactical")
	tactical.cards_drawn = 1
	tactical.energy_gained = 1
	state.deck.initialize([filler])
	state.hand.append(CardInstance.new(tactical))
	state.energy = 3

	var result := state.play_card(state.hand[0])
	_expect(result.cards_drawn == 1, "Draw effect should add one card.")
	_expect(result.energy_gained == 1, "Energy effect should restore one energy.")
	_expect(state.energy == 3, "Energy gain should not exceed maximum energy.")
	_expect(state.hand.size() == 1, "Played card should be replaced by the drawn card.")


func _test_fortify_retains_block_once() -> void:
	var state := _fresh_state()
	var fortify := _card(&"fortify")
	fortify.block = 4
	fortify.retains_block = true
	state.hand.append(CardInstance.new(fortify))
	state.play_card(state.hand[0])

	var attack := EnemyMoveData.new()
	attack.damage = 1
	var first_result := state.end_player_turn(attack, 0)
	_expect(first_result.retained_block == 3, "Fortify should retain block left after damage.")
	_expect(state.player_block == 3, "Retained block should remain for the next turn.")

	var second_result := state.end_player_turn(attack, 0)
	_expect(second_result.retained_block == 0, "Fortify should expire after one enemy action.")
	_expect(state.player_block == 0, "Block should reset normally after Fortify expires.")


func _test_heal_effect_and_cap() -> void:
	var state := _fresh_state()
	state.player_health = 40
	var mend := _card(&"mend")
	mend.heal = 5
	state.hand.append(CardInstance.new(mend))
	var result := state.play_card(state.hand[0])
	_expect(result.healed == 5, "Mend should restore 5 health.")
	_expect(state.player_health == 45, "Health should increase by the heal amount.")

	state.player_health = 48
	var overheal := _card(&"mend")
	overheal.heal = 5
	state.hand.append(CardInstance.new(overheal))
	var capped := state.play_card(state.hand[0])
	_expect(capped.healed == 2, "Heal should report only health actually restored.")
	_expect(state.player_health == 50, "Health should not exceed the maximum.")


func _test_lifesteal_heals_for_damage_dealt() -> void:
	var state := _fresh_state()
	state.player_health = 30
	var devour := _card(&"devour")
	devour.damage = 12
	devour.heals_for_damage_dealt = true
	state.hand.append(CardInstance.new(devour))
	var result := state.play_card(state.hand[0])
	_expect(result.damage_dealt == 12, "Devour should deal full damage to an unblocked enemy.")
	_expect(result.healed == 12, "Devour should heal for the damage dealt.")
	_expect(state.player_health == 42, "Lifesteal should restore health equal to damage dealt.")


func _test_uncapped_energy_exceeds_maximum() -> void:
	var state := _fresh_state()
	var surge := _card(&"second_wind")
	surge.energy_cost = 0
	surge.energy_gained = 2
	surge.energy_uncapped = true
	state.hand.append(CardInstance.new(surge))
	var result := state.play_card(state.hand[0])
	_expect(result.energy_gained == 2, "Second Wind should grant full energy even at the cap.")
	_expect(state.energy == 5, "Uncapped energy should exceed the normal maximum.")


func _test_status_set_basics() -> void:
	var s := StatusSet.new()
	s.add(StatusSet.Type.STRENGTH, 2)
	_expect(s.attack_bonus() == 2, "Strength should report as attack bonus.")
	s.add(StatusSet.Type.WEAK, 1)
	_expect(is_equal_approx(s.outgoing_multiplier(), 0.75), "Weak should reduce outgoing damage.")
	s.add(StatusSet.Type.VULNERABLE, 1)
	_expect(is_equal_approx(s.incoming_multiplier(), 1.25), "Vulnerable should raise incoming damage.")

	s.add(StatusSet.Type.POISON, 3)
	var ticked := s.tick_turn_start()
	_expect(ticked == 3, "Poison tick should return current poison.")
	_expect(s.amount(StatusSet.Type.POISON) == 2, "Poison should decrement after ticking.")

	s.tick_turn_end()
	_expect(s.amount(StatusSet.Type.VULNERABLE) == 0, "Vulnerable should decrement at turn end.")
	_expect(s.amount(StatusSet.Type.WEAK) == 0, "Weak should decrement at turn end.")

	var badges := s.describe()
	_expect(badges.size() == 2, "Only remaining statuses (Strength, Poison) should describe.")


func _fresh_state() -> CombatState:
	var state := CombatState.new()
	state.phase = CombatState.Phase.PLAYER_TURN
	state.player_health = 50
	state.player_max_health = 50
	state.enemy_health = 50
	state.enemy_max_health = 50
	state.energy = 3
	state.max_energy = 3
	return state


func _card(card_id: StringName) -> CardData:
	var definition := CardData.new()
	definition.id = card_id
	definition.energy_cost = 1
	return definition


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
