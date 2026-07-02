extends Node

const SAVE_VERSION := 5
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
const CINDER_HOUND := preload("res://enemies/definitions/cinder_hound.tres")
const PLAGUE_CRAWLER := preload("res://enemies/definitions/plague_crawler.tres")
const BONE_ACOLYTE := preload("res://enemies/definitions/bone_acolyte.tres")
const DREAD_SENTINEL := preload("res://enemies/definitions/dread_sentinel.tres")
const GRAVEMAW := preload("res://enemies/definitions/gravemaw.tres")
const STONE_HEART := preload("res://relics/definitions/stone_heart.tres")
const BATTLE_FERVOR := preload("res://relics/definitions/battle_fervor.tres")
const EVERFLOW_BATTERY := preload("res://relics/definitions/everflow_battery.tres")
const SCRYING_LENS := preload("res://relics/definitions/scrying_lens.tres")
const RELIC_CATALOG := {
	&"stone_heart": STONE_HEART,
	&"battle_fervor": BATTLE_FERVOR,
	&"everflow_battery": EVERFLOW_BATTERY,
	&"scrying_lens": SCRYING_LENS,
}
const ENEMY_CATALOG := {
	&"cinder_hound": CINDER_HOUND,
	&"plague_crawler": PLAGUE_CRAWLER,
	&"bone_acolyte": BONE_ACOLYTE,
	&"dread_sentinel": DREAD_SENTINEL,
	&"gravemaw": GRAVEMAW,
}
const NORMAL_POOL: Array[EnemyData] = [CINDER_HOUND, PLAGUE_CRAWLER, BONE_ACOLYTE]
const ELITE_POOL: Array[EnemyData] = [DREAD_SENTINEL]
const BOSS_ENEMY := GRAVEMAW
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
var gold: int = 0
var map: GameMap = null
var _pending_node_id: int = -1   # node being fought/rested; transient, not serialized
var deck: Array[CardData] = []
var run_complete := false
var awaiting_reward := false
var relics: Array[RelicData] = []
var awaiting_relic := false


func start_new_run() -> void:
	current_health = max_health
	run_complete = false
	awaiting_reward = false
	awaiting_relic = false
	relics = []
	deck = [
		STRIKE_CARD,
		STRIKE_CARD,
		DEFEND_CARD,
		DEFEND_CARD,
		HEAVY_STRIKE_CARD,
	]
	gold = 0
	map = _generate_map()
	_pending_node_id = -1
	save_run()


func _generate_map() -> GameMap:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var normal_ids: Array[StringName] = []
	for enemy in NORMAL_POOL:
		normal_ids.append(enemy.id)
	var elite_ids: Array[StringName] = []
	for enemy in ELITE_POOL:
		elite_ids.append(enemy.id)
	return GameMap.generate(rng, normal_ids, elite_ids, BOSS_ENEMY.id)


func ensure_run_started() -> void:
	if deck.is_empty():
		start_new_run()


func complete_combat(remaining_health: int) -> void:
	var node := map.get_node_by_id(_pending_node_id) if map != null else null
	if node == null or not map.enter(_pending_node_id):
		push_error("complete_combat: no committable pending node (%d)." % _pending_node_id)
		return
	current_health = clampi(remaining_health, 0, max_health)
	match node.type:
		MapNode.Type.ELITE:
			awaiting_relic = true
			add_gold(randi_range(25, 30))
		MapNode.Type.BOSS:
			awaiting_relic = true
		_:
			awaiting_reward = true
			add_gold(randi_range(9, 15))
	save_run()


func add_card(card: CardData) -> void:
	deck.append(card)
	awaiting_reward = false
	save_run()


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	awaiting_relic = false
	save_run()


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	return true


func begin_node(id: int) -> MapNode:
	_pending_node_id = id
	return map.get_node_by_id(id)


func apply_rest() -> void:
	var node := map.get_node_by_id(_pending_node_id) if map != null else null
	if node == null or not map.enter(_pending_node_id):
		push_error("apply_rest: no committable pending node (%d)." % _pending_node_id)
		return
	var heal := int(ceil(max_health * 0.30))
	current_health = clampi(current_health + heal, 0, max_health)
	save_run()


func get_current_enemy() -> EnemyData:
	var node := map.get_node_by_id(_pending_node_id)
	return ENEMY_CATALOG.get(node.enemy_id, null)


func is_pending_boss() -> bool:
	if map == null or _pending_node_id == -1:
		return false
	var node := map.get_node_by_id(_pending_node_id)
	return node != null and node.type == MapNode.Type.BOSS


func is_current_node_boss() -> bool:
	if map == null or map.current_node_id == -1:
		return false
	var node := map.get_node_by_id(map.current_node_id)
	return node != null and node.type == MapNode.Type.BOSS


func has_saved_run() -> bool:
	return SaveManager.has_run()


func get_resume_scene() -> String:
	if awaiting_relic:
		return "res://screens/relic_reward.tscn"
	if awaiting_reward:
		return "res://screens/card_reward.tscn"
	if is_current_node_boss():
		# Boss committed, relic already claimed: the boss node is edgeless, so the
		# map has no available nodes. Route to run-complete instead of a dead map
		# (covers leaving the relic screen via Main Menu / quit before Continue).
		return "res://screens/run_complete.tscn"
	return "res://screens/map_screen.tscn"


func save_run() -> bool:
	var card_ids: Array[String] = []
	for card in deck:
		card_ids.append(String(card.id))

	var relic_ids: Array[String] = []
	for relic in relics:
		relic_ids.append(String(relic.id))

	var save_data := {
		"version": SAVE_VERSION,
		"current_health": current_health,
		"gold": gold,
		"awaiting_reward": awaiting_reward,
		"awaiting_relic": awaiting_relic,
		"deck": card_ids,
		"relics": relic_ids,
		"map": map.to_dict() if map != null else {},
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

	var saved_relic_ids: Variant = save_data.get("relics", [])
	if not saved_relic_ids is Array:
		clear_saved_run()
		return false
	var loaded_relics: Array[RelicData] = []
	for saved_relic_id in saved_relic_ids:
		var relic_id := StringName(str(saved_relic_id))
		if not RELIC_CATALOG.has(relic_id):
			clear_saved_run()
			return false
		loaded_relics.append(RELIC_CATALOG[relic_id])

	var saved_health := int(save_data.get("current_health", 0))
	if saved_health <= 0:
		clear_saved_run()
		return false

	var raw_map: Variant = save_data.get("map", {})
	if typeof(raw_map) != TYPE_DICTIONARY:
		clear_saved_run()
		return false
	var loaded_map := GameMap.from_dict(raw_map)
	if loaded_map == null:
		clear_saved_run()
		return false
	for node in loaded_map.nodes:
		if node.enemy_id != &"" and not ENEMY_CATALOG.has(node.enemy_id):
			clear_saved_run()
			return false

	current_health = clampi(saved_health, 1, max_health)
	gold = maxi(0, int(save_data.get("gold", 0)))
	map = loaded_map
	_pending_node_id = -1
	awaiting_reward = bool(save_data.get("awaiting_reward", false))
	deck = loaded_deck
	relics = loaded_relics
	awaiting_relic = bool(save_data.get("awaiting_relic", false))
	run_complete = false
	return true


func clear_saved_run() -> void:
	var error := SaveManager.delete_run()
	if error != OK:
		push_error("Could not delete saved run (error %d)." % error)
