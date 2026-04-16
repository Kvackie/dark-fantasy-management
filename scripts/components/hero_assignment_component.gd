extends RefCounted


static func find_hero_index(heroes: Array, hero_uid: int) -> int:
	for index in heroes.size():
		var hero_data: Dictionary = heroes[index]
		if int(hero_data.get("uid", -1)) == hero_uid:
			return index
	return -1


static func clear_hero_settlement_assignment(heroes: Array, hero_uid: int) -> void:
	var hero_index := find_hero_index(heroes, hero_uid)
	if hero_index == -1:
		return
	var hero_data: Dictionary = heroes[hero_index]
	hero_data["assigned_settlement_id"] = ""
	hero_data["assigned_slot"] = -1
	heroes[hero_index] = hero_data


static func remove_hero_from_slot(slots: Array, hero_uid: int, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot: Dictionary = slots[slot_index]
	var assigned_ids: Array = []
	for assigned_id in _normalize_int_array(slot.get("assigned_hero_ids", [])):
		if int(assigned_id) != hero_uid:
			assigned_ids.append(int(assigned_id))
	slot["assigned_hero_ids"] = assigned_ids
	slots[slot_index] = slot


static func assign_hero_to_active_settlement_slot(
	heroes: Array,
	slots: Array,
	hero_uid: int,
	slot_index: int,
	active_settlement_id: String,
	get_slot_building_definition: Callable,
	is_hero_world_task_idle_cb: Callable,
	after_clear_assignment_refresh: Callable
) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size():
		return {"ok": false}
	var slot: Dictionary = slots[slot_index]
	var definition: Dictionary = get_slot_building_definition.call(slot_index)
	if definition.is_empty():
		return {"ok": false}
	var assigned_ids: Array = _normalize_int_array(slot.get("assigned_hero_ids", []))
	if not assigned_ids.has(hero_uid) and assigned_ids.size() >= int(definition.get("worker_slots", 0)):
		return {"ok": false}
	var hero_index: int = find_hero_index(heroes, hero_uid)
	if hero_index == -1:
		return {"ok": false}
	var hero_data: Dictionary = heroes[hero_index]
	if not bool(is_hero_world_task_idle_cb.call(hero_uid)):
		return {"ok": false}
	var previous_slot: int = int(hero_data.get("assigned_slot", -1))
	var previous_settlement_id := String(hero_data.get("assigned_settlement_id", "")).strip_edges()
	if previous_slot == slot_index and previous_settlement_id == active_settlement_id:
		return {"ok": true, "changed": false}
	clear_hero_settlement_assignment(heroes, hero_uid)
	if after_clear_assignment_refresh.is_valid():
		after_clear_assignment_refresh.call()
	hero_data = heroes[hero_index]
	hero_data["assigned_settlement_id"] = active_settlement_id
	hero_data["assigned_slot"] = slot_index
	heroes[hero_index] = hero_data
	return {"ok": true, "changed": true}


static func unassign_hero_from_slots(heroes: Array, hero_uid: int) -> bool:
	var hero_index: int = find_hero_index(heroes, hero_uid)
	if hero_index == -1:
		return false
	var hero_data: Dictionary = heroes[hero_index]
	if int(hero_data.get("assigned_slot", -1)) == -1:
		return false
	clear_hero_settlement_assignment(heroes, hero_uid)
	return true


static func _normalize_int_array(value: Variant) -> Array:
	var normalized: Array = []
	if value is Array:
		for entry in value:
			normalized.append(int(entry))
	return normalized
