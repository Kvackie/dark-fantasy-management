extends Node

signal resources_changed()
signal settlement_changed()
signal heroes_changed()
signal inventory_changed()
signal active_settlement_changed(settlement_id)
signal selection_changed(slot_index)
signal save_slots_changed()
signal tick_processed(tick_count, production_delta)
signal save_loaded(slot_index)
signal world_changed()
signal recruit_market_changed()

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const RESOURCE_ID_FOOD := "food"
const RESOURCE_ID_WOOD := "wood"
const RESOURCE_ID_STONE := "stone"
const RESOURCE_ID_CRYSTALS := "crystals"
const RESOURCE_WORK_STAT_MAP := {
	RESOURCE_ID_FOOD: "farming",
	RESOURCE_ID_WOOD: "lumbering",
	RESOURCE_ID_STONE: "mining",
	RESOURCE_ID_CRYSTALS: "mining",
}
const WORK_STAT_PRODUCTION_BONUS_PER_POINT := 0.03

var resources: Dictionary:
	get:
		return _session().resources
	set(value):
		_session().resources = value
var slots: Array:
	get:
		return _session().slots
	set(value):
		_session().slots = value
var settlement_states: Dictionary:
	get:
		return _session().settlement_states
	set(value):
		_session().settlement_states = value
var heroes: Array:
	get:
		return _session().heroes
	set(value):
		_session().heroes = value
var inventory_items: Array:
	get:
		return _session().inventory_items
	set(value):
		_session().inventory_items = value
var inventory_equipment: Array:
	get:
		return _session().inventory_equipment
	set(value):
		_session().inventory_equipment = value
var recruit_market_offers: Array:
	get:
		return _session().recruit_market_offers
	set(value):
		_session().recruit_market_offers = value
var recruit_market_initialized: bool:
	get:
		return _session().recruit_market_initialized
	set(value):
		_session().recruit_market_initialized = value
var owned_settlement_ids: Array:
	get:
		return _session().owned_settlement_ids
	set(value):
		_session().owned_settlement_ids = value
var active_settlement_id: String:
	get:
		return _session().active_settlement_id
	set(value):
		_session().active_settlement_id = value
var world_seed: int:
	get:
		return _session().world_seed
	set(value):
		_session().world_seed = value
var world_zones: Dictionary:
	get:
		return _session().world_zones
	set(value):
		_session().world_zones = value
var selected_slot: int:
	get:
		return _session().selected_slot
	set(value):
		_session().selected_slot = value
var active_save_slot: int:
	get:
		return _session().active_save_slot
	set(value):
		_session().active_save_slot = value
var tick_count: int:
	get:
		return _session().tick_count
	set(value):
		_session().tick_count = value

var _next_hero_uid: int:
	get:
		return _session().next_hero_uid
	set(value):
		_session().next_hero_uid = value
var _next_equipment_uid: int:
	get:
		return _session().next_equipment_uid
	set(value):
		_session().next_equipment_uid = value
var _next_recruit_offer_id: int:
	get:
		return _session().next_recruit_offer_id
	set(value):
		_session().next_recruit_offer_id = value
var _game_session: Node = null
var _tick_timer: Timer


func _ready() -> void:
	randomize()
	_resolve_session_dependency()
	_tick_timer = Timer.new()
	_tick_timer.wait_time = SettlementGameData.TICK_SECONDS
	_tick_timer.autostart = true
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick_timeout)
	add_child(_tick_timer)
	reset_new_game()
	emit_state()


func _process(delta: float) -> void:
	_session().process_autosave(delta, SettlementGameData.AUTOSAVE_INTERVAL, Callable(self, "_serialize_state"))


func reset_new_game() -> void:
	var default_settlement_id := DataLoader.get_default_settlement_id()
	_session().reset_runtime_state(SettlementGameData.duplicate_resources(SettlementGameData.STARTING_RESOURCES), default_settlement_id)
	_sync_active_settlement_slots()
	world_seed = randi()
	world_zones = {}
	_initialize_world_state()
	_seed_starting_inventory()


func emit_state() -> void:
	_sync_active_settlement_slots()
	_reconcile_recruit_market_state(true)
	emit_signal("resources_changed")
	emit_signal("settlement_changed")
	emit_signal("heroes_changed")
	emit_signal("inventory_changed")
	emit_signal("recruit_market_changed")
	emit_signal("active_settlement_changed", active_settlement_id)
	emit_signal("world_changed")
	emit_signal("selection_changed", selected_slot)
	emit_signal("save_slots_changed")


func get_building_catalog() -> Array:
	return DataLoader.get_all_buildings()


func get_inventory_snapshot() -> Dictionary:
	return _session().get_inventory_snapshot()


func get_world_snapshot() -> Dictionary:
	return _session().get_world_snapshot(DataLoader.get_world_config())


func get_owned_settlement_ids() -> Array:
	return owned_settlement_ids.duplicate()


func get_owned_settlement_definitions() -> Array:
	var owned_definitions: Array = []
	for settlement_id in owned_settlement_ids:
		var definition := _get_any_settlement_definition(String(settlement_id))
		if not definition.is_empty():
			owned_definitions.append(definition)
	return owned_definitions


func get_recruit_market_snapshot() -> Dictionary:
	return {
		"unlocked": is_recruitment_unlocked(),
		"tavern_count": get_built_tavern_count(),
		"offer_capacity": get_recruit_offer_capacity(),
		"refresh_cost": get_recruit_refresh_cost(),
		"initialized": recruit_market_initialized,
		"offers": _session().duplicate_dict_array(recruit_market_offers),
	}


func is_recruitment_unlocked() -> bool:
	return get_built_tavern_count() > 0


func get_built_tavern_count() -> int:
	var tavern_count := 0
	for settlement_id in owned_settlement_ids:
		for slot in _get_settlement_slots(String(settlement_id)):
			if String((slot as Dictionary).get("building_id", "")) == "tavern":
				tavern_count += 1
	return tavern_count


func get_recruit_offer_capacity() -> int:
	var recruitment_config := DataLoader.get_recruitment_config()
	var tavern_count := get_built_tavern_count()
	if tavern_count <= 0:
		return 0
	var base_offer_count: int = max(1, int(recruitment_config.get("base_offer_count", 3)))
	var extra_offer_per_tavern: int = max(0, int(recruitment_config.get("extra_offer_per_tavern", 1)))
	return base_offer_count + max(tavern_count - 1, 0) * extra_offer_per_tavern


func get_recruit_refresh_cost() -> Dictionary:
	var recruitment_config := DataLoader.get_recruitment_config()
	return SettlementGameData.resource_list_to_dictionary(_as_array(recruitment_config.get("refresh_cost", [])))


func get_settlement_slots_snapshot(settlement_id: String) -> Array:
	return _session().get_settlement_slots_snapshot(settlement_id)


func get_settlement_built_plot_count(settlement_id: String) -> int:
	var built_slots := 0
	for slot in _get_settlement_slots(settlement_id):
		if not String((slot as Dictionary).get("building_id", "")).is_empty():
			built_slots += 1
	return built_slots


func is_settlement_owned(settlement_id: String) -> bool:
	return owned_settlement_ids.has(String(settlement_id).strip_edges())


func get_active_settlement_definition() -> Dictionary:
	return _get_any_settlement_definition(active_settlement_id)


func get_active_settlement_name() -> String:
	var definition := get_active_settlement_definition()
	if definition.is_empty():
		return "Settlement"
	return String(definition.get("name", "Settlement"))


func get_settlement_display_name(settlement_id: String) -> String:
	var definition := _get_any_settlement_definition(settlement_id)
	if definition.is_empty():
		return String(settlement_id)
	return String(definition.get("name", settlement_id))


func set_active_settlement(settlement_id: String) -> bool:
	var normalized_id := String(settlement_id).strip_edges()
	if normalized_id.is_empty():
		return false
	var definition := _get_any_settlement_definition(normalized_id)
	if definition.is_empty():
		return false
	if not is_settlement_owned(normalized_id):
		return false
	if active_settlement_id == normalized_id:
		return true
	active_settlement_id = normalized_id
	_sync_active_settlement_slots()
	emit_signal("settlement_changed")
	emit_signal("active_settlement_changed", active_settlement_id)
	_request_persistence_update()
	return true


func get_world_zone(zone_key: String) -> Dictionary:
	return _session().get_world_zone_snapshot(zone_key)


func get_available_heroes_for_world_zone(_zone_key: String) -> Array:
	var available: Array = []
	for hero in heroes:
		var hero_data: Dictionary = hero
		if _is_hero_available_for_world(hero_data):
			available.append(hero_data.duplicate(true))
	return available


func start_zone_clearing(zone_key: String, hero_uids: Array) -> bool:
	var zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
	if zone.is_empty() or String(zone.get("state", "")) != "discovered":
		return false
	var world_config: Dictionary = DataLoader.get_world_config()
	var max_party: int = max(1, int(world_config.get("max_clearing_party", 3)))
	var selected_heroes: Array = []
	for hero_uid in hero_uids:
		var normalized_uid := int(hero_uid)
		if normalized_uid <= 0 or selected_heroes.has(normalized_uid):
			continue
		if selected_heroes.size() >= max_party:
			break
		var hero_index := _find_hero_index(normalized_uid)
		if hero_index == -1:
			continue
		var hero_data: Dictionary = heroes[hero_index]
		if not _is_hero_available_for_world(hero_data):
			continue
		selected_heroes.append(normalized_uid)
	if selected_heroes.is_empty():
		return false
	var duration := _get_zone_clear_duration(zone)
	zone["state"] = "clearing"
	zone["assigned_hero_uids"] = selected_heroes.duplicate()
	zone["ticks_remaining"] = duration
	zone["clear_duration"] = duration
	world_zones[zone_key] = zone
	_session().rebuild_world_task_compatibility(heroes, world_zones)
	_emit_world_and_hero_state(true)
	return true


func claim_world_zone(zone_key: String) -> bool:
	var zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
	if zone.is_empty() or String(zone.get("state", "")) != "cleared":
		return false
	var claim_cost := _as_dictionary(zone.get("claim_cost", {}))
	if not apply_cost(claim_cost):
		return false
	zone["state"] = "claimed"
	if String(zone.get("settlement_id", "")).is_empty():
		zone["settlement_id"] = _generated_settlement_id(int(zone.get("x", 0)), int(zone.get("y", 0)))
	if String(zone.get("settlement_name", "")).is_empty():
		zone["settlement_name"] = String(zone.get("generated_name", _generate_zone_name(int(zone.get("x", 0)), int(zone.get("y", 0)))))
	zone["generated_name"] = String(zone.get("settlement_name", ""))
	world_zones[zone_key] = zone
	var settlement_id := String(zone.get("settlement_id", ""))
	_register_generated_settlement_definition(zone)
	if not settlement_id.is_empty() and not owned_settlement_ids.has(settlement_id):
		owned_settlement_ids.append(settlement_id)
	if not settlement_id.is_empty():
		_ensure_settlement_state(settlement_id)
	_apply_world_visibility()
	_emit_world_state(true)
	return true


func get_hero_effective_stats(hero_uid: int) -> Dictionary:
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return {}
	var hero_data: Dictionary = heroes[hero_index]
	var stats: Dictionary = _as_dictionary(hero_data.get("stats", {})).duplicate(true)
	var bonuses: Dictionary = _get_hero_equipment_bonuses(hero_data)
	for stat_key in DataLoader.DEFAULT_HERO_STATS.keys():
		stats[stat_key] = int(stats.get(stat_key, 0)) + int(_as_dictionary(bonuses.get("stats", {})).get(stat_key, 0))
	return stats


func get_hero_effective_work_stats(hero_uid: int) -> Dictionary:
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return {}
	var hero_data: Dictionary = heroes[hero_index]
	var work_stats: Dictionary = _as_dictionary(hero_data.get("work_stats", {})).duplicate(true)
	var bonuses: Dictionary = _get_hero_equipment_bonuses(hero_data)
	for stat_key in DataLoader.DEFAULT_HERO_WORK_STATS.keys():
		work_stats[stat_key] = int(work_stats.get(stat_key, 0)) + int(_as_dictionary(bonuses.get("work_stats", {})).get(stat_key, 0))
	return work_stats


func get_slot(slot_index: int) -> Dictionary:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return {}
	return (slots[slot_index] as Dictionary).duplicate(true)


func get_slot_building_definition(slot_index: int) -> Dictionary:
	var slot: Dictionary = get_slot(slot_index)
	if String(slot.get("building_id", "")).is_empty():
		return {}
	return DataLoader.get_building_definition(String(slot.get("building_id", "")))


func get_upgrade_cost(slot_index: int) -> Dictionary:
	var slot: Dictionary = get_slot(slot_index)
	if String(slot.get("building_id", "")).is_empty():
		return {}
	var definition: Dictionary = get_slot_building_definition(slot_index)
	var growth: float = float(definition.get("upgrade_growth", 1.0))
	return SettlementGameData.scaled_cost(_as_array(definition.get("upgrade_cost", [])), int(slot.get("level", 1)), growth)


func get_total_investment(slot_index: int) -> Dictionary:
	var slot: Dictionary = get_slot(slot_index)
	if String(slot.get("building_id", "")).is_empty():
		return {}
	var definition: Dictionary = get_slot_building_definition(slot_index)
	var investment: Dictionary = SettlementGameData.resource_list_to_dictionary(_as_array(definition.get("build_cost", [])))
	var current_level: int = int(slot.get("level", 1))
	var growth: float = float(definition.get("upgrade_growth", 1.0))
	for paid_level in range(1, current_level):
		investment = SettlementGameData.merge_resource_delta(
			investment,
			SettlementGameData.scaled_cost(_as_array(definition.get("upgrade_cost", [])), paid_level, growth)
		)
	return investment


func get_dismantle_refund(slot_index: int) -> Dictionary:
	return SettlementGameData.scale_resource_dictionary(get_total_investment(slot_index), 0.8)


func build_on_slot(slot_index: int, building_id: String) -> bool:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: Dictionary = slots[slot_index]
	if not String(slot.get("building_id", "")).is_empty():
		return false
	var definition: Dictionary = DataLoader.get_building_definition(building_id)
	if definition.is_empty():
		return false
	var build_cost: Dictionary = SettlementGameData.resource_list_to_dictionary(_as_array(definition.get("build_cost", [])))
	if not apply_cost(build_cost):
		return false
	slot["building_id"] = building_id
	slot["level"] = 1
	slot["assigned_hero_ids"] = []
	slots[slot_index] = slot
	_emit_settlement_state(true)
	return true


func upgrade_building(slot_index: int) -> bool:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: Dictionary = slots[slot_index]
	var definition: Dictionary = get_slot_building_definition(slot_index)
	if definition.is_empty():
		return false
	var max_level: int = int(definition.get("max_level", SettlementGameData.MAX_BUILDING_LEVEL))
	if int(slot.get("level", 1)) >= max_level:
		return false
	var upgrade_cost: Dictionary = get_upgrade_cost(slot_index)
	if not apply_cost(upgrade_cost):
		return false
	slot["level"] = int(slot.get("level", 1)) + 1
	slots[slot_index] = slot
	_emit_settlement_state(true)
	return true


func dismantle_building(slot_index: int) -> bool:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: Dictionary = slots[slot_index]
	if String(slot.get("building_id", "")).is_empty():
		return false
	var refund: Dictionary = get_dismantle_refund(slot_index)
	for hero_index in range(heroes.size()):
		var hero_data: Dictionary = heroes[hero_index]
		if String(hero_data.get("assigned_settlement_id", "")).strip_edges() != active_settlement_id:
			continue
		if int(hero_data.get("assigned_slot", -1)) != slot_index:
			continue
		hero_data["assigned_settlement_id"] = ""
		hero_data["assigned_slot"] = -1
		heroes[hero_index] = hero_data
	slots[slot_index] = SettlementGameData.empty_slot(slot_index)
	_session().rebuild_slot_assignment_compatibility(heroes, settlement_states)
	add_resources(refund)
	_emit_hero_and_settlement_state(true)
	return true


func get_available_heroes_for_slot(_slot_index: int) -> Array:
	var available: Array = []
	for hero in heroes:
		var hero_data: Dictionary = hero
		if not _is_hero_available_for_world(hero_data):
			continue
		available.append(hero_data.duplicate(true))
	return available


func get_slot_production_preview(slot_index: int) -> Dictionary:
	return _calculate_slot_production(get_slot(slot_index))


func get_owned_settlement_production_preview() -> Dictionary:
	var production_delta: Dictionary = {}
	for settlement_id in owned_settlement_ids:
		for slot in _get_settlement_slots(String(settlement_id)):
			var slot_data: Dictionary = slot
			var slot_delta: Dictionary = _calculate_slot_production(slot_data)
			for resource_id in slot_delta.keys():
				production_delta[resource_id] = int(production_delta.get(resource_id, 0)) + int(slot_delta[resource_id])
	return production_delta


func assign_hero_to_slot(hero_uid: int, slot_index: int) -> bool:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: Dictionary = slots[slot_index]
	var definition: Dictionary = get_slot_building_definition(slot_index)
	if definition.is_empty():
		return false
	var assigned_ids: Array = _normalize_int_array(slot.get("assigned_hero_ids", []))
	if not assigned_ids.has(hero_uid) and assigned_ids.size() >= int(definition.get("worker_slots", 0)):
		return false
	var hero_index: int = _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	var hero_data: Dictionary = heroes[hero_index]
	if not _session().hero_world_task_is_idle(hero_uid, world_zones):
		return false
	var previous_slot: int = int(hero_data.get("assigned_slot", -1))
	var previous_settlement_id := String(hero_data.get("assigned_settlement_id", "")).strip_edges()
	if previous_slot == slot_index and previous_settlement_id == active_settlement_id:
		return true
	_remove_hero_from_all_slots(hero_uid)
	hero_data["assigned_settlement_id"] = active_settlement_id
	hero_data["assigned_slot"] = slot_index
	heroes[hero_index] = hero_data
	_session().rebuild_slot_assignment_compatibility(heroes, settlement_states)
	_emit_hero_and_settlement_state(true)
	return true


func unassign_hero(hero_uid: int) -> bool:
	var hero_index: int = _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	var hero_data: Dictionary = heroes[hero_index]
	var previous_slot: int = int(hero_data.get("assigned_slot", -1))
	if previous_slot == -1:
		return false
	_remove_hero_from_all_slots(hero_uid)
	_emit_hero_and_settlement_state(true)
	return true


func refresh_recruit_offers() -> bool:
	if not is_recruitment_unlocked():
		return false
	var refresh_cost := get_recruit_refresh_cost()
	if not apply_cost(refresh_cost):
		return false
	recruit_market_offers = _generate_recruit_offer_batch(get_recruit_offer_capacity())
	recruit_market_initialized = true
	_emit_recruit_market_state(true)
	return true


func recruit_hero_from_offer(offer_id: int) -> Dictionary:
	var offer_index := _find_recruit_offer_index(offer_id)
	if offer_index == -1:
		return {}
	var offer_data: Dictionary = recruit_market_offers[offer_index]
	var recruit_cost := _normalize_resolved_recruit_cost(offer_data.get("recruit_cost", {}))
	if not apply_cost(recruit_cost):
		return {}
	var hero_instance := _create_hero_instance_from_offer(offer_data)
	heroes.append(hero_instance)
	recruit_market_offers.remove_at(offer_index)
	emit_signal("heroes_changed")
	emit_signal("recruit_market_changed")
	_request_persistence_update()
	return hero_instance.duplicate(true)


func dismiss_hero(hero_uid: int) -> bool:
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	_remove_hero_from_all_slots(hero_uid)
	_unequip_all_hero_equipment(hero_index)
	var world_changed := _remove_hero_from_world_tasks(hero_uid)
	heroes.remove_at(hero_index)
	_session().rebuild_slot_assignment_compatibility(heroes, settlement_states)
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))
	_session().rebuild_world_task_compatibility(heroes, world_zones)
	emit_signal("heroes_changed")
	emit_signal("settlement_changed")
	emit_signal("inventory_changed")
	if world_changed:
		emit_signal("world_changed")
	_request_persistence_update()
	return true


func debug_grant_all_resources() -> void:
	var delta: Dictionary = {}
	for resource_id in SettlementGameData.TRACKED_RESOURCES:
		delta[resource_id] = 100000
	add_resources(delta)
	_request_persistence_update()


func debug_recruit_random_hero() -> Dictionary:
	var hero_definition: Dictionary = _roll_hero_definition()
	if hero_definition.is_empty():
		return {}
	var hero_instance: Dictionary = _create_hero_instance(hero_definition)
	heroes.append(hero_instance)
	emit_signal("heroes_changed")
	emit_signal("resources_changed")
	_request_persistence_update()
	return hero_instance.duplicate(true)


func process_tick() -> Dictionary:
	tick_count += 1
	var production_delta := get_owned_settlement_production_preview()
	if not production_delta.is_empty():
		add_resources(production_delta)
	var world_result := _process_world_tick()
	if bool(world_result.get("heroes_changed", false)):
		emit_signal("heroes_changed")
	if bool(world_result.get("world_changed", false)):
		emit_signal("world_changed")
	emit_signal("tick_processed", tick_count, production_delta)
	if tick_count > 0:
		_request_persistence_update()
	return production_delta


func get_resource_snapshot() -> Dictionary:
	return _session().get_resource_snapshot()


func get_slots_snapshot() -> Array:
	_sync_active_settlement_slots()
	return _session().get_slots_snapshot()


func get_heroes_snapshot() -> Array:
	return _session().get_heroes_snapshot()


func add_item_to_inventory(definition_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var item_definition: Dictionary = DataLoader.get_item_definition(definition_id)
	if item_definition.is_empty():
		return
	var max_stack: int = max(1, int(item_definition.get("max_stack", DataLoader.DEFAULT_ITEM_MAX_STACK)))
	var remaining: int = quantity
	for stack_index in range(inventory_items.size()):
		if remaining <= 0:
			break
		var stack: Dictionary = inventory_items[stack_index]
		if String(stack.get("definition_id", "")) != definition_id:
			continue
		var current_quantity := int(stack.get("quantity", 0))
		if current_quantity >= max_stack:
			continue
		var added: int = min(max_stack - current_quantity, remaining)
		stack["quantity"] = current_quantity + added
		inventory_items[stack_index] = stack
		remaining -= added
	while remaining > 0:
		var stack_quantity: int = min(max_stack, remaining)
		inventory_items.append({
			"definition_id": definition_id,
			"quantity": stack_quantity,
		})
		remaining -= stack_quantity


func add_equipment_to_inventory(definition_id: String) -> Dictionary:
	var equipment_definition: Dictionary = DataLoader.get_equipment_definition(definition_id)
	if equipment_definition.is_empty():
		return {}
	var instance := _create_equipment_instance(equipment_definition)
	inventory_equipment.append(instance)
	return instance.duplicate(true)


func get_inventory_equipment_instance(equipment_uid: int) -> Dictionary:
	return _get_inventory_equipment_instance(equipment_uid)


func equip_equipment_to_hero(hero_uid: int, slot_key: String, equipment_uid: int) -> bool:
	if not DataLoader.HERO_EQUIPMENT_KEYS.has(slot_key):
		return false
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	var equipment_index := _find_inventory_equipment_index(equipment_uid)
	if equipment_index == -1:
		return false
	var equipment_instance: Dictionary = inventory_equipment[equipment_index]
	var equipment_definition := DataLoader.get_equipment_definition(String(equipment_instance.get("definition_id", "")))
	if equipment_definition.is_empty():
		return false
	if String(equipment_definition.get("slot", "")) != slot_key:
		return false
	_unequip_hero_slot_internal(hero_index, slot_key)
	_detach_equipment_instance(equipment_uid)
	var hero_data: Dictionary = heroes[hero_index]
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {})).duplicate(true)
	if hero_equipment.is_empty():
		hero_equipment = DataLoader.create_empty_hero_equipment()
		hero_data["equipment"] = hero_equipment
	hero_equipment[slot_key] = str(equipment_uid)
	hero_data["equipment"] = hero_equipment
	heroes[hero_index] = hero_data
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))
	_emit_hero_and_inventory_state(true)
	return true


func unequip_hero_slot(hero_uid: int, slot_key: String) -> bool:
	if not DataLoader.HERO_EQUIPMENT_KEYS.has(slot_key):
		return false
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return false
	if _unequip_hero_slot_internal(hero_index, slot_key) <= 0:
		return false
	_emit_hero_and_inventory_state(true)
	return true


func select_slot(slot_index: int) -> void:
	selected_slot = _session().set_selected_slot(slot_index, slots.size())
	emit_signal("selection_changed", selected_slot)


func can_afford(costs: Dictionary) -> bool:
	for resource_id in costs.keys():
		if int(resources.get(resource_id, 0)) < int(costs[resource_id]):
			return false
	return true


func apply_cost(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for resource_id in costs.keys():
		resources[resource_id] = SettlementGameData.clamp_resource(int(resources.get(resource_id, 0)) - int(costs[resource_id]))
	emit_signal("resources_changed")
	return true


func add_resources(delta: Dictionary) -> void:
	for resource_id in delta.keys():
		resources[resource_id] = SettlementGameData.clamp_resource(int(resources.get(resource_id, 0)) + int(delta[resource_id]))
	emit_signal("resources_changed")


func get_save_slot_metadata() -> Array:
	return _session().get_save_slot_metadata(SettlementGameData.SAVE_SLOT_COUNT, Callable(self, "_resolve_save_slot_name"))


func set_save_slot_name(slot_index: int, slot_name: String) -> void:
	if not _session().set_save_slot_name(slot_index, SettlementGameData.SAVE_SLOT_COUNT, slot_name):
		return
	emit_signal("save_slots_changed")


func reset_save_slot(slot_index: int) -> bool:
	if not _session().reset_save_slot_file(slot_index, SettlementGameData.SAVE_SLOT_COUNT):
		return false
	if slot_index == active_save_slot:
		reset_new_game()
		active_save_slot = slot_index
		emit_state()
	else:
		emit_signal("save_slots_changed")
	return true


func save_game(slot_index: int = active_save_slot) -> bool:
	if not _session().save_serialized_state(slot_index, _serialize_state()):
		return false
	active_save_slot = slot_index
	emit_signal("save_slots_changed")
	return true


func load_game(slot_index: int) -> bool:
	var parsed: Dictionary = _session().load_serialized_state(slot_index)
	if parsed.is_empty():
		return false
	_apply_loaded_state(parsed)
	active_save_slot = slot_index
	_session().clear_pending_save()
	emit_state()
	emit_signal("save_loaded", slot_index)
	return true


func _serialize_state() -> Dictionary:
	return _session().build_serialized_state(_serialize_settlement_states(), _duplicate_generated_settlement_definitions())


func _apply_loaded_state(data: Dictionary) -> void:
	resources = SettlementGameData.duplicate_resources(data.get("resources", {}))
	settlement_states = _normalize_loaded_settlement_states(data.get("settlement_states", {}), data.get("slots", []))
	_session().generated_settlement_definitions = _normalize_loaded_generated_settlement_definitions(data.get("generated_settlement_definitions", {}))
	heroes = []
	for hero in data.get("heroes", []):
		if hero is Dictionary:
			heroes.append(_normalize_loaded_hero((hero as Dictionary).duplicate(true)))
	inventory_items = _normalize_loaded_item_stacks(data.get("inventory_items", []))
	inventory_equipment = _normalize_loaded_equipment_instances(data.get("inventory_equipment", []))
	recruit_market_offers = _normalize_loaded_recruit_market_offers(data.get("recruit_market_offers", []))
	recruit_market_initialized = bool(data.get("recruit_market_initialized", data.has("recruit_market_offers"))) or not recruit_market_offers.is_empty()
	_reconcile_loaded_equipment_links()
	world_seed = int(data.get("world_seed", randi()))
	world_zones = _normalize_loaded_world_zones(data.get("world_zones", {}))
	owned_settlement_ids = _normalize_owned_settlement_ids(data.get("owned_settlement_ids", []))
	if owned_settlement_ids.is_empty():
		var default_settlement_id := DataLoader.get_default_settlement_id()
		if not default_settlement_id.is_empty():
			owned_settlement_ids.append(default_settlement_id)
	active_settlement_id = String(data.get("active_settlement_id", DataLoader.get_default_settlement_id())).strip_edges()
	if _get_any_settlement_definition(active_settlement_id).is_empty() or not is_settlement_owned(active_settlement_id):
		active_settlement_id = DataLoader.get_default_settlement_id()
		if not active_settlement_id.is_empty() and not is_settlement_owned(active_settlement_id):
			owned_settlement_ids.append(active_settlement_id)
	if world_zones.is_empty():
		_initialize_world_state()
	else:
		_reconcile_loaded_world_state()
	_reconcile_generated_settlement_definitions()
	_sync_active_settlement_slots()
	if not data.has("inventory_items") and not data.has("inventory_equipment"):
		_seed_starting_inventory()
	_session().repair_loaded_slot_assignment_state(heroes, settlement_states, owned_settlement_ids, DataLoader.get_default_settlement_id())
	selected_slot = int(data.get("selected_slot", -1))
	tick_count = int(data.get("tick_count", 0))
	_next_hero_uid = max(int(data.get("next_hero_uid", heroes.size() + 1)), _get_max_hero_uid() + 1)
	_next_equipment_uid = max(int(data.get("next_equipment_uid", inventory_equipment.size() + 1)), _get_max_equipment_uid() + 1)
	_next_recruit_offer_id = max(int(data.get("next_recruit_offer_id", recruit_market_offers.size() + 1)), _get_max_recruit_offer_id() + 1)
	_reconcile_recruit_market_state(not data.has("recruit_market_offers"))


func _emit_settlement_state(should_save: bool) -> void:
	_reconcile_recruit_market_state(true)
	emit_signal("settlement_changed")
	emit_signal("recruit_market_changed")
	if should_save:
		_request_persistence_update()


func _emit_hero_and_settlement_state(should_save: bool) -> void:
	_reconcile_recruit_market_state(true)
	emit_signal("heroes_changed")
	emit_signal("settlement_changed")
	emit_signal("recruit_market_changed")
	if should_save:
		_request_persistence_update()


func _emit_hero_and_inventory_state(should_save: bool) -> void:
	emit_signal("heroes_changed")
	emit_signal("inventory_changed")
	if should_save:
		_request_persistence_update()


func _emit_recruit_market_state(should_save: bool) -> void:
	emit_signal("recruit_market_changed")
	if should_save:
		_request_persistence_update()


func _seed_starting_inventory() -> void:
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
	for index in heroes.size():
		var hero_data: Dictionary = heroes[index]
		if int(hero_data.get("uid", -1)) == hero_uid:
			return index
	return -1


func _find_inventory_equipment_index(equipment_uid: int) -> int:
	for index in inventory_equipment.size():
		var equipment_instance: Dictionary = inventory_equipment[index]
		if int(equipment_instance.get("uid", -1)) == equipment_uid:
			return index
	return -1


func _remove_hero_from_slot(hero_uid: int, slot_index: int) -> void:
	_sync_active_settlement_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot: Dictionary = slots[slot_index]
	var assigned_ids: Array = []
	for assigned_id in _normalize_int_array(slot.get("assigned_hero_ids", [])):
		if int(assigned_id) != hero_uid:
			assigned_ids.append(int(assigned_id))
	slot["assigned_hero_ids"] = assigned_ids
	slots[slot_index] = slot


func _remove_hero_from_all_slots(hero_uid: int) -> void:
	var hero_index := _find_hero_index(hero_uid)
	if hero_index == -1:
		return
	var hero_data: Dictionary = heroes[hero_index]
	hero_data["assigned_settlement_id"] = ""
	hero_data["assigned_slot"] = -1
	heroes[hero_index] = hero_data
	_session().rebuild_slot_assignment_compatibility(heroes, settlement_states)


func _calculate_slot_production(slot: Dictionary) -> Dictionary:
	var building_id: String = String(slot.get("building_id", ""))
	if building_id.is_empty():
		return {}
	var definition: Dictionary = DataLoader.get_building_definition(building_id)
	if definition.is_empty():
		return {}
	var production_delta: Dictionary = {}
	var level_multiplier: float = 1.0
	level_multiplier += float(max(int(slot.get("level", 1)) - 1, 0)) * float(definition.get("upgrade_growth", 0.0))
	for entry in _as_array(definition.get("base_production", [])):
		if entry is Dictionary and entry.has("resource"):
			var base_amount: float = float(entry.get("amount", 0))
			var resource_id := String(entry.resource)
			var work_multiplier := 1.0 + (_get_slot_total_relevant_work(slot, resource_id) * WORK_STAT_PRODUCTION_BONUS_PER_POINT)
			var total_amount: int = int(round(base_amount * level_multiplier * work_multiplier))
			production_delta[String(entry.resource)] = total_amount
	return production_delta


func _get_slot_total_relevant_work(slot: Dictionary, resource_id: String) -> int:
	var work_stat_key := String(RESOURCE_WORK_STAT_MAP.get(resource_id, "")).strip_edges()
	if work_stat_key.is_empty():
		return 0
	var total_relevant_work := 0
	for hero_uid in _normalize_int_array(slot.get("assigned_hero_ids", [])):
		var effective_work_stats := get_hero_effective_work_stats(hero_uid)
		total_relevant_work += int(effective_work_stats.get(work_stat_key, 0))
	return total_relevant_work


func _reconcile_recruit_market_state(seed_offers_if_unlocked: bool) -> bool:
	if _next_recruit_offer_id < 1:
		_next_recruit_offer_id = 1
	if not is_recruitment_unlocked():
		return false
	var market_changed := false
	if not recruit_market_offers.is_empty():
		recruit_market_initialized = true
	if seed_offers_if_unlocked and not recruit_market_initialized and recruit_market_offers.is_empty():
		recruit_market_offers = _generate_recruit_offer_batch(get_recruit_offer_capacity())
		recruit_market_initialized = true
		market_changed = true
	if recruit_market_initialized and recruit_market_offers.size() < get_recruit_offer_capacity():
		recruit_market_offers.append_array(_generate_recruit_offer_batch_with_exclusions(get_recruit_offer_capacity() - recruit_market_offers.size(), _get_recruit_offer_definition_ids()))
		market_changed = true
	return market_changed


func _generate_recruit_offer_batch(offer_count: int) -> Array:
	return _generate_recruit_offer_batch_with_exclusions(offer_count, [])


func _generate_recruit_offer_batch_with_exclusions(offer_count: int, excluded_definition_ids: Array) -> Array:
	var offers: Array = []
	var hero_pool: Array = DataLoader.get_all_heroes()
	if offer_count <= 0 or hero_pool.is_empty():
		return offers
	var used_definition_ids: Dictionary = {}
	for definition_id in excluded_definition_ids:
		used_definition_ids[String(definition_id)] = true
	while offers.size() < offer_count:
		var weighted_pool: Array = []
		for entry in hero_pool:
			var hero_definition: Dictionary = entry
			var definition_id := String(hero_definition.get("id", ""))
			if used_definition_ids.has(definition_id):
				continue
			weighted_pool.append(hero_definition)
		if weighted_pool.is_empty():
			weighted_pool = hero_pool
		var selected_definition := _roll_weighted_hero_definition(weighted_pool)
		if selected_definition.is_empty():
			break
		offers.append(_create_recruit_offer(selected_definition))
		used_definition_ids[String(selected_definition.get("id", ""))] = true
	return offers


func _get_recruit_offer_definition_ids() -> Array:
	var definition_ids: Array = []
	for offer_entry in recruit_market_offers:
		var offer_data: Dictionary = offer_entry
		var definition_id := String(offer_data.get("definition_id", "")).strip_edges()
		if definition_id.is_empty():
			continue
		definition_ids.append(definition_id)
	return definition_ids


func _find_recruit_offer_index(offer_id: int) -> int:
	for offer_index in range(recruit_market_offers.size()):
		var offer_data: Dictionary = recruit_market_offers[offer_index]
		if int(offer_data.get("offer_id", -1)) == offer_id:
			return offer_index
	return -1


func _unequip_all_hero_equipment(hero_index: int) -> void:
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
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))


func _remove_hero_from_world_tasks(hero_uid: int) -> bool:
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
	if world_state_changed:
		_apply_world_visibility()
	_session().rebuild_world_task_compatibility(heroes, world_zones)
	return world_state_changed


func _roll_hero_definition() -> Dictionary:
	return _roll_weighted_hero_definition(DataLoader.get_all_heroes())


func _roll_weighted_hero_definition(roster: Array) -> Dictionary:
	if roster.is_empty():
		return {}
	var total_weight: int = 0
	for hero_definition in roster:
		var hero_data: Dictionary = hero_definition
		total_weight += max(1, int(hero_data.get("recruitment_weight", 1)))
	var roll: int = randi_range(1, total_weight)
	var cursor: int = 0
	for hero_definition in roster:
		var hero_data: Dictionary = hero_definition
		cursor += max(1, int(hero_data.get("recruitment_weight", 1)))
		if roll <= cursor:
			return hero_data.duplicate(true)
	return (roster[0] as Dictionary).duplicate(true)


func _create_recruit_offer(hero_definition: Dictionary) -> Dictionary:
	var hero_level := clampi(int(hero_definition.get("level", 1)), 1, 9999)
	var offer_data: Dictionary = {
		"offer_id": _next_recruit_offer_id,
		"definition_id": String(hero_definition.get("id", "")),
		"name": String(hero_definition.get("name", "Unknown Hero")),
		"class": String(hero_definition.get("class", "Supporter")),
		"level": hero_level,
		"recruit_cost": _resolve_recruit_cost(hero_definition, hero_level),
		"stats": _normalize_runtime_stats(hero_definition.get("stats", {}), DataLoader.DEFAULT_HERO_STATS),
		"work_stats": _normalize_runtime_stats(hero_definition.get("work_stats", {}), DataLoader.DEFAULT_HERO_WORK_STATS),
		"source": String(hero_definition.get("source", "core")),
		"mod_id": String(hero_definition.get("mod_id", "")),
	}
	_next_recruit_offer_id += 1
	return offer_data


func _resolve_recruit_cost(hero_definition: Dictionary, hero_level: int) -> Dictionary:
	var resolved_cost: Dictionary = {}
	for cost_entry in _as_array(hero_definition.get("recruit_cost", [])):
		var entry := _as_dictionary(cost_entry)
		var resource_id := String(entry.get("resource", "")).strip_edges()
		if resource_id.is_empty():
			continue
		var base_amount := 0
		if entry.has("min_amount") or entry.has("max_amount"):
			var min_amount := int(entry.get("min_amount", 0))
			var max_amount := int(entry.get("max_amount", min_amount))
			if max_amount < min_amount:
				var swap_amount := min_amount
				min_amount = max_amount
				max_amount = swap_amount
			base_amount = randi_range(min_amount, max_amount)
		else:
			base_amount = int(entry.get("amount", 0))
		var final_amount: int = max(0, base_amount + max(hero_level - 1, 0) * int(entry.get("per_level", 0)))
		if final_amount <= 0:
			continue
		resolved_cost[resource_id] = int(resolved_cost.get(resource_id, 0)) + final_amount
	return resolved_cost


func _normalize_resolved_recruit_cost(value: Variant) -> Dictionary:
	var normalized_cost: Dictionary = {}
	var source_cost := _as_dictionary(value)
	for resource_id in source_cost.keys():
		normalized_cost[String(resource_id)] = max(0, int(source_cost.get(resource_id, 0)))
	return normalized_cost


func _create_hero_instance(hero_definition: Dictionary) -> Dictionary:
	var hero_instance: Dictionary = {
		"uid": _next_hero_uid,
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
	_next_hero_uid += 1
	return hero_instance


func _create_hero_instance_from_offer(offer_data: Dictionary) -> Dictionary:
	var hero_instance: Dictionary = {
		"uid": _next_hero_uid,
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
	_next_hero_uid += 1
	return hero_instance


func _create_equipment_instance(equipment_definition: Dictionary) -> Dictionary:
	var equipment_instance: Dictionary = {
		"uid": _next_equipment_uid,
		"definition_id": String(equipment_definition.get("id", "")),
		"equipped_hero_uid": -1,
		"equipped_slot": "",
	}
	_next_equipment_uid += 1
	return equipment_instance


func _normalize_loaded_hero(hero_data: Dictionary) -> Dictionary:
	var definition_id := String(hero_data.get("definition_id", ""))
	var hero_definition: Dictionary = DataLoader.get_hero_definition(definition_id)
	var normalized: Dictionary = {
		"uid": int(hero_data.get("uid", _next_hero_uid)),
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


func _normalize_runtime_stats(value: Variant, fallback_value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var fallback: Dictionary = _as_dictionary(fallback_value)
	if fallback.is_empty():
		fallback = DataLoader.DEFAULT_HERO_STATS
	var normalized: Dictionary = {}
	for stat_key in fallback.keys():
		normalized[stat_key] = int(source_data.get(stat_key, fallback[stat_key]))
	return normalized


func _normalize_runtime_equipment(value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var equipment: Dictionary = DataLoader.create_empty_hero_equipment()
	for slot_key in equipment.keys():
		equipment[slot_key] = String(source_data.get(slot_key, "")).strip_edges()
	return equipment


func _create_idle_world_task() -> Dictionary:
	return {
		"type": "",
		"zone_key": "",
	}


func _normalize_world_task(value: Variant) -> Dictionary:
	var task_data := _as_dictionary(value)
	return {
		"type": String(task_data.get("type", "")).strip_edges(),
		"zone_key": String(task_data.get("zone_key", "")).strip_edges(),
	}


func _normalize_loaded_item_stacks(value: Variant) -> Array:
	var normalized: Array = []
	if value is not Array:
		return normalized
	for entry in value:
		if entry is not Dictionary:
			continue
		var definition_id := String((entry as Dictionary).get("definition_id", "")).strip_edges()
		var quantity := int((entry as Dictionary).get("quantity", 0))
		var item_definition: Dictionary = DataLoader.get_item_definition(definition_id)
		if item_definition.is_empty() or quantity <= 0:
			continue
		_append_item_stacks(normalized, definition_id, quantity, max(1, int(item_definition.get("max_stack", DataLoader.DEFAULT_ITEM_MAX_STACK))))
	return normalized


func _normalize_loaded_equipment_instances(value: Variant) -> Array:
	var normalized: Array = []
	if value is not Array:
		return normalized
	for entry in value:
		if entry is not Dictionary:
			continue
		var definition_id := String((entry as Dictionary).get("definition_id", "")).strip_edges()
		var equipment_definition: Dictionary = DataLoader.get_equipment_definition(definition_id)
		if equipment_definition.is_empty():
			continue
		var equipped_slot := String((entry as Dictionary).get("equipped_slot", "")).strip_edges()
		if not DataLoader.HERO_EQUIPMENT_KEYS.has(equipped_slot):
			equipped_slot = ""
		var normalized_entry: Dictionary = {
			"uid": int((entry as Dictionary).get("uid", 0)),
			"definition_id": definition_id,
			"equipped_hero_uid": int((entry as Dictionary).get("equipped_hero_uid", -1)),
			"equipped_slot": equipped_slot,
		}
		if int(normalized_entry.get("uid", 0)) <= 0:
			normalized_entry["uid"] = _next_equipment_uid + normalized.size()
		if int(normalized_entry.get("equipped_hero_uid", -1)) <= 0:
			normalized_entry["equipped_hero_uid"] = -1
			normalized_entry["equipped_slot"] = ""
		normalized.append(normalized_entry)
	return normalized


func _normalize_loaded_world_zones(value: Variant) -> Dictionary:
	var normalized: Dictionary = {}
	var source := _as_dictionary(value)
	for source_key in source.keys():
		var zone_data := _as_dictionary(source.get(source_key, {}))
		if zone_data.is_empty():
			continue
		var x := int(zone_data.get("x", 0))
		var y := int(zone_data.get("y", 0))
		var zone_key := _world_zone_key(x, y)
		var state := String(zone_data.get("state", "fog")).strip_edges()
		if not ["fog", "discovered", "clearing", "cleared", "claimed"].has(state):
			state = "fog"
		normalized[zone_key] = {
			"key": zone_key,
			"x": x,
			"y": y,
			"state": state,
			"ticks_remaining": max(0, int(zone_data.get("ticks_remaining", 0))),
			"clear_duration": max(0, int(zone_data.get("clear_duration", 0))),
			"assigned_hero_uids": _normalize_int_array(zone_data.get("assigned_hero_uids", [])),
			"generated_name": String(zone_data.get("generated_name", "")).strip_edges(),
			"claim_cost": _duplicate_optional_dict(zone_data.get("claim_cost", {})),
			"settlement_id": String(zone_data.get("settlement_id", "")).strip_edges(),
			"settlement_name": String(zone_data.get("settlement_name", "")).strip_edges(),
		}
	return normalized


func _normalize_loaded_settlement_states(value: Variant, legacy_slots: Variant) -> Dictionary:
	var normalized_states: Dictionary = {}
	var source_states := _as_dictionary(value)
	for settlement_id in source_states.keys():
		var settlement_key := String(settlement_id).strip_edges()
		if settlement_key.is_empty():
			continue
		var state_data := _as_dictionary(source_states.get(settlement_id, {}))
		normalized_states[settlement_key] = {
			"settlement_id": settlement_key,
			"slots": _normalize_loaded_slots_array(state_data.get("slots", [])),
		}
	if normalized_states.is_empty():
		var default_settlement_id := DataLoader.get_default_settlement_id()
		if not default_settlement_id.is_empty():
			normalized_states[default_settlement_id] = {
				"settlement_id": default_settlement_id,
				"slots": _normalize_loaded_slots_array(legacy_slots),
			}
	return normalized_states


func _normalize_loaded_slots_array(value: Variant) -> Array:
	var normalized_slots := SettlementGameData.create_empty_grid()
	if value is not Array:
		return normalized_slots
	for loaded_slot in value:
		if loaded_slot is not Dictionary:
			continue
		var index := int((loaded_slot as Dictionary).get("index", -1))
		if index < 0 or index >= normalized_slots.size():
			continue
		var slot_data: Dictionary = (loaded_slot as Dictionary).duplicate(true)
		slot_data["assigned_hero_ids"] = _normalize_int_array(slot_data.get("assigned_hero_ids", []))
		normalized_slots[index] = slot_data
	return normalized_slots


func _normalize_loaded_recruit_market_offers(value: Variant) -> Array:
	var normalized_offers: Array = []
	if value is not Array:
		return normalized_offers
	for offer_entry in value:
		if offer_entry is not Dictionary:
			continue
		var offer_data: Dictionary = (offer_entry as Dictionary).duplicate(true)
		var definition_id := String(offer_data.get("definition_id", "")).strip_edges()
		if definition_id.is_empty():
			continue
		var hero_definition := DataLoader.get_hero_definition(definition_id)
		normalized_offers.append({
			"offer_id": max(1, int(offer_data.get("offer_id", normalized_offers.size() + 1))),
			"definition_id": definition_id,
			"name": String(offer_data.get("name", hero_definition.get("name", "Unknown Hero"))),
			"class": String(offer_data.get("class", hero_definition.get("class", "Supporter"))),
			"level": clampi(int(offer_data.get("level", 1)), 1, 9999),
			"recruit_cost": _normalize_resolved_recruit_cost(offer_data.get("recruit_cost", _resolve_recruit_cost(hero_definition, clampi(int(offer_data.get("level", 1)), 1, 9999)))),
			"stats": _normalize_runtime_stats(offer_data.get("stats", {}), hero_definition.get("stats", DataLoader.DEFAULT_HERO_STATS)),
			"work_stats": _normalize_runtime_stats(offer_data.get("work_stats", {}), hero_definition.get("work_stats", DataLoader.DEFAULT_HERO_WORK_STATS)),
			"source": String(offer_data.get("source", hero_definition.get("source", "core"))),
			"mod_id": String(offer_data.get("mod_id", hero_definition.get("mod_id", ""))),
		})
	return normalized_offers


func _reconcile_loaded_equipment_links() -> void:
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))


func _normalize_owned_settlement_ids(value: Variant) -> Array:
	var normalized: Array = []
	if value is not Array:
		return normalized
	for entry in value:
		var settlement_id := String(entry).strip_edges()
		if settlement_id.is_empty():
			continue
		if _get_any_settlement_definition(settlement_id).is_empty():
			continue
		if normalized.has(settlement_id):
			continue
		normalized.append(settlement_id)
	return normalized


func _initialize_world_state() -> void:
	world_zones.clear()
	var start_zone := _create_world_zone(0, 0, "claimed")
	start_zone["settlement_id"] = DataLoader.get_default_settlement_id()
	start_zone["settlement_name"] = _starting_settlement_name()
	start_zone["generated_name"] = _starting_settlement_name()
	world_zones[String(start_zone.get("key", "0,0"))] = start_zone
	_apply_world_visibility()


func _reconcile_loaded_world_state() -> void:
	if world_zones.is_empty():
		_initialize_world_state()
		return
	for zone_key in world_zones.keys():
		var zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
		if String(zone.get("state", "")) != "clearing":
			zone["assigned_hero_uids"] = []
			if String(zone.get("state", "")) == "cleared":
				zone["generated_name"] = _ensure_zone_generated_name(zone)
				zone["claim_cost"] = _ensure_zone_claim_cost(zone)
			world_zones[zone_key] = zone
			continue
		var valid_hero_ids: Array = []
		for hero_uid in _normalize_int_array(zone.get("assigned_hero_uids", [])):
			var hero_index := _find_hero_index(hero_uid)
			if hero_index == -1:
				continue
			valid_hero_ids.append(hero_uid)
		zone["assigned_hero_uids"] = valid_hero_ids
		zone["clear_duration"] = max(1, int(zone.get("clear_duration", _get_zone_clear_duration(zone))))
		if valid_hero_ids.is_empty():
			zone["state"] = "discovered"
			zone["ticks_remaining"] = 0
		world_zones[zone_key] = zone
	if not world_zones.has(_world_zone_key(0, 0)):
		_initialize_world_state()
		return
	_apply_world_visibility()
	_session().rebuild_world_task_compatibility(heroes, world_zones)


func _process_world_tick() -> Dictionary:
	var world_state_changed := false
	var hero_state_changed := false
	for zone_key in world_zones.keys():
		var previous_zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
		if String(previous_zone.get("state", "")) != "clearing":
			continue
		var zone := previous_zone.duplicate(true)
		zone["ticks_remaining"] = max(0, int(zone.get("ticks_remaining", 0)) - 1)
		world_state_changed = true
		if int(zone.get("ticks_remaining", 0)) <= 0:
			zone["state"] = "cleared"
			zone["assigned_hero_uids"] = []
			zone["generated_name"] = _ensure_zone_generated_name(zone)
			zone["claim_cost"] = _ensure_zone_claim_cost(zone)
			hero_state_changed = true
		world_zones[zone_key] = zone
	if world_state_changed:
		_apply_world_visibility()
	if world_state_changed or hero_state_changed:
		_session().rebuild_world_task_compatibility(heroes, world_zones)
	return {
		"world_changed": world_state_changed,
		"heroes_changed": hero_state_changed,
	}


func _emit_world_state(should_save: bool) -> void:
	emit_signal("world_changed")
	if should_save:
		_request_persistence_update()


func _emit_world_and_hero_state(should_save: bool) -> void:
	emit_signal("heroes_changed")
	emit_signal("world_changed")
	if should_save:
		_request_persistence_update()


func _apply_world_visibility() -> void:
	var world_config: Dictionary = DataLoader.get_world_config()
	var reveal_radius: int = max(1, int(world_config.get("reveal_radius", 2)))
	for zone_entry in world_zones.values():
		var source_zone := zone_entry as Dictionary
		var state := String(source_zone.get("state", ""))
		if state == "claimed" and not bool(world_config.get("reveal_from_claimed", true)):
			continue
		if state == "cleared" and not bool(world_config.get("reveal_from_cleared", true)):
			continue
		if state not in ["claimed", "cleared"]:
			continue
		var base_x := int(source_zone.get("x", 0))
		var base_y := int(source_zone.get("y", 0))
		for dx in range(-reveal_radius, reveal_radius + 1):
			for dy in range(-reveal_radius, reveal_radius + 1):
				if dx == 0 and dy == 0:
					continue
				var distance: int = max(abs(dx), abs(dy))
				if distance > reveal_radius:
					continue
				_ensure_world_zone_visibility(base_x + dx, base_y + dy, "discovered" if distance == 1 else "fog")


func _ensure_world_zone_visibility(x: int, y: int, desired_state: String) -> void:
	var zone_key := _world_zone_key(x, y)
	if not world_zones.has(zone_key):
		world_zones[zone_key] = _create_world_zone(x, y, desired_state)
		return
	var zone := _as_dictionary(world_zones.get(zone_key, {})).duplicate(true)
	if _world_state_priority(desired_state) > _world_state_priority(String(zone.get("state", "fog"))):
		zone["state"] = desired_state
		world_zones[zone_key] = zone


func _create_world_zone(x: int, y: int, state: String) -> Dictionary:
	var zone_key := _world_zone_key(x, y)
	var zone: Dictionary = {
		"key": zone_key,
		"x": x,
		"y": y,
		"state": state,
		"ticks_remaining": 0,
		"clear_duration": _get_zone_clear_duration({"key": zone_key, "x": x, "y": y}),
		"assigned_hero_uids": [],
		"generated_name": "",
		"claim_cost": {},
		"settlement_id": "",
		"settlement_name": "",
	}
	return _apply_world_override(zone)


func _apply_world_override(zone: Dictionary) -> Dictionary:
	var override := DataLoader.get_world_zone_override(String(zone.get("key", "")))
	if override.is_empty():
		return zone
	if override.has("state"):
		zone["state"] = String(override.get("state", zone.get("state", "fog"))).strip_edges()
	if override.has("name"):
		zone["generated_name"] = String(override.get("name", "")).strip_edges()
	if override.has("clear_duration"):
		zone["clear_duration"] = max(0, int(override.get("clear_duration", zone.get("clear_duration", 0))))
	if override.has("claim_cost"):
		zone["claim_cost"] = _duplicate_optional_dict(override.get("claim_cost", {}))
	if override.has("settlement_id"):
		zone["settlement_id"] = String(override.get("settlement_id", "")).strip_edges()
	if override.has("settlement_name"):
		zone["settlement_name"] = String(override.get("settlement_name", "")).strip_edges()
	return zone


func _world_zone_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _world_state_priority(state: String) -> int:
	match state:
		"fog":
			return 1
		"discovered":
			return 2
		"clearing":
			return 3
		"cleared":
			return 4
		"claimed":
			return 5
		_:
			return 0


func _is_hero_available_for_world(hero_data: Dictionary) -> bool:
	return int(hero_data.get("assigned_slot", -1)) < 0 and _session().hero_world_task_is_idle(int(hero_data.get("uid", -1)), world_zones)


func _hero_world_task_is_idle(hero_data: Dictionary) -> bool:
	return _session().hero_world_task_is_idle(int(hero_data.get("uid", -1)), world_zones)


func _get_zone_clear_duration(zone: Dictionary) -> int:
	var override := DataLoader.get_world_zone_override(String(zone.get("key", _world_zone_key(int(zone.get("x", 0)), int(zone.get("y", 0))))))
	if override.has("clear_duration"):
		return max(1, int(override.get("clear_duration", 1)))
	var world_config := DataLoader.get_world_config()
	return max(1, int(world_config.get("default_clear_duration", 3)))


func _ensure_zone_generated_name(zone: Dictionary) -> String:
	var existing_name := String(zone.get("generated_name", "")).strip_edges()
	if not existing_name.is_empty():
		return existing_name
	var override := DataLoader.get_world_zone_override(String(zone.get("key", "")))
	if override.has("name"):
		return String(override.get("name", "")).strip_edges()
	return _generate_zone_name(int(zone.get("x", 0)), int(zone.get("y", 0)))


func _ensure_zone_claim_cost(zone: Dictionary) -> Dictionary:
	var existing_cost := _as_dictionary(zone.get("claim_cost", {}))
	if not existing_cost.is_empty() and _dictionary_has_nonzero_values(existing_cost):
		return existing_cost.duplicate(true)
	var override := DataLoader.get_world_zone_override(String(zone.get("key", "")))
	if override.has("claim_cost"):
		var override_cost := _duplicate_optional_dict(override.get("claim_cost", {}))
		if not override_cost.is_empty() and _dictionary_has_nonzero_values(override_cost):
			return override_cost
	return _generate_claim_cost(int(zone.get("x", 0)), int(zone.get("y", 0)))


func _generate_zone_name(x: int, y: int) -> String:
	var world_config := DataLoader.get_world_config()
	var name_config := _as_dictionary(world_config.get("name_generation", {}))
	var prefixes := _as_array(name_config.get("prefixes", []))
	var suffixes := _as_array(name_config.get("suffixes", []))
	var articles := _as_array(name_config.get("articles", []))
	var prefix := String(prefixes[_coord_random_index(x, y, 11, prefixes.size())]) if not prefixes.is_empty() else "Ashen"
	var suffix := String(suffixes[_coord_random_index(x, y, 23, suffixes.size())]) if not suffixes.is_empty() else "Reach"
	var article := String(articles[_coord_random_index(x, y, 37, articles.size())]) if not articles.is_empty() else ""
	var parts: Array[String] = []
	if not article.is_empty():
		parts.append(article)
	parts.append(prefix)
	parts.append(suffix)
	return " ".join(parts)


func _generate_claim_cost(x: int, y: int) -> Dictionary:
	var world_config: Dictionary = DataLoader.get_world_config()
	var claim_config: Dictionary = _as_dictionary(world_config.get("claim_cost", {}))
	var base: Dictionary = _as_dictionary(claim_config.get("base", {}))
	var step: Dictionary = _as_dictionary(claim_config.get("distance_step", {}))
	var variance: Dictionary = _as_dictionary(claim_config.get("variance", {}))
	var distance: int = max(abs(x), abs(y))
	var cost: Dictionary = {}
	for resource_id in base.keys():
		var amount: int = int(base.get(resource_id, 0)) + int(step.get(resource_id, 0)) * distance
		var variance_amount := int(variance.get(resource_id, 0))
		if variance_amount > 0:
			amount += _coord_random_range(x, y, String(resource_id).hash(), 0, variance_amount)
		cost[String(resource_id)] = max(amount, 0)
	return cost


func _generated_settlement_id(x: int, y: int) -> String:
	return "zone_%s_%s" % [_coord_id_component(x), _coord_id_component(y)]


func _coord_id_component(value: int) -> String:
	if value < 0:
		return "n%d" % abs(value)
	return "p%d" % value


func _coord_random_index(x: int, y: int, salt: int, size: int) -> int:
	if size <= 0:
		return 0
	return abs(_coord_hash(x, y, salt)) % size


func _coord_random_range(x: int, y: int, salt: int, min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	return min_value + (abs(_coord_hash(x, y, salt)) % (max_value - min_value + 1))


func _coord_hash(x: int, y: int, salt: int) -> int:
	return int(world_seed) ^ (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)


func _starting_settlement_name() -> String:
	var definition := DataLoader.get_settlement_definition(DataLoader.get_default_settlement_id())
	return String(definition.get("name", "The Hollow March"))


func _register_generated_settlement_definition(zone: Dictionary) -> void:
	var normalized := _create_generated_settlement_definition(zone)
	if normalized.is_empty():
		return
	_session().generated_settlement_definitions[String(normalized.get("id", ""))] = normalized


func _create_generated_settlement_definition(zone: Dictionary) -> Dictionary:
	var settlement_id := String(zone.get("settlement_id", "")).strip_edges()
	if settlement_id.is_empty():
		return {}
	var settlement_name := String(zone.get("settlement_name", zone.get("generated_name", ""))).strip_edges()
	if settlement_name.is_empty():
		return {}
	var generated_definition := DataLoader.normalize_settlement_definition({
		"id": settlement_id,
		"name": settlement_name,
		"icon_path": DataLoader.DEFAULT_CATALOG_ICON,
	})
	if generated_definition.is_empty():
		return {}
	generated_definition["generated_variant"] = true
	return generated_definition


func get_settlement_building_definition(settlement_id: String, slot_index: int) -> Dictionary:
	var settlement_slots := _get_settlement_slots(settlement_id)
	if slot_index < 0 or slot_index >= settlement_slots.size():
		return {}
	var slot: Dictionary = settlement_slots[slot_index]
	if String(slot.get("building_id", "")).is_empty():
		return {}
	return DataLoader.get_building_definition(String(slot.get("building_id", "")))


func _get_any_settlement_definition(settlement_id: String) -> Dictionary:
	var definition := DataLoader.get_settlement_definition(settlement_id)
	if not definition.is_empty():
		return definition
	return _as_dictionary(_session().generated_settlement_definitions.get(settlement_id, {})).duplicate(true)


func _duplicate_generated_settlement_definitions() -> Dictionary:
	var copy: Dictionary = {}
	for settlement_id in _session().generated_settlement_definitions.keys():
		copy[String(settlement_id)] = _as_dictionary(_session().generated_settlement_definitions[settlement_id]).duplicate(true)
	return copy


func _normalize_loaded_generated_settlement_definitions(value: Variant) -> Dictionary:
	var normalized: Dictionary = {}
	var source := _as_dictionary(value)
	for settlement_id in source.keys():
		var definition := DataLoader.normalize_settlement_definition(_as_dictionary(source[settlement_id]))
		if definition.is_empty():
			continue
		definition["generated_variant"] = true
		normalized[String(definition.get("id", settlement_id))] = definition
	return normalized


func _reconcile_generated_settlement_definitions() -> void:
	var generated_definitions: Dictionary = _session().generated_settlement_definitions.duplicate(true)
	for zone_data in world_zones.values():
		var zone := _as_dictionary(zone_data)
		if String(zone.get("state", "")) != "claimed":
			continue
		var normalized := _create_generated_settlement_definition(zone)
		if normalized.is_empty():
			continue
		generated_definitions[String(normalized.get("id", ""))] = normalized
	_session().generated_settlement_definitions = generated_definitions


func _serialize_settlement_states() -> Dictionary:
	var serialized: Dictionary = {}
	for settlement_id in settlement_states.keys():
		serialized[String(settlement_id)] = {
			"settlement_id": String(settlement_id),
			"slots": get_settlement_slots_snapshot(String(settlement_id)),
		}
	return serialized


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


func _get_settlement_slots(settlement_id: String) -> Array:
	var state := _ensure_settlement_state(settlement_id)
	var settlement_slots = state.get("slots", [])
	if settlement_slots is Array:
		return settlement_slots
	state["slots"] = SettlementGameData.create_empty_grid()
	settlement_states[String(settlement_id).strip_edges()] = state
	return state["slots"]


func _sync_active_settlement_slots() -> void:
	if active_settlement_id.is_empty():
		return
	_session().rebuild_slot_assignment_compatibility(heroes, settlement_states)


func _duplicate_optional_dict(value: Variant) -> Dictionary:
	return _as_dictionary(value).duplicate(true)


func _dictionary_has_nonzero_values(values: Dictionary) -> bool:
	for key in values.keys():
		if int(values[key]) != 0:
			return true
	return false


func _append_item_stacks(target: Array, definition_id: String, quantity: int, max_stack: int) -> void:
	var remaining: int = quantity
	for stack_index in range(target.size()):
		if remaining <= 0:
			break
		var stack: Dictionary = target[stack_index]
		if String(stack.get("definition_id", "")) != definition_id:
			continue
		var current_quantity := int(stack.get("quantity", 0))
		if current_quantity >= max_stack:
			continue
		var added: int = min(max_stack - current_quantity, remaining)
		stack["quantity"] = current_quantity + added
		target[stack_index] = stack
		remaining -= added
	while remaining > 0:
		var stack_quantity: int = min(max_stack, remaining)
		target.append({
			"definition_id": definition_id,
			"quantity": stack_quantity,
		})
		remaining -= stack_quantity


func _unequip_hero_slot_internal(hero_index: int, slot_key: String) -> int:
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
	_clear_equipment_instance_link(equipment_uid)
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))
	return equipment_uid


func _detach_equipment_instance(equipment_uid: int) -> void:
	if equipment_uid <= 0:
		return
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
	_clear_equipment_instance_link(equipment_uid)
	_session().rebuild_equipment_compatibility(heroes, inventory_equipment, DataLoader.HERO_EQUIPMENT_KEYS, Callable(DataLoader, "get_equipment_definition"), Callable(DataLoader, "create_empty_hero_equipment"))


func _clear_equipment_instance_link(equipment_uid: int) -> void:
	if equipment_uid <= 0:
		return
	var equipment_index := _find_inventory_equipment_index(equipment_uid)
	if equipment_index == -1:
		return
	var equipment_instance: Dictionary = inventory_equipment[equipment_index]
	equipment_instance["equipped_hero_uid"] = -1
	equipment_instance["equipped_slot"] = ""
	inventory_equipment[equipment_index] = equipment_instance


func _get_hero_equipment_bonuses(hero_data: Dictionary) -> Dictionary:
	var bonuses := {
		"stats": {},
		"work_stats": {},
	}
	var hero_equipment := _as_dictionary(hero_data.get("equipment", {}))
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		var equipment_uid := int(String(hero_equipment.get(slot_key, "")).strip_edges())
		if equipment_uid <= 0:
			continue
		var equipment_instance := _get_inventory_equipment_instance(equipment_uid)
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


func _get_inventory_equipment_instance(equipment_uid: int) -> Dictionary:
	for entry in inventory_equipment:
		var equipment_instance: Dictionary = entry
		if int(equipment_instance.get("uid", -1)) == equipment_uid:
			return equipment_instance.duplicate(true)
	return {}


func _get_max_hero_uid() -> int:
	var max_uid := 0
	for hero_data in heroes:
		max_uid = max(max_uid, int((hero_data as Dictionary).get("uid", 0)))
	return max_uid


func _get_max_equipment_uid() -> int:
	var max_uid := 0
	for equipment_data in inventory_equipment:
		max_uid = max(max_uid, int((equipment_data as Dictionary).get("uid", 0)))
	return max_uid


func _get_max_recruit_offer_id() -> int:
	var max_offer_id := 0
	for offer_data in recruit_market_offers:
		max_offer_id = max(max_offer_id, int((offer_data as Dictionary).get("offer_id", 0)))
	return max_offer_id


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


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


func _resolve_save_slot_name(slot_index: int, metadata: Dictionary) -> String:
	var custom_name := String(metadata.get("name", "")).strip_edges()
	if not custom_name.is_empty():
		return custom_name
	return DataLoader.get_ui_text("save.slot_default_name", {"slot": slot_index}, "Slot %d" % slot_index)


func _resolve_session_dependency() -> void:
	if _game_session != null and is_instance_valid(_game_session):
		return
	var root := get_tree().root
	if root == null:
		push_error("GameManager could not resolve GameSession: scene tree root unavailable.")
		return
	_game_session = root.get_node_or_null("GameSession")
	if _game_session == null:
		push_error("GameManager could not resolve GameSession at startup.")


func _session() -> Node:
	if _game_session == null or not is_instance_valid(_game_session):
		_resolve_session_dependency()
	return _game_session


func _request_persistence_update() -> void:
	_session().mark_save_dirty()


func _on_tick_timeout() -> void:
	process_tick()
