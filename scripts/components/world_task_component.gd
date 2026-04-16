extends RefCounted


static func remove_hero_from_world_zones(world_zones: Dictionary, hero_uid: int) -> bool:
	var world_state_changed := false
	for zone_key in world_zones.keys():
		var zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
		var assigned_ids := _normalize_int_array(zone.get("assigned_hero_uids", []))
		if not assigned_ids.has(hero_uid):
			continue
		var remaining_ids: Array = []
		for assigned_id in assigned_ids:
			if int(assigned_id) != hero_uid:
				remaining_ids.append(int(assigned_id))
		zone["assigned_hero_uids"] = remaining_ids
		if String(zone.get("state", "")) == "clearing" and remaining_ids.is_empty():
			zone["state"] = "discovered"
			zone["ticks_remaining"] = 0
		world_zones[zone_key] = zone
		world_state_changed = true
	return world_state_changed


static func rebuild_world_task_compatibility(hero_list: Array, zone_state: Dictionary) -> void:
	for hero_index in range(hero_list.size()):
		var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
		hero_data["world_task"] = _create_idle_world_task()
		hero_list[hero_index] = hero_data
	var hero_index_by_uid: Dictionary = {}
	for hero_index in range(hero_list.size()):
		hero_index_by_uid[int(_as_dictionary(hero_list[hero_index]).get("uid", -1))] = hero_index
	for zone_key in zone_state.keys():
		var zone := _as_dictionary(zone_state.get(zone_key, {})).duplicate(true)
		if String(zone.get("state", "")) != "clearing":
			zone["assigned_hero_uids"] = []
			zone_state[zone_key] = zone
			continue
		var valid_hero_ids: Array = []
		for uid in _normalize_int_array(zone.get("assigned_hero_uids", [])):
			var hero_index := int(hero_index_by_uid.get(uid, -1))
			if hero_index == -1:
				continue
			var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
			hero_data["world_task"] = {
				"type": "clearing",
				"zone_key": String(zone_key),
			}
			hero_list[hero_index] = hero_data
			valid_hero_ids.append(uid)
		zone["assigned_hero_uids"] = valid_hero_ids
		zone_state[zone_key] = zone


static func hero_world_task_is_idle(hero_uid: int, zone_state: Dictionary) -> bool:
	for zone_key in zone_state.keys():
		var zone := _as_dictionary(zone_state.get(zone_key, {}))
		if String(zone.get("state", "")) != "clearing":
			continue
		if _normalize_int_array(zone.get("assigned_hero_uids", [])).has(hero_uid):
			return false
	return true


static func _create_idle_world_task() -> Dictionary:
	return {
		"type": "",
		"zone_key": "",
	}


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _normalize_int_array(value: Variant) -> Array:
	var normalized: Array = []
	if value is Array:
		for entry in value:
			normalized.append(int(entry))
	return normalized
