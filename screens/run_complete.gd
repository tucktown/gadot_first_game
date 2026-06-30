extends Control

const DECK_VIEWER_SCENE := preload("res://screens/deck_viewer.tscn")

@onready var summary_label: Label = %SummaryLabel


func _ready() -> void:
	RunState.ensure_run_started()
	summary_label.text = "You defeated all three encounters with %d health and a %d-card deck." % [
		RunState.current_health,
		RunState.deck.size(),
	]


func _on_new_run_button_pressed() -> void:
	RunState.start_new_run()
	SceneTransition.transition_to("res://combat/combat_screen.tscn")


func _on_title_button_pressed() -> void:
	SceneTransition.transition_to("res://screens/title_screen.tscn")


func _on_view_deck_button_pressed() -> void:
	if get_node_or_null("DeckViewer"):
		return
	var deck_viewer: DeckViewer = DECK_VIEWER_SCENE.instantiate()
	add_child(deck_viewer)
