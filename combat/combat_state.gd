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
var enemy: EnemyData
var planned_move: EnemyMoveData
var rng := RandomNumberGenerator.new()


func begin(
	card_definitions: Array[CardData],
	starting_enemy_health: int,
	starting_player_health: int = 50,
	starting_player_max_health: int = 50,
	opening_hand_size: int = 5,
	enemy_data: EnemyData = null,
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
	enemy = enemy_data
	rng.randomize()
	plan_enemy_move()


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


func _move_eligible(move: EnemyMoveData) -> bool:
	match move.condition:
		EnemyMoveData.Condition.ENEMY_HP_BELOW:
			var fraction := float(enemy_health) / float(maxi(1, enemy_max_health))
			return fraction < move.condition_value
		EnemyMoveData.Condition.PLAYER_BLOCK_BELOW:
			return float(player_block) < move.condition_value
		_:
			return true


func choose_enemy_move(target: EnemyData) -> EnemyMoveData:
	if target == null or target.moves.is_empty():
		return null
	var eligible: Array[EnemyMoveData] = []
	for move in target.moves:
		if _move_eligible(move):
			eligible.append(move)
	if eligible.is_empty():
		for move in target.moves:
			if move.condition == EnemyMoveData.Condition.ALWAYS:
				return move
		return target.moves[0]
	var total_weight := 0
	for move in eligible:
		total_weight += move.weight
	if total_weight <= 0:
		return eligible[0]
	var roll := rng.randi_range(1, total_weight)
	var accumulated := 0
	for move in eligible:
		accumulated += move.weight
		if roll <= accumulated:
			return move
	return eligible[eligible.size() - 1]


func plan_enemy_move() -> void:
	if enemy == null:
		return
	planned_move = choose_enemy_move(enemy)


func end_player_turn(new_hand_size: int = 5) -> Dictionary:
	if phase != Phase.PLAYER_TURN:
		return {}

	var enemy_move := planned_move
	if enemy_move == null:
		enemy_move = EnemyMoveData.new()

	for card in hand:
		deck.discard(card)
	hand.clear()
	energy = 0
	phase = Phase.ENEMY_TURN

	# Player's turn ends: their duration debuffs count down.
	player_status.tick_turn_end()

	# Enemy turn begins with poison (ignores block).
	var enemy_poison := enemy_status.tick_turn_start()
	enemy_health = maxi(0, enemy_health - enemy_poison)

	var result := {
		"move_name": enemy_move.display_name,
		"attack": 0,
		"blocked": 0,
		"damage_taken": 0,
		"enemy_block_gained": 0,
		"retained_block": 0,
		"enemy_poison_damage": enemy_poison,
		"player_poison_damage": 0,
		"weak_applied": enemy_move.weak_applied,
		"vulnerable_applied": enemy_move.vulnerable_applied,
		"poison_applied": enemy_move.poison_applied,
	}

	if enemy_health == 0:
		phase = Phase.WON
		return result

	# Enemy attacks; its Strength/Weak and the player's Vulnerable adjust damage.
	enemy_block = 0
	var attack_damage := _attack_damage(enemy_move.damage, enemy_status, player_status)
	var blocked_damage := mini(player_block, attack_damage)
	var damage_taken := maxi(0, attack_damage - player_block)
	player_health = maxi(0, player_health - damage_taken)
	var remaining_block := maxi(0, player_block - attack_damage)
	var retained_block := remaining_block if retain_block_this_turn else 0
	player_block = retained_block
	retain_block_this_turn = false
	enemy_block += enemy_move.block
	enemy_turn_index += 1

	result.attack = attack_damage
	result.blocked = blocked_damage
	result.damage_taken = damage_taken
	result.enemy_block_gained = enemy_move.block
	result.retained_block = retained_block

	# The move applies statuses to the player and can buff the enemy.
	player_status.add(StatusSet.Type.WEAK, enemy_move.weak_applied)
	player_status.add(StatusSet.Type.VULNERABLE, enemy_move.vulnerable_applied)
	player_status.add(StatusSet.Type.POISON, enemy_move.poison_applied)
	enemy_status.add(StatusSet.Type.STRENGTH, enemy_move.strength_gained)

	# Enemy's turn ends: its duration debuffs count down.
	enemy_status.tick_turn_end()

	if player_health == 0:
		phase = Phase.LOST
		return result

	# Player regains control: their poison ticks before the new turn.
	var player_poison := player_status.tick_turn_start()
	player_health = maxi(0, player_health - player_poison)
	result.player_poison_damage = player_poison
	if player_health == 0:
		phase = Phase.LOST
		return result

	plan_enemy_move()
	phase = Phase.PLAYER_TURN
	energy = max_energy
	draw_cards(new_hand_size)
	return result
