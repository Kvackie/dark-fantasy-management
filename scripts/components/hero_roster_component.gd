extends RefCounted


static func create_hero_instance(hero_definition: Dictionary, assigned_uid: int) -> Dictionary:
	var hero_instance: Dictionary = {
		"uid": assigned_uid,
		"definition_id": String(hero_definition.get("id", "")),
		"name": String(hero_definition.get("name", "Unknown Hero")),
		"class": String(hero_definition.get("class", "Supporter")),
		"assigned_settlement_id": "",
		"assigned_slot": -1,
		"level": clampi(int(hero_definition.get("level", 1)), 1, 9999),
		"stats": _normalize_runtime_stats(hero_definition.get("stats", {}), DataLoader.DEFAULT_HERO_STATS),
		"work_stats": _normalize_runtime_stats(hero_definition.get("work_stats", {}), DataLoader.DEFAULT_HERO_WORK_STATS),
		"equipment": DataLoader.create_empty_hero_equipment(),
		"world_task": _create_idle_world_task(),
		"source": String(hero_definition.get("source", "core")),
		"mod_id": String(hero_definition.get("mod_id", "")),
	}
	return hero_instance


static func create_hero_instance_from_offer(offer_data: Dictionary, assigned_uid: int) -> Dictionary:
	var hero_instance: Dictionary = {
		"uid": assigned_uid,
		"definition_id": String(offer_data.get("definition_id", "")),
		"name": String(offer_data.get("name", "Unknown Hero")),
		"class": String(offer_data.get("class", "Supporter")),
		"assigned_settlement_id": "",
		"assigned_slot": -1,
		"level": clampi(int(offer_data.get("level", 1)), 1, 9999),
		"stats": _normalize_runtime_stats(offer_data.get("stats", {}), DataLoader.DEFAULT_HERO_STATS),
		"work_stats": _normalize_runtime_stats(offer_data.get("work_stats", {}), DataLoader.DEFAULT_HERO_WORK_STATS),
		"equipment": DataLoader.create_empty_hero_equipment(),
		"world_task": _create_idle_world_task(),
		"source": String(offer_data.get("source", "core")),
		"mod_id": String(offer_data.get("mod_id", "")),
	}
	return hero_instance


static func normalize_loaded_hero(hero_data: Dictionary, fallback_uid: int) -> Dictionary:
	var definition_id := String(hero_data.get("definition_id", ""))
	var hero_definition: Dictionary = DataLoader.get_hero_definition(definition_id)
	var normalized: Dictionary = {
		"uid": int(hero_data.get("uid", fallback_uid)),
		"definition_id": definition_id,
		"name": String(hero_data.get("name", hero_definition.get("name", "Unknown Hero"))),
		"class": String(hero_definition.get("class", DataLoader.normalize_hero_class(String(hero_data.get("class", "Supporter"))))),
		"level": clampi(int(hero_data.get("level", 1)), 1, 9999),
		"assigned_settlement_id": String(hero_data.get("assigned_settlement_id", "")).strip_edges(),
		"assigned_slot": int(hero_data.get("assigned_slot", -1)),
		"stats": _normalize_runtime_stats(hero_data.get("stats", {}), hero_definition.get("stats", DataLoader.DEFAULT_HERO_STATS)),
		"work_stats": _normalize_runtime_stats(hero_data.get("work_stats", {}), hero_definition.get("work_stats", DataLoader.DEFAULT_HERO_WORK_STATS)),
		"equipment": _normalize_runtime_equipment(hero_data.get("equipment", {})),
		"world_task": _normalize_world_task(hero_data.get("world_task", {})),
		"source": String(hero_data.get("source", hero_definition.get("source", "core"))),
		"mod_id": String(hero_data.get("mod_id", hero_definition.get("mod_id", ""))),
	}
	if normalized["name"] == "Unknown Hero" and not hero_definition.is_empty():
		normalized["name"] = String(hero_definition.get("name", "Unknown Hero"))
	return normalized


static func _normalize_runtime_stats(value: Variant, fallback_value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var fallback: Dictionary = _as_dictionary(fallback_value)
	if fallback.is_empty():
		fallback = DataLoader.DEFAULT_HERO_STATS
	var normalized: Dictionary = {}
	for stat_key in fallback.keys():
		normalized[stat_key] = int(source_data.get(stat_key, fallback[stat_key]))
	return normalized


static func _normalize_runtime_equipment(value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var equipment: Dictionary = DataLoader.create_empty_hero_equipment()
	for slot_key in equipment.keys():
		equipment[slot_key] = String(source_data.get(slot_key, "")).strip_edges()
	return equipment


static func _create_idle_world_task() -> Dictionary:
	return {
		"type": "",
		"zone_key": "",
	}


static func _normalize_world_task(value: Variant) -> Dictionary:
	var task_data := _as_dictionary(value)
	return {
		"type": String(task_data.get("type", "")).strip_edges(),
		"zone_key": String(task_data.get("zone_key", "")).strip_edges(),
	}


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}
