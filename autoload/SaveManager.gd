extends Node
## Save / load the game in 3 slots: user://saves/slot_1.json ... slot_3.json
## A save is a JSON copy of GameState (see GameState.to_dict / from_dict).
## Each save has a "version" so old saves can be upgraded after game updates.
##
## On Windows, user:// is %APPDATA%\Godot\app_userdata\Habal-Habal Simulator\

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3
const SAVE_VERSION := 1


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	return latest_slot() != -1


## Saves the current GameState into a slot. Returns true on success.
func save_game(slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := GameState.to_dict()
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	data["saved_unix"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save slot %d (error %d)" % [slot, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	GameState.save_slot = slot
	return true


## Loads a slot into GameState. Returns true on success.
func load_game(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	data = _upgrade(data)
	GameState.from_dict(data)
	GameState.save_slot = slot
	return true


## Raw save data for showing slot info in menus ({} if empty/broken).
func read_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var text := FileAccess.get_file_as_string(slot_path(slot))
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("Save slot %d is broken and was ignored." % slot)
	return {}


func delete_slot(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


## The most recently saved slot (for "Continue"), or -1.
func latest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for slot in range(1, SLOT_COUNT + 1):
		var data := read_slot(slot)
		if data.is_empty():
			continue
		var t := float(data.get("saved_unix", 0.0))
		if t > best_time:
			best_time = t
			best = slot
	return best


## Short text for a menu button, e.g. "Day 3 · Juan · ₱61,200".
func describe_slot(slot: int) -> String:
	var data := read_slot(slot)
	if data.is_empty():
		return "Empty"
	return "Day %d · %s · %s" % [int(data.get("day", 1)), str(data.get("player_name", "?")),
		Economy.format_peso(int(data.get("money", 0)))]


## Upgrade old save formats here when SAVE_VERSION goes up.
func _upgrade(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version < 1:
		pass   # (example) version 0 -> 1 changes would go here
	return data
