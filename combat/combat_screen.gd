class_name CombatScreen
extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")

@onready var player_health_label: Label = %PlayerHealthLabel
@onready var player_block_label: Label = %PlayerBlockLabel
@onready var energy_label: Label = %EnergyLabel
@onready var encounter_label: Label = %EncounterLabel
@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_health_label: Label = %EnemyHealthLabel
@onready var enemy_block_label: Label = %EnemyBlockLabel
@onready var enemy_intent_label: Label = %EnemyIntentLabel
@onready var message_label: Label = %MessageLabel
@onready var hand_container: HBoxContainer = %Hand
@onready var end_turn_button: Button = %EndTurnButton
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_action_button: Button = %ResultActionButton

var state := CombatState.new()
var enemy: EnemyData


func _ready() -> void:
	_start_combat()


func _start_combat() -> void:
	RunState.ensure_run_started()
	enemy = RunState.get_current_enemy()
	state.begin(
		RunState.deck,
		enemy.max_health,
		RunState.current_health,
		RunState.max_health,
	)
	message_label.text = "Choose a card to play."
	_refresh_combat_view()


func _refresh_combat_view() -> void:
	player_health_label.text = "Health: %d / %d" % [state.player_health, state.player_max_health]
	player_block_label.text = "Block: %d" % state.player_block
	energy_label.text = "Energy: %d / %d" % [state.energy, state.max_energy]
	encounter_label.text = "Encounter %d  |  Deck: %d" % [RunState.encounter_number, RunState.deck.size()]
	enemy_name_label.text = enemy.display_name
	enemy_health_label.text = "Health: %d / %d" % [state.enemy_health, state.enemy_max_health]
	enemy_block_label.text = "Block: %d" % state.enemy_block
	enemy_intent_label.text = _get_intent_text(enemy.get_move(state.enemy_turn_index))
	end_turn_button.disabled = state.phase != CombatState.Phase.PLAYER_TURN
	result_overlay.visible = state.phase in [CombatState.Phase.WON, CombatState.Phase.LOST]
	if state.phase == CombatState.Phase.WON:
		result_title.text = "VICTORY"
		result_action_button.text = "Complete Run" if RunState.is_final_encounter() else "Choose Card Reward"
	elif state.phase == CombatState.Phase.LOST:
		result_title.text = "DEFEAT"
		result_action_button.text = "Start New Run"
	_refresh_hand()


func _refresh_hand() -> void:
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()

	for card in state.hand:
		var card_view: CardView = CARD_VIEW_SCENE.instantiate()
		hand_container.add_child(card_view)
		card_view.display(card)
		card_view.set_playable(state.can_play(card))
		card_view.selected.connect(_on_card_selected)


func _on_card_selected(card: CardInstance) -> void:
	if not state.can_play(card):
		message_label.text = "That card cannot be played right now."
		return

	var card_name := card.definition.display_name
	var result := state.play_card(card)

	if state.phase == CombatState.Phase.WON:
		message_label.text = "%s wins the combat!" % card_name
	elif result.damage_dealt > 0 and result.block_gained > 0:
		message_label.text = "%s deals %d damage and grants %d block." % [
			card_name,
			result.damage_dealt,
			result.block_gained,
		]
	elif card.definition.damage > 0:
		message_label.text = "%s deals %d damage (%d blocked)." % [
			card_name,
			result.damage_dealt,
			result.damage_blocked,
		]
	elif result.block_gained > 0:
		message_label.text = "%s grants %d block." % [card_name, result.block_gained]

	_refresh_combat_view()


func _on_end_turn_button_pressed() -> void:
	var enemy_move := enemy.get_move(state.enemy_turn_index)
	var result := state.end_player_turn(enemy_move)
	if result.is_empty():
		return

	if state.phase == CombatState.Phase.LOST:
		message_label.text = "%s uses %s. You were defeated." % [
			enemy.display_name,
			result.move_name,
		]
	else:
		var effects: Array[String] = []
		if result.attack > 0:
			effects.append("%d damage taken, %d blocked" % [result.damage_taken, result.blocked])
		if result.enemy_block_gained > 0:
			effects.append("%d block gained" % result.enemy_block_gained)
		message_label.text = "%s uses %s: %s." % [
			enemy.display_name,
			result.move_name,
			", ".join(effects),
		]

	_refresh_combat_view()


func _on_result_action_button_pressed() -> void:
	if state.phase == CombatState.Phase.WON:
		RunState.complete_combat(state.player_health)
		if RunState.run_complete:
			get_tree().change_scene_to_file("res://screens/run_complete.tscn")
		else:
			get_tree().change_scene_to_file("res://screens/card_reward.tscn")
	elif state.phase == CombatState.Phase.LOST:
		RunState.start_new_run()
		_start_combat()


func _on_title_button_pressed() -> void:
	get_tree().change_scene_to_file("res://screens/main.tscn")


func _get_intent_text(move: EnemyMoveData) -> String:
	if move == null:
		return "Intent: Waiting"
	if move.damage > 0 and move.block > 0:
		return "Intent: %s - %d damage + %d block" % [move.display_name, move.damage, move.block]
	if move.damage > 0:
		return "Intent: %s - %d damage" % [move.display_name, move.damage]
	return "Intent: %s - %d block" % [move.display_name, move.block]
