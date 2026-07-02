# systems/map_node.gd
class_name MapNode
extends RefCounted

enum Type { COMBAT, ELITE, REST, BOSS, SHOP }

var id: int = -1
var type: Type = Type.COMBAT
var row: int = 0
var column: int = 0
var edges: Array[int] = []       # ids of reachable nodes in the next row
var enemy_id: StringName = &""    # set for COMBAT/ELITE/BOSS; &"" for REST
