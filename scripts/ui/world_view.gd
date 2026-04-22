extends Control

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const MIN_MAP_ZOOM := 0.1
const MAX_MAP_ZOOM := 1.5
const MAP_ZOOM_STEP := 0.1

signal zone_selected(zone_key: String)
signal settlement_selected(settlement_id)

@onready var _map_viewport: Control = get_node("MapFrame/MapViewport")
@onready var _zones_layer: Control = get_node("MapFrame/MapViewport/ZonesLayer")
@onready var _hint_label: Label = get_node("MapHint")

var _world_snapshot: Dictionary = {}
var _zone_controls: Dictionary = {}
var _map_offset: Vector2 = Vector2.ZERO
var _map_zoom: float = 1.0
var _dragging: bool = false
var _selected_zone_key: String = ""
var _countdown_refresh_elapsed: float = 0.0


func _ready() -> void:
	_map_viewport.gui_input.connect(_on_map_gui_input)
	_hint_label.text = DataLoader.get_ui_text("world.pan_hint", {}, "Drag empty space to pan the world map. Use the mouse wheel to zoom.")
	_rebuild_zone_map()
	center_on_origin()


func _process(delta: float) -> void:
	if not _snapshot_has_clearing_zone():
		return
	_countdown_refresh_elapsed += delta
	if _countdown_refresh_elapsed < 0.25:
		return
	_countdown_refresh_elapsed = 0.0
	_refresh_clearing_zone_labels()


func set_world_snapshot(world_snapshot: Dictionary) -> void:
	_world_snapshot = world_snapshot.duplicate(true)
	if is_node_ready():
		_rebuild_zone_map()


func _center_map_on_origin() -> void:
	var world_config := _as_dictionary(_world_snapshot.get("config", {}))
	var zone_size := int(world_config.get("zone_size", 104))
	_map_offset = (_map_viewport.size * 0.5) - Vector2(zone_size * 0.5, zone_size * 0.5)
	_update_map_transform()


func center_on_origin() -> void:
	call_deferred("_center_map_on_origin_after_layout")


func _center_map_on_origin_after_layout() -> void:
	await get_tree().process_frame
	_center_map_on_origin()


func _rebuild_zone_map() -> void:
	for child in _zones_layer.get_children():
		child.queue_free()
	_zone_controls.clear()
	var zones := _as_dictionary(_world_snapshot.get("zones", {}))
	var ordered_keys := zones.keys()
	ordered_keys.sort_custom(func(a, b):
		var zone_a := _as_dictionary(zones.get(a, {}))
		var zone_b := _as_dictionary(zones.get(b, {}))
		if int(zone_a.get("y", 0)) == int(zone_b.get("y", 0)):
			return int(zone_a.get("x", 0)) < int(zone_b.get("x", 0))
		return int(zone_a.get("y", 0)) < int(zone_b.get("y", 0))
	)
	for zone_key in ordered_keys:
		var zone := _as_dictionary(zones.get(zone_key, {}))
		var button := _make_zone_button(zone)
		_zone_controls[zone_key] = button
		_zones_layer.add_child(button)


func _make_zone_button(zone: Dictionary) -> Button:
	var world_config := _as_dictionary(_world_snapshot.get("config", {}))
	var zone_size := int(world_config.get("zone_size", 104))
	var zone_gap := int(world_config.get("zone_gap", 10))
	var state := String(zone.get("state", "fog"))
	var button := Button.new()
	button.custom_minimum_size = Vector2(zone_size, zone_size)
	button.size = Vector2(zone_size, zone_size)
	button.position = Vector2(int(zone.get("x", 0)) * (zone_size + zone_gap), int(zone.get("y", 0)) * (zone_size + zone_gap))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.text = _zone_button_text(zone)
	button.disabled = state == "fog"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not button.disabled else Control.CURSOR_ARROW
	_style_zone_button(button, zone, state, String(zone.get("key", "")) == _selected_zone_key)
	if not button.disabled:
		button.pressed.connect(Callable(self, "_on_zone_pressed").bind(String(zone.get("key", ""))))
	return button


func _zone_button_text(zone: Dictionary) -> String:
	match String(zone.get("state", "fog")):
		"claimed":
			return "%s\n%s" % [String(zone.get("settlement_name", zone.get("generated_name", "Claimed Zone"))), _display_biome_name(String(zone.get("biome", "neutral")))]
		"cleared":
			return "%s\n%s" % [String(zone.get("generated_name", "Cleared Zone")), _display_biome_name(String(zone.get("biome", "neutral")))]
		"clearing":
			return "Clearing\n%s" % SettlementGameData.format_duration_label(_get_zone_display_remaining_seconds(zone))
		"discovered":
			return "Unknown\n%s" % _display_biome_name(String(zone.get("biome", "neutral")))
		_:
			return ""


func _style_zone_button(button: Button, zone: Dictionary, state: String, selected: bool) -> void:
	var world_config := _as_dictionary(_world_snapshot.get("config", {}))
	var color_config := _as_dictionary(world_config.get("zone_colors", {}))
	var fill_color := _zone_fill_color(String(zone.get("biome", "neutral")), state, String(color_config.get(state, "#66686f")))
	var border_color := Color("d0a170") if selected else fill_color.lightened(0.18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill_color
	normal.border_color = border_color
	normal.set_border_width_all(3 if selected else 2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = fill_color.lightened(0.08)
	hover.border_color = border_color.lightened(0.08)
	var pressed := hover.duplicate()
	pressed.bg_color = fill_color.darkened(0.08)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("f4f1e8"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("f4f1e8"))
	button.add_theme_color_override("font_disabled_color", Color("d7d2cb"))


func _snapshot_has_clearing_zone() -> bool:
	for zone_data in _as_dictionary(_world_snapshot.get("zones", {})).values():
		if String(_as_dictionary(zone_data).get("state", "")) == "clearing":
			return true
	return false


func _refresh_clearing_zone_labels() -> void:
	for zone_key in _zone_controls.keys():
		var zone := GameManager.get_world_zone(String(zone_key))
		if String(zone.get("state", "")) != "clearing":
			continue
		var button := _zone_controls.get(zone_key, null) as Button
		if button == null or not is_instance_valid(button):
			continue
		var snapshot_zones := _as_dictionary(_world_snapshot.get("zones", {}))
		snapshot_zones[String(zone_key)] = zone.duplicate(true)
		_world_snapshot["zones"] = snapshot_zones
		button.text = _zone_button_text(zone)


func _get_zone_display_remaining_seconds(zone: Dictionary) -> float:
	var clear_end_unix := float(zone.get("clear_end_unix", 0.0))
	if clear_end_unix > 0.0:
		return max(0.0, clear_end_unix - Time.get_unix_time_from_system())
	return float(int(zone.get("ticks_remaining", 0))) * SettlementGameData.TICK_SECONDS


func _zone_fill_color(biome: String, state: String, fallback_color: String) -> Color:
	var biome_color := Color(fallback_color)
	match String(biome).to_lower():
		"starting_zone":
			biome_color = Color("#4f3426")
		"forest":
			biome_color = Color("#4f8a4f")
		"mountain":
			biome_color = Color("#4b4f57")
		"plains":
			biome_color = Color("#c8b64f")
		"mixed":
			biome_color = Color("#7fb7d9")
		"crystal_cavern":
			biome_color = Color("#8d7be0")
		_:
			biome_color = Color("#b28a6a")
	if state == "fog":
		return Color("#efefec")
	if state == "discovered":
		return Color("#a84a46")
	if state == "clearing":
		return Color("#c98142")
	if state == "claimed":
		return biome_color.lightened(0.08) if String(biome).to_lower() != "starting_zone" else biome_color
	if state == "cleared":
		return biome_color
	return biome_color


func _display_biome_name(biome: String) -> String:
	match String(biome).to_lower():
		"starting_zone":
			return ""
		"forest":
			return "<FOREST>"
		"mountain":
			return "<MOUNTAIN>"
		"plains":
			return "<PLAINS>"
		"mixed":
			return "<MIXED>"
		"crystal_cavern":
			return "<CRYSTAL CAVERN>"
		_:
			return "<NEUTRAL>"


func _on_zone_pressed(zone_key: String) -> void:
	var zones := _as_dictionary(_world_snapshot.get("zones", {}))
	var zone := _as_dictionary(zones.get(zone_key, {}))
	if zone.is_empty():
		return
	if String(zone.get("state", "")) == "claimed":
		emit_signal("settlement_selected", String(zone.get("settlement_id", "")))
		return
	_selected_zone_key = zone_key
	_rebuild_zone_map()
	emit_signal("zone_selected", zone_key)


func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button_event.pressed
			return
		if mouse_button_event.pressed:
			if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_zoom(MAP_ZOOM_STEP, mouse_button_event.position)
				return
			if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_zoom(-MAP_ZOOM_STEP, mouse_button_event.position)
				return
	if event is InputEventMouseMotion and _dragging:
		_map_offset += (event as InputEventMouseMotion).relative
		_update_map_transform()


func _adjust_zoom(delta: float, pivot: Vector2) -> void:
	var next_zoom := clampf(_map_zoom + delta, MIN_MAP_ZOOM, MAX_MAP_ZOOM)
	if is_equal_approx(next_zoom, _map_zoom):
		return
	var map_point := (pivot - _map_offset) / _map_zoom
	_map_zoom = next_zoom
	_map_offset = pivot - (map_point * _map_zoom)
	_update_map_transform()


func _update_map_transform() -> void:
	_zones_layer.position = _map_offset
	_zones_layer.scale = Vector2.ONE * _map_zoom


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


func clear_zone_selection() -> void:
	if _selected_zone_key.is_empty():
		return
	_selected_zone_key = ""
	_rebuild_zone_map()
