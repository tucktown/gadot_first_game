extends SceneTree

var failures := 0
var _save_backup: Variant = null  # bytes of user://run.json, or null if none


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_backup_save()
	_test_relic_defaults()
	if failures == 0:
		print("Relic tests passed.")
	_restore_save()
	call_deferred("_finish")


func _finish() -> void:
	quit(failures)


func _test_relic_defaults() -> void:
	var relic := RelicData.new()
	_expect(relic.magnitude == 0, "Relic magnitude should default to 0.")
	_expect(relic.trigger == RelicData.Trigger.COMBAT_START, "Relic trigger should default to COMBAT_START.")
	_expect(relic.effect == RelicData.Effect.GAIN_BLOCK, "Relic effect should default to GAIN_BLOCK.")


func _backup_save() -> void:
	if FileAccess.file_exists("user://run.json"):
		_save_backup = FileAccess.get_file_as_bytes("user://run.json")


func _restore_save() -> void:
	if _save_backup != null:
		var file := FileAccess.open("user://run.json", FileAccess.WRITE)
		file.store_buffer(_save_backup)
	elif FileAccess.file_exists("user://run.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://run.json"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
