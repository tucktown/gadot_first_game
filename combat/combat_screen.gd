class_name CombatScreen
extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")
const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")

@onready var player_health_label: Label = %PlayerHealthLabel
@onready var player_health_bar: ProgressBar = %PlayerHealthBar
@onready var player_block_label: Label = %PlayerBlockLabel
@onready var energy_label: Label = %EnergyLabel
@onready var encounter_label: Label = %EncounterLabel
@onready var status_bar: HBoxContainer = %StatusBar
@onready var enemy_panel: PanelContainer = %EnemyPanel
@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_health_label: Label = %EnemyHealthLabel
@onready var enemy_health_bar: ProgressBar = %EnemyHealthBar
@onready var enemy_block_label: Label = %EnemyBlockLabel
@onready var enemy_intent_label: Label = %EnemyIntentLabel
@onready var message_label: Label = %MessageLabel
@onready var hand_container: HBoxContainer = %Hand
@onready var end_turn_button: Button = %EndTurnButton
@onready var view_deck_button: Button = %ViewDeckButton
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_action_button: Button = %ResultActionButton

var state := CombatState.new()
var enemy: EnemyData
var input_locked := false
var player_health_tween: Tween
var enemy_health_tween: Tween


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
	input_locked = false
	_refresh_combat_view(false)


func _refresh_combat_view(animate_health := true) -> void:
	player_health_label.text = "Health: %d / %d" % [state.player_health, state.player_max_health]
	player_health_bar.max_value = state.player_max_health
	_set_bar_value(player_health_bar, state.player_health, animate_health, true)
	player_block_label.text = "Block: %d" % state.player_block
	energy_label.text = "Energy: %d / %d" % [state.energy, state.max_energy]
	encounter_label.text = "Encounter %d  |  Deck: %d" % [RunState.encounter_number, RunState.deck.size()]
	enemy_name_label.text = enemy.display_name
	enemy_health_label.text = "Health: %d / %d" % [state.enemy_health, state.enemy_max_health]
	enemy_health_bar.max_value = state.enemy_max_health
	_set_bar_value(enemy_health_bar, state.enemy_health, animate_health, false)
	enemy_block_label.text = "Block: %d" % state.enemy_block
	enemy_intent_label.text = _get_intent_text(enemy.get_move(state.enemy_turn_index))
	end_turn_button.disabled = input_locked or state.phase != CombatState.Phase.PLAYER_TURN
	view_deck_button.disabled = input_locked
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
		card_view.set_playable(not input_locked and state.can_play(card))
		card_view.selected.connect(_on_card_selected)


func _on_card_selected(card: CardInstance) -> void:
	if input_locked or not state.can_play(card):
		message_label.text = "That card cannot be played right now."
		return

	var card_view := _find_card_view(card)
	_set_input_locked(true)
	var card_name := card.definition.display_name
	var target := enemy_panel.global_position + enemy_panel.size * 0.5
	if card.definition.damage == 0:
		target = status_bar.global_position + status_bar.size * 0.25
	if card_view:
		await card_view.animate_play_toward(target)

	var result := state.play_card(card)
	if result.damage_dealt > 0:
		_spawn_floating_value("-%d" % result.damage_dealt, enemy_panel, Color(1.0, 0.35, 0.3))
		await _animate_hit(enemy_panel)
	if result.block_gained > 0:
		_spawn_floating_value("+%d BLOCK" % result.block_gained, status_bar, Color(0.35, 0.75, 1.0))

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

	_set_input_locked(false)
	_refresh_combat_view()


func _on_end_turn_button_pressed() -> void:
	if input_locked or state.phase != CombatState.Phase.PLAYER_TURN:
		return

	_set_input_locked(true)
	var enemy_move := enemy.get_move(state.enemy_turn_index)
	message_label.text = "%s prepares %s..." % [enemy.display_name, enemy_move.display_name]
	await get_tree().create_timer(0.4).timeout
	var result := state.end_player_turn(enemy_move)
	if result.is_empty():
		_set_input_locked(false)
		return
	if result.damage_taken > 0:
		_spawn_floating_value("-%d" % result.damage_taken, status_bar, Color(1.0, 0.35, 0.3))
		await _animate_hit(status_bar)
	elif result.blocked > 0:
		_spawn_floating_value("BLOCKED", status_bar, Color(0.35, 0.75, 1.0))
	if result.enemy_block_gained > 0:
		_spawn_floating_value("+%d BLOCK" % result.enemy_block_gained, enemy_panel, Color(0.35, 0.75, 1.0))

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

	await get_tree().create_timer(0.25).timeout
	_set_input_locked(false)
	_refresh_combat_view()


func _on_result_action_button_pressed() -> void:
	if state.phase == CombatState.Phase.WON:
		RunState.complete_combat(state.player_health)
		if RunState.run_complete:
			SceneTransition.transition_to("res://screens/run_complete.tscn")
		else:
			SceneTransition.transition_to("res://screens/card_reward.tscn")
	elif state.phase == CombatState.Phase.LOST:
		RunState.start_new_run()
		_start_combat()


func _on_title_button_pressed() -> void:
	SceneTransition.transition_to("res://screens/main.tscn")


func _on_view_deck_button_pressed() -> void:
	if input_locked or get_node_or_null("DeckViewer"):
		return
	var deck_viewer: DeckViewer = DECK_VIEWER_SCENE.instantiate()
	add_child(deck_viewer)


func _get_intent_text(move: EnemyMoveData) -> String:
	if move == null:
		return "Intent: Waiting"
	if move.damage > 0 and move.block > 0:
		return "Intent: %s - %d damage + %d block" % [move.display_name, move.damage, move.block]
	if move.damage > 0:
		return "Intent: %s - %d damage" % [move.display_name, move.damage]
	return "Intent: %s - %d block" % [move.display_name, move.block]


func _find_card_view(card: CardInstance) -> CardView:
	for child in hand_container.get_children():
		if child is CardView and child.card == card:
			return child
	return null


func _set_input_locked(locked: bool) -> void:
	input_locked = locked
	end_turn_button.disabled = locked or state.phase != CombatState.Phase.PLAYER_TURN
	view_deck_button.disabled = locked
	for child in hand_container.get_children():
		if child is CardView:
			child.set_playable(not locked and state.can_play(child.card))


func _set_bar_value(bar: ProgressBar, target_value: float, animated: bool, is_player: bool) -> void:
	var active_tween := player_health_tween if is_player else enemy_health_tween
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	if not animated:
		bar.value = target_value
		return
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "value", target_value, 0.3)
	if is_player:
		player_health_tween = tween
	else:
		enemy_health_tween = tween


func _animate_hit(target: Control) -> void:
	var original_position := target.position
	var tween := create_tween()
	tween.tween_property(target, "modulate", Color(1.0, 0.35, 0.35, 1.0), 0.06)
	tween.parallel().tween_property(target, "position", original_position + Vector2(9, 0), 0.06)
	tween.tween_property(target, "position", original_position - Vector2(7, 0), 0.06)
	tween.tween_property(target, "position", original_position, 0.06)
	tween.parallel().tween_property(target, "modulate", Color.WHITE, 0.1)
	await tween.finished


func _spawn_floating_value(text: String, target: Control, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 200
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	label.global_position = target.global_position + target.size * 0.5 - Vector2(35, 10)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 55, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.finished.connect(label.queue_free)
