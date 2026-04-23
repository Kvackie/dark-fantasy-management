extends Node


var _session: Node = null


func configure(session: Node) -> void:
	_session = session


func add_item_to_inventory(definition_id: String, quantity: int) -> void:
	if quantity <= 0 or _session == null:
		return
	var item_definition: Dictionary = DataLoader.get_item_definition(definition_id)
	if item_definition.is_empty():
		return
	var max_stack: int = max(1, int(item_definition.get("max_stack", DataLoader.DEFAULT_ITEM_MAX_STACK)))
	var items: Array = _inventory_items()
	var remaining: int = quantity
	for stack_index in range(items.size()):
		if remaining <= 0:
			break
		var stack: Dictionary = items[stack_index]
		if String(stack.get("definition_id", "")) != definition_id:
			continue
		var current_quantity := int(stack.get("quantity", 0))
		if current_quantity >= max_stack:
			continue
		var added: int = min(max_stack - current_quantity, remaining)
		stack["quantity"] = current_quantity + added
		items[stack_index] = stack
		remaining -= added
	while remaining > 0:
		var stack_quantity: int = min(max_stack, remaining)
		items.append({
			"definition_id": definition_id,
			"quantity": stack_quantity,
		})
		remaining -= stack_quantity
	_set_inventory_items(items)


func add_equipment_to_inventory(definition_id: String) -> Dictionary:
	if _session == null:
		return {}
	var equipment_definition: Dictionary = DataLoader.get_equipment_definition(definition_id)
	if equipment_definition.is_empty():
		return {}
	var instance := _create_equipment_instance(equipment_definition)
	var equipment: Array = _inventory_equipment()
	equipment.append(instance)
	_set_inventory_equipment(equipment)
	return instance.duplicate(true)


func get_inventory_equipment_instance(equipment_uid: int) -> Dictionary:
	if equipment_uid <= 0 or _session == null:
		return {}
	for entry in _inventory_equipment():
		var equipment_instance: Dictionary = entry
		if int(equipment_instance.get("uid", -1)) == equipment_uid:
			return equipment_instance.duplicate(true)
	return {}


func equip_equipment_to_hero(hero_uid: int, slot_key: String, equipment_uid: int) -> bool:
	if _session == null:
		return false
	if not DataLoader.HERO_EQUIPMENT_KEYS.has(slot_key):
		return false
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	var equipment_index := _find_inventory_equipment_index(equipment_uid)
	if equipment_index == -1:
		return false
	var equipment_instance: Dictionary = _inventory_equipment()[equipment_index]
	var equipment_definition := DataLoader.get_equipment_definition(String(equipment_instance.get("definition_id", "")))
	if equipment_definition.is_empty():
		return false
	if String(equipment_definition.get("slot", "")) != slot_key:
		return false
	_unequip_hero_slot_internal(hero_index, slot_key)
	_detach_equipment_instance(equipment_uid)
	var heroes: Array = _heroes()
	var hero_data: Dictionary = heroes[hero_index]
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
	if hero_equipment.is_empty():
		hero_equipment = DataLoader.create_empty_hero_equipment()
		hero_data["equipment"] = hero_equipment
	hero_equipment[slot_key] = str(equipment_uid)
	hero_data["equipment"] = hero_equipment
	heroes[hero_index] = hero_data
	_set_heroes(heroes)
	_rebuild_equipment_compatibility()
	return true


func unequip_hero_slot(hero_uid: int, slot_key: String) -> bool:
	if _session == null:
		return false
	if not DataLoader.HERO_EQUIPMENT_KEYS.has(slot_key):
		return false
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	if _unequip_hero_slot_internal(hero_index, slot_key) <= 0:
		return false
	return true


func strip_all_equipment_from_hero(hero_uid: int) -> void:
	if hero_uid <= 0 or _session == null:
		return
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return
	var heroes: Array = _heroes()
	if hero_index < 0 or hero_index >= heroes.size():
		return
	var hero_data: Dictionary = heroes[hero_index]
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
	if hero_equipment.is_empty():
		hero_equipment = DataLoader.create_empty_hero_equipment()
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		hero_equipment[slot_key] = ""
	hero_data["equipment"] = hero_equipment
	heroes[hero_index] = hero_data
	_set_heroes(heroes)
	_rebuild_equipment_compatibility()


func seed_starting_inventory() -> void:
	var starting_inventory := DataLoader.get_starting_inventory_config()
	for entry in _as_array(starting_inventory.get("items", [])):
		add_item_to_inventory(String((entry as Dictionary).get("definition_id", "")), int((entry as Dictionary).get("quantity", 0)))
	for equipment_id in _as_array(starting_inventory.get("equipment", [])):
		add_equipment_to_inventory(String(equipment_id))


func _find_hero_index(hero_uid: int) -> int:
	if _session == null:
		return -1
	var heroes: Array = _heroes()
	for index in heroes.size():
		var hero_data: Dictionary = heroes[index]
		if int(hero_data.get("uid", -1)) == hero_uid:
			return index
	return -1


func _find_inventory_equipment_index(equipment_uid: int) -> int:
	if _session == null:
		return -1
	var equipment: Array = _inventory_equipment()
	for index in equipment.size():
		var equipment_instance: Dictionary = equipment[index]
		if int(equipment_instance.get("uid", -1)) == equipment_uid:
			return index
	return -1


func _create_equipment_instance(equipment_definition: Dictionary) -> Dictionary:
	if _session == null:
		return {}
	var equipment_instance: Dictionary = {
		"uid": int(_next_equipment_uid()),
		"definition_id": String(equipment_definition.get("id", "")),
		"equipped_hero_uid": -1,
		"equipped_slot": "",
	}
	_set_next_equipment_uid(_next_equipment_uid() + 1)
	return equipment_instance


func _unequip_hero_slot_internal(hero_index: int, slot_key: String) -> int:
	if _session == null:
		return -1
	var heroes: Array = _heroes()
	if hero_index < 0 or hero_index >= heroes.size():
		return -1
	var hero_data: Dictionary = heroes[hero_index]
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
	if hero_equipment.is_empty():
		hero_equipment = DataLoader.create_empty_hero_equipment()
	var equipment_uid := int(String(hero_equipment.get(slot_key, "")).strip_edges())
	hero_equipment[slot_key] = ""
	hero_data["equipment"] = hero_equipment
	heroes[hero_index] = hero_data
	_set_heroes(heroes)
	_clear_equipment_instance_link(equipment_uid)
	_rebuild_equipment_compatibility()
	return equipment_uid


func _detach_equipment_instance(equipment_uid: int) -> void:
	if equipment_uid <= 0 or _session == null:
		return
	var heroes: Array = _heroes()
	for hero_index in range(heroes.size()):
		var hero_data: Dictionary = heroes[hero_index]
		var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
		if hero_equipment.is_empty():
			continue
		var changed := false
		for slot_key in hero_equipment.keys():
			if int(String(hero_equipment.get(slot_key, "")).strip_edges()) == equipment_uid:
				hero_equipment[slot_key] = ""
				changed = true
		if changed:
			hero_data["equipment"] = hero_equipment
			heroes[hero_index] = hero_data
	_set_heroes(heroes)
	_clear_equipment_instance_link(equipment_uid)
	_rebuild_equipment_compatibility()


func _clear_equipment_instance_link(equipment_uid: int) -> void:
	if equipment_uid <= 0 or _session == null:
		return
	var equipment: Array = _inventory_equipment()
	var equipment_index := -1
	for index in range(equipment.size()):
		var equipment_instance: Dictionary = equipment[index]
		if int(equipment_instance.get("uid", -1)) == equipment_uid:
			equipment_index = index
			break
	if equipment_index == -1:
		return
	var target_equipment_instance: Dictionary = equipment[equipment_index]
	target_equipment_instance["equipped_hero_uid"] = -1
	target_equipment_instance["equipped_slot"] = ""
	equipment[equipment_index] = target_equipment_instance
	_set_inventory_equipment(equipment)


func _inventory_items() -> Array:
	return _as_array(_session.get_inventory_items())


func _set_inventory_items(items: Array) -> void:
	_session.set_inventory_items(items)


func _inventory_equipment() -> Array:
	return _as_array(_session.get_inventory_equipment())


func _set_inventory_equipment(equipment: Array) -> void:
	_session.set_inventory_equipment(equipment)


func _heroes() -> Array:
	return _as_array(_session.get_heroes())


func _set_heroes(heroes: Array) -> void:
	_session.set_heroes(heroes)


func _next_equipment_uid() -> int:
	return _session.get_next_equipment_uid()


func _set_next_equipment_uid(value: int) -> void:
	_session.set_next_equipment_uid(value)


func _rebuild_equipment_compatibility() -> void:
	_session.refresh_equipment_compatibility()


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
