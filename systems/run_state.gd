extends Node

const STRIKE_CARD := preload("res://cards/definitions/strike.tres")
const DEFEND_CARD := preload("res://cards/definitions/defend.tres")
const HEAVY_STRIKE_CARD := preload("res://cards/definitions/heavy_strike.tres")
const TRAINING_DUMMY := preload("res://enemies/definitions/training_dummy.tres")
const RAIDER := preload("res://enemies/definitions/raider.tres")
const GUARDIAN := preload("res://enemies/definitions/guardian.tres")
const ENCOUNTERS: Array[EnemyData] = [TRAINING_DUMMY, RAIDER, GUARDIAN]

var max_health: int = 50
var current_health: int = 50
var encounter_number: int = 1
var deck: Array[CardData] = []
var run_complete := false


func start_new_run() -> void:
	current_health = max_health
	encounter_number = 1
	run_complete = false
	deck = [
		STRIKE_CARD,
		STRIKE_CARD,
		DEFEND_CARD,
		DEFEND_CARD,
		HEAVY_STRIKE_CARD,
	]


func ensure_run_started() -> void:
	if deck.is_empty():
		start_new_run()


func complete_combat(remaining_health: int) -> void:
	current_health = clampi(remaining_health, 0, max_health)
	if encounter_number >= ENCOUNTERS.size():
		run_complete = true
	else:
		encounter_number += 1


func add_card(card: CardData) -> void:
	deck.append(card)


func get_current_enemy() -> EnemyData:
	var index := clampi(encounter_number - 1, 0, ENCOUNTERS.size() - 1)
	return ENCOUNTERS[index]


func is_final_encounter() -> bool:
	return encounter_number >= ENCOUNTERS.size()
