extends HBoxContainer


const HeroDetailViewBuilders = preload("res://scripts/ui/hero_detail_view_builders.gd")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")

const HERO_TAB_INFO := "info"
const HERO_TAB_EQUIPMENT := "equipment"
const HERO_TAB_SKILLS := "skills"
const HERO_TAB_LORE := "lore"
const HERO_DETAIL_TABS := [HERO_TAB_INFO, HERO_TAB_EQUIPMENT, HERO_TAB_SKILLS, HERO_TAB_LORE]
const EQUIPMENT_SLOT_COLUMNS := 3
const EQUIPMENT_SLOT_GAP := 16

signal back_requested

@onready var _context_panel: PanelContainer = get_node("ContextPanel")
@onready var _name_bar: PanelContainer = get_node("RightSection/NameBar")
@onready var _hero_name_label: Label = get_node("RightSection/NameBar/NameRow/HeroName")
@onready var _back_button: Button = get_node("RightSection/NameBar/NameRow/BackButton")
@onready var _tabs_column: VBoxContainer = get_node("RightSection/ContentSplit/TabsColumn")
@onready var _tab_panel: PanelContainer = get_node("RightSection/ContentSplit/TabPanel")
@onready var _tab_scroll: ScrollContainer = get_node("RightSection/ContentSplit/TabPanel/TabScroll")
@onready var _tab_body: VBoxContainer = get_node("RightSection/ContentSplit/TabPanel/TabScroll/TabBody")

var _selected_hero_uid: int = -1
var _heroes_snapshot: Array = []
var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}
var _hero_detail_tab: String = HERO_TAB_INFO
var _selected_slot: String = ""
var _selected_equipment_uid: int = -1
var _equipment_slots_grid: GridContainer = null
var _browser_root: Control = null
var _equipment_list_scroll: ScrollContainer = null
var _browser_scroll_value: int = 0
var _hover_popup: Control = null
var _hover_popup_body: VBoxContainer = null
var _equipment_dialog: Control = null
var _dismiss_confirm_uid: int = -1
var _equipment_tiles: Dictionary = {}


func _ready() -> void:
	_style_shell()
	var back_callback := Callable(self, "_on_back_pressed")
	if not _back_button.pressed.is_connected(back_callback):
		_back_button.pressed.connect(back_callback)


func set_selected_hero_uid(hero_uid: int) -> void:
	if _selected_hero_uid == hero_uid:
		return
	_selected_hero_uid = hero_uid
	_reset_local_state()


func set_heroes_snapshot(heroes_snapshot: Array) -> void:
	_heroes_snapshot = heroes_snapshot.duplicate(true)


func set_inventory_snapshot(inventory_snapshot: Dictionary) -> void:
	_inventory_snapshot = inventory_snapshot.duplicate(true)


func refresh() -> void:
	_style_shell()
	var hero_data := _get_selected_hero()
	if hero_data.is_empty():
		UIScreenHelpers.clear_container(_tabs_column)
		UIScreenHelpers.clear_container(_tab_body)
		UIScreenHelpers.clear_container(_context_panel)
		_hero_name_label.text = "Hero Unavailable"
		_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_build_unavailable_state()
		return
	_hero_name_label.text = String(hero_data.get("name", "Unknown Hero"))
	if _refresh_in_place(hero_data):
		return
	UIScreenHelpers.clear_container(_tabs_column)
	UIScreenHelpers.clear_container(_tab_body)
	UIScreenHelpers.clear_container(_context_panel)
	for tab_id in HERO_DETAIL_TABS:
		_tabs_column.add_child(_make_hero_tab_button(tab_id))
	var equipment_tab_active := _hero_detail_tab == HERO_TAB_EQUIPMENT
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if equipment_tab_active else ScrollContainer.SCROLL_MODE_AUTO
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if _hero_detail_tab == HERO_TAB_EQUIPMENT:
		_tab_scroll.scroll_vertical = 0
		_tab_scroll.scroll_horizontal = 0
	_build_context_panel(hero_data)
	_build_tab_content(_tab_body, hero_data)


func _refresh_in_place(hero_data: Dictionary) -> bool:
	if _hero_detail_tab != HERO_TAB_EQUIPMENT or _selected_slot.is_empty():
		return false
	if _browser_root == null or not is_instance_valid(_browser_root):
		return false
	if _equipment_list_scroll == null or not is_instance_valid(_equipment_list_scroll):
		return false
	if _equipment_slots_grid == null or not is_instance_valid(_equipment_slots_grid):
		return false
	_refresh_equipment_slot_grid(hero_data)
	var slot_entries := _get_inventory_equipment_entries_for_slot(_selected_slot)
	if slot_entries.size() != _equipment_tiles.size():
		return false
	for equipment_entry in slot_entries:
		var entry := UIScreenHelpers.as_dictionary(equipment_entry)
		var equipment_uid := int(entry.get("uid", -1))
		var tile: PanelContainer = _equipment_tiles.get(equipment_uid, null) as PanelContainer
		if tile == null or not is_instance_valid(tile):
			return false
		_populate_equipment_browser_tile(tile, entry)
	if _selected_equipment_uid <= 0:
		if _equipment_dialog != null and is_instance_valid(_equipment_dialog):
			_equipment_dialog.queue_free()
		_equipment_dialog = null
		return true
	var selected_entry := _get_inventory_equipment_entry(_selected_equipment_uid)
	if selected_entry.is_empty():
		if _equipment_dialog != null and is_instance_valid(_equipment_dialog):
			_equipment_dialog.queue_free()
		_equipment_dialog = null
		_selected_equipment_uid = -1
		return true
	if _equipment_dialog != null and is_instance_valid(_equipment_dialog):
		_equipment_dialog.queue_free()
	_equipment_dialog = _make_equipment_detail_dialog(hero_data, _selected_slot, selected_entry)
	_browser_root.add_child(_equipment_dialog)
	call_deferred("_restore_browser_scroll")
	return true


func _refresh_equipment_slot_grid(hero_data: Dictionary) -> void:
	if _equipment_slots_grid == null or not is_instance_valid(_equipment_slots_grid):
		return
	_clear_container_immediately(_equipment_slots_grid)
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		_equipment_slots_grid.add_child(_make_hero_equipment_slot_button(hero_data, slot_key))


func _build_unavailable_state() -> void:
	var message := UIScreenHelpers.make_label("That hero is no longer available in the roster.", 18)
	_tab_body.add_child(message)
	_tab_body.add_child(UIScreenHelpers.make_small_nav_button("Back To Heroes", Callable(self, "_on_back_pressed")))


func _build_context_panel(hero_data: Dictionary) -> void:
	_equipment_slots_grid = null
	_browser_root = null
	_equipment_list_scroll = null
	_hover_popup = null
	_hover_popup_body = null
	_equipment_dialog = null
	_equipment_tiles.clear()
	if _hero_detail_tab == HERO_TAB_EQUIPMENT and not _selected_slot.is_empty():
		_build_equipment_browser(hero_data)
		return
	_build_portrait_panel(hero_data)


func _build_portrait_panel(hero_data: Dictionary) -> void:
	var portrait_texture := TextureRect.new()
	portrait_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_texture.offset_left = 0.0
	portrait_texture.offset_top = 0.0
	portrait_texture.offset_right = 0.0
	portrait_texture.offset_bottom = 0.0
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.texture = UIScreenHelpers.load_hero_texture(hero_data)
	portrait_texture.self_modulate = Color(1, 1, 1, 1)
	_context_panel.add_child(portrait_texture)


func _build_tab_content(container: VBoxContainer, hero_data: Dictionary) -> void:
	match _hero_detail_tab:
		HERO_TAB_EQUIPMENT:
			var title := UIScreenHelpers.make_label("Equipment", 21)
			container.add_child(title)
			var slot_host := Control.new()
			slot_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var available_height := maxf(0.0, _tab_scroll.size.y - title.get_combined_minimum_size().y - float(container.get_theme_constant("separation")))
			slot_host.custom_minimum_size = Vector2(0, available_height)
			container.add_child(slot_host)
			var grid := GridContainer.new()
			grid.columns = EQUIPMENT_SLOT_COLUMNS
			grid.set_anchors_preset(Control.PRESET_FULL_RECT)
			grid.offset_left = 0.0
			grid.offset_top = 0.0
			grid.offset_right = 0.0
			grid.offset_bottom = 0.0
			grid.add_theme_constant_override("h_separation", EQUIPMENT_SLOT_GAP)
			grid.add_theme_constant_override("v_separation", EQUIPMENT_SLOT_GAP)
			_equipment_slots_grid = grid
			slot_host.add_child(grid)
			for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
				grid.add_child(_make_hero_equipment_slot_button(hero_data, slot_key))
		HERO_TAB_SKILLS:
			container.add_child(UIScreenHelpers.make_label("Skills", 21))
			container.add_child(UIScreenHelpers.make_label("Active and passive abilities will be shown here in a future pass.", 16))
			container.add_child(UIScreenHelpers.make_label("No learned skills yet.", 16))
		HERO_TAB_LORE:
			container.add_child(UIScreenHelpers.make_label("Lore", 21))
			var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
			container.add_child(UIScreenHelpers.make_label(String(hero_definition.get("description", "No lore recorded.")), 17))
			container.add_child(Control.new())
			if _dismiss_confirm_uid == int(hero_data.get("uid", -1)):
				var warning := UIScreenHelpers.make_label("Dismiss this hero permanently? Assignments, world tasks, and equipment links will be cleared.", 15)
				warning.add_theme_color_override("font_color", Color("e8b0a7"))
				container.add_child(warning)
				var confirm_row := HBoxContainer.new()
				confirm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				confirm_row.add_theme_constant_override("separation", 10)
				container.add_child(confirm_row)
				confirm_row.add_child(UIScreenHelpers.make_small_action_button("Cancel", Callable(self, "_cancel_hero_dismiss")))
				confirm_row.add_child(UIScreenHelpers.make_danger_button("Confirm Dismiss", Callable(self, "_confirm_hero_dismiss").bind(int(hero_data.get("uid", -1)))))
			else:
				container.add_child(UIScreenHelpers.make_danger_button("Dismiss", Callable(self, "_prompt_hero_dismiss").bind(int(hero_data.get("uid", -1)))))
		_:
			var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
			var assigned_slot: int = int(hero_data.get("assigned_slot", -1))
			var assignment_name := "Unassigned"
			if assigned_slot >= 0:
				var building_definition: Dictionary = GameManager.get_slot_building_definition(assigned_slot)
				assignment_name = String(building_definition.get("name", "Assigned"))
			var combat_stats: Dictionary = GameManager.get_hero_effective_stats(int(hero_data.get("uid", -1)))
			var work_stats: Dictionary = GameManager.get_hero_effective_work_stats(int(hero_data.get("uid", -1)))
			if combat_stats.is_empty():
				combat_stats = UIScreenHelpers.as_dictionary(hero_data.get("stats", hero_definition.get("stats", {})))
			if work_stats.is_empty():
				work_stats = UIScreenHelpers.as_dictionary(hero_data.get("work_stats", hero_definition.get("work_stats", {})))
			container.add_child(HeroDetailViewBuilders.make_hero_info_section(
				"Hero Record",
				[
					{"label": "Name", "value": String(hero_data.get("name", hero_definition.get("name", "Unknown Hero")))},
					{"label": "Class", "value": String(hero_data.get("class", hero_definition.get("class", "Hero")))} ,
					{"label": "Level", "value": str(int(hero_data.get("level", 1)))},
					{"label": "Experience", "value": "%d/%d" % [int(hero_data.get("experience", 0)), GameManager.get_hero_experience_ceiling(int(hero_data.get("uid", -1)))]},
					{"label": "Assignment", "value": assignment_name},
					{"label": "Source", "value": _hero_source_text(hero_data)},
				],
				Color("d0a170")
			))
			container.add_child(HeroDetailViewBuilders.make_hero_info_section(
				"Combat Stats",
				[
					{"label": "Health", "value": "%d/%d" % [int(combat_stats.get("current_health", combat_stats.get("health", 0))), int(combat_stats.get("max_health", combat_stats.get("health", 0)))], "color": Color("d8847b")},
					{"label": "Sanity", "value": "%d/%d" % [int(combat_stats.get("current_sanity", combat_stats.get("sanity", 0))), int(combat_stats.get("max_sanity", combat_stats.get("sanity", 0)))], "color": Color("c8b8d9")},
					{"label": "Attack", "value": str(int(combat_stats.get("attack", 0))), "color": Color("d0a170")},
					{"label": "Defense", "value": str(int(combat_stats.get("defense", 0))), "color": Color("88a8c8")},
					{"label": "Crit Chance", "value": str(int(combat_stats.get("critical_chance", 0))), "color": Color("f0c96c")},
					{"label": "Crit Damage", "value": str(int(combat_stats.get("critical_damage", 0))), "color": Color("e5b86f")},
				],
				Color("b76558")
			))
			container.add_child(HeroDetailViewBuilders.make_hero_info_section(
				"Work Stats",
				[
					{"label": "Farming", "value": str(int(work_stats.get("farming", 0)))},
					{"label": "Mining", "value": str(int(work_stats.get("mining", 0)))},
					{"label": "Lumbering", "value": str(int(work_stats.get("lumbering", 0)))},
				],
				Color("7f9f84")
			))


func _build_equipment_browser(hero_data: Dictionary) -> void:
	var slot_key := _selected_slot
	var equipment_entries := _get_inventory_equipment_entries_for_slot(slot_key)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_context_panel.add_child(body)
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 10)
	body.add_child(header_row)
	var title := UIScreenHelpers.make_label("%s Loadout" % _equipment_slot_label(slot_key), 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(UIScreenHelpers.make_small_nav_button("Portrait", Callable(self, "_close_equipment_browser")))
	var browser_panel := UIScreenHelpers.make_panel()
	browser_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(browser_panel)
	var browser_root := Control.new()
	browser_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	browser_root.offset_left = 0.0
	browser_root.offset_top = 0.0
	browser_root.offset_right = 0.0
	browser_root.offset_bottom = 0.0
	browser_panel.add_child(browser_root)
	_browser_root = browser_root
	var browser_body := VBoxContainer.new()
	browser_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	browser_body.offset_left = 0.0
	browser_body.offset_top = 0.0
	browser_body.offset_right = 0.0
	browser_body.offset_bottom = 0.0
	browser_body.add_theme_constant_override("separation", 10)
	browser_root.add_child(browser_body)
	browser_body.add_child(UIScreenHelpers.make_label("Available Equipment", 18))
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	browser_body.add_child(list_scroll)
	_equipment_list_scroll = list_scroll
	call_deferred("_restore_browser_scroll")
	if equipment_entries.is_empty():
		var empty_state := CenterContainer.new()
		empty_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.add_child(empty_state)
		var empty_label := UIScreenHelpers.make_label("No inventory equipment matches this slot.", 15)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		empty_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color("cbbba9"))
		empty_state.add_child(empty_label)
	else:
		var list_body := GridContainer.new()
		list_body.columns = 3
		list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_body.add_theme_constant_override("h_separation", 8)
		list_body.add_theme_constant_override("v_separation", 8)
		list_scroll.add_child(list_body)
		for equipment_entry in equipment_entries:
			var entry := UIScreenHelpers.as_dictionary(equipment_entry)
			var tile := _make_equipment_browser_tile(entry)
			_equipment_tiles[int(entry.get("uid", -1))] = tile
			list_body.add_child(tile)
	var hover_popup := Panel.new()
	hover_popup.visible = false
	hover_popup.top_level = true
	hover_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_popup.custom_minimum_size = Vector2(220, 210)
	hover_popup.size = Vector2(220, 210)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("0f0c0d", 0.96)
	hover_style.border_color = Color("8b6d57")
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(8)
	hover_popup.add_theme_stylebox_override("panel", hover_style)
	_context_panel.add_child(hover_popup)
	var hover_margin := MarginContainer.new()
	hover_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	hover_margin.offset_left = 10.0
	hover_margin.offset_top = 10.0
	hover_margin.offset_right = -10.0
	hover_margin.offset_bottom = -10.0
	hover_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_popup.add_child(hover_margin)
	var hover_body := VBoxContainer.new()
	hover_body.add_theme_constant_override("separation", 6)
	hover_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_margin.add_child(hover_body)
	_hover_popup = hover_popup
	_hover_popup_body = hover_body
	var selected_entry := _get_inventory_equipment_entry(_selected_equipment_uid)
	if selected_entry.is_empty():
		return
	_equipment_dialog = _make_equipment_detail_dialog(hero_data, slot_key, selected_entry)
	_browser_root.add_child(_equipment_dialog)


func _make_equipment_detail_dialog(hero_data: Dictionary, slot_key: String, equipment_entry: Dictionary) -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	overlay.color = Color(0, 0, 0, 0.42)
	var dialog := PanelContainer.new()
	dialog.anchor_left = 0.08
	dialog.anchor_top = 0.12
	dialog.anchor_right = 0.92
	dialog.anchor_bottom = 0.88
	dialog.offset_left = 0.0
	dialog.offset_top = 0.0
	dialog.offset_right = 0.0
	dialog.offset_bottom = 0.0
	UIScreenHelpers.style_panel(dialog, Color("151113"), Color("8b6d57"), 10)
	overlay.add_child(dialog)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	dialog.add_child(body)
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	body.add_child(header_row)
	var definition := DataLoader.get_equipment_definition(String(equipment_entry.get("definition_id", "")))
	var title := UIScreenHelpers.make_label(String(definition.get("name", "Unknown Equipment")), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(UIScreenHelpers.make_small_nav_button("Close", Callable(self, "_close_equipment_dialog")))
	var status_label := UIScreenHelpers.make_label(_equipment_owner_text(equipment_entry), 14)
	status_label.add_theme_color_override("font_color", Color("c9d5e8"))
	body.add_child(status_label)
	body.add_child(HeroDetailViewBuilders.make_bonus_section("Combat Bonuses", UIScreenHelpers.as_dictionary(UIScreenHelpers.as_dictionary(definition.get("bonuses", {})).get("stats", {})), Color("c77265")))
	body.add_child(HeroDetailViewBuilders.make_bonus_section("Work Bonuses", UIScreenHelpers.as_dictionary(UIScreenHelpers.as_dictionary(definition.get("bonuses", {})).get("work_stats", {})), Color("7fa283")))
	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	var equip_disabled := _is_selected_equipment_already_equipped(equipment_entry, int(hero_data.get("uid", -1)), slot_key)
	action_row.add_child(UIScreenHelpers.make_button("Equip", Callable(self, "_equip_selected_equipment"), equip_disabled))
	if _hero_slot_equipment_uid(hero_data, slot_key) > 0:
		action_row.add_child(UIScreenHelpers.make_button("Unequip", Callable(self, "_unequip_selected_hero_slot"), false))
	return overlay


func _make_equipment_browser_tile(equipment_entry: Dictionary) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(112, 112)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_equipment_browser_tile(tile, equipment_entry)
	return tile


func _populate_equipment_browser_tile(tile: PanelContainer, equipment_entry: Dictionary) -> void:
	var definition := DataLoader.get_equipment_definition(String(equipment_entry.get("definition_id", "")))
	var label_text := String(definition.get("name", "Unknown Equipment"))
	var detail_text := _equipment_owner_short_text(equipment_entry)
	_clear_container_immediately(tile)
	UIScreenHelpers.style_panel(tile, Color("141113"), Color("d0a170") if int(equipment_entry.get("uid", -1)) == _selected_equipment_uid else Color("8d8478"), 10)
	UIScreenHelpers.build_inventory_tile_content(tile, definition, detail_text, Color("b8c3d9"), Color("efe7db"), 44, 13, 12, label_text)
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.offset_left = 0.0
	button.offset_top = 0.0
	button.offset_right = 0.0
	button.offset_bottom = 0.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10))
	button.add_theme_stylebox_override("hover", _button_style(Color(1, 1, 1, 0.03), Color("d0a170"), 10))
	button.add_theme_stylebox_override("pressed", _button_style(Color(1, 1, 1, 0.05), Color("d0a170"), 10))
	button.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0), Color("d0a170"), 10))
	button.pressed.connect(Callable(self, "_select_equipment_entry").bind(int(equipment_entry.get("uid", -1))))
	button.mouse_entered.connect(Callable(self, "_show_equipment_hover_popup").bind(int(equipment_entry.get("uid", -1))))
	button.mouse_exited.connect(Callable(self, "_hide_equipment_hover_popup"))
	tile.add_child(button)
	if int(equipment_entry.get("uid", -1)) == _selected_equipment_uid:
		button.add_theme_stylebox_override("normal", _button_style(Color(1, 1, 1, 0.04), Color("d0a170"), 10))


func _make_hero_equipment_slot_button(hero_data: Dictionary, slot_key: String) -> Control:
	var current_uid := _hero_slot_equipment_uid(hero_data, slot_key)
	var current_entry: Dictionary = {}
	var current_definition: Dictionary = {}
	var occupied := current_uid > 0
	if current_uid > 0:
		current_entry = _get_inventory_equipment_entry(current_uid)
		if not current_entry.is_empty():
			current_definition = DataLoader.get_equipment_definition(String(current_entry.get("definition_id", "")))
			occupied = not current_definition.is_empty()
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIScreenHelpers.style_panel(tile, Color("171315") if occupied else Color("100d0f"), Color("d0a170") if _selected_slot == slot_key else (Color("8b6d57") if occupied else Color("675042")), 8)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(body)
	var slot_label := UIScreenHelpers.make_label(_equipment_slot_label(slot_key), 13)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_color_override("font_color", Color("d8c4ae") if occupied else Color("b7a291"))
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(slot_label)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(center)
	if occupied:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = UIScreenHelpers.load_texture_from_path(String(current_definition.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
		if icon.texture == null:
			icon.texture = UIScreenHelpers.load_texture_from_path(DataLoader.DEFAULT_CATALOG_ICON)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon)
		var name_label := UIScreenHelpers.make_label(String(current_definition.get("name", "Occupied")), 12)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", Color("efe7db"))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(name_label)
	else:
		var empty_label := UIScreenHelpers.make_label("Empty", 15)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		empty_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color("8f8178"))
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(empty_label)
		var hint_label := UIScreenHelpers.make_label("No gear", 11)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		hint_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_label.add_theme_color_override("font_color", Color("756962"))
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(hint_label)
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.offset_left = 0.0
	button.offset_top = 0.0
	button.offset_right = 0.0
	button.offset_bottom = 0.0
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8))
	button.add_theme_stylebox_override("hover", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8))
	button.pressed.connect(Callable(self, "_select_hero_equipment_slot").bind(slot_key))
	tile.add_child(button)
	return tile


func _make_hero_tab_button(tab_id: String) -> Button:
	var button := UIScreenHelpers.make_button(tab_id.capitalize(), Callable(self, "_set_hero_detail_tab").bind(tab_id), false)
	if tab_id == _hero_detail_tab:
		button.add_theme_stylebox_override("normal", _button_style(Color("3a2b25"), Color("d0a170"), 7))
		button.add_theme_stylebox_override("hover", _button_style(Color("3a2b25"), Color("d0a170"), 7))
		button.add_theme_stylebox_override("pressed", _button_style(Color("3a2b25"), Color("d0a170"), 7))
	return button


func _set_hero_detail_tab(tab_id: String) -> void:
	_hero_detail_tab = tab_id
	_dismiss_confirm_uid = -1
	if tab_id != HERO_TAB_EQUIPMENT:
		_selected_slot = ""
		_selected_equipment_uid = -1
	refresh()


func _prompt_hero_dismiss(hero_uid: int) -> void:
	_dismiss_confirm_uid = hero_uid
	refresh()


func _cancel_hero_dismiss() -> void:
	_dismiss_confirm_uid = -1
	refresh()


func _confirm_hero_dismiss(hero_uid: int) -> void:
	_dismiss_confirm_uid = -1
	if GameManager.dismiss_hero(hero_uid):
		emit_signal("back_requested")


func _select_hero_equipment_slot(slot_key: String) -> void:
	_browser_scroll_value = 0
	_selected_slot = slot_key
	_selected_equipment_uid = -1
	_hide_equipment_hover_popup()
	refresh()


func _select_equipment_entry(equipment_uid: int) -> void:
	_remember_browser_scroll()
	_selected_equipment_uid = equipment_uid
	_hide_equipment_hover_popup()
	if _browser_root == null or not is_instance_valid(_browser_root):
		refresh()
		return
	if _equipment_dialog != null and is_instance_valid(_equipment_dialog):
		_equipment_dialog.queue_free()
	var hero_data := _get_selected_hero()
	if hero_data.is_empty() or _selected_slot.is_empty():
		return
	var selected_entry := _get_inventory_equipment_entry(_selected_equipment_uid)
	if selected_entry.is_empty():
		return
	_equipment_dialog = _make_equipment_detail_dialog(hero_data, _selected_slot, selected_entry)
	_browser_root.add_child(_equipment_dialog)


func _close_equipment_browser() -> void:
	_browser_scroll_value = 0
	_selected_slot = ""
	_selected_equipment_uid = -1
	_hide_equipment_hover_popup()
	refresh()


func _close_equipment_dialog() -> void:
	_remember_browser_scroll()
	_selected_equipment_uid = -1
	if _equipment_dialog != null and is_instance_valid(_equipment_dialog):
		_equipment_dialog.queue_free()
	_equipment_dialog = null


func _equip_selected_equipment() -> void:
	if _selected_slot.is_empty() or _selected_equipment_uid <= 0:
		return
	_remember_browser_scroll()
	GameManager.equip_equipment_to_hero(_selected_hero_uid, _selected_slot, _selected_equipment_uid)


func _unequip_selected_hero_slot() -> void:
	if _selected_slot.is_empty():
		return
	_remember_browser_scroll()
	GameManager.unequip_hero_slot(_selected_hero_uid, _selected_slot)


func _show_equipment_hover_popup(equipment_uid: int) -> void:
	if _hover_popup == null or not is_instance_valid(_hover_popup) or _hover_popup_body == null or not is_instance_valid(_hover_popup_body):
		return
	var equipment_entry := _get_inventory_equipment_entry(equipment_uid)
	if equipment_entry.is_empty():
		return
	UIScreenHelpers.clear_container(_hover_popup_body)
	var definition := DataLoader.get_equipment_definition(String(equipment_entry.get("definition_id", "")))
	var title := HeroDetailViewBuilders.make_tooltip_label(String(definition.get("name", "Unknown Equipment")), 16, Color("fff4e4"), true)
	_hover_popup_body.add_child(title)
	var combat_values := UIScreenHelpers.as_dictionary(UIScreenHelpers.as_dictionary(definition.get("bonuses", {})).get("stats", {}))
	var work_values := UIScreenHelpers.as_dictionary(UIScreenHelpers.as_dictionary(definition.get("bonuses", {})).get("work_stats", {}))
	_hover_popup_body.add_child(HeroDetailViewBuilders.make_tooltip_bonus_section("Combat", combat_values, Color("c77265")))
	_hover_popup_body.add_child(HeroDetailViewBuilders.make_tooltip_bonus_section("Work", work_values, Color("7fa283")))
	_set_mouse_filter_recursive(_hover_popup, Control.MOUSE_FILTER_IGNORE)
	_hover_popup_body.update_minimum_size()
	var popup_size := _get_equipment_hover_popup_size()
	_hover_popup.custom_minimum_size = popup_size
	_hover_popup.size = popup_size
	_position_equipment_hover_popup()
	_hover_popup.visible = true


func _hide_equipment_hover_popup() -> void:
	if _hover_popup == null or not is_instance_valid(_hover_popup):
		return
	_hover_popup.visible = false


func _position_equipment_hover_popup() -> void:
	if _hover_popup == null or not is_instance_valid(_hover_popup):
		return
	var panel_rect := _context_panel.get_global_rect()
	var mouse_pos: Vector2 = _context_panel.get_viewport().get_mouse_position()
	var popup_size := _hover_popup.size
	if popup_size == Vector2.ZERO:
		popup_size = _get_equipment_hover_popup_size()
	var desired_pos := mouse_pos + Vector2(14, 14)
	if desired_pos.x + popup_size.x > panel_rect.position.x + panel_rect.size.x - 8.0:
		desired_pos.x = mouse_pos.x - popup_size.x - 14.0
	if desired_pos.y + popup_size.y > panel_rect.position.y + panel_rect.size.y - 8.0:
		desired_pos.y = panel_rect.position.y + panel_rect.size.y - popup_size.y - 8.0
	desired_pos.x = clampf(desired_pos.x, panel_rect.position.x + 8.0, max(panel_rect.position.x + 8.0, panel_rect.position.x + panel_rect.size.x - popup_size.x - 8.0))
	desired_pos.y = clampf(desired_pos.y, panel_rect.position.y + 8.0, max(panel_rect.position.y + 8.0, panel_rect.position.y + panel_rect.size.y - popup_size.y - 8.0))
	_hover_popup.global_position = desired_pos
	_hover_popup.size = popup_size


func _get_equipment_hover_popup_size() -> Vector2:
	if _hover_popup_body == null or not is_instance_valid(_hover_popup_body):
		return Vector2(280, 180)
	var content_size := _hover_popup_body.get_combined_minimum_size()
	var width := clampf(content_size.x + 20.0, 280.0, 420.0)
	var height := clampf(content_size.y + 20.0, 140.0, 360.0)
	return Vector2(width, height)


func _remember_browser_scroll() -> void:
	if _equipment_list_scroll == null or not is_instance_valid(_equipment_list_scroll):
		return
	_browser_scroll_value = _equipment_list_scroll.scroll_vertical


func _restore_browser_scroll() -> void:
	if _equipment_list_scroll == null or not is_instance_valid(_equipment_list_scroll):
		return
	_equipment_list_scroll.scroll_vertical = _browser_scroll_value


func _get_selected_hero() -> Dictionary:
	for hero_data in _heroes_snapshot:
		var hero := UIScreenHelpers.as_dictionary(hero_data)
		if int(hero.get("uid", -1)) == _selected_hero_uid:
			return hero.duplicate(true)
	return {}


func _hero_source_text(hero_data: Dictionary) -> String:
	var source := String(hero_data.get("source", "core"))
	if source == "mod":
		var mod_id := String(hero_data.get("mod_id", "")).strip_edges()
		return "Mod: %s" % (mod_id if not mod_id.is_empty() else "Unknown")
	return "Core"


func _hero_slot_equipment_uid(hero_data: Dictionary, slot_key: String) -> int:
	return int(String(UIScreenHelpers.as_dictionary(hero_data.get("equipment", {})).get(slot_key, "")).strip_edges())


func _get_inventory_equipment_entries_for_slot(slot_key: String) -> Array:
	var entries: Array = []
	for equipment_entry in UIScreenHelpers.as_array(_inventory_snapshot.get("equipment", [])):
		if equipment_entry is not Dictionary:
			continue
		var definition := DataLoader.get_equipment_definition(String((equipment_entry as Dictionary).get("definition_id", "")))
		if String(definition.get("slot", "")) == slot_key:
			entries.append((equipment_entry as Dictionary).duplicate(true))
	return entries


func _get_inventory_equipment_entry(equipment_uid: int) -> Dictionary:
	for equipment_entry in UIScreenHelpers.as_array(_inventory_snapshot.get("equipment", [])):
		if equipment_entry is Dictionary and int((equipment_entry as Dictionary).get("uid", -1)) == equipment_uid:
			return (equipment_entry as Dictionary).duplicate(true)
	return {}


func _hero_name_by_uid(hero_uid: int) -> String:
	for hero_data in _heroes_snapshot:
		var hero := UIScreenHelpers.as_dictionary(hero_data)
		if int(hero.get("uid", -1)) == hero_uid:
			return String(hero.get("name", "Unknown Hero"))
	return "Unknown Hero"


func _equipment_owner_text(equipment_entry: Dictionary) -> String:
	var owner_uid := int(equipment_entry.get("equipped_hero_uid", -1))
	if owner_uid <= 0:
		return "Stored in inventory."
	return _hero_name_by_uid(owner_uid)


func _equipment_owner_short_text(equipment_entry: Dictionary) -> String:
	var owner_uid := int(equipment_entry.get("equipped_hero_uid", -1))
	return "Equipped" if owner_uid > 0 else ""


func _is_selected_equipment_already_equipped(equipment_entry: Dictionary, hero_uid: int, slot_key: String) -> bool:
	return int(equipment_entry.get("equipped_hero_uid", -1)) == hero_uid and String(equipment_entry.get("equipped_slot", "")) == slot_key


func _equipment_slot_label(slot_key: String) -> String:
	return UIScreenHelpers.equipment_slot_label(slot_key)


func _set_mouse_filter_recursive(node: Node, filter_mode: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter_mode
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter_mode)


func _on_back_pressed() -> void:
	emit_signal("back_requested")


func _reset_local_state() -> void:
	_hero_detail_tab = HERO_TAB_INFO
	_selected_slot = ""
	_selected_equipment_uid = -1
	_browser_root = null
	_equipment_list_scroll = null
	_browser_scroll_value = 0
	_hover_popup = null
	_hover_popup_body = null
	_equipment_dialog = null
	_equipment_slots_grid = null
	_dismiss_confirm_uid = -1
	_equipment_tiles.clear()


func _style_shell() -> void:
	UIScreenHelpers.style_panel(_context_panel, Color("161214"), Color("675042"), 10)
	UIScreenHelpers.style_panel(_name_bar, Color("1d1719"), Color("7c5f4d"), 10)
	UIScreenHelpers.style_panel(_tab_panel, Color("181416"), Color("675042"), 10)
	UIScreenHelpers.style_label(_hero_name_label, 28, true)
	UIScreenHelpers.style_button(_back_button)


func _clear_container_immediately(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _button_style(bg_color: Color, border_color: Color, corner_radius: int) -> StyleBoxFlat:
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
