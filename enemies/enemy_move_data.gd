class_name EnemyMoveData
extends Resource

@export var display_name: String = "Enemy Move"
@export_range(0, 999) var damage: int = 0
@export_range(0, 999) var block: int = 0
@export_range(0, 99) var weak_applied: int = 0
@export_range(0, 99) var vulnerable_applied: int = 0
@export_range(0, 99) var poison_applied: int = 0
@export_range(0, 99) var strength_gained: int = 0
