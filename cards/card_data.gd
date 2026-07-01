class_name CardData
extends Resource

enum Target {
	NONE,
	SELF,
	SINGLE_ENEMY,
}

@export_category("Identity")
@export var id: StringName
@export var display_name: String = "New Card"
@export_multiline var description: String

@export_category("Rules")
@export_range(0, 9) var energy_cost: int = 1
@export var target: Target = Target.SINGLE_ENEMY
@export_range(0, 999) var damage: int = 0
@export_range(0, 999) var block: int = 0
@export_range(0, 9) var cards_drawn: int = 0
@export_range(0, 9) var energy_gained: int = 0
@export var retains_block: bool = false
@export_range(0, 999) var heal: int = 0
@export var heals_for_damage_dealt: bool = false
@export var energy_uncapped: bool = false
@export_range(0, 99) var vulnerable_applied: int = 0
@export_range(0, 99) var weak_applied: int = 0
@export_range(0, 99) var poison_applied: int = 0
@export_range(0, 99) var strength_gained: int = 0

@export_category("Presentation")
@export var artwork: Texture2D
