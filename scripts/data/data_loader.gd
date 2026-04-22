extends Node

signal data_reloaded

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")

const BUILDINGS_PATH := "res://data/buildings.json"
const SETTLEMENTS_PATH := "res://data/settlements.json"
const UI_TEXT_PATH := "res://data/ui_text.json"
const WORLD_CONFIG_PATH := "res://data/world.json"
const RECRUITMENT_CONFIG_PATH := "res://data/recruitment.json"
const HEROES_PATH := "res://data/heroes.json"
const ITEMS_PATH := "res://data/items.json"
const EQUIPMENT_PATH := "res://data/equipment.json"

const HERO_MODS_ROOT := "user://mods/heroes"
const ITEM_MODS_ROOT := "user://mods/items"
const EQUIPMENT_MODS_ROOT := "user://mods/equipment"

const TEMPLATE_HERO_MOD_ID := "template_hero"
const TEMPLATE_ITEM_MOD_ID := "template_item"
const TEMPLATE_EQUIPMENT_MOD_ID := "template_equipment"

const DEFAULT_HERO_IMAGE := "res://icon.svg"
const DEFAULT_CATALOG_ICON := "res://icon.svg"
const DEFAULT_ITEM_MAX_STACK := 100000

const HERO_CLASSES := ["Attacker", "Defender", "Supporter"]
const HERO_EQUIPMENT_KEYS := ["head", "chest", "gloves", "boots", "amulet", "ring_1"]

const DEFAULT_HERO_STATS := {
	"health": 100,
	"sanity": 100,
	"attack": 10,
	"defense": 10,
	"critical_chance": 5,
	"critical_damage": 150,
}

const DEFAULT_HERO_STAT_GROWTH := {
	"health": 3,
	"sanity": 2,
	"attack": 1,
	"defense": 1,
	"critical_chance": 1,
	"critical_damage": 1,
}

const DEFAULT_HERO_WORK_STATS := {
	"farming": 0,
	"mining": 0,
	"lumbering": 0,
}

const DEFAULT_HERO_WORK_STAT_GROWTH := {
	"farming": 1,
	"mining": 1,
	"lumbering": 1,
}

var building_definitions: Dictionary = {}
var settlement_definitions: Dictionary = {}
var ui_texts: Dictionary = {}
var world_config: Dictionary = {}
var recruitment_config: Dictionary = {}
var hero_definitions: Dictionary = {}
var item_definitions: Dictionary = {}
var equipment_definitions: Dictionary = {}

var settlement_pool: Array = []
var hero_pool: Array = []
var item_pool: Array = []
var equipment_pool: Array = []


func _ready() -> void:
	reload_data()


func reload_data() -> void:
	building_definitions.clear()
	settlement_definitions.clear()
	ui_texts.clear()
	world_config.clear()
	recruitment_config.clear()
	hero_definitions.clear()
	item_definitions.clear()
	equipment_definitions.clear()
	settlement_pool.clear()
	hero_pool.clear()
	item_pool.clear()
	equipment_pool.clear()

	_load_ui_texts()
	_load_world_config()
	_load_recruitment_config()
	_load_settlements()
	_load_buildings()
	_load_core_heroes()
	_load_mod_heroes()
	_load_core_items()
	_load_mod_items()
	_load_core_equipment()
	_load_mod_equipment()

	emit_signal("data_reloaded")


func get_building_definition(building_id: String) -> Dictionary:
	return (building_definitions.get(building_id, {}) as Dictionary).duplicate(true)


func get_ui_text(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	var text := str(ui_texts.get(key, fallback if not fallback.is_empty() else key))
	for replacement_key in replacements.keys():
		text = text.replace("{%s}" % str(replacement_key), str(replacements[replacement_key]))
	return text


func get_world_config() -> Dictionary:
	return world_config.duplicate(true)


func get_recruitment_config() -> Dictionary:
	return recruitment_config.duplicate(true)


func get_world_zone_override(zone_key: String) -> Dictionary:
	var overrides := _as_dictionary(world_config.get("overrides", {}))
	return _as_dictionary(overrides.get(zone_key, {})).duplicate(true)


func get_settlement_definition(settlement_id: String) -> Dictionary:
	return (settlement_definitions.get(settlement_id, {}) as Dictionary).duplicate(true)


func get_all_settlements() -> Array:
	return _duplicate_dictionary_array(settlement_pool)


func get_default_settlement_id() -> String:
	if settlement_pool.is_empty():
		return ""
	return String((settlement_pool[0] as Dictionary).get("id", "")).strip_edges()


func get_building_ids() -> Array:
	return building_definitions.keys()


func get_all_buildings() -> Array:
	return _duplicate_dictionary_array(building_definitions.values())


func get_hero_definition(hero_id: String) -> Dictionary:
	return (hero_definitions.get(hero_id, {}) as Dictionary).duplicate(true)


func get_all_heroes() -> Array:
	return _duplicate_dictionary_array(hero_pool)


func get_item_definition(item_id: String) -> Dictionary:
	return (item_definitions.get(item_id, {}) as Dictionary).duplicate(true)


func get_all_items() -> Array:
	return _duplicate_dictionary_array(item_pool)


func get_equipment_definition(equipment_id: String) -> Dictionary:
	return (equipment_definitions.get(equipment_id, {}) as Dictionary).duplicate(true)


func get_all_equipment() -> Array:
	return _duplicate_dictionary_array(equipment_pool)


func get_mod_category_summaries(category: String) -> Array:
	var normalized_category := String(category).strip_edges().to_lower()
	var root_path := ""
	var json_file_name := ""
	var includes_portrait := false
	var definitions: Array = []
	match normalized_category:
		"heroes":
			root_path = HERO_MODS_ROOT
			json_file_name = "hero.json"
			includes_portrait = true
			definitions = hero_pool
		"items":
			root_path = ITEM_MODS_ROOT
			json_file_name = "item.json"
			definitions = item_pool
		"equipment":
			root_path = EQUIPMENT_MODS_ROOT
			json_file_name = "equipment.json"
			definitions = equipment_pool
		_:
			return []
	var summaries: Array = []
	for folder_name in _get_mod_folders(root_path):
		var mod_folder_path := root_path.path_join(folder_name)
		var loaded_count := 0
		for definition_value in definitions:
			var definition := _as_dictionary(definition_value)
			if String(definition.get("source", "")) == "mod" and String(definition.get("mod_id", "")) == folder_name:
				loaded_count += 1
		var includes: Array = []
		var missing: Array = []
		if FileAccess.file_exists(mod_folder_path.path_join(json_file_name)):
			includes.append(json_file_name)
		else:
			missing.append(json_file_name)
		if FileAccess.file_exists(mod_folder_path.path_join("icon.png")):
			includes.append("icon.png")
		else:
			missing.append("icon.png")
		if includes_portrait:
			if FileAccess.file_exists(mod_folder_path.path_join("portrait.png")):
				includes.append("portrait.png")
			else:
				missing.append("portrait.png")
		summaries.append({
			"id": folder_name,
			"category": normalized_category,
			"loaded_count": loaded_count,
			"includes": includes,
			"missing": missing,
		})
	return summaries


func create_empty_hero_equipment() -> Dictionary:
	var equipment: Dictionary = {}
	for slot_key in HERO_EQUIPMENT_KEYS:
		equipment[slot_key] = ""
	return equipment


func normalize_hero_class(hero_class: String) -> String:
	var normalized_input := hero_class.strip_edges().to_lower()
	match normalized_input:
		"":
			return "Supporter"
		"attacker":
			return "Attacker"
		"defender":
			return "Defender"
		"supporter":
			return "Supporter"
		_:
			return "Supporter"


func normalize_hero_definition(entry: Dictionary, source: String = "core", mod_id: String = "", mod_folder_path: String = "") -> Dictionary:
	if entry.is_empty():
		return {}

	var hero_id := _sanitize_identifier(String(entry.get("id", "")))
	if hero_id.is_empty() and source == "mod":
		hero_id = _sanitize_identifier(mod_id)
	if hero_id.is_empty():
		return {}

	var hero_name := String(entry.get("name", "")).strip_edges()
	if hero_name.is_empty():
		return {}

	var original_class := String(entry.get("class", "")).strip_edges()
	var normalized_class := normalize_hero_class(original_class)
	if not original_class.is_empty() and not HERO_CLASSES.has(original_class) and original_class != normalized_class:
		push_warning("Normalized hero class '%s' to '%s' for hero '%s'." % [original_class, normalized_class, hero_id])

	var normalized: Dictionary = {
		"id": hero_id,
		"name": hero_name,
		"class": normalized_class,
		"description": String(entry.get("description", "")).strip_edges(),
		"level": max(1, int(entry.get("level", 1))),
		"experience": max(int(entry.get("experience", 0)), max(int(entry.get("level", 1)) - 1, 0) * 10),
		"recruitment_weight": max(1, int(entry.get("recruitment_weight", 1))),
		"recruit_cost": _normalize_recruit_cost_entries(entry.get("recruit_cost", [])),
		"stats": _normalize_stat_block(entry.get("stats", {}), DEFAULT_HERO_STATS),
		"stat_growth": _normalize_growth_block(entry.get("stat_growth", {}), DEFAULT_HERO_STAT_GROWTH),
		"work_stats": _normalize_stat_block(entry.get("work_stats", {}), DEFAULT_HERO_WORK_STATS),
		"work_stat_growth": _normalize_growth_block(entry.get("work_stat_growth", {}), DEFAULT_HERO_WORK_STAT_GROWTH),
		"source": source,
		"mod_id": mod_id if source == "mod" else "",
		"portrait_path": _resolve_catalog_image_path(entry, mod_folder_path, "portrait_path", "portrait.png", DEFAULT_HERO_IMAGE),
		"icon_path": _resolve_catalog_image_path(entry, mod_folder_path, "icon_path", "icon.png", DEFAULT_HERO_IMAGE),
	}
	if entry.has("schema_version"):
		normalized["schema_version"] = entry["schema_version"]
	return normalized


func normalize_settlement_definition(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var settlement_id := _sanitize_identifier(String(entry.get("id", "")))
	if settlement_id.is_empty():
		return {}
	var settlement_name := String(entry.get("name", "")).strip_edges()
	if settlement_name.is_empty():
		return {}
	var normalized: Dictionary = {
		"id": settlement_id,
		"name": settlement_name,
		"icon_path": _resolve_catalog_image_path(entry, "", "icon_path", "icon.png", DEFAULT_CATALOG_ICON),
		"biome": String(entry.get("biome", "neutral")).strip_edges().to_lower(),
		"plot_count": max(1, int(entry.get("plot_count", SettlementGameData.GRID_SIZE))),
		"allowed_buildings": _normalize_allowed_buildings(entry.get("allowed_buildings", ["ALL"])),
	}
	if entry.has("schema_version"):
		normalized["schema_version"] = entry["schema_version"]
	return normalized


func _normalize_recruit_cost_entries(value: Variant) -> Array:
	var normalized_entries: Array = []
	if value is not Array:
		return normalized_entries
	for entry_value in value:
		if entry_value is not Dictionary:
			continue
		var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
		var resource_id := String(entry.get("resource", "")).strip_edges()
		if resource_id.is_empty():
			continue
		var normalized_entry: Dictionary = {
			"resource": resource_id,
		}
		if entry.has("min_amount") or entry.has("max_amount"):
			var min_amount := int(entry.get("min_amount", 0))
			var max_amount := int(entry.get("max_amount", min_amount))
			if max_amount < min_amount:
				var swap_amount := min_amount
				min_amount = max_amount
				max_amount = swap_amount
			normalized_entry["min_amount"] = max(0, min_amount)
			normalized_entry["max_amount"] = max(0, max_amount)
		else:
			var amount_value = entry.get("amount", 0)
			if amount_value is String:
				var amount_text := String(amount_value).strip_edges()
				var separator_index := amount_text.find("-")
				if separator_index > 0 and separator_index < amount_text.length() - 1:
					var min_text := amount_text.substr(0, separator_index).strip_edges()
					var max_text := amount_text.substr(separator_index + 1).strip_edges()
					var min_amount := int(min_text)
					var max_amount := int(max_text)
					if max_amount < min_amount:
						var swap_amount := min_amount
						min_amount = max_amount
						max_amount = swap_amount
					normalized_entry["min_amount"] = max(0, min_amount)
					normalized_entry["max_amount"] = max(0, max_amount)
				else:
					normalized_entry["amount"] = max(0, int(amount_text))
			else:
				normalized_entry["amount"] = max(0, int(amount_value))
		normalized_entry["per_level"] = int(entry.get("per_level", 0))
		normalized_entries.append(normalized_entry)
	return normalized_entries


func normalize_building_definition(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var building_id := _sanitize_identifier(String(entry.get("id", "")))
	if building_id.is_empty():
		return {}
	var building_name := String(entry.get("name", "")).strip_edges()
	if building_name.is_empty():
		return {}
	var normalized: Dictionary = {
		"id": building_id,
		"name": building_name,
		"description": String(entry.get("description", "")).strip_edges(),
		"icon_path": _resolve_catalog_image_path(entry, "", "icon_path", "icon.png", DEFAULT_CATALOG_ICON),
		"build_cost": _duplicate_dictionary_array(entry.get("build_cost", [])),
		"upgrade_cost": _duplicate_dictionary_array(entry.get("upgrade_cost", [])),
		"upgrade_growth": float(entry.get("upgrade_growth", 1.0)),
		"base_production": _duplicate_dictionary_array(entry.get("base_production", [])),
		"worker_slots": max(0, int(entry.get("worker_slots", 0))),
		"max_level": max(1, int(entry.get("max_level", 1))),
	}
	if entry.has("recruit_cost"):
		normalized["recruit_cost"] = _duplicate_dictionary_array(entry.get("recruit_cost", []))
	if entry.has("schema_version"):
		normalized["schema_version"] = entry["schema_version"]
	return normalized


func normalize_item_definition(entry: Dictionary, source: String = "core", mod_id: String = "", mod_folder_path: String = "", fallback_id: String = "") -> Dictionary:
	if entry.is_empty():
		return {}
	var item_id := _sanitize_identifier(String(entry.get("id", "")))
	if item_id.is_empty() and source == "mod":
		item_id = _sanitize_identifier(fallback_id if not fallback_id.is_empty() else mod_id)
	if item_id.is_empty():
		return {}
	var item_name := String(entry.get("name", "")).strip_edges()
	if item_name.is_empty():
		return {}
	var normalized: Dictionary = {
		"id": item_id,
		"name": item_name,
		"icon_path": _resolve_catalog_image_path(entry, mod_folder_path, "icon_path", "icon.png", DEFAULT_CATALOG_ICON),
		"max_stack": max(1, int(entry.get("max_stack", DEFAULT_ITEM_MAX_STACK))),
		"source": source,
		"mod_id": mod_id if source == "mod" else "",
	}
	if entry.has("schema_version"):
		normalized["schema_version"] = entry["schema_version"]
	return normalized


func normalize_equipment_definition(entry: Dictionary, source: String = "core", mod_id: String = "", mod_folder_path: String = "", fallback_id: String = "") -> Dictionary:
	if entry.is_empty():
		return {}
	var equipment_id := _sanitize_identifier(String(entry.get("id", "")))
	if equipment_id.is_empty() and source == "mod":
		equipment_id = _sanitize_identifier(fallback_id if not fallback_id.is_empty() else mod_id)
	if equipment_id.is_empty():
		return {}
	var equipment_name := String(entry.get("name", "")).strip_edges()
	if equipment_name.is_empty():
		return {}
	var slot_key := String(entry.get("slot", "")).strip_edges().to_lower()
	if not HERO_EQUIPMENT_KEYS.has(slot_key):
		push_warning("Skipping equipment '%s' with invalid slot '%s'." % [equipment_id, slot_key])
		return {}
	var normalized: Dictionary = {
		"id": equipment_id,
		"name": equipment_name,
		"slot": slot_key,
		"icon_path": _resolve_catalog_image_path(entry, mod_folder_path, "icon_path", "icon.png", DEFAULT_CATALOG_ICON),
		"bonuses": _normalize_equipment_bonuses(entry.get("bonuses", {})),
		"source": source,
		"mod_id": mod_id if source == "mod" else "",
	}
	if entry.has("schema_version"):
		normalized["schema_version"] = entry["schema_version"]
	return normalized


func _load_ui_texts() -> void:
	var text_payload: Dictionary = _load_json(UI_TEXT_PATH)
	if text_payload.get("texts", null) is Dictionary:
		ui_texts = (text_payload["texts"] as Dictionary).duplicate(true)


func _load_world_config() -> void:
	var payload: Dictionary = _load_json(WORLD_CONFIG_PATH)
	if payload.get("config", null) is Dictionary:
		world_config = (payload["config"] as Dictionary).duplicate(true)


func _load_recruitment_config() -> void:
	var payload: Dictionary = _load_json(RECRUITMENT_CONFIG_PATH)
	if payload.get("config", null) is Dictionary:
		recruitment_config = (payload["config"] as Dictionary).duplicate(true)


func _load_buildings() -> void:
	var buildings_payload: Dictionary = _load_json(BUILDINGS_PATH)
	_load_catalog_entries(buildings_payload.get("buildings", []), Callable(self, "normalize_building_definition"), Callable(self, "_register_building_definition"))


func _load_settlements() -> void:
	var settlements_payload: Dictionary = _load_json(SETTLEMENTS_PATH)
	_load_catalog_entries(settlements_payload.get("settlements", []), Callable(self, "normalize_settlement_definition"), Callable(self, "_register_settlement_definition"))


func _load_core_heroes() -> void:
	var heroes_payload: Dictionary = _load_json(HEROES_PATH)
	_load_catalog_entries(heroes_payload.get("heroes", []), Callable(self, "normalize_hero_definition").bind("core", "", ""), Callable(self, "_register_hero_definition"))


func _load_core_items() -> void:
	var items_payload: Dictionary = _load_json(ITEMS_PATH)
	_load_catalog_entries(items_payload.get("items", []), Callable(self, "normalize_item_definition").bind("core", "", ""), Callable(self, "_register_item_definition"))


func _load_core_equipment() -> void:
	var equipment_payload: Dictionary = _load_json(EQUIPMENT_PATH)
	_load_catalog_entries(equipment_payload.get("equipment", []), Callable(self, "normalize_equipment_definition").bind("core", "", ""), Callable(self, "_register_equipment_definition"))


func _load_mod_heroes() -> void:
	for folder_name in _get_mod_folders(HERO_MODS_ROOT):
		var mod_folder_path := HERO_MODS_ROOT.path_join(folder_name)
		var hero_json_path := mod_folder_path.path_join("hero.json")
		if not FileAccess.file_exists(hero_json_path):
			continue
		var payload: Dictionary = _load_json(hero_json_path)
		var hero_entry: Dictionary = payload["hero"] if payload.get("hero", null) is Dictionary else payload
		var normalized := normalize_hero_definition(hero_entry, "mod", folder_name, mod_folder_path)
		if normalized.is_empty():
			push_warning("Skipping malformed mod hero in %s." % hero_json_path)
			continue
		_register_hero_definition(normalized)


func _load_mod_items() -> void:
	for folder_name in _get_mod_folders(ITEM_MODS_ROOT):
		var mod_folder_path := ITEM_MODS_ROOT.path_join(folder_name)
		var item_json_path := mod_folder_path.path_join("item.json")
		if not FileAccess.file_exists(item_json_path):
			continue
		var payload: Dictionary = _load_json(item_json_path)
		var item_entries := _get_mod_definition_entries(payload, "item", "items")
		for entry_index in range(item_entries.size()):
			var item_entry: Dictionary = item_entries[entry_index]
			var normalized := normalize_item_definition(item_entry, "mod", folder_name, mod_folder_path, "%s_item_%d" % [folder_name, entry_index + 1])
			if normalized.is_empty():
				push_warning("Skipping malformed mod item in %s." % item_json_path)
				continue
			_register_item_definition(normalized)


func _load_mod_equipment() -> void:
	for folder_name in _get_mod_folders(EQUIPMENT_MODS_ROOT):
		var mod_folder_path := EQUIPMENT_MODS_ROOT.path_join(folder_name)
		var equipment_json_path := mod_folder_path.path_join("equipment.json")
		if not FileAccess.file_exists(equipment_json_path):
			continue
		var payload: Dictionary = _load_json(equipment_json_path)
		var equipment_entries := _get_mod_definition_entries(payload, "equipment", "equipment")
		for entry_index in range(equipment_entries.size()):
			var equipment_entry: Dictionary = equipment_entries[entry_index]
			var normalized := normalize_equipment_definition(equipment_entry, "mod", folder_name, mod_folder_path, "%s_equipment_%d" % [folder_name, entry_index + 1])
			if normalized.is_empty():
				push_warning("Skipping malformed mod equipment in %s." % equipment_json_path)
				continue
			_register_equipment_definition(normalized)


func _register_hero_definition(hero_definition: Dictionary) -> void:
	_register_definition(hero_definition, hero_definitions, hero_pool, "hero")


func _register_building_definition(building_definition: Dictionary) -> void:
	_register_definition(building_definition, building_definitions, [], "building")


func _register_settlement_definition(settlement_definition: Dictionary) -> void:
	_register_definition(settlement_definition, settlement_definitions, settlement_pool, "settlement")


func _register_item_definition(item_definition: Dictionary) -> void:
	_register_definition(item_definition, item_definitions, item_pool, "item")


func _register_equipment_definition(equipment_definition: Dictionary) -> void:
	_register_definition(equipment_definition, equipment_definitions, equipment_pool, "equipment")


func _register_definition(definition: Dictionary, target_map: Dictionary, target_pool: Array, label: String) -> void:
	if definition.is_empty():
		return
	var definition_id := String(definition.get("id", ""))
	if definition_id.is_empty():
		return
	if target_map.has(definition_id):
		push_warning("Skipping duplicate %s definition id '%s'." % [label, definition_id])
		return
	target_map[definition_id] = definition.duplicate(true)
	target_pool.append(definition.duplicate(true))




func _get_mod_folders(root_path: String) -> Array[String]:
	var mods_dir := DirAccess.open(root_path)
	if mods_dir == null:
		return []
	var mod_folders: Array[String] = []
	mods_dir.list_dir_begin()
	var entry_name := mods_dir.get_next()
	while not entry_name.is_empty():
		if mods_dir.current_is_dir() and not entry_name.begins_with("."):
			mod_folders.append(entry_name)
		entry_name = mods_dir.get_next()
	mods_dir.list_dir_end()
	mod_folders.sort()
	return mod_folders


func _load_catalog_entries(entries_value: Variant, normalize_callable: Callable, register_callable: Callable) -> void:
	if entries_value is not Array:
		return
	for entry in entries_value:
		if entry is Dictionary:
			var normalized = normalize_callable.call(entry)
			register_callable.call(normalized)


func _get_mod_definition_entries(payload: Dictionary, singular_key: String, plural_key: String) -> Array:
	var entries: Array = []
	if payload.get(plural_key, null) is Array:
		entries = payload[plural_key]
	elif payload.get(singular_key, null) is Dictionary:
		entries = [payload[singular_key]]
	elif not payload.is_empty():
		entries = [payload]
	var normalized_entries: Array = []
	for entry in entries:
		if entry is Dictionary:
			normalized_entries.append(entry)
	return normalized_entries


func _resolve_catalog_image_path(entry: Dictionary, mod_folder_path: String, field_name: String, file_name: String, fallback_path: String) -> String:
	if not mod_folder_path.is_empty():
		var mod_image_path := mod_folder_path.path_join(file_name)
		if _resource_path_exists(mod_image_path):
			return mod_image_path
	var raw_path := String(entry.get(field_name, entry.get(field_name.replace("_path", ""), ""))).strip_edges()
	if _resource_path_exists(raw_path):
		return raw_path
	return fallback_path


func _resource_path_exists(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with("user://"):
		return FileAccess.file_exists(path)
	if path.begins_with("res://"):
		return ResourceLoader.exists(path)
	return FileAccess.file_exists(path)


func _normalize_equipment_bonuses(value: Variant) -> Dictionary:
	var source_data := _as_dictionary(value)
	var stats_source := _as_dictionary(source_data.get("stats", {}))
	var work_source := _as_dictionary(source_data.get("work_stats", {}))
	if stats_source.is_empty() and work_source.is_empty():
		stats_source = source_data
		work_source = source_data
	return {
		"stats": _normalize_bonus_block(stats_source, DEFAULT_HERO_STATS.keys()),
		"work_stats": _normalize_bonus_block(work_source, DEFAULT_HERO_WORK_STATS.keys()),
	}


func _normalize_bonus_block(source_data: Dictionary, allowed_keys: Array) -> Dictionary:
	var normalized: Dictionary = {}
	for stat_key in allowed_keys:
		var amount := int(source_data.get(stat_key, 0))
		if amount != 0:
			normalized[stat_key] = amount
	return normalized


func _normalize_stat_block(value: Variant, defaults: Dictionary) -> Dictionary:
	var source_data := _as_dictionary(value)
	var normalized: Dictionary = {}
	for stat_key in defaults.keys():
		normalized[stat_key] = int(source_data.get(stat_key, defaults[stat_key]))
	return normalized


func _normalize_growth_block(value: Variant, defaults: Dictionary) -> Dictionary:
	var source_data := _as_dictionary(value)
	var normalized: Dictionary = {}
	for stat_key in defaults.keys():
		var stat_value: Variant = source_data.get(stat_key, defaults[stat_key])
		if stat_value is Dictionary:
			var range_data := stat_value as Dictionary
			var min_amount := int(range_data.get("min", range_data.get("min_amount", defaults[stat_key])))
			var max_amount := int(range_data.get("max", range_data.get("max_amount", min_amount)))
			if max_amount < min_amount:
				var swap_amount := min_amount
				min_amount = max_amount
				max_amount = swap_amount
			normalized[stat_key] = {"min": min_amount, "max": max_amount}
		elif stat_value is String:
			var stat_text := String(stat_value).strip_edges()
			var separator_index := stat_text.find("-")
			if separator_index > 0 and separator_index < stat_text.length() - 1:
				var min_amount := int(stat_text.substr(0, separator_index).strip_edges())
				var max_amount := int(stat_text.substr(separator_index + 1).strip_edges())
				if max_amount < min_amount:
					var swap_amount := min_amount
					min_amount = max_amount
					max_amount = swap_amount
				normalized[stat_key] = {"min": min_amount, "max": max_amount}
			else:
				normalized[stat_key] = int(stat_text)
		else:
			normalized[stat_key] = int(stat_value)
	return normalized


func _normalize_allowed_buildings(value: Variant) -> Array:
	var normalized: Array = []
	if value is not Array:
		return ["ALL"]
	for entry in value:
		var building_key := String(entry).strip_edges()
		if building_key.is_empty():
			continue
		if building_key.to_upper() == "ALL":
			return ["ALL"]
		normalized.append(building_key)
	if normalized.is_empty():
		return ["ALL"]
	return normalized


func _duplicate_dictionary_array(source: Variant) -> Array:
	var copy: Array = []
	if source is Array:
		for entry in source:
			if entry is Dictionary:
				copy.append((entry as Dictionary).duplicate(true))
	return copy


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _sanitize_identifier(value: String) -> String:
	var input := value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	var result := ""
	for index in range(input.length()):
		var code := input.unicode_at(index)
		var character := input.substr(index, 1)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "_":
			result += character
	return result


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var raw_text := FileAccess.get_file_as_string(path)
	if raw_text.is_empty():
		return {}
	var parsed = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed
	push_warning("Failed to parse data file: %s" % path)
	return {}
