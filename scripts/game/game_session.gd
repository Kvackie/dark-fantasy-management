extends Node


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")


const SAVE_SLOT_MANIFEST_PATH := "user://save_slots_manifest.json"


var resources: Dictionary = {}
var slots: Array:
	get:
		return _get_active_settlement_slots()
	set(value):
		_set_active_settlement_slots(value)
var settlement_states: Dictionary = {}
var generated_settlement_definitions: Dictionary = {}
var heroes: Array = []
var inventory_items: Array = []
var inventory_equipment: Array = []
var recruit_market_offers: Array = []
var recruit_market_initialized: bool = false
var owned_settlement_ids: Array = []
var active_settlement_id: String = ""
var world_seed: int = 0
var world_zones: Dictionary = {}
var selected_slot: int = -1
var active_save_slot: int = 1
var tick_count: int = 0
var next_hero_uid: int = 1
var next_equipment_uid: int = 1
var next_recruit_offer_id: int = 1
var autosave_elapsed: float = 0.0
var pending_save: bool = false

var inventory_component: Node = null


class InventoryComponent extends Node:
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
		var items: Array = _session.inventory_items
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
		_session.inventory_items = items

	func add_equipment_to_inventory(definition_id: String) -> Dictionary:
		if _session == null:
			return {}
		var equipment_definition: Dictionary = DataLoader.get_equipment_definition(definition_id)
		if equipment_definition.is_empty():
			return {}
		var instance := _create_equipment_instance(equipment_definition)
		var equipment: Array = _session.inventory_equipment
		equipment.append(instance)
		_session.inventory_equipment = equipment
		return instance.duplicate(true)

	func get_inventory_equipment_instance(equipment_uid: int) -> Dictionary:
		if equipment_uid <= 0 or _session == null:
			return {}
		for entry in _session.inventory_equipment:
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
		var equipment_instance: Dictionary = _session.inventory_equipment[equipment_index]
		var equipment_definition := DataLoader.get_equipment_definition(String(equipment_instance.get("definition_id", "")))
		if equipment_definition.is_empty():
			return false
		if String(equipment_definition.get("slot", "")) != slot_key:
			return false
		_unequip_hero_slot_internal(hero_index, slot_key)
		_detach_equipment_instance(equipment_uid)
		var heroes: Array = _session.heroes
		var hero_data: Dictionary = heroes[hero_index]
		var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
		if hero_equipment.is_empty():
			hero_equipment = DataLoader.create_empty_hero_equipment()
			hero_data["equipment"] = hero_equipment
		hero_equipment[slot_key] = str(equipment_uid)
		hero_data["equipment"] = hero_equipment
		heroes[hero_index] = hero_data
		_session.heroes = heroes
		_session.rebuild_equipment_compatibility(_session.heroes, _session.inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))
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

	func seed_starting_inventory() -> void:
		for entry in [
			{"definition_id": "rations", "quantity": 24},
			{"definition_id": "timber_bundle", "quantity": 48},
			{"definition_id": "grave_coin", "quantity": 135},
			{"definition_id": "veil_crystal", "quantity": 7},
		]:
			add_item_to_inventory(String((entry as Dictionary).get("definition_id", "")), int((entry as Dictionary).get("quantity", 0)))
		for equipment_id in [
			"grave_hood",
			"watcher_cowl",
			"ashen_mask",
			"thorn_circlet",
			"veil_cap",
			"iron_brow",
			"bone_visor",
			"lantern_veil",
			"mire_hat",
			"gilded_band",
			"crypt_wreath",
			"pit_gloves",
			"ember_amulet",
		]:
			add_equipment_to_inventory(equipment_id)

	func _find_hero_index(hero_uid: int) -> int:
		if _session == null:
			return -1
		for index in _session.heroes.size():
			var hero_data: Dictionary = _session.heroes[index]
			if int(hero_data.get("uid", -1)) == hero_uid:
				return index
		return -1

	func _find_inventory_equipment_index(equipment_uid: int) -> int:
		if _session == null:
			return -1
		for index in _session.inventory_equipment.size():
			var equipment_instance: Dictionary = _session.inventory_equipment[index]
			if int(equipment_instance.get("uid", -1)) == equipment_uid:
				return index
		return -1

	func _create_equipment_instance(equipment_definition: Dictionary) -> Dictionary:
		if _session == null:
			return {}
		var equipment_instance: Dictionary = {
			"uid": int(_session.next_equipment_uid),
			"definition_id": String(equipment_definition.get("id", "")),
			"equipped_hero_uid": -1,
			"equipped_slot": "",
		}
		_session.next_equipment_uid = int(_session.next_equipment_uid) + 1
		return equipment_instance

	func _unequip_hero_slot_internal(hero_index: int, slot_key: String) -> int:
		if _session == null:
			return -1
		var heroes: Array = _session.heroes
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
		_session.heroes = heroes
		_clear_equipment_instance_link(equipment_uid)
		_session.rebuild_equipment_compatibility(_session.heroes, _session.inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))
		return equipment_uid

	func _detach_equipment_instance(equipment_uid: int) -> void:
		if equipment_uid <= 0 or _session == null:
			return
		var heroes: Array = _session.heroes
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
		_session.heroes = heroes
		_clear_equipment_instance_link(equipment_uid)
		_session.rebuild_equipment_compatibility(_session.heroes, _session.inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))

	func _clear_equipment_instance_link(equipment_uid: int) -> void:
		if equipment_uid <= 0 or _session == null:
			return
		var equipment: Array = _session.inventory_equipment
		var equipment_index := -1
		for index in range(equipment.size()):
			var equipment_instance: Dictionary = equipment[index]
			if int(equipment_instance.get("uid", -1)) == equipment_uid:
				equipment_index = index
				break
		if equipment_index == -1:
			return
		var equipment_instance: Dictionary = equipment[equipment_index]
		equipment_instance["equipped_hero_uid"] = -1
		equipment_instance["equipped_slot"] = ""
		equipment[equipment_index] = equipment_instance
		_session.inventory_equipment = equipment

	func _as_dictionary(value: Variant) -> Dictionary:
		if value is Dictionary:
			return value
		return {}


func _ready() -> void:
	ensure_inventory_component()


func ensure_inventory_component() -> void:
	if inventory_component != null and is_instance_valid(inventory_component):
		return
	var component := InventoryComponent.new()
	component.name = "InventoryComponent"
	component.configure(self)
	add_child(component)
	inventory_component = component


func reset_runtime_state(starting_resources: Dictionary, default_settlement_id: String) -> void:
	resources = starting_resources.duplicate(true)
	settlement_states = {}
	if not default_settlement_id.is_empty():
		settlement_states[default_settlement_id] = {
			"settlement_id": default_settlement_id,
			"slots": SettlementGameData.create_empty_grid(),
		}
	generated_settlement_definitions = {}
	heroes = []
	inventory_items = []
	inventory_equipment = []
	recruit_market_offers = []
	recruit_market_initialized = false
	owned_settlement_ids = []
	if not default_settlement_id.is_empty():
		owned_settlement_ids.append(default_settlement_id)
	active_settlement_id = default_settlement_id
	world_seed = 0
	world_zones = {}
	selected_slot = -1
	tick_count = 0
	next_hero_uid = 1
	next_equipment_uid = 1
	next_recruit_offer_id = 1
	autosave_elapsed = 0.0
	pending_save = false
	ensure_inventory_component()


func set_selected_slot(slot_index: int, slot_count: int) -> int:
	selected_slot = clamp(slot_index, -1, slot_count - 1)
	return selected_slot


func save_serialized_state(slot_index: int, state: Dictionary) -> bool:
	active_save_slot = slot_index
	var file := FileAccess.open(_save_path(slot_index), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	file.close()
	autosave_elapsed = 0.0
	pending_save = false
	return true


func load_serialized_state(slot_index: int) -> Dictionary:
	var path := _save_path(slot_index)
	if not FileAccess.file_exists(path):
		return {}
	var raw_text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw_text)
	if parsed is not Dictionary:
		return {}
	active_save_slot = slot_index
	autosave_elapsed = 0.0
	pending_save = false
	return (parsed as Dictionary).duplicate(true)


func mark_save_dirty() -> void:
	pending_save = true


func process_autosave(delta: float, autosave_interval: float, serialize_state: Callable) -> bool:
	autosave_elapsed += delta
	if not pending_save or autosave_elapsed < autosave_interval:
		return false
	return save_serialized_state(active_save_slot, serialize_state.call())


func clear_pending_save() -> void:
	autosave_elapsed = 0.0
	pending_save = false


func get_save_slot_metadata(slot_count: int, resolve_name: Callable) -> Array:
	var manifest := _load_save_slot_manifest()
	var manifest_slots := _as_dictionary(manifest.get("slots", {}))
	var slot_info: Array = []
	for slot_index in range(1, slot_count + 1):
		var path := _save_path(slot_index)
		var metadata := _as_dictionary(manifest_slots.get(str(slot_index), {}))
		slot_info.append({
			"slot": slot_index,
			"exists": FileAccess.file_exists(path),
			"active": slot_index == active_save_slot,
			"name": resolve_name.call(slot_index, metadata),
		})
	return slot_info


func get_inventory_snapshot() -> Dictionary:
	ensure_inventory_component()
	var item_snapshots: Array = []
	for item_stack in inventory_items:
		item_snapshots.append(_build_inventory_item_snapshot(item_stack))
	var equipment_snapshots: Array = []
	for equipment_entry in inventory_equipment:
		equipment_snapshots.append(_build_inventory_equipment_snapshot(equipment_entry))
	return {
		"items": item_snapshots,
		"equipment": equipment_snapshots,
	}


func get_world_snapshot(world_config: Dictionary) -> Dictionary:
	var zone_snapshots: Dictionary = {}
	for zone_key in world_zones.keys():
		zone_snapshots[String(zone_key)] = _build_world_zone_snapshot(String(zone_key), world_zones.get(zone_key, {}))
	return {
		"seed": world_seed,
		"zones": zone_snapshots,
		"config": world_config.duplicate(true),
		"active_settlement_id": active_settlement_id,
	}


func get_resource_snapshot() -> Dictionary:
	var snapshot := SettlementGameData.duplicate_resources(resources)
	snapshot["heroes"] = heroes.size()
	return snapshot


func get_slots_snapshot() -> Array:
	var copy: Array = []
	for slot_index in range(slots.size()):
		copy.append(_build_slot_snapshot(slot_index, slots[slot_index]))
	return copy


func get_heroes_snapshot() -> Array:
	var snapshots: Array = []
	for hero_data in heroes:
		snapshots.append(_build_hero_snapshot(hero_data))
	return snapshots


func get_settlement_slots_snapshot(settlement_id: String) -> Array:
	var copy: Array = []
	var settlement_slots := _get_settlement_slots_from_state(_ensure_settlement_state(settlement_id))
	for slot_index in range(settlement_slots.size()):
		copy.append(_build_slot_snapshot(slot_index, settlement_slots[slot_index]))
	return copy


func get_world_zone_snapshot(zone_key: String) -> Dictionary:
	return _build_world_zone_snapshot(zone_key, world_zones.get(zone_key, {}))


func build_serialized_state(settlement_states_snapshot: Dictionary, generated_settlement_definitions_snapshot: Dictionary) -> Dictionary:
	return {
		"resources": SettlementGameData.duplicate_resources(resources),
		"settlement_states": settlement_states_snapshot.duplicate(true),
		"generated_settlement_definitions": generated_settlement_definitions_snapshot.duplicate(true),
		"heroes": duplicate_dict_array(heroes),
		"inventory_items": duplicate_dict_array(inventory_items),
		"inventory_equipment": duplicate_dict_array(inventory_equipment),
		"recruit_market_offers": duplicate_dict_array(recruit_market_offers),
		"recruit_market_initialized": recruit_market_initialized,
		"owned_settlement_ids": owned_settlement_ids.duplicate(),
		"active_settlement_id": active_settlement_id,
		"world_seed": world_seed,
		"world_zones": duplicate_world_zones(world_zones),
		"selected_slot": selected_slot,
		"tick_count": tick_count,
		"next_hero_uid": next_hero_uid,
		"next_equipment_uid": next_equipment_uid,
		"next_recruit_offer_id": next_recruit_offer_id,
	}


func set_save_slot_name(slot_index: int, slot_count: int, slot_name: String) -> bool:
	if slot_index < 1 or slot_index > slot_count:
		return false
	var manifest := _load_save_slot_manifest()
	var manifest_slots := _as_dictionary(manifest.get("slots", {}))
	var slot_key := str(slot_index)
	var metadata := _as_dictionary(manifest_slots.get(slot_key, {}))
	var normalized_name := String(slot_name).strip_edges()
	if normalized_name.is_empty():
		metadata.erase("name")
	else:
		metadata["name"] = normalized_name
	if metadata.is_empty():
		manifest_slots.erase(slot_key)
	else:
		manifest_slots[slot_key] = metadata
	manifest["slots"] = manifest_slots
	_save_save_slot_manifest(manifest)
	return true


func reset_save_slot_file(slot_index: int, slot_count: int) -> bool:
	if slot_index < 1 or slot_index > slot_count:
		return false
	var absolute_path := ProjectSettings.globalize_path(_save_path(slot_index))
	if FileAccess.file_exists(_save_path(slot_index)):
		var error := DirAccess.remove_absolute(absolute_path)
		if error != OK and error != ERR_DOES_NOT_EXIST:
			return false
	return true


func rebuild_slot_assignment_compatibility(hero_list: Array, all_settlement_states: Dictionary) -> void:
	for settlement_id in all_settlement_states.keys():
		var settlement_state := _as_dictionary(all_settlement_states.get(settlement_id, {}))
		var settlement_slots = settlement_state.get("slots", [])
		if settlement_slots is not Array:
			continue
		for slot_index in range(settlement_slots.size()):
			var slot_data: Dictionary = _as_dictionary(settlement_slots[slot_index]).duplicate(true)
			slot_data["assigned_hero_ids"] = []
			settlement_slots[slot_index] = slot_data
	for hero_index in range(hero_list.size()):
		var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
		var settlement_id := String(hero_data.get("assigned_settlement_id", "")).strip_edges()
		var slot_index := int(hero_data.get("assigned_slot", -1))
		if settlement_id.is_empty() or slot_index < 0:
			hero_data["assigned_settlement_id"] = ""
			hero_data["assigned_slot"] = -1
			hero_list[hero_index] = hero_data
			continue
		var settlement_state := _as_dictionary(all_settlement_states.get(settlement_id, {}))
		var settlement_slots = settlement_state.get("slots", [])
		if settlement_slots is not Array or slot_index >= settlement_slots.size():
			hero_data["assigned_settlement_id"] = ""
			hero_data["assigned_slot"] = -1
			hero_list[hero_index] = hero_data
			continue
		var slot_data: Dictionary = _as_dictionary(settlement_slots[slot_index]).duplicate(true)
		if String(slot_data.get("building_id", "")).is_empty():
			hero_data["assigned_settlement_id"] = ""
			hero_data["assigned_slot"] = -1
			hero_list[hero_index] = hero_data
			continue
		var assigned_ids := _normalize_int_array(slot_data.get("assigned_hero_ids", []))
		var hero_uid := int(hero_data.get("uid", -1))
		if hero_uid > 0 and not assigned_ids.has(hero_uid):
			assigned_ids.append(hero_uid)
		slot_data["assigned_hero_ids"] = assigned_ids
		settlement_slots[slot_index] = slot_data


func repair_loaded_slot_assignment_state(hero_list: Array, all_settlement_states: Dictionary, owned_ids: Array, default_settlement_id: String) -> void:
	for settlement_id in owned_ids:
		_ensure_settlement_state(String(settlement_id).strip_edges())
	for settlement_id in all_settlement_states.keys():
		var settlement_slots = _get_settlement_slots_from_state(_as_dictionary(all_settlement_states.get(settlement_id, {})))
		for slot_index in range(settlement_slots.size()):
			var slot_data: Dictionary = _as_dictionary(settlement_slots[slot_index]).duplicate(true)
			slot_data["assigned_hero_ids"] = []
			settlement_slots[slot_index] = slot_data
	for hero_index in range(hero_list.size()):
		var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
		var assigned_settlement_id := String(hero_data.get("assigned_settlement_id", "")).strip_edges()
		var assigned_slot: int = int(hero_data.get("assigned_slot", -1))
		if assigned_settlement_id.is_empty() and assigned_slot >= 0:
			assigned_settlement_id = default_settlement_id
			if not assigned_settlement_id.is_empty():
				hero_data["assigned_settlement_id"] = assigned_settlement_id
		if assigned_slot >= 0 and not assigned_settlement_id.is_empty():
			var settlement_state := _ensure_settlement_state(assigned_settlement_id)
			var settlement_slots = _get_settlement_slots_from_state(settlement_state)
			if assigned_slot >= 0 and assigned_slot < settlement_slots.size() and not String(_as_dictionary(settlement_slots[assigned_slot]).get("building_id", "")).is_empty():
				var slot_data: Dictionary = _as_dictionary(settlement_slots[assigned_slot]).duplicate(true)
				var assigned_ids: Array = _normalize_int_array(slot_data.get("assigned_hero_ids", []))
				assigned_ids.append(int(hero_data.get("uid", -1)))
				slot_data["assigned_hero_ids"] = assigned_ids
				settlement_slots[assigned_slot] = slot_data
			else:
				hero_data["assigned_settlement_id"] = ""
				hero_data["assigned_slot"] = -1
				hero_list[hero_index] = hero_data
		else:
			hero_data["assigned_settlement_id"] = ""
			hero_data["assigned_slot"] = -1
			hero_list[hero_index] = hero_data


func rebuild_equipment_compatibility(hero_list: Array, equipment_list: Array, equipment_slot_keys: Array, get_equipment_definition: Callable, create_empty_equipment: Callable) -> void:
	var equipment_by_uid: Dictionary = {}
	var loaded_links_by_uid: Dictionary = {}
	for equipment_index in range(equipment_list.size()):
		var equipment_instance: Dictionary = _as_dictionary(equipment_list[equipment_index]).duplicate(true)
		var loaded_hero_uid := int(equipment_instance.get("equipped_hero_uid", -1))
		var loaded_slot := String(equipment_instance.get("equipped_slot", "")).strip_edges()
		if loaded_hero_uid > 0 and equipment_slot_keys.has(loaded_slot):
			loaded_links_by_uid[int(equipment_instance.get("uid", -1))] = {
				"hero_uid": loaded_hero_uid,
				"slot_key": loaded_slot,
			}
		equipment_instance["equipped_hero_uid"] = -1
		equipment_instance["equipped_slot"] = ""
		equipment_list[equipment_index] = equipment_instance
		equipment_by_uid[int(equipment_instance.get("uid", -1))] = equipment_index
	var hero_index_by_uid: Dictionary = {}
	var hero_equipment_by_uid: Dictionary = {}
	var claimed_equipment_uids: Dictionary = {}
	for hero_index in range(hero_list.size()):
		var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
		var hero_uid := int(hero_data.get("uid", -1))
		if hero_uid > 0:
			hero_index_by_uid[hero_uid] = hero_index
		var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
		if hero_equipment.is_empty():
			hero_equipment = create_empty_equipment.call()
		var normalized_equipment: Dictionary = _as_dictionary(create_empty_equipment.call()).duplicate(true)
		for slot_key_variant in equipment_slot_keys:
			var slot_key := String(slot_key_variant)
			var equipment_uid := int(String(hero_equipment.get(slot_key, "")).strip_edges())
			if equipment_uid <= 0:
				continue
			var equipment_index := int(equipment_by_uid.get(equipment_uid, -1))
			if equipment_index == -1:
				continue
			var equipment_instance: Dictionary = _as_dictionary(equipment_list[equipment_index]).duplicate(true)
			var equipment_definition: Dictionary = get_equipment_definition.call(String(equipment_instance.get("definition_id", "")))
			if equipment_definition.is_empty() or String(equipment_definition.get("slot", "")) != slot_key or claimed_equipment_uids.has(equipment_uid):
				continue
			normalized_equipment[slot_key] = str(equipment_uid)
			claimed_equipment_uids[equipment_uid] = true
		hero_equipment_by_uid[hero_uid] = normalized_equipment
	for equipment_uid_variant in loaded_links_by_uid.keys():
		var equipment_uid := int(equipment_uid_variant)
		if equipment_uid <= 0 or claimed_equipment_uids.has(equipment_uid):
			continue
		var equipment_index := int(equipment_by_uid.get(equipment_uid, -1))
		if equipment_index == -1:
			continue
		var loaded_link := _as_dictionary(loaded_links_by_uid.get(equipment_uid, {}))
		var hero_uid := int(loaded_link.get("hero_uid", -1))
		var slot_key := String(loaded_link.get("slot_key", "")).strip_edges()
		var hero_index := int(hero_index_by_uid.get(hero_uid, -1))
		if hero_index == -1 or not equipment_slot_keys.has(slot_key):
			continue
		var hero_equipment := _as_dictionary(hero_equipment_by_uid.get(hero_uid, create_empty_equipment.call())).duplicate(true)
		if not String(hero_equipment.get(slot_key, "")).strip_edges().is_empty():
			continue
		var equipment_instance: Dictionary = _as_dictionary(equipment_list[equipment_index]).duplicate(true)
		var equipment_definition: Dictionary = get_equipment_definition.call(String(equipment_instance.get("definition_id", "")))
		if equipment_definition.is_empty() or String(equipment_definition.get("slot", "")) != slot_key:
			continue
		hero_equipment[slot_key] = str(equipment_uid)
		hero_equipment_by_uid[hero_uid] = hero_equipment
		claimed_equipment_uids[equipment_uid] = true
	for hero_index in range(hero_list.size()):
		var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
		var hero_uid := int(hero_data.get("uid", -1))
		hero_data["equipment"] = _as_dictionary(hero_equipment_by_uid.get(hero_uid, create_empty_equipment.call())).duplicate(true)
		hero_list[hero_index] = hero_data
	for equipment_uid_variant in equipment_by_uid.keys():
		var equipment_uid := int(equipment_uid_variant)
		var equipment_index := int(equipment_by_uid.get(equipment_uid, -1))
		if equipment_index == -1:
			continue
		var equipment_instance: Dictionary = _as_dictionary(equipment_list[equipment_index]).duplicate(true)
		for hero_uid_variant in hero_equipment_by_uid.keys():
			var hero_uid := int(hero_uid_variant)
			var hero_equipment := _as_dictionary(hero_equipment_by_uid.get(hero_uid, {}))
			for slot_key_variant in equipment_slot_keys:
				var slot_key := String(slot_key_variant)
				if int(String(hero_equipment.get(slot_key, "")).strip_edges()) != equipment_uid:
					continue
				equipment_instance["equipped_hero_uid"] = hero_uid
				equipment_instance["equipped_slot"] = slot_key
				break
			if int(equipment_instance.get("equipped_hero_uid", -1)) > 0:
				break
		equipment_list[equipment_index] = equipment_instance


func rebuild_world_task_compatibility(hero_list: Array, zone_state: Dictionary) -> void:
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
		for hero_uid in _normalize_int_array(zone.get("assigned_hero_uids", [])):
			var hero_index := int(hero_index_by_uid.get(hero_uid, -1))
			if hero_index == -1:
				continue
			var hero_data: Dictionary = _as_dictionary(hero_list[hero_index]).duplicate(true)
			hero_data["world_task"] = {
				"type": "clearing",
				"zone_key": String(zone_key),
			}
			hero_list[hero_index] = hero_data
			valid_hero_ids.append(hero_uid)
		zone["assigned_hero_uids"] = valid_hero_ids
		zone_state[zone_key] = zone


func hero_world_task_is_idle(hero_uid: int, zone_state: Dictionary) -> bool:
	for zone_key in zone_state.keys():
		var zone := _as_dictionary(zone_state.get(zone_key, {}))
		if String(zone.get("state", "")) != "clearing":
			continue
		if _normalize_int_array(zone.get("assigned_hero_uids", [])).has(hero_uid):
			return false
	return true


func _get_active_settlement_slots() -> Array:
	if active_settlement_id.is_empty():
		return SettlementGameData.create_empty_grid()
	var settlement_state := _ensure_settlement_state(active_settlement_id)
	var settlement_slots = settlement_state.get("slots", [])
	if settlement_slots is Array:
		return settlement_slots
	settlement_state["slots"] = SettlementGameData.create_empty_grid()
	settlement_states[active_settlement_id] = settlement_state
	return settlement_state["slots"]


func _set_active_settlement_slots(value: Array) -> void:
	if active_settlement_id.is_empty():
		return
	var settlement_state := _ensure_settlement_state(active_settlement_id)
	settlement_state["slots"] = value
	settlement_states[active_settlement_id] = settlement_state


func _ensure_settlement_state(settlement_id: String) -> Dictionary:
	var normalized_id := String(settlement_id).strip_edges()
	if normalized_id.is_empty():
		return {}
	if not settlement_states.has(normalized_id):
		settlement_states[normalized_id] = {
			"settlement_id": normalized_id,
			"slots": SettlementGameData.create_empty_grid(),
		}
	return _as_dictionary(settlement_states.get(normalized_id, {}))


func _get_settlement_slots_from_state(settlement_state: Dictionary) -> Array:
	var settlement_slots = settlement_state.get("slots", [])
	if settlement_slots is Array:
		return settlement_slots
	settlement_state["slots"] = SettlementGameData.create_empty_grid()
	return settlement_state["slots"]


func _save_path(slot_index: int) -> String:
	return "user://save_slot_%d.json" % slot_index


func _load_save_slot_manifest() -> Dictionary:
	if not FileAccess.file_exists(SAVE_SLOT_MANIFEST_PATH):
		return {}
	var raw_text := FileAccess.get_file_as_string(SAVE_SLOT_MANIFEST_PATH)
	if raw_text.is_empty():
		return {}
	var parsed = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _save_save_slot_manifest(manifest: Dictionary) -> void:
	var file := FileAccess.open(SAVE_SLOT_MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()


func duplicate_dict_array(source: Variant) -> Array:
	var copy: Array = []
	if source is Array:
		for entry in source:
			if entry is Dictionary:
				copy.append((entry as Dictionary).duplicate(true))
	return copy


func duplicate_world_zones(source: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for zone_key in source.keys():
		copy[zone_key] = _as_dictionary(source[zone_key]).duplicate(true)
	return copy


func _build_slot_snapshot(slot_index: int, slot_value: Variant) -> Dictionary:
	var slot_data := _as_dictionary(slot_value).duplicate(true)
	var assigned_ids := _normalize_int_array(slot_data.get("assigned_hero_ids", []))
	slot_data["index"] = slot_index
	slot_data["building_id"] = String(slot_data.get("building_id", "")).strip_edges()
	slot_data["level"] = max(1, int(slot_data.get("level", 1)))
	slot_data["assigned_hero_ids"] = assigned_ids
	slot_data["assigned_hero_count"] = assigned_ids.size()
	return slot_data


func _build_hero_snapshot(hero_value: Variant) -> Dictionary:
	var hero_data := _as_dictionary(hero_value).duplicate(true)
	var assignment := {
		"settlement_id": String(hero_data.get("assigned_settlement_id", "")).strip_edges(),
		"slot_index": int(hero_data.get("assigned_slot", -1)),
	}
	assignment["assigned"] = not String(assignment.get("settlement_id", "")).is_empty() and int(assignment.get("slot_index", -1)) >= 0
	hero_data["uid"] = int(hero_data.get("uid", -1))
	hero_data["definition_id"] = String(hero_data.get("definition_id", "")).strip_edges()
	hero_data["name"] = String(hero_data.get("name", "Unknown Hero"))
	hero_data["class"] = String(hero_data.get("class", "Hero"))
	hero_data["level"] = max(1, int(hero_data.get("level", 1)))
	hero_data["assigned_settlement_id"] = String(assignment.get("settlement_id", ""))
	hero_data["assigned_slot"] = int(assignment.get("slot_index", -1))
	hero_data["assignment"] = assignment
	hero_data["equipment"] = _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
	hero_data["stats"] = _as_dictionary(hero_data.get("stats", {})).duplicate(true)
	hero_data["work_stats"] = _as_dictionary(hero_data.get("work_stats", {})).duplicate(true)
	hero_data["world_task"] = _as_dictionary(hero_data.get("world_task", {})).duplicate(true)
	hero_data["source"] = String(hero_data.get("source", "core"))
	hero_data["mod_id"] = String(hero_data.get("mod_id", ""))
	return hero_data


func _build_inventory_item_snapshot(item_value: Variant) -> Dictionary:
	var item_data := _as_dictionary(item_value).duplicate(true)
	item_data["definition_id"] = String(item_data.get("definition_id", "")).strip_edges()
	item_data["quantity"] = max(0, int(item_data.get("quantity", 0)))
	return item_data


func _build_inventory_equipment_snapshot(equipment_value: Variant) -> Dictionary:
	var equipment_data := _as_dictionary(equipment_value).duplicate(true)
	equipment_data["uid"] = int(equipment_data.get("uid", -1))
	equipment_data["definition_id"] = String(equipment_data.get("definition_id", "")).strip_edges()
	equipment_data["equipped_hero_uid"] = int(equipment_data.get("equipped_hero_uid", -1))
	equipment_data["equipped_slot"] = String(equipment_data.get("equipped_slot", "")).strip_edges()
	equipment_data["slot_key"] = String(equipment_data.get("equipped_slot", "")).strip_edges()
	equipment_data["is_equipped"] = int(equipment_data.get("equipped_hero_uid", -1)) > 0
	return equipment_data


func _build_world_zone_snapshot(zone_key: String, zone_value: Variant) -> Dictionary:
	var zone_data := _as_dictionary(zone_value).duplicate(true)
	var assigned_hero_uids := _normalize_int_array(zone_data.get("assigned_hero_uids", []))
	zone_data["key"] = String(zone_data.get("key", zone_key)).strip_edges()
	zone_data["x"] = int(zone_data.get("x", 0))
	zone_data["y"] = int(zone_data.get("y", 0))
	zone_data["state"] = String(zone_data.get("state", "fog")).strip_edges()
	zone_data["ticks_remaining"] = max(0, int(zone_data.get("ticks_remaining", 0)))
	zone_data["clear_duration"] = max(0, int(zone_data.get("clear_duration", 0)))
	zone_data["assigned_hero_uids"] = assigned_hero_uids
	zone_data["assigned_hero_count"] = assigned_hero_uids.size()
	zone_data["generated_name"] = String(zone_data.get("generated_name", "")).strip_edges()
	zone_data["claim_cost"] = _as_dictionary(zone_data.get("claim_cost", {})).duplicate(true)
	zone_data["settlement_id"] = String(zone_data.get("settlement_id", "")).strip_edges()
	zone_data["settlement_name"] = String(zone_data.get("settlement_name", "")).strip_edges()
	zone_data["is_settlement_zone"] = not String(zone_data.get("settlement_id", "")).strip_edges().is_empty()
	return zone_data


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _normalize_int_array(value: Variant) -> Array:
	var normalized: Array = []
	if value is Array:
		for entry in value:
			normalized.append(int(entry))
	return normalized


func _create_idle_world_task() -> Dictionary:
	return {
		"type": "",
		"zone_key": "",
	}
