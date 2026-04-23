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


static func build_main_menu(content: VBoxContainer, viewport_width: float, mode: String, mod_category: String, callbacks: Dictionary) -> String:
	UIScreenHelpers.clear_container(content)
	match mode:
		"saves":
			_build_main_menu_saves(content, viewport_width, callbacks)
			return "Load Save"
		"mods":
			_build_main_menu_mods_root(content, viewport_width, callbacks)
			return "Mods"
		"mods_category":
			_build_main_menu_mods_category(content, viewport_width, mod_category, callbacks)
			return "%s Mods" % mod_category.capitalize()
		_:
			_build_main_menu_root(content, viewport_width, callbacks)
			return "Main Menu"


static func build_recruit_page(page_content: VBoxContainer, market_state: Dictionary, callbacks: Dictionary) -> void:
	if not bool(market_state.get("unlocked", false)):
		page_content.add_child(UIScreenHelpers.make_label("Build a Veil Tavern in any owned settlement to unlock the Recruit market.", 17))
		return
	var summary_panel := UIScreenHelpers.make_panel()
	summary_panel.custom_minimum_size = Vector2(0, 92)
	page_content.add_child(summary_panel)
	var summary_body := HBoxContainer.new()
	summary_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_body.add_theme_constant_override("separation", 18)
	summary_panel.add_child(summary_body)
	var left_summary := VBoxContainer.new()
	left_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_theme_constant_override("separation", 4)
	summary_body.add_child(left_summary)
	var summary_label := UIScreenHelpers.make_label(_txt("recruit.available_heroes", {"count": int(market_state.get("offer_capacity", 0))}, "Available Heroes: %d" % int(market_state.get("offer_capacity", 0))), 19)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_child(summary_label)
	var refresh_cost := _make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("recruit.refresh_cost", {"cost": ""}, "Refresh Cost:").trim_suffix(" "), _format_resource_bbcode(UIScreenHelpers.as_dictionary(market_state.get("refresh_cost", {})), "cost")], 13)
	refresh_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_child(refresh_cost)
	var action_column := VBoxContainer.new()
	action_column.size_flags_horizontal = Control.SIZE_SHRINK_END
	action_column.alignment = BoxContainer.ALIGNMENT_CENTER
	action_column.add_theme_constant_override("separation", 4)
	summary_body.add_child(action_column)
	var refresh_button := UIScreenHelpers.make_small_action_button(_txt("recruit.refresh_heroes", {}, "Refresh Heroes"), callbacks.get("refresh_recruit_market", Callable()))
	refresh_button.custom_minimum_size = Vector2(164, 34)
	refresh_button.add_theme_font_size_override("font_size", 20)
	refresh_button.disabled = not GameManager.can_afford(UIScreenHelpers.as_dictionary(market_state.get("refresh_cost", {})))
	action_column.add_child(refresh_button)
	var tavern_label := UIScreenHelpers.make_label(_txt("recruit.taverns_owned", {"count": int(market_state.get("tavern_count", 0))}, "Taverns Owned: %d" % int(market_state.get("tavern_count", 0))), 13)
	tavern_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tavern_label.custom_minimum_size = Vector2(160, 0)
	tavern_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tavern_label.size_flags_horizontal = Control.SIZE_FILL
	tavern_label.add_theme_color_override("font_color", Color("cbbba9"))
	action_column.add_child(tavern_label)
	var offers := UIScreenHelpers.as_array(market_state.get("offers", []))
	if offers.is_empty():
		page_content.add_child(UIScreenHelpers.make_label("No heroes are currently waiting. Refresh the market to draw a new slate.", 17))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	page_content.add_child(grid)
	for offer_entry in offers:
		var offer_data := UIScreenHelpers.as_dictionary(offer_entry)
		grid.add_child(_make_recruit_offer_card(offer_data, UIScreenHelpers.as_dictionary(offer_data.get("recruit_cost", {})), callbacks.get("recruit_offer", Callable())))


static func build_debug_page(page_content: VBoxContainer, callbacks: Dictionary) -> void:
	page_content.add_child(UIScreenHelpers.make_label("Use these tools to accelerate testing and UI verification.", 16))
	var resources_panel := UIScreenHelpers.make_panel()
	page_content.add_child(resources_panel)
	var resources_body := VBoxContainer.new()
	resources_panel.add_child(resources_body)
	resources_body.add_child(UIScreenHelpers.make_label("Resource Injection", 20))
	resources_body.add_child(UIScreenHelpers.make_label("Adds 100000 of every tracked resource immediately.", 16))
	resources_body.add_child(UIScreenHelpers.make_button("Grant 100000 All Resources", callbacks.get("debug_grant_resources", Callable()), false))

	var heroes_panel := UIScreenHelpers.make_panel()
	page_content.add_child(heroes_panel)
	var heroes_body := VBoxContainer.new()
	heroes_panel.add_child(heroes_body)
	heroes_body.add_child(UIScreenHelpers.make_label("Hero Recruitment", 20))
	heroes_body.add_child(UIScreenHelpers.make_label("Generates and recruits a random hero without Tavern or cost requirements.", 16))
	heroes_body.add_child(UIScreenHelpers.make_button("Recruit Random Hero", callbacks.get("debug_recruit_hero", Callable()), false))
	heroes_body.add_child(UIScreenHelpers.make_label("Adds 100 experience to every recruited hero.", 16))
	heroes_body.add_child(UIScreenHelpers.make_button("Grant 100 XP All Heroes", callbacks.get("debug_grant_hero_experience", Callable()), false))


static func _build_main_menu_root(content: VBoxContainer, viewport_width: float, callbacks: Dictionary) -> void:
	var last_played_slot := GameManager.get_last_played_save_slot()
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("New Game", callbacks.get("start_new_game", Callable()), false, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Continue", callbacks.get("continue_game", Callable()), last_played_slot <= 0, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Load Save", callbacks.get("open_saves", Callable()), false, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Mods", callbacks.get("open_mods", Callable()), false, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Exit", callbacks.get("exit_game", Callable()), false, viewport_width))


static func _build_main_menu_saves(content: VBoxContainer, viewport_width: float, callbacks: Dictionary) -> void:
	var save_entries: Array = []
	for slot_data in GameManager.get_save_slot_metadata():
		var entry := UIScreenHelpers.as_dictionary(slot_data)
		if not bool(entry.get("exists", false)):
			continue
		save_entries.append(GameManager.get_save_slot_summary(int(entry.get("slot", 0))))
	if save_entries.is_empty():
		_add_main_menu_centered_label(content, "No saves found.", 16)
	else:
		for save_entry in save_entries:
			_add_main_menu_centered_control(content, _build_main_menu_save_card(UIScreenHelpers.as_dictionary(save_entry), viewport_width, callbacks))
	_add_main_menu_centered_control(content, UIScreenHelpers.make_small_action_button("Back", callbacks.get("back_to_root", Callable())))


static func _build_main_menu_save_card(save_entry: Dictionary, viewport_width: float, callbacks: Dictionary) -> PanelContainer:
	var panel := UIScreenHelpers.make_panel()
	panel.custom_minimum_size = Vector2(_responsive_main_menu_card_width(viewport_width), 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var slot_index := int(save_entry.get("slot", 0))
	body.add_child(UIScreenHelpers.make_label(String(save_entry.get("name", "Unnamed Save")), 18))
	if bool(save_entry.get("last_played", false)):
		var last_played_timestamp := String(save_entry.get("last_played_timestamp", "")).strip_edges()
		body.add_child(UIScreenHelpers.make_label("Last Played%s" % (" %s" % last_played_timestamp if not last_played_timestamp.is_empty() else ""), 14))
	body.add_child(UIScreenHelpers.make_label("Ticks %d  |  Heroes %d  |  Settlements %d" % [int(save_entry.get("tick_count", 0)), int(save_entry.get("hero_count", 0)), int(save_entry.get("claimed_area_count", 0))], 14))
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(UIScreenHelpers.make_small_action_button("Load", callbacks.get("prompt_load_save", Callable()).bind(slot_index)))
	action_row.add_child(UIScreenHelpers.make_danger_button("Delete", callbacks.get("prompt_delete_save", Callable()).bind(slot_index)))
	return panel


static func _build_main_menu_mods_root(content: VBoxContainer, viewport_width: float, callbacks: Dictionary) -> void:
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Heroes", callbacks.get("open_mod_category", Callable()).bind("heroes"), false, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Items", callbacks.get("open_mod_category", Callable()).bind("items"), false, viewport_width))
	_add_main_menu_centered_control(content, _make_main_menu_choice_button("Equipment", callbacks.get("open_mod_category", Callable()).bind("equipment"), false, viewport_width))
	_add_main_menu_centered_control(content, UIScreenHelpers.make_small_action_button("Back", callbacks.get("back_to_root", Callable())))


static func _build_main_menu_mods_category(content: VBoxContainer, viewport_width: float, category: String, callbacks: Dictionary) -> void:
	var mod_summaries := DataLoader.get_mod_category_summaries(category)
	if mod_summaries.is_empty():
		_add_main_menu_centered_label(content, "No %s mods found." % category, 16)
	else:
		for mod_summary in mod_summaries:
			_add_main_menu_centered_control(content, _build_main_menu_mod_card(UIScreenHelpers.as_dictionary(mod_summary), viewport_width))
	_add_main_menu_centered_control(content, UIScreenHelpers.make_small_action_button("Back", callbacks.get("open_mods", Callable())))


static func _build_main_menu_mod_card(mod_summary: Dictionary, viewport_width: float) -> PanelContainer:
	var panel := UIScreenHelpers.make_panel()
	panel.custom_minimum_size = Vector2(_responsive_main_menu_card_width(viewport_width), 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	body.add_child(UIScreenHelpers.make_label(String(mod_summary.get("id", "Unknown Mod")), 18))
	body.add_child(UIScreenHelpers.make_label("Loaded entries: %d" % int(mod_summary.get("loaded_count", 0)), 14))
	body.add_child(UIScreenHelpers.make_label("Includes: %s" % _format_main_menu_list(UIScreenHelpers.as_array(mod_summary.get("includes", []))), 14))
	body.add_child(UIScreenHelpers.make_label("Missing: %s" % _format_main_menu_list(UIScreenHelpers.as_array(mod_summary.get("missing", []))), 14))
	return panel


static func _add_main_menu_centered_control(content: VBoxContainer, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(control)
	content.add_child(row)


static func _add_main_menu_centered_label(content: VBoxContainer, text: String, font_size: int) -> void:
	var label := UIScreenHelpers.make_label(text, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_main_menu_centered_control(content, label)


static func _make_main_menu_choice_button(text: String, callback: Callable, disabled: bool, viewport_width: float) -> Button:
	var button := UIScreenHelpers.make_button(text, callback, disabled)
	button.custom_minimum_size = Vector2(_responsive_main_menu_button_width(viewport_width), 84)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 26)
	return button


static func _responsive_main_menu_card_width(viewport_width: float) -> float:
	return clampf(viewport_width * 0.92, 360.0, 700.0)


static func _responsive_main_menu_button_width(viewport_width: float) -> float:
	return clampf(viewport_width * 0.82, 320.0, 500.0)


static func _format_main_menu_list(values: Array) -> String:
	if values.is_empty():
		return "none"
	var text_values: Array[String] = []
	for value in values:
		text_values.append(String(value))
	return ", ".join(text_values)


static func _make_recruit_offer_card(offer_data: Dictionary, recruit_cost: Dictionary, recruit_callback: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 236)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIScreenHelpers.style_panel(panel, Color("151214"), Color("78614e"), 10)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 12)
	body.add_child(header_row)
	var portrait_holder := PanelContainer.new()
	portrait_holder.custom_minimum_size = Vector2(92, 92)
	portrait_holder.add_theme_stylebox_override("panel", _button_style(Color("100d0e"), Color("4f3f36"), 8))
	header_row.add_child(portrait_holder)
	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 6.0
	portrait.offset_top = 6.0
	portrait.offset_right = -6.0
	portrait.offset_bottom = -6.0
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = UIScreenHelpers.load_hero_texture(offer_data)
	portrait_holder.add_child(portrait)
	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_text.add_theme_constant_override("separation", 4)
	header_row.add_child(header_text)
	var hero_name := UIScreenHelpers.make_label(String(offer_data.get("name", "Unknown Hero")), 18)
	hero_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	header_text.add_child(hero_name)
	var hero_meta := UIScreenHelpers.make_label("Lv.%d  |  %s" % [int(offer_data.get("level", 1)), String(offer_data.get("class", "Hero"))], 14)
	hero_meta.add_theme_color_override("font_color", Color("cbbba9"))
	header_text.add_child(hero_meta)
	var stats := UIScreenHelpers.as_dictionary(offer_data.get("stats", {}))
	var work_stats := UIScreenHelpers.as_dictionary(offer_data.get("work_stats", {}))
	body.add_child(_make_rich_text_label(_format_recruit_combat_stats_bbcode(stats), 13))
	body.add_child(_make_rich_text_label(_format_work_stats_bbcode(work_stats), 13))
	body.add_child(_make_rich_text_label("[color=#d8d1c6]Recruit Cost:[/color] %s" % _format_resource_bbcode(recruit_cost, "cost"), 13))
	body.add_child(UIScreenHelpers.make_button("Recruit Hero", recruit_callback.bind(int(offer_data.get("offer_id", -1))), not GameManager.can_afford(recruit_cost)))
	return panel


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


static func _format_recruit_combat_stats_bbcode(stats: Dictionary) -> String:
	var parts: Array[String] = [
		"[color=#d8847b]HP %d[/color]" % int(stats.get("health", 0)),
		"[color=#c8b8d9]SAN %d/%d[/color]" % [int(stats.get("current_sanity", stats.get("sanity", 0))), int(stats.get("max_sanity", stats.get("sanity", 0)))],
		"[color=#d0a170]ATK %d[/color]" % int(stats.get("attack", 0)),
		"[color=#88a8c8]DEF %d[/color]" % int(stats.get("defense", 0)),
		"[color=#f0c96c]CRIT %d%%[/color]" % int(stats.get("critical_chance", 0)),
		"[color=#e5b86f]CRIT DMG %d%%[/color]" % int(stats.get("critical_damage", 0)),
	]
	return "  |  ".join(parts)


static func _txt(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	return DataLoader.get_ui_text(key, replacements, fallback)


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
