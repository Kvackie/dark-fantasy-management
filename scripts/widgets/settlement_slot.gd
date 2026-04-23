extends Button

signal slot_selected(slot_index)

var slot_index: int = -1

@onready var _icon_rect: TextureRect = get_node("Margin/VBox/Icon")
@onready var _name_label: Label = get_node("Margin/VBox/Name")
@onready var _level_label: Label = get_node("Margin/VBox/Level")
@onready var _workers_label: Label = get_node("Margin/VBox/Workers")
@onready var _margin: MarginContainer = get_node("Margin")
@onready var _box: VBoxContainer = get_node("Margin/VBox")


func _ready() -> void:
	custom_minimum_size = Vector2(180, 224)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_rect.custom_minimum_size = Vector2(108, 82)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clip_contents = true
	_margin.add_theme_constant_override("margin_left", 10)
	_margin.add_theme_constant_override("margin_top", 10)
	_margin.add_theme_constant_override("margin_right", 10)
	_margin.add_theme_constant_override("margin_bottom", 10)
	_box.add_theme_constant_override("separation", 6)
	_name_label.add_theme_font_size_override("font_size", 21)
	_level_label.add_theme_font_size_override("font_size", 18)
	_workers_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color("f6f1ea"))
	_level_label.add_theme_color_override("font_color", Color("ece3d8"))
	_workers_label.add_theme_color_override("font_color", Color("d8cdc0"))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_workers_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_icon_rect.modulate = Color(1.12, 1.08, 1.03)
	_icon_rect.self_modulate = Color(1.12, 1.08, 1.03)
	_expand_icon_area()
	_apply_card_style(false)
	pressed.connect(_on_pressed)


func set_view(slot_data: Dictionary, building_definition: Dictionary, is_selected: bool) -> void:
	var building_id: String = String(slot_data.get("building_id", ""))
	if building_id.is_empty() or building_definition.is_empty():
		_icon_rect.visible = false
		_name_label.text = "Empty Plot"
		_level_label.text = "Build structure"
		_workers_label.text = "Unworked"
		_icon_rect.texture = null
	else:
		_icon_rect.visible = true
		_name_label.text = String(building_definition.get("name", building_id.capitalize()))
		_level_label.text = "Level %d" % int(slot_data.get("level", 1))
		_workers_label.text = "%d/%d workers" % [
			_as_array(slot_data.get("assigned_hero_ids", [])).size(),
			int(building_definition.get("worker_slots", 0)),
		]
		var icon_path: String = String(building_definition.get("icon_path", ""))
		if ResourceLoader.exists(icon_path):
			_icon_rect.texture = load(icon_path)
		else:
			_icon_rect.texture = null
	_apply_card_style(is_selected)


func _on_pressed() -> void:
	emit_signal("slot_selected", slot_index)


func _expand_icon_area() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_box.move_child(_icon_rect, 0)
	if _icon_rect.get_index() == 0:
		_box.add_child(spacer)
		_box.move_child(spacer, 1)


func _apply_card_style(is_selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("191315") if not is_selected else Color("25191a")
	normal.border_color = Color("47362f") if not is_selected else Color("b88a58")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(14)
	normal.shadow_color = Color(0, 0, 0, 0.18)
	normal.shadow_size = 6
	normal.content_margin_left = 0
	normal.content_margin_top = 0
	normal.content_margin_right = 0
	normal.content_margin_bottom = 0
	var hover := normal.duplicate()
	hover.bg_color = Color("22191a") if not is_selected else Color("2d1d1d")
	hover.border_color = Color("8f6e54") if not is_selected else Color("d0a170")
	var pressed_style := hover.duplicate()
	pressed_style.bg_color = Color("2d211f")
	pressed_style.border_color = Color("e1b47c")
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", hover)


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
