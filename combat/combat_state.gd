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
var hand: Array[CardInstance] = []
var deck := Deck.new()


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
	hand.clear()
	deck.initialize(card_definitions)
	draw_cards(opening_hand_size)


func draw_cards(amount: int) -> void:
	for _index in amount:
		var card := deck.draw_card()
		if card == null:
			return
		hand.append(card)


func can_play(card: CardInstance) -> bool:
	return phase == Phase.PLAYER_TURN and hand.has(card) and energy >= card.get_energy_cost()


func play_card(card: CardInstance) -> Dictionary:
	if not can_play(card):
		return {}

	energy -= card.get_energy_cost()
	player_block += card.definition.block
	var damage_blocked := mini(enemy_block, card.definition.damage)
	var damage_dealt := maxi(0, card.definition.damage - enemy_block)
	enemy_block = maxi(0, enemy_block - card.definition.damage)
	enemy_health = maxi(0, enemy_health - damage_dealt)
	hand.erase(card)
	deck.discard(card)

	if enemy_health == 0:
		phase = Phase.WON

	return {
		"damage_dealt": damage_dealt,
		"damage_blocked": damage_blocked,
		"block_gained": card.definition.block,
	}


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
	player_block = 0
	enemy_block += enemy_move.block
	enemy_turn_index += 1

	var result := {
		"move_name": enemy_move.display_name,
		"attack": enemy_move.damage,
		"blocked": blocked_damage,
		"damage_taken": damage_taken,
		"enemy_block_gained": enemy_move.block,
	}

	if player_health == 0:
		phase = Phase.LOST
		return result

	phase = Phase.PLAYER_TURN
	energy = max_energy
	draw_cards(new_hand_size)
	return result
