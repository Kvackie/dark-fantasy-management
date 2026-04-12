extends Control

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")

signal zone_selected(zone_key: String)
signal settlement_selected(settlement_id)

@onready var _map_viewport: Control = get_node("MapFrame/MapViewport")
@onready var _zones_layer: Control = get_node("MapFrame/MapViewport/ZonesLayer")
@onready var _hint_label: Label = get_node("MapHint")

var _world_snapshot: Dictionary = {}
var _zone_controls: Dictionary = {}
var _map_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _selected_zone_key: String = ""


func _ready() -> void:
	_map_viewport.gui_input.connect(_on_map_gui_input)
	_hint_label.text = DataLoader.get_ui_text("world.pan_hint", {}, "Drag empty space to pan the world map.")
	_rebuild_zone_map()
	call_deferred("_center_map_on_origin")


func set_world_snapshot(world_snapshot: Dictionary) -> void:
	_world_snapshot = world_snapshot.duplicate(true)
	if is_node_ready():
		_rebuild_zone_map()


func _center_map_on_origin() -> void:
	var world_config := _as_dictionary(_world_snapshot.get("config", {}))
	var zone_size := int(world_config.get("zone_size", 104))
	_map_offset = (_map_viewport.size * 0.5) - Vector2(zone_size * 0.5, zone_size * 0.5)
	_zones_layer.position = _map_offset


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
	_style_zone_button(button, state, String(zone.get("key", "")) == _selected_zone_key)
	if not button.disabled:
		button.pressed.connect(Callable(self, "_on_zone_pressed").bind(String(zone.get("key", ""))))
	return button


func _zone_button_text(zone: Dictionary) -> String:
	match String(zone.get("state", "fog")):
		"claimed":
			return String(zone.get("settlement_name", zone.get("generated_name", "Claimed Zone")))
		"cleared":
			return String(zone.get("generated_name", "Cleared Zone"))
		"clearing":
			return "Clearing\n%.1fs\n%dH" % [float(int(zone.get("ticks_remaining", 0))) * SettlementGameData.TICK_SECONDS, _as_array(zone.get("assigned_hero_uids", [])).size()]
		"discovered":
			return "Unknown\nZone"
		_:
			return ""


func _style_zone_button(button: Button, state: String, selected: bool) -> void:
	var world_config := _as_dictionary(_world_snapshot.get("config", {}))
	var color_config := _as_dictionary(world_config.get("zone_colors", {}))
	var fill_color := Color(String(color_config.get(state, "#66686f")))
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
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		return
	if event is InputEventMouseMotion and _dragging:
		_map_offset += (event as InputEventMouseMotion).relative
		_zones_layer.position = _map_offset


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
