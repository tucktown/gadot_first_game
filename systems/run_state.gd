extends Node

const SAVE_VERSION := 1
const STRIKE_CARD := preload("res://cards/definitions/strike.tres")
const DEFEND_CARD := preload("res://cards/definitions/defend.tres")
const HEAVY_STRIKE_CARD := preload("res://cards/definitions/heavy_strike.tres")
const GUARDED_STRIKE_CARD := preload("res://cards/definitions/guarded_strike.tres")
const POWER_BLOW_CARD := preload("res://cards/definitions/power_blow.tres")
const QUICK_GUARD_CARD := preload("res://cards/definitions/quick_guard.tres")
const FORTIFY_CARD := preload("res://cards/definitions/fortify.tres")
const SECOND_WIND_CARD := preload("res://cards/definitions/second_wind.tres")
const DEVOUR_CARD := preload("res://cards/definitions/devour.tres")
const MEND_CARD := preload("res://cards/definitions/mend.tres")
const BULWARK_CARD := preload("res://cards/definitions/bulwark.tres")
const RALLY_CARD := preload("res://cards/definitions/rally.tres")
const EXPOSE_CARD := preload("res://cards/definitions/expose.tres")
const SAP_CARD := preload("res://cards/definitions/sap.tres")
const FLEX_CARD := preload("res://cards/definitions/flex.tres")
const VENOM_CUT_CARD := preload("res://cards/definitions/venom_cut.tres")
const TRAINING_DUMMY := preload("res://enemies/definitions/training_dummy.tres")
const RAIDER := preload("res://enemies/definitions/raider.tres")
const GUARDIAN := preload("res://enemies/definitions/guardian.tres")
const ENCOUNTERS: Array[EnemyData] = [TRAINING_DUMMY, RAIDER, GUARDIAN]
const CARD_CATALOG := {
	&"strike": STRIKE_CARD,
	&"defend": DEFEND_CARD,
	&"heavy_strike": HEAVY_STRIKE_CARD,
	&"guarded_strike": GUARDED_STRIKE_CARD,
	&"power_blow": POWER_BLOW_CARD,
	&"quick_guard": QUICK_GUARD_CARD,
	&"fortify": FORTIFY_CARD,
	&"second_wind": SECOND_WIND_CARD,
	&"devour": DEVOUR_CARD,
	&"mend": MEND_CARD,
	&"bulwark": BULWARK_CARD,
	&"rally": RALLY_CARD,
	&"expose": EXPOSE_CARD,
	&"sap": SAP_CARD,
	&"flex": FLEX_CARD,
	&"venom_cut": VENOM_CUT_CARD,
}

var max_health: int = 50
var current_health: int = 50
var encounter_number: int = 1
var deck: Array[CardData] = []
var run_complete := false
var awaiting_reward := false


func start_new_run() -> void:
	current_health = max_health
	encounter_number = 1
	run_complete = false
	awaiting_reward = false
	deck = [
		STRIKE_CARD,
		STRIKE_CARD,
		DEFEND_CARD,
		DEFEND_CARD,
		HEAVY_STRIKE_CARD,
	]
	save_run()


func ensure_run_started() -> void:
	if deck.is_empty():
		start_new_run()


func complete_combat(remaining_health: int) -> void:
	current_health = clampi(remaining_health, 0, max_health)
	if encounter_number >= ENCOUNTERS.size():
		run_complete = true
		clear_saved_run()
	else:
		encounter_number += 1
		awaiting_reward = true
		save_run()


func add_card(card: CardData) -> void:
	deck.append(card)
	awaiting_reward = false
	save_run()


func get_current_enemy() -> EnemyData:
	var index := clampi(encounter_number - 1, 0, ENCOUNTERS.size() - 1)
	return ENCOUNTERS[index]


func is_final_encounter() -> bool:
	return encounter_number >= ENCOUNTERS.size()


func has_saved_run() -> bool:
	return SaveManager.has_run()


func get_resume_scene() -> String:
	return "res://screens/card_reward.tscn" if awaiting_reward else "res://combat/combat_screen.tscn"


func save_run() -> bool:
	var card_ids: Array[String] = []
	for card in deck:
		card_ids.append(String(card.id))

	var save_data := {
		"version": SAVE_VERSION,
		"current_health": current_health,
		"encounter_number": encounter_number,
		"awaiting_reward": awaiting_reward,
		"deck": card_ids,
	}
	var error := SaveManager.save_run(save_data)
	if error != OK:
		push_error("Could not save run (error %d)." % error)
		return false
	return true


func load_saved_run() -> bool:
	var save_data := SaveManager.load_run()
	if save_data.is_empty() or int(save_data.get("version", -1)) != SAVE_VERSION:
		clear_saved_run()
		return false

	var saved_card_ids: Variant = save_data.get("deck", [])
	if not saved_card_ids is Array or saved_card_ids.is_empty():
		clear_saved_run()
		return false

	var loaded_deck: Array[CardData] = []
	for saved_id in saved_card_ids:
		var card_id := StringName(str(saved_id))
		if not CARD_CATALOG.has(card_id):
			clear_saved_run()
			return false
		loaded_deck.append(CARD_CATALOG[card_id])

	var saved_health := int(save_data.get("current_health", 0))
	var saved_encounter := int(save_data.get("encounter_number", 0))
	if saved_health <= 0 or saved_encounter < 1 or saved_encounter > ENCOUNTERS.size():
		clear_saved_run()
		return false

	current_health = clampi(saved_health, 1, max_health)
	encounter_number = saved_encounter
	awaiting_reward = bool(save_data.get("awaiting_reward", false))
	deck = loaded_deck
	run_complete = false
	return true


func clear_saved_run() -> void:
	var error := SaveManager.delete_run()
	if error != OK:
		push_error("Could not delete saved run (error %d)." % error)
