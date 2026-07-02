extends SceneTree

var failures := 0

# base id -> expected + id
const UPGRADES := {
	&"strike": &"strike_plus", &"defend": &"defend_plus",
	&"heavy_strike": &"heavy_strike_plus", &"guarded_strike": &"guarded_strike_plus",
	&"power_blow": &"power_blow_plus", &"quick_guard": &"quick_guard_plus",
	&"fortify": &"fortify_plus", &"second_wind": &"second_wind_plus",
	&"devour": &"devour_plus", &"mend": &"mend_plus",
	&"bulwark": &"bulwark_plus", &"rally": &"rally_plus",
	&"expose": &"expose_plus", &"sap": &"sap_plus",
	&"flex": &"flex_plus", &"venom_cut": &"venom_cut_plus",
}


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var catalog: Dictionary = RunState.CARD_CATALOG
	for base_id in UPGRADES:
		var plus_id: StringName = UPGRADES[base_id]
		_expect(catalog.has(base_id), "Base card %s should be catalogued." % base_id)
		_expect(catalog.has(plus_id), "Upgraded card %s should be catalogued." % plus_id)
		if catalog.has(base_id) and catalog.has(plus_id):
			var base: CardData = catalog[base_id]
			var plus: CardData = catalog[plus_id]
			_expect(base.upgrade_id == plus_id, "%s.upgrade_id should point to %s." % [base_id, plus_id])
			_expect(plus.upgrade_id == &"", "%s should not be further upgradable." % plus_id)
			_expect(_stats_improved(base, plus), "%s should improve on %s." % [plus_id, base_id])
	if failures == 0:
		print("Upgrade catalog tests passed.")
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _stats_improved(base: CardData, plus: CardData) -> bool:
	# At least one meaningful stat is strictly better.
	return (plus.damage > base.damage or plus.block > base.block or plus.heal > base.heal
		or plus.vulnerable_applied > base.vulnerable_applied or plus.weak_applied > base.weak_applied
		or plus.poison_applied > base.poison_applied or plus.strength_gained > base.strength_gained
		or plus.cards_drawn > base.cards_drawn or plus.energy_gained > base.energy_gained)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
