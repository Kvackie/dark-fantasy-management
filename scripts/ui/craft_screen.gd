extends VBoxContainer


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")

const STAT_COLORS := {
	"health": "#d8847b",
	"sanity": "#c8b8d9",
	"attack": "#d0a170",
	"defense": "#88a8c8",
	"critical_chance": "#f0c96c",
	"critical_damage": "#e5b86f",
}
const WORK_STAT_COLORS := {
	"farming": "#7f9f84",
	"mining": "#7f9f84",
	"lumbering": "#7f9f84",
}
const RESOURCE_COLORS := {
	"wood": "#b98b60",
	"food": "#d4a25c",
	"stone": "#b7bcc7",
	"gold": "#f0cc66",
	"gems": "#73b5ff",
	"crystals": "#7dd7ff",
}
const RESOURCE_ICONS := {
	"wood": "res://assets/resources/wood.png",
	"food": "res://assets/resources/food.png",
	"stone": "res://assets/resources/metal.png",
	"gold": "res://assets/resources/coins.png",
	"gems": "res://assets/resources/gems.png",
	"crystals": "res://assets/resources/crystals.png",
}
var _crafting_snapshot: Dictionary = {"recipes": []}
var _selected_recipe_id: String = ""
var _active_slot_filter: String = "head"
var _sort_level_ascending: bool = true
var _recipe_list: VBoxContainer = null
var _recipe_scroll: ScrollContainer = null
var _detail_panel: VBoxContainer = null
var _recipe_buttons: Dictionary = {}
var _detail_description_label: Label = null
var _detail_cost_grid: GridContainer = null
var _detail_result_icon: TextureRect = null
var _detail_result_label: RichTextLabel = null
var _detail_stats_body: VBoxContainer = null
var _detail_scroll_body: VBoxContainer = null


func set_crafting_snapshot(crafting_snapshot: Dictionary) -> void:
	_crafting_snapshot = crafting_snapshot.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 16)
	add_child(content_row)
	var recipes := UIScreenHelpers.as_array(_crafting_snapshot.get("recipes", []))
	var filtered_recipes := _filter_recipes(recipes)
	_sort_recipes_by_level(filtered_recipes)
	if not _recipe_matches_slot(_get_selected_recipe(recipes), _active_slot_filter):
		_selected_recipe_id = ""
	if _selected_recipe_id.is_empty() and not recipes.is_empty():
		_selected_recipe_id = String((filtered_recipes[0] as Dictionary).get("id", "")) if not filtered_recipes.is_empty() else ""
	var list_panel := UIScreenHelpers.make_panel()
	list_panel.custom_minimum_size = Vector2(230, 0)
	content_row.add_child(list_panel)
	var list_body := VBoxContainer.new()
	list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_body.add_theme_constant_override("separation", 8)
	list_panel.add_child(list_body)
	list_body.add_child(_make_slot_tabs())
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_scroll.follow_focus = false
	list_body.add_child(_recipe_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 8)
	_recipe_scroll.add_child(_recipe_list)
	var right_panel := UIScreenHelpers.make_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_child(right_panel)
	_detail_panel = VBoxContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_theme_constant_override("separation", 10)
	right_panel.add_child(_detail_panel)
	_build_recipe_detail_shell()
	_build_recipe_list(filtered_recipes)
	_update_recipe_detail(_get_selected_recipe(recipes))


func _build_recipe_list(recipes: Array) -> void:
	_recipe_buttons.clear()
	if recipes.is_empty():
		_recipe_list.add_child(UIScreenHelpers.make_label("No recipes for this slot.", 16))
		return
	for recipe_value in recipes:
		var recipe := UIScreenHelpers.as_dictionary(recipe_value)
		var button := _make_recipe_button(recipe)
		var recipe_id := String(recipe.get("id", ""))
		_recipe_buttons[recipe_id] = button
		_recipe_list.add_child(button)
	_update_recipe_button_states()


func _make_recipe_button(recipe: Dictionary) -> Button:
	var button := UIScreenHelpers.make_small_action_button("", Callable(self, "_select_recipe").bind(String(recipe.get("id", ""))))
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 72)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10.0
	row.offset_top = 8.0
	row.offset_right = -10.0
	row.offset_bottom = -8.0
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	button.add_child(row)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(54, 54)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIScreenHelpers.load_texture_from_path(String(UIScreenHelpers.as_dictionary(recipe.get("result_equipment", {})).get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
	row.add_child(icon)
	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)
	var name_label := UIScreenHelpers.make_label(String(recipe.get("name", "Recipe")), 17)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_child(name_label)
	var level_label := UIScreenHelpers.make_label("Level %d" % int(recipe.get("level", 1)), 14)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	level_label.clip_text = true
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.custom_minimum_size = Vector2(58, 0)
	level_label.add_theme_color_override("font_color", Color("cbbba9"))
	row.add_child(level_label)
	return button


func _make_slot_tabs() -> GridContainer:
	var tabs := GridContainer.new()
	tabs.columns = 3
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		var label: String = slot_key.capitalize()
		if slot_key == _active_slot_filter:
			var arrow := "↑"
			if not _sort_level_ascending:
				arrow = "↓"
			label = "%s %s" % [label, arrow]
		var button := UIScreenHelpers.make_small_action_button(label, Callable(self, "_set_slot_filter").bind(slot_key))
		button.self_modulate = Color("cfa36e") if slot_key == _active_slot_filter else Color.WHITE
		button.custom_minimum_size = Vector2(0, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	return tabs


func _build_recipe_detail_shell() -> void:
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(top_row)
	_detail_description_label = UIScreenHelpers.make_label("", 13)
	_detail_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_description_label.add_theme_color_override("font_color", Color("b9afa4"))
	top_row.add_child(_detail_description_label)
	var craft_button := UIScreenHelpers.make_small_action_button("Craft", Callable())
	craft_button.custom_minimum_size = Vector2(118, 44)
	craft_button.add_theme_font_size_override("font_size", 20)
	craft_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_row.add_child(craft_button)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(detail_scroll)
	_detail_scroll_body = VBoxContainer.new()
	_detail_scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll_body.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(_detail_scroll_body)
	var cost_panel := UIScreenHelpers.make_panel()
	cost_panel.custom_minimum_size = Vector2(0, 120)
	cost_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail_scroll_body.add_child(cost_panel)
	var cost_body := VBoxContainer.new()
	cost_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_body.add_theme_constant_override("separation", 6)
	cost_panel.add_child(cost_body)
	var cost_title := UIScreenHelpers.make_label("Cost", 15)
	cost_title.add_theme_color_override("font_color", Color("d8c0a0"))
	cost_body.add_child(cost_title)
	_detail_cost_grid = GridContainer.new()
	_detail_cost_grid.columns = 4
	_detail_cost_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_cost_grid.add_theme_constant_override("h_separation", 6)
	_detail_cost_grid.add_theme_constant_override("v_separation", 6)
	cost_body.add_child(_detail_cost_grid)
	var result_panel := UIScreenHelpers.make_panel()
	result_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll_body.add_child(result_panel)
	var result_body := HBoxContainer.new()
	result_body.add_theme_constant_override("separation", 12)
	result_panel.add_child(result_body)
	_detail_result_icon = TextureRect.new()
	_detail_result_icon.custom_minimum_size = Vector2(92, 92)
	_detail_result_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_result_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_body.add_child(_detail_result_icon)
	var result_text := VBoxContainer.new()
	result_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_text.add_theme_constant_override("separation", 8)
	result_body.add_child(result_text)
	_detail_result_label = _make_rich_text_label("", 20)
	result_text.add_child(_detail_result_label)
	_detail_stats_body = VBoxContainer.new()
	_detail_stats_body.add_theme_constant_override("separation", 4)
	result_text.add_child(_detail_stats_body)


func _update_recipe_detail(recipe: Dictionary) -> void:
	if recipe.is_empty():
		_detail_description_label.text = "Select a recipe to begin."
		UIScreenHelpers.clear_container(_detail_cost_grid)
		_detail_result_icon.texture = null
		_detail_result_label.text = ""
		UIScreenHelpers.clear_container(_detail_stats_body)
		return
	var result_equipment := UIScreenHelpers.as_dictionary(recipe.get("result_equipment", {}))
	_detail_description_label.text = String(recipe.get("description", "Placeholder crafting recipe."))
	_update_cost_grid(UIScreenHelpers.as_array(recipe.get("cost", [])))
	_detail_result_icon.texture = UIScreenHelpers.load_texture_from_path(String(result_equipment.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
	_detail_result_label.text = "[color=#f0d0a8]%s[/color]  [color=#cbbba9](%s)[/color]" % [String(result_equipment.get("name", "Equipment")), String(result_equipment.get("slot", "slot")).capitalize()]
	_build_stat_rows(UIScreenHelpers.as_dictionary(result_equipment.get("bonuses", {})))


func _select_recipe(recipe_id: String) -> void:
	if _selected_recipe_id == recipe_id:
		return
	_selected_recipe_id = recipe_id
	_update_recipe_button_states()
	_update_recipe_detail(_get_selected_recipe(UIScreenHelpers.as_array(_crafting_snapshot.get("recipes", []))))


func _set_slot_filter(slot_key: String) -> void:
	if _active_slot_filter == slot_key:
		_sort_level_ascending = not _sort_level_ascending
	else:
		_sort_level_ascending = true
	_active_slot_filter = slot_key
	_selected_recipe_id = ""
	refresh()


func _update_recipe_button_states() -> void:
	for recipe_id in _recipe_buttons.keys():
		var button: Button = _recipe_buttons[recipe_id]
		button.self_modulate = Color("cfa36e") if String(recipe_id) == _selected_recipe_id else Color.WHITE


func _get_selected_recipe(recipes: Array) -> Dictionary:
	for recipe_value in recipes:
		var recipe := UIScreenHelpers.as_dictionary(recipe_value)
		if String(recipe.get("id", "")) == _selected_recipe_id:
			return recipe
	return {}


func _filter_recipes(recipes: Array) -> Array:
	var filtered: Array = []
	for recipe_value in recipes:
		var recipe := UIScreenHelpers.as_dictionary(recipe_value)
		if _recipe_matches_slot(recipe, _active_slot_filter):
			filtered.append(recipe)
	return filtered


func _sort_recipes_by_level(recipes: Array) -> void:
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var level_a := int(a.get("level", 1))
		var level_b := int(b.get("level", 1))
		if level_a == level_b:
			return String(a.get("name", "")) < String(b.get("name", ""))
		return level_a < level_b if _sort_level_ascending else level_a > level_b
	)


func _recipe_matches_slot(recipe: Dictionary, slot_key: String) -> bool:
	return String(UIScreenHelpers.as_dictionary(recipe.get("result_equipment", {})).get("slot", "")) == slot_key


func _update_cost_grid(cost_entries: Array) -> void:
	UIScreenHelpers.clear_container(_detail_cost_grid)
	if cost_entries.is_empty():
		_detail_cost_grid.add_child(UIScreenHelpers.make_label("None", 14))
		return
	for entry_value in cost_entries:
		var entry := UIScreenHelpers.as_dictionary(entry_value)
		var resource_id := String(entry.get("resource", "")).strip_edges()
		if not resource_id.is_empty():
			var amount := int(entry.get("amount", 0))
			_detail_cost_grid.add_child(_make_cost_chip(resource_id.capitalize(), amount, String(RESOURCE_ICONS.get(resource_id, DataLoader.DEFAULT_CATALOG_ICON)), Color(String(RESOURCE_COLORS.get(resource_id, "#e6ddd3"))), _has_resource_cost(resource_id, amount)))
			continue
		var item_id := String(entry.get("item", "")).strip_edges()
		if item_id.is_empty():
			continue
		var item_definition := DataLoader.get_item_definition(item_id)
		var amount := int(entry.get("amount", 0))
		_detail_cost_grid.add_child(_make_cost_chip(String(item_definition.get("name", item_id.capitalize())), amount, String(item_definition.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)), Color("d9cbb7"), _has_item_cost(item_id, amount)))


func _make_cost_chip(label_text: String, amount: int, icon_path: String, text_color: Color, can_afford: bool) -> PanelContainer:
	var panel := UIScreenHelpers.make_panel()
	panel.custom_minimum_size = Vector2(104, 46)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIScreenHelpers.style_panel(panel, Color("120f10"), Color("5f2e2e") if not can_afford else Color("3f7a4d"), 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIScreenHelpers.load_texture_from_path(icon_path)
	row.add_child(icon)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)
	var name_label := UIScreenHelpers.make_label(label_text, 12)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.add_theme_color_override("font_color", text_color)
	text_column.add_child(name_label)
	var amount_label := UIScreenHelpers.make_label("x%d" % amount, 12)
	amount_label.add_theme_color_override("font_color", Color("e6ddd3"))
	text_column.add_child(amount_label)
	return panel


func _has_resource_cost(resource_id: String, amount: int) -> bool:
	var resources := UIScreenHelpers.as_dictionary(_crafting_snapshot.get("resources", {}))
	return int(resources.get(resource_id, 0)) >= amount


func _has_item_cost(item_id: String, amount: int) -> bool:
	var total := 0
	for item_value in UIScreenHelpers.as_array(_crafting_snapshot.get("items", [])):
		var item_stack := UIScreenHelpers.as_dictionary(item_value)
		if String(item_stack.get("definition_id", "")) == item_id:
			total += int(item_stack.get("quantity", 0))
	return total >= amount


func _build_stat_rows(bonuses: Dictionary) -> void:
	UIScreenHelpers.clear_container(_detail_stats_body)
	_detail_stats_body.add_child(_make_stat_section("Combat Stats", UIScreenHelpers.as_dictionary(bonuses.get("stats", {})), STAT_COLORS))
	_detail_stats_body.add_child(_make_stat_section("Work Stats", UIScreenHelpers.as_dictionary(bonuses.get("work_stats", {})), WORK_STAT_COLORS))


func _make_stat_section(title: String, values: Dictionary, colors: Dictionary) -> PanelContainer:
	var panel := UIScreenHelpers.make_panel()
	UIScreenHelpers.style_panel(panel, Color("120f10"), Color("4f3f36"), 8)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var header := UIScreenHelpers.make_label(title, 15)
	header.add_theme_color_override("font_color", Color("d8c0a0"))
	body.add_child(header)
	if values.is_empty():
		var empty := UIScreenHelpers.make_label("none", 13)
		empty.add_theme_color_override("font_color", Color("9f9388"))
		body.add_child(empty)
		return panel
	for stat_key in values.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(row)
		var stat_color := Color(String(colors.get(String(stat_key), "#e6ddd3")))
		var stat_label := UIScreenHelpers.make_label(String(stat_key).capitalize().replace("_", " "), 14)
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.add_theme_color_override("font_color", stat_color)
		row.add_child(stat_label)
		var value_label := UIScreenHelpers.make_label(_format_stat_value(values[stat_key]), 14)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", stat_color)
		row.add_child(value_label)
	return panel


func _format_stat_value(value: Variant) -> String:
	if value is Dictionary:
		var range_value := UIScreenHelpers.as_dictionary(value)
		return "+%d - %d" % [int(range_value.get("min", 0)), int(range_value.get("max", 0))]
	return "+%d" % int(value)


func _make_rich_text_label(bbcode_text: String, font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size + 2)
	label.add_theme_color_override("default_color", Color("e6ddd3"))
	label.text = bbcode_text
	return label
