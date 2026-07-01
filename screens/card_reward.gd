extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")
const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")
const REWARD_CHOICES := 3
const REWARD_POOL: Array[CardData] = [
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

@onready var reward_container: HBoxContainer = %RewardContainer
@onready var message_label: Label = %MessageLabel
@onready var deck_size_label: Label = %DeckSizeLabel
@onready var continue_button: Button = %ContinueButton

var reward_chosen := false


func _ready() -> void:
	RunState.ensure_run_started()
	deck_size_label.text = "Current deck: %d cards" % RunState.deck.size()
	var rewards := REWARD_POOL.duplicate()
	rewards.shuffle()
	rewards = rewards.slice(0, REWARD_CHOICES)
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
	AudioManager.play_card()
	RunState.add_card(card.definition)
	message_label.text = "%s was added to your deck." % card.definition.display_name
	deck_size_label.text = "Current deck: %d cards" % RunState.deck.size()
	continue_button.disabled = false
	for card_view in reward_container.get_children():
		card_view.show_reward_result(card_view.card == card)


func _on_continue_button_pressed() -> void:
	if reward_chosen:
		SceneTransition.transition_to("res://combat/combat_screen.tscn")


func _on_main_menu_button_pressed() -> void:
	SceneTransition.transition_to("res://screens/title_screen.tscn")


func _on_view_deck_button_pressed() -> void:
	if get_node_or_null("DeckViewer"):
		return
	var deck_viewer: DeckViewer = DECK_VIEWER_SCENE.instantiate()
	add_child(deck_viewer)
