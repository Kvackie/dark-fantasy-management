extends RefCounted


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")


static func apply_dialog_shell_style(popup_panel: PanelContainer, popup_content_frame: PanelContainer, hero_hover_frame: PanelContainer, hero_hover_panel: PanelContainer, popup_title: Label, popup_subtitle: Label) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("1a1517")
	panel_style.border_color = Color("b08961")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 18
	popup_panel.add_theme_stylebox_override("panel", panel_style)
	var content_style := StyleBoxFlat.new()
	content_style.bg_color = Color("120f10")
	content_style.border_color = Color("5a4639")
	content_style.set_border_width_all(1)
	content_style.set_corner_radius_all(10)
	popup_content_frame.add_theme_stylebox_override("panel", content_style)
	hero_hover_frame.add_theme_stylebox_override("panel", content_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("171214")
	hover_style.border_color = Color("8f6e54")
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(10)
	hover_style.shadow_color = Color(0, 0, 0, 0.35)
	hover_style.shadow_size = 16
	hero_hover_panel.add_theme_stylebox_override("panel", hover_style)
	popup_title.add_theme_font_size_override("font_size", 24)
	popup_title.add_theme_color_override("font_color", Color("f6ecdf"))
	popup_subtitle.add_theme_font_size_override("font_size", 15)
	popup_subtitle.add_theme_color_override("font_color", Color("cdb9a4"))


static func make_popup_label(text: String, font_size: int, accent: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f3eadc") if accent else Color("d8cec1"))
	return label


static func make_popup_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


static func format_resource_dict(values: Dictionary) -> String:
	if values.is_empty():
		return DataLoader.get_ui_text("common.none", {}, "none")
	var parts: Array[String] = []
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		if values.has(resource_id) and int(values[resource_id]) != 0:
			parts.append("%s %d" % [DataLoader.get_ui_text("resource.%s" % resource_id, {}, String(resource_id).capitalize()), int(values[resource_id])])
	return ", ".join(parts)


static func format_zone_requirements(requirements: Dictionary) -> String:
	var attack_requirement := int(requirements.get("attack", 0))
	var defense_requirement := int(requirements.get("defense", 0))
	if attack_requirement <= 0 and defense_requirement <= 0:
		return "ATK REQ 0  |  DEF REQ 0"
	return "ATK REQ %d  |  DEF REQ %d" % [attack_requirement, defense_requirement]


static func format_zone_time_label(total_seconds: float, label_text: String) -> String:
	return "%s: %s" % [label_text, SettlementGameData.format_duration_label(total_seconds)]


static func format_claimed_reward_text(reward: Dictionary) -> String:
	if reward.is_empty():
		return "No passive reward."
	return "%d %s every %d ticks." % [int(reward.get("amount", 0)), String(reward.get("resource", "resource")).capitalize(), max(1, int(reward.get("interval", 1)))]


static func make_hover_label(text: String, font_size: int, accent: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f3eadc") if accent else Color("d8cec1"))
	return label


static func make_colored_stat_line(label_text: String, value_text: String, accent_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label := make_hover_label(label_text, 14, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", accent_color.lightened(0.22))
	row.add_child(label)
	var value := make_hover_label(value_text, 14, false)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", Color("f4ede2"))
	row.add_child(value)
	return row
