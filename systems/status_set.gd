class_name StatusSet
extends RefCounted

enum Type { VULNERABLE, WEAK, STRENGTH, POISON }

const _DISPLAY_ORDER := [Type.VULNERABLE, Type.WEAK, Type.STRENGTH, Type.POISON]
const _LABELS := {
	Type.VULNERABLE: "Vuln",
	Type.WEAK: "Weak",
	Type.STRENGTH: "Str",
	Type.POISON: "Poison",
}
const _KINDS := {
	Type.VULNERABLE: "debuff",
	Type.WEAK: "debuff",
	Type.STRENGTH: "buff",
	Type.POISON: "poison",
}

var stacks := {}


func amount(type: Type) -> int:
	return int(stacks.get(type, 0))


func add(type: Type, amount_to_add: int) -> void:
	if amount_to_add == 0:
		return
	var total := amount(type) + amount_to_add
	if total <= 0:
		stacks.erase(type)
	else:
		stacks[type] = total


func attack_bonus() -> int:
	return amount(Type.STRENGTH)


func outgoing_multiplier() -> float:
	return 0.75 if amount(Type.WEAK) > 0 else 1.0


func incoming_multiplier() -> float:
	return 1.25 if amount(Type.VULNERABLE) > 0 else 1.0


func tick_turn_start() -> int:
	var poison := amount(Type.POISON)
	if poison > 0:
		add(Type.POISON, -1)
	return poison


func tick_turn_end() -> void:
	add(Type.VULNERABLE, -1)
	add(Type.WEAK, -1)


func describe() -> Array:
	var out := []
	for type in _DISPLAY_ORDER:
		var n := amount(type)
		if n > 0:
			out.append({"label": _LABELS[type], "amount": n, "kind": _KINDS[type]})
	return out
