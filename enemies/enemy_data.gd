class_name EnemyData
extends Resource

@export var id: StringName
@export var display_name: String = "New Enemy"
@export_range(1, 9999) var max_health: int = 20
@export var move_pattern: Array[EnemyMoveData] = []
@export var artwork: Texture2D


func get_move(turn_index: int) -> EnemyMoveData:
	if move_pattern.is_empty():
		return null
	return move_pattern[turn_index % move_pattern.size()]
