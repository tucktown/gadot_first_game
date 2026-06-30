class_name DeckViewer
extends Control

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")

@onready var card_grid: GridContainer = %CardGrid
@onready var count_label: Label = %CountLabel


func _ready() -> void:
	count_label.text = "%d cards" % RunState.deck.size()
	for definition in RunState.deck:
		var card_view: CardView = CARD_VIEW_SCENE.instantiate()
		card_grid.add_child(card_view)
		card_view.display(CardInstance.new(definition))
		card_view.set_preview_mode()


func _on_close_button_pressed() -> void:
	queue_free()
