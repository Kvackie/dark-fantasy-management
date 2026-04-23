extends RefCounted


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")


static func make_hero_info_section(title: String, rows: Array, accent_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color("141113")
	stylebox.border_color = accent_color.darkened(0.25)
	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(10)
	stylebox.content_margin_left = 12
	stylebox.content_margin_top = 12
	stylebox.content_margin_right = 12
	stylebox.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", stylebox)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var header := UIScreenHelpers.make_label(title, 18)
	header.add_theme_color_override("font_color", accent_color)
	body.add_child(header)
	for row_data in rows:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var label := UIScreenHelpers.make_label(String((row_data as Dictionary).get("label", "")), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("bfb1a2"))
		row.add_child(label)
		var value := UIScreenHelpers.make_label(String((row_data as Dictionary).get("value", "")), 15)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override("font_color", (row_data as Dictionary).get("color", Color("fff6ea")))
		row.add_child(value)
	return panel


static func make_bonus_section(title: String, values: Dictionary, accent_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color("120f10")
	stylebox.border_color = accent_color.darkened(0.2)
	stylebox.set_border_width_all(1)
	stylebox.set_corner_radius_all(8)
	stylebox.content_margin_left = 10
	stylebox.content_margin_top = 8
	stylebox.content_margin_right = 10
	stylebox.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", stylebox)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var header := UIScreenHelpers.make_label(title, 15)
	header.add_theme_color_override("font_color", accent_color)
	body.add_child(header)
	if values.is_empty():
		var empty := UIScreenHelpers.make_label("none", 14)
		empty.add_theme_color_override("font_color", Color("b9afa4"))
		body.add_child(empty)
		return panel
	for key in values.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(row)
		var stat_label := UIScreenHelpers.make_label(String(key).capitalize().replace("_", " "), 14)
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.add_theme_color_override("font_color", Color("c8bcae"))
		row.add_child(stat_label)
		var value_label := UIScreenHelpers.make_label("%+d" % int(values[key]), 14)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", accent_color.lightened(0.15))
		row.add_child(value_label)
	return panel


static func make_tooltip_bonus_section(title: String, values: Dictionary, accent_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color("120f10")
	stylebox.border_color = accent_color.darkened(0.2)
	stylebox.set_border_width_all(1)
	stylebox.set_corner_radius_all(8)
	stylebox.content_margin_left = 10
	stylebox.content_margin_top = 8
	stylebox.content_margin_right = 10
	stylebox.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", stylebox)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var header := make_tooltip_label(title, 15, accent_color, true)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)
	if values.is_empty():
		var empty := make_tooltip_label("none", 14, Color("b9afa4"), false)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(empty)
		return panel
	for key in values.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		var stat_label := make_tooltip_label(String(key).capitalize().replace("_", " "), 14, Color("c8bcae"), false)
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.clip_text = true
		row.add_child(stat_label)
		var value_label := make_tooltip_label("%+d" % int(values[key]), 14, accent_color.lightened(0.15), true)
		value_label.custom_minimum_size = Vector2(34, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
	panel.update_minimum_size()
	return panel


static func make_tooltip_label(text: String, font_size: int, color: Color, accent: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_FILL
	UIScreenHelpers.style_label(label, font_size, accent)
	label.add_theme_color_override("font_color", color)
	return label
