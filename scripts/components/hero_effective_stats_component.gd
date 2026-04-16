extends RefCounted


static func build_effective_combat_stats(hero_data: Dictionary, get_equipment_instance: Callable) -> Dictionary:
	var stats: Dictionary = _as_dictionary(hero_data.get("stats", {})).duplicate(true)
	var bonuses: Dictionary = compute_equipment_bonuses(hero_data, get_equipment_instance)
	for stat_key in DataLoader.DEFAULT_HERO_STATS.keys():
		stats[stat_key] = int(stats.get(stat_key, 0)) + int(_as_dictionary(bonuses.get("stats", {})).get(stat_key, 0))
	return stats


static func build_effective_work_stats(hero_data: Dictionary, get_equipment_instance: Callable) -> Dictionary:
	var work_stats: Dictionary = _as_dictionary(hero_data.get("work_stats", {})).duplicate(true)
	var bonuses: Dictionary = compute_equipment_bonuses(hero_data, get_equipment_instance)
	for stat_key in DataLoader.DEFAULT_HERO_WORK_STATS.keys():
		work_stats[stat_key] = int(work_stats.get(stat_key, 0)) + int(_as_dictionary(bonuses.get("work_stats", {})).get(stat_key, 0))
	return work_stats


static func compute_equipment_bonuses(hero_data: Dictionary, get_equipment_instance: Callable) -> Dictionary:
	var bonuses := {
		"stats": {},
		"work_stats": {},
	}
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {}))
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		var equipment_uid := int(String(hero_equipment.get(slot_key, "")).strip_edges())
		if equipment_uid <= 0:
			continue
		var equipment_instance: Dictionary = {}
		if get_equipment_instance.is_valid():
			equipment_instance = get_equipment_instance.call(equipment_uid)
		if equipment_instance.is_empty():
			continue
		if int(equipment_instance.get("equipped_hero_uid", -1)) != int(hero_data.get("uid", -1)):
			continue
		var equipment_definition := DataLoader.get_equipment_definition(String(equipment_instance.get("definition_id", "")))
		var definition_bonuses := _as_dictionary(equipment_definition.get("bonuses", {}))
		for stat_key in DataLoader.DEFAULT_HERO_STATS.keys():
			var current_stat := int(_as_dictionary(bonuses.get("stats", {})).get(stat_key, 0))
			var added_stat := int(_as_dictionary(definition_bonuses.get("stats", {})).get(stat_key, 0))
			if added_stat != 0:
				bonuses["stats"][stat_key] = current_stat + added_stat
		for stat_key in DataLoader.DEFAULT_HERO_WORK_STATS.keys():
			var current_work := int(_as_dictionary(bonuses.get("work_stats", {})).get(stat_key, 0))
			var added_work := int(_as_dictionary(definition_bonuses.get("work_stats", {})).get(stat_key, 0))
			if added_work != 0:
				bonuses["work_stats"][stat_key] = current_work + added_work
	return bonuses


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}
