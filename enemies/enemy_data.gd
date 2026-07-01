class_name EnemyData
extends Resource

@export var id: StringName
@export var display_name: String = "New Enemy"
@export_range(1, 9999) var max_health: int = 20
@export var moves: Array[EnemyMoveData] = []
@export var artwork: Texture2D
