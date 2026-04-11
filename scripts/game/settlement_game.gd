extends Node

const RESOURCE_ORDER := ["wood", "food", "stone", "gold", "heroes", "gems", "crystals"]
const TRACKED_RESOURCES := ["wood", "food", "stone", "gold", "gems", "crystals"]
const GRID_SIZE := 9
const GRID_COLUMNS := 3
const SAVE_SLOT_COUNT := 3
const TICK_SECONDS := 2.0
const AUTOSAVE_INTERVAL := 12.0
const MAX_BUILDING_LEVEL := 5
const STARTING_RESOURCES := {
	"wood": 120,
	"food": 90,
	"stone": 70,
	"gold": 150,
	"gems": 8,
	"crystals": 4,
}


static func duplicate_resources(values: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for resource_id in TRACKED_RESOURCES:
		copy[resource_id] = int(values.get(resource_id, 0))
	return copy


static func empty_slot(index: int) -> Dictionary:
	return {
		"index": index,
		"building_id": "",
		"level": 0,
		"assigned_hero_ids": [],
	}


static func create_empty_grid() -> Array:
	var slots: Array = []
	for index in GRID_SIZE:
		slots.append(empty_slot(index))
	return slots


static func clamp_resource(value: int) -> int:
	return max(value, 0)


static func resource_list_to_dictionary(entries: Array) -> Dictionary:
	var mapped: Dictionary = {}
	for entry in entries:
		if entry is Dictionary and entry.has("resource"):
			mapped[String(entry.resource)] = int(entry.get("amount", 0))
	return mapped


static func scaled_cost(entries: Array, level: int, growth: float) -> Dictionary:
	var scaled: Dictionary = {}
	for entry in entries:
		if entry is Dictionary and entry.has("resource"):
			var base_amount := float(entry.get("amount", 0))
			var amount := int(round(base_amount * pow(growth, max(level - 1, 0))))
			scaled[String(entry.resource)] = amount
	return scaled


static func merge_resource_delta(target: Dictionary, delta: Dictionary) -> Dictionary:
	var merged := duplicate_resources(target)
	for resource_id in delta.keys():
		merged[resource_id] = int(merged.get(resource_id, 0)) + int(delta[resource_id])
	return merged


static func scale_resource_dictionary(values: Dictionary, multiplier: float) -> Dictionary:
	var scaled: Dictionary = {}
	for resource_id in values.keys():
		scaled[String(resource_id)] = int(round(float(values[resource_id]) * multiplier))
	return scaled
