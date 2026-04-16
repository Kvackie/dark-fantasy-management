extends Node


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")

const RESOURCE_WORK_STAT_MAP := {
	"food": "farming",
	"wood": "lumbering",
	"stone": "mining",
	"crystals": "mining",
}
const WORK_STAT_PRODUCTION_BONUS_PER_POINT := 0.03

var _game: Node = null
var _timer: Timer = null


func configure(game_manager: Node) -> void:
	_game = game_manager


func start_tick_timer() -> void:
	if _timer != null and is_instance_valid(_timer):
		return
	_timer = Timer.new()
	_timer.wait_time = SettlementGameData.TICK_SECONDS
	_timer.autostart = true
	_timer.one_shot = false
	_timer.timeout.connect(_on_tick_timeout)
	add_child(_timer)


func stop_tick_timer() -> void:
	if _timer == null or not is_instance_valid(_timer):
		return
	_timer.stop()


func get_slot_production_preview(slot_index: int) -> Dictionary:
	if _game == null:
		return {}
	return _calculate_slot_production(_as_dictionary(_game.get_slot(slot_index)))


func get_owned_settlement_production_preview() -> Dictionary:
	if _game == null:
		return {}
	var production_delta: Dictionary = {}
	for settlement_id in _as_array(_game.get_owned_settlement_ids()):
		for slot in _as_array(_game.get_settlement_slots_snapshot(String(settlement_id))):
			var slot_data: Dictionary = _as_dictionary(slot)
			var slot_delta: Dictionary = _calculate_slot_production(slot_data)
			for resource_id in slot_delta.keys():
				production_delta[resource_id] = int(production_delta.get(resource_id, 0)) + int(slot_delta[resource_id])
	return production_delta


func _on_tick_timeout() -> void:
	if _game == null:
		return
	_game.process_tick()


func _calculate_slot_production(slot: Dictionary) -> Dictionary:
	if _game == null:
		return {}
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
	if _game == null:
		return 0
	var work_stat_key := String(RESOURCE_WORK_STAT_MAP.get(resource_id, "")).strip_edges()
	if work_stat_key.is_empty():
		return 0
	var total_relevant_work := 0
	for hero_uid in _normalize_int_array(slot.get("assigned_hero_ids", [])):
		var effective_work_stats := _as_dictionary(_game.get_hero_effective_work_stats(int(hero_uid)))
		total_relevant_work += int(effective_work_stats.get(work_stat_key, 0))
	return total_relevant_work


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

