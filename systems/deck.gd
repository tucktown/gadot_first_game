class_name Deck
extends RefCounted

var draw_pile: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []


func initialize(card_definitions: Array[CardData]) -> void:
	draw_pile.clear()
	discard_pile.clear()
	for definition in card_definitions:
		draw_pile.append(CardInstance.new(definition))
	draw_pile.shuffle()


func draw_card() -> CardInstance:
	if draw_pile.is_empty():
		_reshuffle_discard_pile()
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


func discard(card: CardInstance) -> void:
	discard_pile.append(card)


func _reshuffle_discard_pile() -> void:
	draw_pile.assign(discard_pile)
	discard_pile.clear()
	draw_pile.shuffle()
