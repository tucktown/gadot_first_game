class_name CardView
extends PanelContainer

signal selected(card: CardInstance)

@onready var name_label: Label = %NameLabel
@onready var cost_label: Label = %CostLabel
@onready var description_label: Label = %DescriptionLabel
@onready var select_button: Button = %SelectButton

var card: CardInstance


func display(card_instance: CardInstance) -> void:
	card = card_instance
	name_label.text = card.definition.display_name
	cost_label.text = str(card.get_energy_cost())
	description_label.text = card.definition.description


func set_playable(is_playable: bool) -> void:
	select_button.disabled = not is_playable
	self_modulate = Color.WHITE if is_playable else Color(0.55, 0.55, 0.55, 1.0)


func _on_select_button_pressed() -> void:
	selected.emit(card)
