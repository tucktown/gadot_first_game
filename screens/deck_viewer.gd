class_name DeckViewer
extends Control

signal card_selected(deck_index: int)

const CARD_VIEW_SCENE := preload("res://cards/card_view.tscn")

@onready var card_grid: GridContainer = %CardGrid
@onready var count_label: Label = %CountLabel
@onready var title_label: Label = %Title

var _selectable := false
var _title := "YOUR DECK"
var _eligible := func(_index: int, _card: CardData) -> bool: return true


func set_picker(title: String, eligible: Callable) -> void:
	_selectable = true
	_title = title
	_eligible = eligible


func _ready() -> void:
	title_label.text = _title
	count_label.text = "%d cards" % RunState.deck.size()
	for i in RunState.deck.size():
		var definition: CardData = RunState.deck[i]
		var card_view: CardView = CARD_VIEW_SCENE.instantiate()
		card_grid.add_child(card_view)
		card_view.display(CardInstance.new(definition))
		if _selectable:
			var ok: bool = _eligible.call(i, definition)
			card_view.set_playable(ok)
			if ok:
				card_view.selected.connect(func(_card): card_selected.emit(i))
		else:
			card_view.set_preview_mode()


func _on_close_button_pressed() -> void:
	queue_free()
