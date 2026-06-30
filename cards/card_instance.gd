class_name CardInstance
extends RefCounted

var definition: CardData
var temporary_cost_modifier: int = 0


func _init(card_definition: CardData) -> void:
	definition = card_definition


func get_energy_cost() -> int:
	return maxi(0, definition.energy_cost + temporary_cost_modifier)
