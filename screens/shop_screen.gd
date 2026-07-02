extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")
const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")
const CARD_STOCK := 3
const RELIC_STOCK := 2
const CARD_POOL: Array[CardData] = [
	preload("res://cards/definitions/guarded_strike.tres"),
	preload("res://cards/definitions/power_blow.tres"),
	preload("res://cards/definitions/quick_guard.tres"),
	preload("res://cards/definitions/fortify.tres"),
	preload("res://cards/definitions/second_wind.tres"),
	preload("res://cards/definitions/devour.tres"),
	preload("res://cards/definitions/mend.tres"),
	preload("res://cards/definitions/bulwark.tres"),
	preload("res://cards/definitions/rally.tres"),
	preload("res://cards/definitions/expose.tres"),
	preload("res://cards/definitions/sap.tres"),
	preload("res://cards/definitions/flex.tres"),
	preload("res://cards/definitions/venom_cut.tres"),
]
const RELIC_POOL: Array[RelicData] = [
	preload("res://relics/definitions/stone_heart.tres"),
	preload("res://relics/definitions/battle_fervor.tres"),
	preload("res://relics/definitions/everflow_battery.tres"),
	preload("res://relics/definitions/scrying_lens.tres"),
]

@onready var gold_label: Label = %GoldLabel
@onready var card_row: HBoxContainer = %CardRow
@onready var relic_row: HBoxContainer = %RelicRow
@onready var remove_button: Button = %RemoveButton

var _card_buttons: Array[Button] = []
var _relic_buttons: Array[Button] = []


func _ready() -> void:
	RunState.ensure_run_started()
	AudioManager.play_game_music()
	_build_cards()
	_build_relics()
	_refresh_affordability()


func _build_cards() -> void:
	var pool := CARD_POOL.duplicate()
	pool.shuffle()
	for definition in pool.slice(0, CARD_STOCK):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		# Parent the box into the live tree before instantiating the CardView into
		# it: CardView.display()/set_preview_mode() touch @onready node refs that
		# are only populated once the node actually enters the SceneTree.
		card_row.add_child(box)
		var view: CardView = CARD_VIEW_SCENE.instantiate()
		box.add_child(view)
		view.display(CardInstance.new(definition))
		view.set_preview_mode()
		var buy := Button.new()
		buy.text = "Buy (%d)" % RunState.SHOP_CARD_PRICE
		buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		buy.pressed.connect(_on_buy_card.bind(definition, buy))
		box.add_child(buy)
		_card_buttons.append(buy)


func _build_relics() -> void:
	var pool := RELIC_POOL.duplicate()
	pool.shuffle()
	for relic in pool.slice(0, RELIC_STOCK):
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(200, 0)
		box.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = relic.display_name
		name_label.add_theme_color_override("font_color", Color(0.96, 0.79, 0.47))
		box.add_child(name_label)
		var desc := Label.new()
		desc.text = relic.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.custom_minimum_size = Vector2(200, 0)
		box.add_child(desc)
		var buy := Button.new()
		buy.text = "Buy (%d)" % RunState.SHOP_RELIC_PRICE
		buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		buy.pressed.connect(_on_buy_relic.bind(relic, buy))
		box.add_child(buy)
		relic_row.add_child(box)
		_relic_buttons.append(buy)


func _on_buy_card(definition: CardData, button: Button) -> void:
	if RunState.buy_card(definition):
		AudioManager.play_card()
		button.text = "Sold"
		button.disabled = true
		_refresh_affordability()


func _on_buy_relic(relic: RelicData, button: Button) -> void:
	if RunState.buy_relic(relic):
		AudioManager.play_card()
		button.text = "Sold"
		button.disabled = true
		_refresh_affordability()


func _on_remove_button_pressed() -> void:
	if get_node_or_null("Picker") or RunState.gold < RunState.SHOP_REMOVE_PRICE or RunState.deck.size() <= 1:
		return
	AudioManager.play_ui_click()
	var picker := DECK_VIEWER_SCENE.instantiate()
	picker.name = "Picker"
	picker.set_picker("Remove a card (%d gold)" % RunState.SHOP_REMOVE_PRICE,
		func(_index, _card): return true)
	picker.card_selected.connect(_on_card_to_remove)
	add_child(picker)


func _on_card_to_remove(deck_index: int) -> void:
	if RunState.purchase_removal(deck_index):
		AudioManager.play_card()
	var picker := get_node_or_null("Picker")
	if picker != null:
		picker.queue_free()
	_refresh_affordability()


func _on_leave_button_pressed() -> void:
	AudioManager.play_ui_click()
	SceneTransition.transition_to("res://screens/map_screen.tscn")


func _refresh_affordability() -> void:
	gold_label.text = "Gold: %d" % RunState.gold
	for button in _card_buttons:
		if button.text != "Sold":
			button.disabled = RunState.gold < RunState.SHOP_CARD_PRICE
	for button in _relic_buttons:
		if button.text != "Sold":
			button.disabled = RunState.gold < RunState.SHOP_RELIC_PRICE
	remove_button.disabled = RunState.gold < RunState.SHOP_REMOVE_PRICE or RunState.deck.size() <= 1
