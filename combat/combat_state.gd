class_name CombatState
extends RefCounted

enum Phase {
	PLAYER_TURN,
	ENEMY_TURN,
	WON,
	LOST,
}

var phase: Phase = Phase.PLAYER_TURN
var player_max_health: int = 50
var player_health: int = 50
var player_block: int = 0
var max_energy: int = 3
var energy: int = 3
var enemy_max_health: int = 0
var enemy_health: int = 0
var enemy_block: int = 0
var enemy_turn_index: int = 0
var retain_block_this_turn := false
var hand: Array[CardInstance] = []
var deck := Deck.new()
var player_status: StatusSet = StatusSet.new()
var enemy_status: StatusSet = StatusSet.new()


func begin(
	card_definitions: Array[CardData],
	starting_enemy_health: int,
	starting_player_health: int = 50,
	starting_player_max_health: int = 50,
	opening_hand_size: int = 5,
) -> void:
	phase = Phase.PLAYER_TURN
	player_max_health = starting_player_max_health
	player_health = clampi(starting_player_health, 1, player_max_health)
	player_block = 0
	energy = max_energy
	enemy_max_health = starting_enemy_health
	enemy_health = starting_enemy_health
	enemy_block = 0
	enemy_turn_index = 0
	retain_block_this_turn = false
	player_status.stacks.clear()
	enemy_status.stacks.clear()
	hand.clear()
	deck.initialize(card_definitions)
	draw_cards(opening_hand_size)


func draw_cards(amount: int) -> int:
	var drawn := 0
	for _index in amount:
		var card := deck.draw_card()
		if card == null:
			break
		hand.append(card)
		drawn += 1
	return drawn


func can_play(card: CardInstance) -> bool:
	return phase == Phase.PLAYER_TURN and hand.has(card) and energy >= card.get_energy_cost()


func play_card(card: CardInstance) -> Dictionary:
	if not can_play(card):
		return {}

	energy -= card.get_energy_cost()
	player_block += card.definition.block
	var raw_damage := _attack_damage(card.definition.damage, player_status, enemy_status)
	var damage_blocked := mini(enemy_block, raw_damage)
	var damage_dealt := maxi(0, raw_damage - enemy_block)
	enemy_block = maxi(0, enemy_block - raw_damage)
	enemy_health = maxi(0, enemy_health - damage_dealt)
	hand.erase(card)

	enemy_status.add(StatusSet.Type.VULNERABLE, card.definition.vulnerable_applied)
	enemy_status.add(StatusSet.Type.WEAK, card.definition.weak_applied)
	enemy_status.add(StatusSet.Type.POISON, card.definition.poison_applied)
	player_status.add(StatusSet.Type.STRENGTH, card.definition.strength_gained)

	var heal_amount := card.definition.heal
	if card.definition.heals_for_damage_dealt:
		heal_amount += damage_dealt
	var health_before := player_health
	player_health = mini(player_max_health, player_health + heal_amount)
	var healed := player_health - health_before

	var cards_drawn := draw_cards(card.definition.cards_drawn)
	var energy_gained := card.definition.energy_gained
	if not card.definition.energy_uncapped:
		energy_gained = mini(energy_gained, max_energy - energy)
	energy += energy_gained
	if card.definition.retains_block:
		retain_block_this_turn = true
	deck.discard(card)

	if enemy_health == 0:
		phase = Phase.WON

	return {
		"damage_dealt": damage_dealt,
		"damage_blocked": damage_blocked,
		"block_gained": card.definition.block,
		"cards_drawn": cards_drawn,
		"energy_gained": energy_gained,
		"healed": healed,
		"block_retention_armed": card.definition.retains_block,
		"vulnerable_applied": card.definition.vulnerable_applied,
		"weak_applied": card.definition.weak_applied,
		"poison_applied": card.definition.poison_applied,
		"strength_gained": card.definition.strength_gained,
	}


func _attack_damage(base: int, attacker: StatusSet, defender: StatusSet) -> int:
	if base <= 0:
		return 0
	var raw := base + attacker.attack_bonus()
	var weakened := floori(raw * attacker.outgoing_multiplier())
	var result := floori(weakened * defender.incoming_multiplier())
	return maxi(0, result)


func end_player_turn(enemy_move: EnemyMoveData, new_hand_size: int = 5) -> Dictionary:
	if phase != Phase.PLAYER_TURN:
		return {}

	for card in hand:
		deck.discard(card)
	hand.clear()
	energy = 0
	phase = Phase.ENEMY_TURN

	enemy_block = 0
	var blocked_damage := mini(player_block, enemy_move.damage)
	var damage_taken := maxi(0, enemy_move.damage - player_block)
	player_health = maxi(0, player_health - damage_taken)
	var remaining_block := maxi(0, player_block - enemy_move.damage)
	var retained_block := remaining_block if retain_block_this_turn else 0
	player_block = retained_block
	retain_block_this_turn = false
	enemy_block += enemy_move.block
	enemy_turn_index += 1

	var result := {
		"move_name": enemy_move.display_name,
		"attack": enemy_move.damage,
		"blocked": blocked_damage,
		"damage_taken": damage_taken,
		"enemy_block_gained": enemy_move.block,
		"retained_block": retained_block,
	}

	if player_health == 0:
		phase = Phase.LOST
		return result

	phase = Phase.PLAYER_TURN
	energy = max_energy
	draw_cards(new_hand_size)
	return result
