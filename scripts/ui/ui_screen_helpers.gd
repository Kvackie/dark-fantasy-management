extends RefCounted


const FONT_SIZE_BONUS := 2
const BUTTON_FONT_SIZE_BONUS := 2


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")


static func txt(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	return DataLoader.get_ui_text(key, replacements, fallback)


static func clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


static func as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_panel(panel, Color("181416"), Color("675042"), 8)
	return panel


static func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var effective_font_size := (font_size if font_size >= 20 else font_size + 1) + FONT_SIZE_BONUS
	style_label(label, effective_font_size, font_size >= 20)
	return label


static func make_button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button(button)
	button.pressed.connect(callback)
	return button


static func make_small_nav_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(116, 30)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_font_size_override("font_size", 12 + FONT_SIZE_BONUS + BUTTON_FONT_SIZE_BONUS)
	button.add_theme_color_override("font_color", Color("e9dfd2"))
	button.add_theme_color_override("font_hover_color", Color("f7efe3"))
	button.add_theme_color_override("font_pressed_color", Color("fff1dc"))
	button.add_theme_color_override("font_disabled_color", Color("96897f"))
	button.add_theme_stylebox_override("normal", _button_style(Color("130f10"), Color("5e4a3d"), 6))
	button.add_theme_stylebox_override("hover", _button_style(Color("1b1516"), Color("876850"), 6))
	button.add_theme_stylebox_override("pressed", _button_style(Color("241c1b"), Color("a17d5c"), 6))
	button.add_theme_stylebox_override("disabled", _button_style(Color("100d0e"), Color("433734"), 6))
	button.pressed.connect(callback)
	return button


static func make_small_action_button(text: String, callback: Callable) -> Button:
	var button := make_small_nav_button(text, callback)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


static func make_danger_button(text: String, callback: Callable) -> Button:
	var button := make_small_nav_button(text, callback)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_color_override("font_color", Color("f2d8d4"))
	button.add_theme_color_override("font_hover_color", Color("fff0ed"))
	button.add_theme_color_override("font_pressed_color", Color("fff7f5"))
	button.add_theme_stylebox_override("normal", _button_style(Color("2a1415"), Color("8a4c49"), 6))
	button.add_theme_stylebox_override("hover", _button_style(Color("34191a"), Color("b76558"), 6))
	button.add_theme_stylebox_override("pressed", _button_style(Color("421d1d"), Color("d17a6d"), 6))
	button.add_theme_stylebox_override("disabled", _button_style(Color("1a1011"), Color("4a2f31"), 6))
	return button


static func make_overview_settlement_tile(settlement_entry: Dictionary, open_callback: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(176, 214)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var settlement_id := String(settlement_entry.get("settlement_id", settlement_entry.get("id", "")))
	var accent := Color("d0a170") if bool(settlement_entry.get("is_active", false)) else Color("7a5e4b")
	_style_panel(panel, Color("141113"), accent, 10)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	var name_label := make_label(String(settlement_entry.get("name", "Unknown Settlement")), 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color("efe7db"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(name_label)
	var icon_holder := CenterContainer.new()
	icon_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon_holder)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture_from_path(String(settlement_entry.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
	if icon.texture == null:
		icon.texture = _load_texture_from_path(DataLoader.DEFAULT_CATALOG_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(icon)
	var plots_label := make_label(txt("overview.plots", {"built": int(settlement_entry.get("built_plot_count", 0)), "total": int(settlement_entry.get("plot_count", 0))}), 13)
	plots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plots_label.add_theme_color_override("font_color", Color("d9cbb7"))
	plots_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(plots_label)
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.offset_left = 0.0
	button.offset_top = 0.0
	button.offset_right = 0.0
	button.offset_bottom = 0.0
	button.text = ""
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10))
	button.add_theme_stylebox_override("hover", _button_style(Color(1, 1, 1, 0.03), Color("d0a170"), 10))
	button.add_theme_stylebox_override("pressed", _button_style(Color(1, 1, 1, 0.05), Color("d0a170"), 10))
	button.pressed.connect(open_callback)
	panel.add_child(button)
	return panel


static func build_inventory_entries(items: Array, equipment: Array) -> Array:
	var entries: Array = []
	for item_stack in items:
		if item_stack is not Dictionary:
			continue
		var definition: Dictionary = DataLoader.get_item_definition(String((item_stack as Dictionary).get("definition_id", "")))
		if definition.is_empty():
			continue
		entries.append({
			"kind": "item",
			"definition": definition,
			"quantity": int((item_stack as Dictionary).get("quantity", 0)),
		})
	for equipment_entry in equipment:
		if equipment_entry is not Dictionary:
			continue
		var equipment_data := equipment_entry as Dictionary
		var definition: Dictionary = DataLoader.get_equipment_definition(String(equipment_data.get("definition_id", "")))
		if definition.is_empty():
			continue
		entries.append({
			"kind": "equipment",
			"definition": definition,
			"uid": int(equipment_data.get("uid", -1)),
			"equipped_hero_uid": int(equipment_data.get("equipped_hero_uid", -1)),
		})
	return entries


static func make_inventory_slot(entry: Dictionary) -> PanelContainer:
	var kind := String(entry.get("kind", "item"))
	var definition := as_dictionary(entry.get("definition", {}))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(148, 148)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent_color := Color("7a5e4b") if kind == "item" else Color("8d8478")
	style_panel(panel, Color("141113"), accent_color, 10)
	var footer_text := "x%d" % int(entry.get("quantity", 0)) if kind == "item" else _inventory_equipment_footer(entry, definition)
	build_inventory_tile_content(panel, definition, footer_text, Color("d9cbb7") if kind == "item" else Color("b8c3d9"), Color("efe7db"), 72, 15, 14)
	return panel


static func equipment_slot_label(slot_key: String) -> String:
	return _equipment_slot_label(slot_key)


static func build_inventory_tile_content(parent: Control, definition: Dictionary, footer_text: String, footer_color: Color, title_color: Color, icon_size: int, title_font_size: int, footer_font_size: int, title_override: String = "") -> void:
	_build_inventory_tile_content(parent, definition, footer_text, footer_color, title_color, icon_size, title_font_size, footer_font_size, title_override)


static func style_panel(panel: Control, bg_color: Color, border_color: Color, corner_radius: int) -> void:
	_style_panel(panel, bg_color, border_color, corner_radius)


static func style_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 17 + FONT_SIZE_BONUS + BUTTON_FONT_SIZE_BONUS)
	button.add_theme_color_override("font_color", Color("faf5ef"))
	button.add_theme_color_override("font_hover_color", Color("fffaf4"))
	button.add_theme_color_override("font_pressed_color", Color("fff0dc"))
	button.add_theme_color_override("font_disabled_color", Color("9d9287"))
	button.add_theme_stylebox_override("normal", _button_style(Color("171315"), Color("6f5648"), 7))
	button.add_theme_stylebox_override("hover", _button_style(Color("261d1d"), Color("a88563"), 7))
	button.add_theme_stylebox_override("pressed", _button_style(Color("362925"), Color("d0a170"), 7))
	button.add_theme_stylebox_override("disabled", _button_style(Color("121012"), Color("4c3e3a"), 7))


static func style_label(label: Label, font_size: int, accent: bool) -> void:
	_style_label(label, font_size, accent)


static func load_texture_from_path(path: String) -> Texture2D:
	return _load_texture_from_path(path)


static func load_hero_texture(hero_data: Dictionary) -> Texture2D:
	var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
	var portrait_path := String(hero_definition.get("portrait_path", ""))
	var icon_path := String(hero_definition.get("icon_path", ""))
	var resolved_path := portrait_path
	if resolved_path.is_empty() or resolved_path == DataLoader.DEFAULT_HERO_IMAGE:
		if not icon_path.is_empty() and icon_path != DataLoader.DEFAULT_HERO_IMAGE:
			resolved_path = icon_path
	if resolved_path.is_empty():
		resolved_path = DataLoader.DEFAULT_HERO_IMAGE
	var texture := _load_texture_from_path(resolved_path)
	if texture != null:
		return texture
	return _load_texture_from_path(DataLoader.DEFAULT_HERO_IMAGE)


static func _inventory_equipment_footer(entry: Dictionary, definition: Dictionary) -> String:
	if int(entry.get("equipped_hero_uid", -1)) > 0:
		return "Equipped"
	return _equipment_slot_label(String(definition.get("slot", "")))


static func _equipment_slot_label(slot_key: String) -> String:
	match slot_key:
		"head":
			return "Head"
		"chest":
			return "Chest"
		"gloves":
			return "Gloves"
		"boots":
			return "Boots"
		"amulet":
			return "Amulet"
		"ring_1":
			return "Ring 1"
		_:
			return slot_key.capitalize()


static func _settlement_plot_counts_from_built(built_slots: int) -> Dictionary:
	return {
		"built": built_slots,
		"available": max(SettlementGameData.GRID_SIZE - built_slots, 0),
	}


static func _build_inventory_tile_content(parent: Control, definition: Dictionary, footer_text: String, footer_color: Color, title_color: Color, icon_size: int, title_font_size: int, footer_font_size: int, title_override: String = "") -> void:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(body)
	var icon_holder := CenterContainer.new()
	icon_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon_holder)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture_from_path(String(definition.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
	if icon.texture == null:
		icon.texture = _load_texture_from_path(DataLoader.DEFAULT_CATALOG_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(icon)
	var title_text := title_override if not title_override.is_empty() else String(definition.get("name", "Unknown"))
	var title := make_label(title_text, title_font_size)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", title_color)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	var footer := make_label(footer_text, footer_font_size)
	footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", footer_color)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(footer)


static func _load_texture_from_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return load(path)
		return null
	if path.begins_with("user://") or path.is_absolute_path():
		if not FileAccess.file_exists(path):
			return null
		var image := Image.new()
		if image.load(path) != OK:
			return null
		return ImageTexture.create_from_image(image)
	return null


static func _style_panel(panel: Control, bg_color: Color, border_color: Color, corner_radius: int) -> void:
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = bg_color
	stylebox.border_color = border_color
	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(corner_radius)
	stylebox.content_margin_left = 10
	stylebox.content_margin_top = 10
	stylebox.content_margin_right = 10
	stylebox.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", stylebox)


static func _style_label(label: Label, font_size: int, accent: bool) -> void:
	label.add_theme_font_size_override("font_size", font_size + FONT_SIZE_BONUS)
	label.add_theme_color_override("font_color", Color("fff9f1") if accent else Color("efe7db"))


static func _button_style(bg_color: Color, border_color: Color, corner_radius: int) -> StyleBoxFlat:
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = bg_color
	stylebox.border_color = border_color
	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(corner_radius)
	stylebox.content_margin_left = 10
	stylebox.content_margin_top = 8
	stylebox.content_margin_right = 10
	stylebox.content_margin_bottom = 8
	return stylebox
