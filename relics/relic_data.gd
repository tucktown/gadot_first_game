class_name RelicData
extends Resource

enum Trigger { COMBAT_START, TURN_START }
enum Effect { GAIN_BLOCK, GAIN_ENERGY, GAIN_STRENGTH, DRAW_CARD }

@export var id: StringName
@export var display_name: String = "New Relic"
@export var description: String = ""
@export var trigger: Trigger = Trigger.COMBAT_START
@export var effect: Effect = Effect.GAIN_BLOCK
@export_range(0, 99) var magnitude: int = 0
