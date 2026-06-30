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

@export_category("Presentation")
@export var artwork: Texture2D
