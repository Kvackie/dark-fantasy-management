extends VBoxContainer


const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")

var _crafting_snapshot: Dictionary = {"recipes": []}
var _selected_recipe_id: String = ""
var _active_slot_filter: String = "head"
var _sort_level_ascending: bool = true
var _recipe_list: VBoxContainer = null
var _recipe_scroll: ScrollContainer = null
var _detail_panel: VBoxContainer = null
var _recipe_buttons: Dictionary = {}
var _detail_title_label: Label = null
var _detail_level_label: Label = null
var _detail_description_label: Label = null
var _detail_cost_label: Label = null
var _detail_result_label: Label = null


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
	_detail_title_label = UIScreenHelpers.make_label("", 26)
	_detail_panel.add_child(_detail_title_label)
	_detail_level_label = UIScreenHelpers.make_label("", 17)
	_detail_panel.add_child(_detail_level_label)
	_detail_description_label = UIScreenHelpers.make_label("", 16)
	_detail_panel.add_child(_detail_description_label)
	_detail_cost_label = UIScreenHelpers.make_label("", 16)
	_detail_panel.add_child(_detail_cost_label)
	_detail_result_label = UIScreenHelpers.make_label("", 18)
	_detail_panel.add_child(_detail_result_label)
	var puzzle_panel := UIScreenHelpers.make_panel()
	puzzle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	puzzle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_child(puzzle_panel)
	var puzzle_body := VBoxContainer.new()
	puzzle_body.add_theme_constant_override("separation", 8)
	puzzle_panel.add_child(puzzle_body)
	puzzle_body.add_child(UIScreenHelpers.make_label("Puzzle Placeholder", 24))
	puzzle_body.add_child(UIScreenHelpers.make_label("The crafting puzzle for this recipe will be wired here later.", 16))


func _update_recipe_detail(recipe: Dictionary) -> void:
	if recipe.is_empty():
		_detail_title_label.text = "Select a recipe to begin."
		_detail_level_label.text = ""
		_detail_description_label.text = ""
		_detail_cost_label.text = ""
		_detail_result_label.text = ""
		return
	var result_equipment := UIScreenHelpers.as_dictionary(recipe.get("result_equipment", {}))
	_detail_title_label.text = String(recipe.get("name", "Recipe"))
	_detail_level_label.text = "Level %d" % int(recipe.get("level", 1))
	_detail_description_label.text = String(recipe.get("description", "Placeholder crafting recipe."))
	_detail_cost_label.text = "Cost: %s" % _format_cost(UIScreenHelpers.as_array(recipe.get("cost", [])))
	_detail_result_label.text = "Result: %s (%s)" % [String(result_equipment.get("name", "Equipment")), String(result_equipment.get("slot", "slot")).capitalize()]


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


func _format_cost(cost_entries: Array) -> String:
	if cost_entries.is_empty():
		return "None"
	var parts: Array[String] = []
	for entry_value in cost_entries:
		var entry := UIScreenHelpers.as_dictionary(entry_value)
		var resource_id := String(entry.get("resource", "")).strip_edges()
		if resource_id.is_empty():
			continue
		parts.append("%s %d" % [resource_id.capitalize(), int(entry.get("amount", 0))])
	return " | ".join(parts) if not parts.is_empty() else "None"
