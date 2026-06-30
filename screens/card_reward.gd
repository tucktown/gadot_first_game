extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")
const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")
const GUARDED_STRIKE_CARD := preload("res://cards/definitions/guarded_strike.tres")
const POWER_BLOW_CARD := preload("res://cards/definitions/power_blow.tres")
const QUICK_GUARD_CARD := preload("res://cards/definitions/quick_guard.tres")

@onready var reward_container: HBoxContainer = %RewardContainer
@onready var message_label: Label = %MessageLabel
@onready var deck_size_label: Label = %DeckSizeLabel
@onready var continue_button: Button = %ContinueButton

var reward_chosen := false


func _ready() -> void:
	RunState.ensure_run_started()
	deck_size_label.text = "Current deck: %d cards" % RunState.deck.size()
	var rewards: Array[CardData] = [GUARDED_STRIKE_CARD, POWER_BLOW_CARD, QUICK_GUARD_CARD]
	for definition in rewards:
		var card_view: CardView = CARD_VIEW_SCENE.instantiate()
		reward_container.add_child(card_view)
		card_view.display(CardInstance.new(definition))
		card_view.set_playable(true)
		card_view.selected.connect(_on_reward_selected)


func _on_reward_selected(card: CardInstance) -> void:
	if reward_chosen:
		return

	reward_chosen = true
	RunState.add_card(card.definition)
	message_label.text = "%s was added to your deck." % card.definition.display_name
	deck_size_label.text = "Current deck: %d cards" % RunState.deck.size()
	continue_button.disabled = false
	for card_view in reward_container.get_children():
		card_view.set_playable(false)


func _on_continue_button_pressed() -> void:
	if reward_chosen:
		SceneTransition.transition_to("res://combat/combat_screen.tscn")


func _on_view_deck_button_pressed() -> void:
	if get_node_or_null("DeckViewer"):
		return
	var deck_viewer: DeckViewer = DECK_VIEWER_SCENE.instantiate()
	add_child(deck_viewer)
