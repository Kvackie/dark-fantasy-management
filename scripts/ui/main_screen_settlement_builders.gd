extends RefCounted


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")

const RESOURCE_TEXT_COLORS := {
	"wood": "#b98b60",
	"food": "#d4a25c",
	"stone": "#b7bcc7",
	"gold": "#f0cc66",
	"heroes": "#d8778f",
	"gems": "#73b5ff",
	"crystals": "#7dd7ff",
}

const WORK_STAT_COLORS := {
	"farming": "#93be73",
	"mining": "#8db0d8",
	"lumbering": "#b38b5e",
}


static func build_settlement_detail(detail_content: VBoxContainer, selected_slot: int, detail_mode: String, heroes_snapshot: Array, callbacks: Dictionary) -> void:
	if selected_slot == -1:
		return
	var slot_data: Dictionary = GameManager.get_slot(selected_slot)
	if String(slot_data.get("building_id", "")).is_empty():
		_build_empty_plot_panel(detail_content, selected_slot, callbacks)
	else:
		_build_building_panel(detail_content, selected_slot, slot_data, detail_mode, heroes_snapshot, callbacks)


static func _build_empty_plot_panel(detail_content: VBoxContainer, slot_index: int, callbacks: Dictionary) -> void:
	_add_detail_header(detail_content, _txt("settlement.empty_plot", {"index": slot_index + 1}), callbacks.get("close_settlement_details", Callable()))
	var intro_panel := _make_section_panel(detail_content, "Plot Info")
	intro_panel.add_child(_make_muted_label(_txt("settlement.choose_structure"), 15))
	_add_section(detail_content, "Available Buildings")
	for building_definition in GameManager.get_building_catalog():
		var building_data: Dictionary = building_definition
		var build_cost: Dictionary = SettlementGameData.resource_list_to_dictionary(UIScreenHelpers.as_array(building_data.get("build_cost", [])))
		var body := _make_section_panel(detail_content, String(building_data.get("name", "Unknown")))
		body.add_child(_make_muted_label(String(building_data.get("description", "")), 13))
		body.add_child(_make_rich_text_label("%s [color=#d7d0c6]%s[/color]" % [_txt("settlement.cost", {"cost": ""}).trim_suffix(" "), _format_resource_bbcode(build_cost, "cost")], 13))
		body.add_child(_make_primary_action_button("Build %s" % String(building_data.get("name", "Structure")), callbacks.get("build_selected_building", Callable()).bind(slot_index, String(building_data.get("id", ""))), not GameManager.can_afford(build_cost)))


static func _build_building_panel(detail_content: VBoxContainer, slot_index: int, slot_data: Dictionary, detail_mode: String, heroes_snapshot: Array, callbacks: Dictionary) -> void:
	var building_definition: Dictionary = GameManager.get_slot_building_definition(slot_index)
	var building_name := String(building_definition.get("name", "Unknown Structure"))
	_add_detail_header(detail_content, building_name, callbacks.get("close_settlement_details", Callable()))
	var current_level := int(slot_data.get("level", 1))
	var assigned_count := UIScreenHelpers.as_array(slot_data.get("assigned_hero_ids", [])).size()
	var worker_slots := int(building_definition.get("worker_slots", 0))
	var max_level: int = int(building_definition.get("max_level", SettlementGameData.MAX_BUILDING_LEVEL))
	var at_max_level: bool = current_level >= max_level
	var upgrade_cost: Dictionary = GameManager.get_upgrade_cost(slot_index)
	var dismantle_refund: Dictionary = GameManager.get_dismantle_refund(slot_index)

	var overview_body := _make_section_panel(detail_content, "")
	overview_body.add_child(_make_muted_label(String(building_definition.get("description", "")), 14))
	var stats_row := HBoxContainer.new()
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_theme_constant_override("separation", 8)
	overview_body.add_child(stats_row)
	stats_row.add_child(_make_info_chip("Level", "%d / %d" % [current_level, max_level]))
	stats_row.add_child(_make_info_chip("Workers", "%d / %d" % [assigned_count, worker_slots]))
	var production_preview: Dictionary = GameManager.get_slot_production_preview(slot_index)
	if not production_preview.is_empty():
		overview_body.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.production", {"production": ""}).trim_suffix(" "), _format_resource_bbcode(production_preview, "refund")], 15))

	var action_body := _make_section_panel(detail_content, "")
	action_body.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.upgrade_cost", {"cost": ""}).trim_suffix(" "), _format_resource_bbcode(upgrade_cost, "cost")], 14))
	action_body.add_child(_make_primary_action_button(_txt("settlement.upgrade_button"), callbacks.get("upgrade_slot", Callable()).bind(slot_index), at_max_level or not GameManager.can_afford(upgrade_cost)))
	action_body.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.dismantle_refund", {"refund": ""}).trim_suffix(" "), _format_resource_bbcode(dismantle_refund, "refund")], 14))
	action_body.add_child(_make_danger_action_button(_txt("settlement.dismantle_button"), callbacks.get("dismantle_slot", Callable()).bind(slot_index)))

	_add_section(detail_content, _txt("settlement.assigned_heroes"))
	var assigned_any := false
	for hero_data in heroes_snapshot:
		var hero: Dictionary = hero_data
		if int(hero.get("assigned_slot", -1)) == slot_index and String(hero.get("assigned_settlement_id", "")) == GameManager.active_settlement_id:
			assigned_any = true
			_add_hero_entry(detail_content, hero, true, detail_mode, slot_index, callbacks)
	if not assigned_any:
		_add_empty_state(detail_content, _txt("settlement.no_assigned_heroes"))
	_add_section(detail_content, _txt("settlement.available_heroes"))
	var available_heroes: Array = GameManager.get_available_heroes_for_slot(slot_index)
	if available_heroes.is_empty():
		_add_empty_state(detail_content, _txt("settlement.no_available_heroes"))
	else:
		for hero_data in available_heroes:
			var hero: Dictionary = hero_data
			if not (int(hero.get("assigned_slot", -1)) == slot_index and String(hero.get("assigned_settlement_id", "")) == GameManager.active_settlement_id):
				_add_hero_entry(detail_content, hero, false, detail_mode, slot_index, callbacks)


static func _add_hero_entry(detail_content: VBoxContainer, hero: Dictionary, assigned: bool, detail_mode: String, selected_slot: int, callbacks: Dictionary) -> void:
	var panel: PanelContainer = UIScreenHelpers.make_panel()
	detail_content.add_child(panel)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var assigned_slot: int = int(hero.get("assigned_slot", -1))
	var assigned_settlement_id := String(hero.get("assigned_settlement_id", "")).strip_edges()
	var work_stats: Dictionary = GameManager.get_hero_effective_work_stats(int(hero.get("uid", -1)))
	if work_stats.is_empty():
		work_stats = UIScreenHelpers.as_dictionary(hero.get("work_stats", {}))
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIScreenHelpers.load_hero_texture(hero)
	body.add_child(icon)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 4)
	body.add_child(text_column)
	text_column.add_child(_make_rich_text_label(_format_work_stats_bbcode(work_stats), 13))
	if not assigned and assigned_slot >= 0 and not assigned_settlement_id.is_empty():
		var current_building: Dictionary = GameManager.get_settlement_building_definition(assigned_settlement_id, assigned_slot)
		var assignment_name := String(current_building.get("name", "another site"))
		if assigned_settlement_id != GameManager.active_settlement_id:
			assignment_name = "%s (%s)" % [assignment_name, String(GameManager.get_settlement_display_name(assigned_settlement_id))]
		text_column.add_child(_make_muted_label(_txt("settlement.current_assignment", {"building": assignment_name}), 12))
	if detail_mode == "settlement" and selected_slot >= 0:
		if assigned:
			body.add_child(_make_secondary_action_button(_txt("hero.unassign"), callbacks.get("unassign_hero", Callable()).bind(int(hero.get("uid", -1)))))
		else:
			var button_text := _txt("hero.move_here") if assigned_slot >= 0 and not assigned_settlement_id.is_empty() else _txt("hero.assign")
			body.add_child(_make_secondary_action_button(button_text, callbacks.get("assign_hero", Callable()).bind(int(hero.get("uid", -1)), selected_slot)))


static func _add_detail_header(detail_content: VBoxContainer, text: String, close_callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	detail_content.add_child(row)
	var title := UIScreenHelpers.make_label(text, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(UIScreenHelpers.make_small_nav_button("Close", close_callback))


static func _add_section(detail_content: VBoxContainer, text: String) -> void:
	var label := UIScreenHelpers.make_label(text, 20)
	label.add_theme_color_override("font_color", Color("d8c0a0"))
	detail_content.add_child(label)


static func _add_text(detail_content: VBoxContainer, text: String) -> void:
	detail_content.add_child(UIScreenHelpers.make_label(text, 15))


static func _add_button(detail_content: VBoxContainer, text: String, callback: Callable, disabled: bool) -> void:
	detail_content.add_child(UIScreenHelpers.make_button(text, callback, disabled))


static func _make_section_panel(detail_content: VBoxContainer, title_text: String) -> VBoxContainer:
	var panel := UIScreenHelpers.make_panel()
	detail_content.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	if not title_text.is_empty():
		var title := UIScreenHelpers.make_label(title_text, 17)
		title.add_theme_color_override("font_color", Color("f0d0a8"))
		body.add_child(title)
	return body


static func _make_info_chip(label_text: String, value_text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIScreenHelpers.style_panel(chip, Color("100d0e"), Color("4f3f36"), 7)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	chip.add_child(body)
	var label := _make_muted_label(label_text, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(label)
	var value := UIScreenHelpers.make_label(value_text, 18)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(value)
	return chip


static func _make_muted_label(text: String, font_size: int) -> Label:
	var label := UIScreenHelpers.make_label(text, font_size)
	label.add_theme_color_override("font_color", Color("cbbba9"))
	return label


static func _make_primary_action_button(text: String, callback: Callable, disabled: bool) -> Button:
	var button := UIScreenHelpers.make_button(text, callback, disabled)
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 20)
	return button


static func _make_secondary_action_button(text: String, callback: Callable) -> Button:
	var button := UIScreenHelpers.make_small_action_button(text, callback)
	button.custom_minimum_size = Vector2(116, 34)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	return button


static func _make_danger_action_button(text: String, callback: Callable) -> Button:
	var button := UIScreenHelpers.make_danger_button(text, callback)
	button.custom_minimum_size = Vector2(0, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


static func _add_empty_state(detail_content: VBoxContainer, text: String) -> void:
	var body := _make_section_panel(detail_content, "")
	body.add_child(_make_muted_label(text, 14))


static func _make_rich_text_label(bbcode_text: String, font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", (font_size if font_size >= 20 else font_size + 1) + 2)
	label.add_theme_color_override("default_color", Color("e6ddd3"))
	label.text = bbcode_text
	return label


static func _format_resource_bbcode(values: Dictionary, style: String) -> String:
	if values.is_empty():
		return _txt("common.none")
	var parts: Array[String] = []
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		if not values.has(resource_id) or int(values[resource_id]) == 0:
			continue
		var amount := int(values[resource_id])
		var signed_amount := amount
		if style == "cost":
			signed_amount = -abs(amount)
		elif style == "refund":
			signed_amount = abs(amount)
		var amount_text := "%+d" % signed_amount if style in ["cost", "refund"] else "%d" % signed_amount
		parts.append("[color=%s]%s %s[/color]" % [String(RESOURCE_TEXT_COLORS.get(resource_id, "#e6ddd3")), _txt("resource.%s" % resource_id, {}, resource_id.capitalize()), amount_text])
	for resource_id_variant in values.keys():
		var resource_id := String(resource_id_variant)
		if SettlementGameData.RESOURCE_ORDER.has(resource_id) or int(values[resource_id]) == 0:
			continue
		var amount := int(values[resource_id])
		var signed_amount := amount
		if style == "cost":
			signed_amount = -abs(amount)
		elif style == "refund":
			signed_amount = abs(amount)
		var amount_text := "%+d" % signed_amount if style in ["cost", "refund"] else "%d" % signed_amount
		parts.append("[color=#e6ddd3]%s %s[/color]" % [resource_id.capitalize(), amount_text])
	return "  |  ".join(parts)


static func _format_work_stats_bbcode(work_stats: Dictionary) -> String:
	var parts: Array[String] = []
	for stat_key in ["farming", "mining", "lumbering"]:
		parts.append("[color=%s]%s %d[/color]" % [String(WORK_STAT_COLORS.get(stat_key, "#e6ddd3")), _txt("work.%s" % stat_key, {}, stat_key.capitalize()), int(work_stats.get(stat_key, 0))])
	return "  |  ".join(parts)


static func _txt(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	return DataLoader.get_ui_text(key, replacements, fallback)
