extends RefCounted


static func create_hero_instance(hero_definition: Dictionary, assigned_uid: int) -> Dictionary:
	var hero_level := clampi(int(hero_definition.get("level", 1)), 1, 9999)
	var stat_growth := _resolve_growth_block(hero_definition.get("stat_growth", {}), DataLoader.DEFAULT_HERO_STAT_GROWTH)
	var work_stat_growth := _resolve_growth_block(hero_definition.get("work_stat_growth", {}), DataLoader.DEFAULT_HERO_WORK_STAT_GROWTH)
	var hero_instance: Dictionary = {
		"uid": assigned_uid,
		"definition_id": String(hero_definition.get("id", "")),
		"name": String(hero_definition.get("name", "Unknown Hero")),
		"class": String(hero_definition.get("class", "Supporter")),
		"assigned_settlement_id": "",
		"assigned_slot": -1,
		"level": hero_level,
		"experience": _normalize_experience(int(hero_definition.get("experience", 0)), hero_level),
		"stat_growth": stat_growth,
		"work_stat_growth": work_stat_growth,
		"stats": _build_runtime_stats(hero_definition, stat_growth, hero_level, {}),
		"work_stats": _build_runtime_work_stats(hero_definition, work_stat_growth, hero_level),
		"equipment": DataLoader.create_empty_hero_equipment(),
		"world_task": _create_idle_world_task(),
		"source": String(hero_definition.get("source", "core")),
		"mod_id": String(hero_definition.get("mod_id", "")),
	}
	return hero_instance


static func create_hero_instance_from_offer(offer_data: Dictionary, assigned_uid: int) -> Dictionary:
	var hero_level := clampi(int(offer_data.get("level", 1)), 1, 9999)
	var hero_definition := DataLoader.get_hero_definition(String(offer_data.get("definition_id", "")))
	var growth_source := hero_definition if not hero_definition.is_empty() else offer_data
	var stat_growth := _resolve_growth_block(growth_source.get("stat_growth", {}), DataLoader.DEFAULT_HERO_STAT_GROWTH)
	var work_stat_growth := _resolve_growth_block(growth_source.get("work_stat_growth", {}), DataLoader.DEFAULT_HERO_WORK_STAT_GROWTH)
	var hero_instance: Dictionary = {
		"uid": assigned_uid,
		"definition_id": String(offer_data.get("definition_id", "")),
		"name": String(offer_data.get("name", "Unknown Hero")),
		"class": String(offer_data.get("class", "Supporter")),
		"assigned_settlement_id": "",
		"assigned_slot": -1,
		"level": hero_level,
		"experience": _normalize_experience(int(offer_data.get("experience", 0)), hero_level),
		"stat_growth": stat_growth,
		"work_stat_growth": work_stat_growth,
		"stats": _build_runtime_stats(growth_source, stat_growth, hero_level, {}),
		"work_stats": _build_runtime_work_stats(growth_source, work_stat_growth, hero_level),
		"equipment": DataLoader.create_empty_hero_equipment(),
		"world_task": _create_idle_world_task(),
		"source": String(offer_data.get("source", "core")),
		"mod_id": String(offer_data.get("mod_id", "")),
	}
	return hero_instance


static func normalize_loaded_hero(hero_data: Dictionary, fallback_uid: int) -> Dictionary:
	var definition_id := String(hero_data.get("definition_id", ""))
	var hero_definition: Dictionary = DataLoader.get_hero_definition(definition_id)
	var hero_level := clampi(int(hero_data.get("level", 1)), 1, 9999)
	var growth_source := hero_definition if not hero_definition.is_empty() else hero_data
	var stat_growth := _normalize_resolved_growth_block(hero_data.get("stat_growth", growth_source.get("stat_growth", {})), DataLoader.DEFAULT_HERO_STAT_GROWTH)
	var work_stat_growth := _normalize_resolved_growth_block(hero_data.get("work_stat_growth", growth_source.get("work_stat_growth", {})), DataLoader.DEFAULT_HERO_WORK_STAT_GROWTH)
	var normalized: Dictionary = {
		"uid": int(hero_data.get("uid", fallback_uid)),
		"definition_id": definition_id,
		"name": String(hero_data.get("name", hero_definition.get("name", "Unknown Hero"))),
		"class": String(hero_definition.get("class", DataLoader.normalize_hero_class(String(hero_data.get("class", "Supporter"))))),
		"level": hero_level,
		"experience": _normalize_experience(int(hero_data.get("experience", 0)), hero_level),
		"stat_growth": stat_growth,
		"work_stat_growth": work_stat_growth,
		"assigned_settlement_id": String(hero_data.get("assigned_settlement_id", "")).strip_edges(),
		"assigned_slot": int(hero_data.get("assigned_slot", -1)),
		"stats": _build_runtime_stats(growth_source, stat_growth, hero_level, _as_dictionary(hero_data.get("stats", {}))),
		"work_stats": _build_runtime_work_stats(growth_source, work_stat_growth, hero_level),
		"equipment": _normalize_runtime_equipment(hero_data.get("equipment", {})),
		"world_task": _normalize_world_task(hero_data.get("world_task", {})),
		"source": String(hero_data.get("source", hero_definition.get("source", "core"))),
		"mod_id": String(hero_data.get("mod_id", hero_definition.get("mod_id", ""))),
	}
	if normalized["name"] == "Unknown Hero" and not hero_definition.is_empty():
		normalized["name"] = String(hero_definition.get("name", "Unknown Hero"))
	return normalized


static func level_up_hero(hero_data: Dictionary) -> Dictionary:
	var leveled_hero := hero_data.duplicate(true)
	var hero_definition := DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
	if hero_definition.is_empty():
		leveled_hero["level"] = max(1, int(leveled_hero.get("level", 1))) + 1
		return leveled_hero
	var stat_growth := _normalize_resolved_growth_block(leveled_hero.get("stat_growth", hero_definition.get("stat_growth", {})), DataLoader.DEFAULT_HERO_STAT_GROWTH)
	var work_stat_growth := _normalize_resolved_growth_block(leveled_hero.get("work_stat_growth", hero_definition.get("work_stat_growth", {})), DataLoader.DEFAULT_HERO_WORK_STAT_GROWTH)
	var stats := _as_dictionary(leveled_hero.get("stats", {})).duplicate(true)
	var previous_max_health := int(stats.get("max_health", stats.get("health", 0)))
	var previous_max_sanity := int(stats.get("max_sanity", stats.get("sanity", 0)))
	for stat_key in DataLoader.DEFAULT_HERO_STATS.keys():
		stats[stat_key] = int(stats.get(stat_key, 0)) + int(stat_growth.get(stat_key, 0))
	stats["max_health"] = int(stats.get("health", 0))
	stats["current_health"] = min(int(stats.get("current_health", previous_max_health)) + int(stat_growth.get("health", 0)), int(stats.get("max_health", 0)))
	stats["max_sanity"] = int(stats.get("sanity", 0))
	stats["current_sanity"] = min(int(stats.get("current_sanity", previous_max_sanity)) + int(stat_growth.get("sanity", 0)), int(stats.get("max_sanity", 0)))
	leveled_hero["stats"] = stats
	var work_stats := _as_dictionary(leveled_hero.get("work_stats", {})).duplicate(true)
	for stat_key in DataLoader.DEFAULT_HERO_WORK_STATS.keys():
		work_stats[stat_key] = int(work_stats.get(stat_key, 0)) + int(work_stat_growth.get(stat_key, 0))
	leveled_hero["work_stats"] = work_stats
	leveled_hero["level"] = max(1, int(leveled_hero.get("level", 1))) + 1
	return leveled_hero


static func _normalize_runtime_stats(value: Variant, fallback_value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var fallback: Dictionary = _as_dictionary(fallback_value)
	if fallback.is_empty():
		fallback = DataLoader.DEFAULT_HERO_STATS
	var normalized: Dictionary = {}
	for stat_key in fallback.keys():
		normalized[stat_key] = int(source_data.get(stat_key, fallback[stat_key]))
	var base_health := int(normalized.get("health", 0))
	var base_sanity := int(normalized.get("sanity", 0))
	normalized["max_health"] = int(source_data.get("max_health", base_health))
	normalized["current_health"] = int(source_data.get("current_health", normalized.get("max_health", base_health)))
	normalized["max_sanity"] = int(source_data.get("max_sanity", base_sanity))
	normalized["current_sanity"] = int(source_data.get("current_sanity", normalized.get("max_sanity", base_sanity)))
	return normalized


static func _normalize_runtime_equipment(value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var equipment: Dictionary = DataLoader.create_empty_hero_equipment()
	for slot_key in equipment.keys():
		equipment[slot_key] = String(source_data.get(slot_key, "")).strip_edges()
	return equipment


static func _normalize_experience(experience: int, level: int) -> int:
	return max(experience, max(level - 1, 0) * 10)


static func _build_runtime_stats(source_data: Dictionary, stat_growth: Dictionary, level: int, existing_stats: Dictionary) -> Dictionary:
	var stats := _normalize_runtime_stats(source_data.get("stats", {}), DataLoader.DEFAULT_HERO_STATS)
	for stat_key in DataLoader.DEFAULT_HERO_STATS.keys():
		stats[stat_key] = int(stats.get(stat_key, 0)) + (max(level - 1, 0) * int(stat_growth.get(stat_key, 0)))
	stats["max_health"] = int(stats.get("health", 0))
	stats["max_sanity"] = int(stats.get("sanity", 0))
	if existing_stats.is_empty():
		stats["current_health"] = int(stats.get("max_health", 0))
		stats["current_sanity"] = int(stats.get("max_sanity", 0))
	else:
		var current_health := int(existing_stats.get("current_health", int(existing_stats.get("max_health", stats.get("max_health", 0)))))
		var current_sanity := int(existing_stats.get("current_sanity", int(existing_stats.get("max_sanity", stats.get("max_sanity", 0)))))
		stats["current_health"] = min(current_health, int(stats.get("max_health", 0)))
		stats["current_sanity"] = min(current_sanity, int(stats.get("max_sanity", 0)))
	return stats


static func _build_runtime_work_stats(source_data: Dictionary, work_stat_growth: Dictionary, level: int) -> Dictionary:
	var work_stats := _normalize_runtime_stats(source_data.get("work_stats", {}), DataLoader.DEFAULT_HERO_WORK_STATS)
	for stat_key in DataLoader.DEFAULT_HERO_WORK_STATS.keys():
		work_stats[stat_key] = int(work_stats.get(stat_key, 0)) + (max(level - 1, 0) * int(work_stat_growth.get(stat_key, 0)))
	return work_stats


static func _resolve_growth_block(value: Variant, defaults: Dictionary) -> Dictionary:
	var source_data := _as_dictionary(value)
	var resolved: Dictionary = {}
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
			resolved[stat_key] = randi_range(min_amount, max_amount)
		else:
			resolved[stat_key] = int(stat_value)
	return resolved


static func _normalize_resolved_growth_block(value: Variant, defaults: Dictionary) -> Dictionary:
	var source_data := _as_dictionary(value)
	var normalized: Dictionary = {}
	for stat_key in defaults.keys():
		var stat_value: Variant = source_data.get(stat_key, defaults[stat_key])
		if stat_value is Dictionary:
			normalized[stat_key] = _resolve_growth_block({stat_key: stat_value}, {stat_key: defaults[stat_key]}).get(stat_key, defaults[stat_key])
		else:
			normalized[stat_key] = int(stat_value)
	return normalized


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
