extends Control

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const ResourceBadgeScene = preload("res://scenes/widgets/resource_badge.tscn")
const SettlementSlotScene = preload("res://scenes/widgets/settlement_slot.tscn")
const HeroCardScene = preload("res://scenes/widgets/hero_card.tscn")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const UITheme = preload("res://resources/themes/ui_theme.tres")

const RESOURCE_ICONS := {
	"wood": "res://assets/resources/wood.png",
	"food": "res://assets/resources/food.png",
	"stone": "res://assets/resources/metal.png",
	"gold": "res://assets/resources/coins.png",
	"heroes": "res://assets/resources/population.png",
	"gems": "res://assets/resources/gems.png",
	"crystals": "res://assets/resources/crystals.png",
}

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

@onready var _resources_row: HBoxContainer = get_node("Shell/TopBar/TopBarMargin/ResourcesRow")
@onready var _top_bar: PanelContainer = get_node("Shell/TopBar")
@onready var _settlement_title: Label = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/Title")
@onready var _settlement_scroll: ScrollContainer = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/SettlementScroll")
@onready var _grid_container: GridContainer = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/SettlementScroll/Grid")
@onready var _details_panel: PanelContainer = get_node("Shell/MainRow/DetailsPanel")
@onready var _detail_content: VBoxContainer = get_node("Shell/MainRow/DetailsPanel/DetailsMargin/DetailScroll/DetailContent")
@onready var _page_root: VBoxContainer = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/PageRoot")
@onready var _page_title: Label = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/PageRoot/PageTitle")
@onready var _page_scroll: ScrollContainer = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/PageRoot/PageScroll")
@onready var _page_content: VBoxContainer = get_node("Shell/MainRow/SettlementPanel/SettlementMargin/SettlementColumn/PageRoot/PageScroll/PageContent")

var _resource_badges: Dictionary = {}
var _slot_widgets: Array = []
var _selected_slot: int = -1
var _detail_mode: String = "overview"
var _selected_hero_uid: int = -1
var _hero_detail_tab: String = "info"
var _hero_detail_selected_slot: String = ""
var _hero_detail_selected_equipment_uid: int = -1
var _hero_detail_context_panel: PanelContainer = null
var _hero_detail_browser_root: Control = null
var _hero_detail_equipment_list_scroll: ScrollContainer = null
var _hero_detail_browser_scroll_value: int = 0
var _hero_detail_hover_popup: Control = null
var _hero_detail_hover_popup_body: VBoxContainer = null
var _hero_detail_equipment_dialog: Control = null
var _hero_detail_equipment_slots_grid: GridContainer = null
var _hero_detail_equipment_tiles: Dictionary = {}
var _save_slot_labels: Dictionary = {}
var _save_slot_name_inputs: Dictionary = {}
var _save_slot_load_buttons: Dictionary = {}
var _slots_snapshot: Array = []
var _heroes_snapshot: Array = []
var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}
var _resource_values: Dictionary = {}
var _resource_yields: Dictionary = {}


func _ready() -> void:
	theme = UITheme
	_configure_root_layout()
	_apply_theme()
	_apply_ui_text_bundle()
	_wire_navigation()
	_build_resource_bar()
	_build_grid()
	_connect_game_manager()
	_refresh_settlement_title()
	_apply_mode_layout()
	if not GameManager.load_game(1):
		GameManager.emit_state()
	else:
		_selected_slot = GameManager.selected_slot


func _configure_root_layout() -> void:
	custom_minimum_size = Vector2.ZERO
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var window: Window = get_window()
	if window != null:
		window.min_size = Vector2i(1152, 648)
	var background: TextureRect = get_node("Background")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 0.0
	background.offset_top = 0.0
	background.offset_right = 0.0
	background.offset_bottom = 0.0
	background.custom_minimum_size = Vector2.ZERO
	background.texture = null
	background.visible = false
	var shell: Control = get_node("Shell")
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 0.0
	shell.offset_top = 0.0
	shell.offset_right = 0.0
	shell.offset_bottom = 0.0
	var settlement_panel: Control = get_node("Shell/MainRow/SettlementPanel")
	settlement_panel.size_flags_stretch_ratio = 1.6
	var details_panel: Control = get_node("Shell/MainRow/DetailsPanel")
	details_panel.size_flags_stretch_ratio = 1.0


func _apply_theme() -> void:
	var chrome_nodes: Array = [
		get_node("Shell/TopBar"),
		get_node("Shell/MainRow/SettlementPanel"),
		get_node("Shell/MainRow/DetailsPanel"),
		get_node("Shell/BottomBar"),
	]
	for chrome in chrome_nodes:
		_style_panel(chrome, Color("211a1c"), Color("7a5e4b"), 10)
	var bottom_buttons: Array = [
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/WorldButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/OverviewButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/HeroesButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/InventoryButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/DebugButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/SavesButton"),
		get_node("Shell/BottomBar/BottomBarMargin/NavRow/BackButton"),
	]
	for button in bottom_buttons:
		_style_button(button)
	_style_label(_settlement_title, 24, true)
	_style_label(_page_title, 24, true)
	_settlement_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _apply_ui_text_bundle() -> void:
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/WorldButton").text = _txt("nav.world")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/OverviewButton").text = _txt("nav.settlements")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/HeroesButton").text = _txt("nav.heroes")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/InventoryButton").text = _txt("nav.inventory")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/DebugButton").text = _txt("nav.debug")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/SavesButton").text = _txt("nav.saves")
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/BackButton").text = _txt("nav.home")


func _wire_navigation() -> void:
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/WorldButton").pressed.connect(Callable(self, "_set_detail_mode").bind("world"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/OverviewButton").pressed.connect(Callable(self, "_set_detail_mode").bind("overview"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/HeroesButton").pressed.connect(Callable(self, "_set_detail_mode").bind("heroes"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/InventoryButton").pressed.connect(Callable(self, "_set_detail_mode").bind("inventory"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/DebugButton").pressed.connect(Callable(self, "_set_detail_mode").bind("debug"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/SavesButton").pressed.connect(Callable(self, "_set_detail_mode").bind("saves"))
	get_node("Shell/BottomBar/BottomBarMargin/NavRow/BackButton").pressed.connect(_on_back_pressed)


func _connect_game_manager() -> void:
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.settlement_changed.connect(_on_settlement_changed)
	GameManager.active_settlement_changed.connect(_on_active_settlement_changed)
	GameManager.heroes_changed.connect(_on_heroes_changed)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.selection_changed.connect(_on_selection_changed)
	GameManager.save_slots_changed.connect(_on_save_slots_changed)
	GameManager.tick_processed.connect(_on_tick_processed)


func _build_resource_bar() -> void:
	_clear_container(_resources_row)
	_resource_badges.clear()
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		var badge: PanelContainer = ResourceBadgeScene.instantiate()
		_resources_row.add_child(badge)
		_resource_badges[resource_id] = badge
	_resource_values = {}
	_resource_yields = {}
	_refresh_resource_badges()


func _build_grid() -> void:
	_clear_container(_grid_container)
	_slot_widgets.clear()
	for slot_index in SettlementGameData.GRID_SIZE:
		var slot_button: Button = SettlementSlotScene.instantiate()
		slot_button.slot_index = slot_index
		slot_button.slot_selected.connect(_on_slot_selected)
		_grid_container.add_child(slot_button)
		_slot_widgets.append(slot_button)


func _set_detail_mode(mode: String) -> void:
	if mode != "settlement" and _selected_slot != -1:
		_selected_slot = -1
		GameManager.select_slot(-1)
	_detail_mode = mode
	_apply_mode_layout()
	_refresh_active_content()


func _on_back_pressed() -> void:
	_selected_slot = -1
	GameManager.select_slot(-1)
	_detail_mode = "world"
	_apply_mode_layout()
	_refresh_grid()
	_refresh_active_content()


func _on_slot_selected(slot_index: int) -> void:
	_detail_mode = "settlement"
	_apply_mode_layout()
	GameManager.select_slot(slot_index)


func _on_resources_changed(resource_values: Dictionary) -> void:
	_resource_values = resource_values.duplicate(true)
	_refresh_resource_badges()


func _on_settlement_changed(slots: Array) -> void:
	_slots_snapshot = slots
	_refresh_settlement_title()
	_refresh_resource_yields()
	_refresh_grid()
	_refresh_active_content()


func _on_active_settlement_changed(_settlement_id: String) -> void:
	_refresh_settlement_title()


func _on_heroes_changed(heroes: Array) -> void:
	_heroes_snapshot = heroes
	_resource_values["heroes"] = heroes.size()
	_refresh_resource_badges()
	_refresh_resource_yields()
	if _detail_mode == "world":
		return
	if _detail_mode == "hero_detail" and _hero_detail_tab == "equipment":
		_refresh_hero_detail_equipment_slots()
		return
	_refresh_active_content()


func _on_inventory_changed(inventory_state: Dictionary) -> void:
	_inventory_snapshot = inventory_state.duplicate(true)
	if _detail_mode == "inventory" or (_detail_mode == "hero_detail" and _hero_detail_tab == "equipment"):
		if _detail_mode == "hero_detail" and _hero_detail_tab == "equipment":
			_refresh_hero_detail_equipment_ui_state()
			return
		_refresh_active_content()


func _refresh_resource_yields() -> void:
	_resource_yields.clear()
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		_resource_yields[resource_id] = 0
	for slot_index in range(GameManager.slots.size()):
		var production: Dictionary = GameManager.get_slot_production_preview(slot_index)
		for resource_id in production.keys():
			_resource_yields[resource_id] = int(_resource_yields.get(resource_id, 0)) + int(production[resource_id])
	_refresh_resource_badges()


func _refresh_resource_badges() -> void:
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		if _resource_badges.has(resource_id):
			_resource_badges[resource_id].set_badge(
				resource_id,
				int(_resource_values.get(resource_id, 0)),
				int(_resource_yields.get(resource_id, 0)),
				String(RESOURCE_ICONS.get(resource_id, ""))
			)


func _on_selection_changed(slot_index: int) -> void:
	_selected_slot = slot_index
	_apply_mode_layout()
	_refresh_grid()
	_refresh_active_content()


func _on_save_slots_changed(_slots: Array) -> void:
	if _detail_mode == "saves":
		_refresh_saves_page_state(_slots)


func _on_tick_processed(_tick_count: int, _production_delta: Dictionary) -> void:
	_refresh_resource_yields()


func _refresh_grid() -> void:
	if _slots_snapshot.is_empty():
		_slots_snapshot = GameManager.get_slots_snapshot()
	for slot_index in range(_slot_widgets.size()):
		var slot_data: Dictionary = _slots_snapshot[slot_index] if slot_index < _slots_snapshot.size() else {}
		var building_definition: Dictionary = {}
		if not String(slot_data.get("building_id", "")).is_empty():
			building_definition = GameManager.get_slot_building_definition(slot_index)
		_slot_widgets[slot_index].set_view(slot_data, building_definition, slot_index == _selected_slot)


func _refresh_detail_panel() -> void:
	_clear_container(_detail_content)
	match _detail_mode:
		"settlement":
			_build_settlement_detail_panel()
		_:
			pass


func _refresh_active_content() -> void:
	if _is_full_page_mode():
		_refresh_page_content()
	else:
		_refresh_detail_panel()


func _refresh_page_content() -> void:
	if _detail_mode != "saves":
		_save_slot_labels.clear()
		_save_slot_name_inputs.clear()
		_save_slot_load_buttons.clear()
	_clear_container_immediately(_page_content)
	match _detail_mode:
		"overview":
			_build_overview_page()
		"saves":
			_build_saves_page()
		"world":
			_build_world_page()
		"heroes":
			_build_heroes_page()
		"inventory":
			_build_inventory_page()
		"hero_detail":
			_build_hero_detail_page()
		"debug":
			_build_debug_page()


func _apply_mode_layout() -> void:
	var full_page_mode: bool = _is_full_page_mode()
	_top_bar.visible = _detail_mode != "heroes" and _detail_mode != "hero_detail" and _detail_mode != "inventory"
	_details_panel.visible = _detail_mode == "settlement" and _selected_slot != -1
	_settlement_title.visible = _detail_mode == "settlement"
	_settlement_scroll.visible = _detail_mode == "settlement"
	_page_root.visible = full_page_mode
	_page_title.visible = _detail_mode != "hero_detail" and _detail_mode != "world"
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _detail_mode == "hero_detail" or _detail_mode == "world" else ScrollContainer.SCROLL_MODE_AUTO
	if _detail_mode == "hero_detail" or _detail_mode == "world":
		_page_scroll.scroll_vertical = 0
	match _detail_mode:
		"overview":
			_page_title.text = _txt("page.settlements")
		"saves":
			_page_title.text = _txt("page.save_vault")
		"world":
			_page_title.text = ""
		"heroes":
			_page_title.text = _txt("page.hero_inventory")
		"inventory":
			_page_title.text = _txt("page.inventory")
		"hero_detail":
			_page_title.text = ""
		"debug":
			_page_title.text = _txt("page.debug")
		_:
			_page_title.text = ""


func _is_full_page_mode() -> bool:
	return _detail_mode == "overview" or _detail_mode == "saves" or _detail_mode == "world" or _detail_mode == "heroes" or _detail_mode == "inventory" or _detail_mode == "hero_detail" or _detail_mode == "debug"


func _build_overview_page() -> void:
	_populate_overview_content(_page_content)


func _build_world_page() -> void:
	var world_view := WorldViewScene.instantiate()
	world_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_view.set_world_snapshot(GameManager.get_world_snapshot())
	world_view.settlement_selected.connect(_open_settlement)
	_page_content.add_child(world_view)



func _populate_overview_content(target: VBoxContainer) -> void:
	var owned_settlements: Array = GameManager.get_owned_settlement_definitions()
	if owned_settlements.is_empty():
		target.add_child(_make_label(_txt("overview.no_settlements"), 16))
	else:
		var owned_grid := GridContainer.new()
		owned_grid.columns = 4
		owned_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		owned_grid.add_theme_constant_override("h_separation", 12)
		owned_grid.add_theme_constant_override("v_separation", 12)
		target.add_child(owned_grid)
		for settlement_definition in owned_settlements:
			owned_grid.add_child(_make_overview_settlement_tile(_as_dictionary(settlement_definition)))


func _build_settlement_detail_panel() -> void:
	if _selected_slot == -1:
		return
	var slot_data: Dictionary = GameManager.get_slot(_selected_slot)
	if String(slot_data.get("building_id", "")).is_empty():
		_build_empty_plot_panel(_selected_slot)
	else:
		_build_building_panel(_selected_slot, slot_data)


func _build_empty_plot_panel(slot_index: int) -> void:
	_add_detail_header(_txt("settlement.empty_plot", {"index": slot_index + 1}))
	_add_text(_txt("settlement.choose_structure"))
	for building_definition in GameManager.get_building_catalog():
		var building_data: Dictionary = building_definition
		var build_cost: Dictionary = SettlementGameData.resource_list_to_dictionary(_as_array(building_data.get("build_cost", [])))
		var panel: PanelContainer = _make_panel()
		_detail_content.add_child(panel)
		var body: VBoxContainer = VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		panel.add_child(body)
		body.add_child(_make_label(String(building_data.get("name", "Unknown")), 18))
		body.add_child(_make_label(String(building_data.get("description", "")), 13))
		body.add_child(_make_rich_text_label("%s [color=#d7d0c6]%s[/color]" % [_txt("settlement.cost", {"cost": ""}).trim_suffix(" "), _format_resource_bbcode(build_cost, "cost")], 13))
		var disabled: bool = not GameManager.can_afford(build_cost)
		var button: Button = _make_button("Build %s" % String(building_data.get("name", "Structure")), Callable(self, "_build_selected_building").bind(slot_index, String(building_data.get("id", ""))), disabled)
		body.add_child(button)


func _build_building_panel(slot_index: int, slot_data: Dictionary) -> void:
	var building_definition: Dictionary = GameManager.get_slot_building_definition(slot_index)
	var building_name: String = String(building_definition.get("name", "Unknown Structure"))
	_add_detail_header(building_name)
	_add_text(String(building_definition.get("description", "")))
	_add_text("Level %d  |  Workers %d / %d" % [
		int(slot_data.get("level", 1)),
		_as_array(slot_data.get("assigned_hero_ids", [])).size(),
		int(building_definition.get("worker_slots", 0)),
	])
	_detail_content.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.production", {"production": ""}).trim_suffix(" "), _format_resource_bbcode(GameManager.get_slot_production_preview(slot_index), "refund")], 15))

	var upgrade_cost: Dictionary = GameManager.get_upgrade_cost(slot_index)
	var dismantle_refund: Dictionary = GameManager.get_dismantle_refund(slot_index)
	var max_level: int = int(building_definition.get("max_level", SettlementGameData.MAX_BUILDING_LEVEL))
	var at_max_level: bool = int(slot_data.get("level", 1)) >= max_level
	_detail_content.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.upgrade_cost", {"cost": ""}).trim_suffix(" "), _format_resource_bbcode(upgrade_cost, "cost")], 15))
	_add_button(
		_txt("settlement.upgrade_button"),
		Callable(self, "_upgrade_slot").bind(slot_index),
		at_max_level or not GameManager.can_afford(upgrade_cost)
	)
	_detail_content.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.dismantle_refund", {"refund": ""}).trim_suffix(" "), _format_resource_bbcode(dismantle_refund, "refund")], 15))
	_add_button(
		_txt("settlement.dismantle_button"),
		Callable(self, "_dismantle_slot").bind(slot_index),
		false
	)

	if String(building_definition.get("id", "")) == "tavern":
		var recruit_cost: Dictionary = SettlementGameData.resource_list_to_dictionary(_as_array(building_definition.get("recruit_cost", [])))
		_detail_content.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.recruit_cost", {"cost": ""}).trim_suffix(" "), _format_resource_bbcode(recruit_cost, "cost")], 15))
		_add_button(
			_txt("settlement.recruit_button"),
			Callable(self, "_recruit_from_tavern").bind(slot_index),
			not GameManager.can_afford(recruit_cost)
		)

	_add_section(_txt("settlement.assigned_heroes"))
	var assigned_any: bool = false
	for hero_data in _heroes_snapshot:
		var hero: Dictionary = hero_data
		if int(hero.get("assigned_slot", -1)) == slot_index and String(hero.get("assigned_settlement_id", "")) == GameManager.active_settlement_id:
			assigned_any = true
			_add_hero_entry(hero, true)
	if not assigned_any:
		_add_text(_txt("settlement.no_assigned_heroes"))

	_add_section(_txt("settlement.available_heroes"))
	var available_heroes: Array = GameManager.get_available_heroes_for_slot(slot_index)
	if available_heroes.is_empty():
		_add_text(_txt("settlement.no_available_heroes"))
	else:
		for hero_data in available_heroes:
			var hero: Dictionary = hero_data
			if not (int(hero.get("assigned_slot", -1)) == slot_index and String(hero.get("assigned_settlement_id", "")) == GameManager.active_settlement_id):
				_add_hero_entry(hero, false)


func _build_heroes_page() -> void:
	var intro: Label = _make_label("All recruited heroes are gathered here. Portrait art will be used automatically when available.", 16)
	_page_content.add_child(intro)
	if _heroes_snapshot.is_empty():
		_page_content.add_child(_make_label("No heroes recruited yet. Recruit one from a Tavern or use the Debug menu.", 17))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 18)
	_page_content.add_child(grid)
	for hero_data in _heroes_snapshot:
		var card: PanelContainer = HeroCardScene.instantiate()
		card.set_hero(hero_data)
		card.selected.connect(_open_hero_detail)
		grid.add_child(card)


func _open_settlement(settlement_id: String) -> void:
	if not GameManager.set_active_settlement(settlement_id):
		return
	_detail_mode = "settlement"
	_selected_slot = -1
	_apply_mode_layout()
	GameManager.select_slot(-1)
	_refresh_grid()
	_refresh_active_content()


func _make_overview_settlement_tile(settlement_definition: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(176, 214)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var settlement_id := String(settlement_definition.get("id", ""))
	var accent := Color("d0a170") if settlement_id == GameManager.active_settlement_id else Color("7a5e4b")
	_style_panel(panel, Color("141113"), accent, 10)
	var plot_counts := _get_settlement_plot_counts(settlement_id)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	var name_label := _make_label(String(settlement_definition.get("name", "Unknown Settlement")), 16)
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
	icon.texture = _load_texture_from_path(String(settlement_definition.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
	if icon.texture == null:
		icon.texture = _load_texture_from_path(DataLoader.DEFAULT_CATALOG_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(icon)
	var plots_label := _make_label(_txt("overview.plots", {"built": int(plot_counts.get("built", 0)), "total": SettlementGameData.GRID_SIZE}), 13)
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
	button.pressed.connect(Callable(self, "_open_settlement").bind(settlement_id))
	panel.add_child(button)
	return panel


func _get_settlement_plot_counts(settlement_id: String) -> Dictionary:
	var built_slots: int = GameManager.get_settlement_built_plot_count(settlement_id)
	return {
		"built": built_slots,
		"available": max(SettlementGameData.GRID_SIZE - built_slots, 0),
	}


func _build_inventory_page() -> void:
	var items: Array = _as_array(_inventory_snapshot.get("items", []))
	var equipment: Array = _as_array(_inventory_snapshot.get("equipment", []))
	_page_content.add_child(_make_label("Recovered supplies, relics, and equipment are stored here for later use.", 16))
	_page_content.add_child(_make_label("Item Stacks %d  |  Equipment %d" % [items.size(), equipment.size()], 16))
	var entries := _build_inventory_entries(items, equipment)
	if entries.is_empty():
		_page_content.add_child(_make_label("No inventory has been recovered yet.", 18))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_page_content.add_child(grid)
	for entry in entries:
		grid.add_child(_make_inventory_slot(entry))


func _build_inventory_entries(items: Array, equipment: Array) -> Array:
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
		var definition: Dictionary = DataLoader.get_equipment_definition(String((equipment_entry as Dictionary).get("definition_id", "")))
		if definition.is_empty():
			continue
		entries.append({
			"kind": "equipment",
			"definition": definition,
			"uid": int((equipment_entry as Dictionary).get("uid", -1)),
			"equipped_hero_uid": int((equipment_entry as Dictionary).get("equipped_hero_uid", -1)),
		})
	return entries


func _make_inventory_slot(entry: Dictionary) -> PanelContainer:
	var kind := String(entry.get("kind", "item"))
	var definition := _as_dictionary(entry.get("definition", {}))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(148, 148)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent_color := Color("7a5e4b") if kind == "item" else Color("8d8478")
	_style_panel(panel, Color("141113"), accent_color, 10)
	var footer_text := "x%d" % int(entry.get("quantity", 0)) if kind == "item" else _inventory_equipment_footer(entry, definition)
	_build_inventory_tile_content(panel, definition, footer_text, Color("d9cbb7") if kind == "item" else Color("b8c3d9"), Color("efe7db"), 72, 15, 14)
	return panel


func _inventory_equipment_footer(entry: Dictionary, definition: Dictionary) -> String:
	if int(entry.get("equipped_hero_uid", -1)) > 0:
		return "Equipped"
	return _equipment_slot_label(String(definition.get("slot", "")))


func _build_hero_detail_page() -> void:
	var hero_data: Dictionary = _get_selected_hero()
	if hero_data.is_empty():
		_page_content.add_child(_make_label("That hero is no longer available in the roster.", 18))
		_page_content.add_child(_make_small_nav_button("Back To Heroes", Callable(self, "_back_to_heroes")))
		return

	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(0, 0)
	root.add_theme_constant_override("separation", 18)
	_page_content.add_child(root)

	var portrait_panel := PanelContainer.new()
	portrait_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_panel.size_flags_stretch_ratio = 0.44
	_style_panel(portrait_panel, Color("161214"), Color("675042"), 10)
	root.add_child(portrait_panel)
	_hero_detail_context_panel = portrait_panel
	_build_hero_detail_context_panel(portrait_panel, hero_data)

	var right_section := VBoxContainer.new()
	right_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_section.size_flags_stretch_ratio = 0.56
	right_section.add_theme_constant_override("separation", 14)
	root.add_child(right_section)

	var name_bar := PanelContainer.new()
	name_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(name_bar, Color("1d1719"), Color("7c5f4d"), 10)
	right_section.add_child(name_bar)

	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 12)
	name_bar.add_child(name_row)

	var name_label := _make_label(String(hero_data.get("name", "Unknown Hero")), 28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(_make_small_nav_button("Back To Heroes", Callable(self, "_back_to_heroes")))

	var content_split := HBoxContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_split.add_theme_constant_override("separation", 14)
	right_section.add_child(content_split)

	var tabs_column := VBoxContainer.new()
	tabs_column.custom_minimum_size = Vector2(136, 0)
	tabs_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs_column.add_theme_constant_override("separation", 10)
	content_split.add_child(tabs_column)
	for tab_id in ["info", "equipment", "skills", "lore"]:
		tabs_column.add_child(_make_hero_tab_button(tab_id))

	var tab_panel := PanelContainer.new()
	tab_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_panel(tab_panel, Color("181416"), Color("675042"), 10)
	content_split.add_child(tab_panel)

	var tab_scroll := ScrollContainer.new()
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _hero_detail_tab == "equipment" else ScrollContainer.SCROLL_MODE_AUTO
	tab_panel.add_child(tab_scroll)

	var tab_body := VBoxContainer.new()
	tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_body.add_theme_constant_override("separation", 10)
	tab_scroll.add_child(tab_body)
	_build_hero_detail_tab_content(tab_body, hero_data)


func _build_hero_detail_tab_content(container: VBoxContainer, hero_data: Dictionary) -> void:
	match _hero_detail_tab:
		"equipment":
			container.add_child(_make_label("Equipment", 21))
			var slot_area := CenterContainer.new()
			slot_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
			container.add_child(slot_area)

			var grid := GridContainer.new()
			grid.columns = 3
			grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_theme_constant_override("h_separation", 16)
			grid.add_theme_constant_override("v_separation", 16)
			_hero_detail_equipment_slots_grid = grid
			slot_area.add_child(grid)
			_populate_hero_detail_equipment_slots(grid, hero_data)
		"skills":
			_hero_detail_equipment_slots_grid = null
			container.add_child(_make_label("Skills", 21))
			container.add_child(_make_label("Active and passive abilities will be shown here in a future pass.", 16))
			container.add_child(_make_label("No learned skills yet.", 16))
		"lore":
			_hero_detail_equipment_slots_grid = null
			container.add_child(_make_label("Lore", 21))
			var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
			container.add_child(_make_label(String(hero_definition.get("description", "No lore recorded.")), 17))
		_:
			_hero_detail_equipment_slots_grid = null
			var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
			var assigned_slot: int = int(hero_data.get("assigned_slot", -1))
			var assignment_name := "Unassigned"
			if assigned_slot >= 0:
				var building_definition: Dictionary = GameManager.get_slot_building_definition(assigned_slot)
				assignment_name = String(building_definition.get("name", "Assigned"))
			var combat_stats: Dictionary = GameManager.get_hero_effective_stats(int(hero_data.get("uid", -1)))
			var work_stats: Dictionary = GameManager.get_hero_effective_work_stats(int(hero_data.get("uid", -1)))
			if combat_stats.is_empty():
				combat_stats = _as_dictionary(hero_data.get("stats", hero_definition.get("stats", {})))
			if work_stats.is_empty():
				work_stats = _as_dictionary(hero_data.get("work_stats", hero_definition.get("work_stats", {})))
			container.add_child(_make_hero_info_section(
				"Hero Record",
				[
					{"label": "Name", "value": String(hero_data.get("name", hero_definition.get("name", "Unknown Hero")))},
					{"label": "Class", "value": String(hero_data.get("class", hero_definition.get("class", "Hero")))} ,
					{"label": "Level", "value": str(int(hero_data.get("level", 1)))},
					{"label": "Assignment", "value": assignment_name},
					{"label": "Source", "value": _hero_source_text(hero_data)},
				],
				Color("d0a170")
			))
			container.add_child(_make_hero_info_section(
				"Combat Stats",
				[
					{"label": "Health", "value": str(int(combat_stats.get("health", 0)))},
					{"label": "Sanity", "value": str(int(combat_stats.get("sanity", 0)))},
					{"label": "Attack", "value": str(int(combat_stats.get("attack", 0)))},
					{"label": "Defense", "value": str(int(combat_stats.get("defense", 0)))},
					{"label": "Crit Chance", "value": str(int(combat_stats.get("critical_chance", 0)))},
					{"label": "Crit Damage", "value": str(int(combat_stats.get("critical_damage", 0)))},
				],
				Color("b76558")
			))
			container.add_child(_make_hero_info_section(
				"Work Stats",
				[
					{"label": "Farming", "value": str(int(work_stats.get("farming", 0)))},
					{"label": "Mining", "value": str(int(work_stats.get("mining", 0)))},
					{"label": "Lumbering", "value": str(int(work_stats.get("lumbering", 0)))},
				],
				Color("7f9f84")
			))


func _build_hero_detail_context_panel(panel: PanelContainer, hero_data: Dictionary) -> void:
	_hero_detail_context_panel = panel
	_hero_detail_browser_root = null
	_hero_detail_equipment_list_scroll = null
	_hero_detail_hover_popup = null
	_hero_detail_hover_popup_body = null
	_hero_detail_equipment_dialog = null
	_hero_detail_equipment_tiles.clear()
	_clear_container(panel)
	if _hero_detail_tab == "equipment" and not _hero_detail_selected_slot.is_empty():
		_build_hero_equipment_browser(panel, hero_data)
	else:
		_build_hero_portrait_panel(panel, hero_data)


func _build_hero_portrait_panel(panel: PanelContainer, hero_data: Dictionary) -> void:
	var portrait_texture := TextureRect.new()
	portrait_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_texture.offset_left = 0.0
	portrait_texture.offset_top = 0.0
	portrait_texture.offset_right = 0.0
	portrait_texture.offset_bottom = 0.0
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.texture = _load_hero_texture(hero_data)
	portrait_texture.self_modulate = Color(1, 1, 1, 1)
	panel.add_child(portrait_texture)


func _build_hero_equipment_browser(panel: PanelContainer, hero_data: Dictionary) -> void:
	var slot_key := _hero_detail_selected_slot
	var equipment_entries := _get_inventory_equipment_entries_for_slot(slot_key)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 10)
	body.add_child(header_row)

	var title := _make_label("%s Loadout" % _equipment_slot_label(slot_key), 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(_make_small_nav_button("Portrait", Callable(self, "_close_equipment_browser")))

	var browser_panel := _make_panel()
	browser_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(browser_panel)
	var browser_root := Control.new()
	browser_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	browser_root.offset_left = 0.0
	browser_root.offset_top = 0.0
	browser_root.offset_right = 0.0
	browser_root.offset_bottom = 0.0
	browser_panel.add_child(browser_root)
	_hero_detail_browser_root = browser_root
	var browser_body := VBoxContainer.new()
	browser_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	browser_body.offset_left = 0.0
	browser_body.offset_top = 0.0
	browser_body.offset_right = 0.0
	browser_body.offset_bottom = 0.0
	browser_body.add_theme_constant_override("separation", 10)
	browser_root.add_child(browser_body)
	browser_body.add_child(_make_label("Available Equipment", 18))

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	browser_body.add_child(list_scroll)
	_hero_detail_equipment_list_scroll = list_scroll
	call_deferred("_restore_hero_detail_browser_scroll")

	if equipment_entries.is_empty():
		var empty_state := CenterContainer.new()
		empty_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.add_child(empty_state)
		var empty_label := _make_label("No inventory equipment matches this slot.", 15)
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
			var tile := _make_equipment_browser_tile(_as_dictionary(equipment_entry))
			_hero_detail_equipment_tiles[int(_as_dictionary(equipment_entry).get("uid", -1))] = tile
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
	panel.add_child(hover_popup)
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
	_hero_detail_hover_popup = hover_popup
	_hero_detail_hover_popup_body = hover_body
	var selected_entry := _get_inventory_equipment_entry(_hero_detail_selected_equipment_uid)
	if selected_entry.is_empty():
		return
	_hero_detail_equipment_dialog = _make_equipment_detail_dialog(hero_data, slot_key, selected_entry)
	browser_root.add_child(_hero_detail_equipment_dialog)


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
	_style_panel(dialog, Color("151113"), Color("8b6d57"), 10)
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
	var title := _make_label(String(definition.get("name", "Unknown Equipment")), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(_make_small_nav_button("Close", Callable(self, "_close_equipment_dialog")))

	var status_label := _make_label(_equipment_owner_text(equipment_entry), 14)
	status_label.add_theme_color_override("font_color", Color("c9d5e8"))
	body.add_child(status_label)
	body.add_child(_make_bonus_section("Combat Bonuses", _as_dictionary(_as_dictionary(definition.get("bonuses", {})).get("stats", {})), Color("c77265")))
	body.add_child(_make_bonus_section("Work Bonuses", _as_dictionary(_as_dictionary(definition.get("bonuses", {})).get("work_stats", {})), Color("7fa283")))

	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	var equip_disabled := _is_selected_equipment_already_equipped(equipment_entry, int(hero_data.get("uid", -1)), slot_key)
	action_row.add_child(_make_button("Equip", Callable(self, "_equip_selected_equipment"), equip_disabled))
	if _hero_slot_equipment_uid(hero_data, slot_key) > 0:
		action_row.add_child(_make_button("Unequip", Callable(self, "_unequip_selected_hero_slot"), false))
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
	_style_panel(tile, Color("141113"), Color("d0a170") if int(equipment_entry.get("uid", -1)) == _hero_detail_selected_equipment_uid else Color("8d8478"), 10)
	_build_inventory_tile_content(tile, definition, detail_text, Color("b8c3d9"), Color("efe7db"), 44, 13, 12, label_text)
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
	if int(equipment_entry.get("uid", -1)) == _hero_detail_selected_equipment_uid:
		button.add_theme_stylebox_override("normal", _button_style(Color(1, 1, 1, 0.04), Color("d0a170"), 10))


func _build_debug_page() -> void:
	_page_content.add_child(_make_label("Use these tools to accelerate testing and UI verification.", 16))
	var resources_panel: PanelContainer = _make_panel()
	_page_content.add_child(resources_panel)
	var resources_body := VBoxContainer.new()
	resources_panel.add_child(resources_body)
	resources_body.add_child(_make_label("Resource Injection", 20))
	resources_body.add_child(_make_label("Adds 100000 of every tracked resource immediately.", 16))
	resources_body.add_child(_make_button("Grant 100000 All Resources", Callable(self, "_debug_grant_resources"), false))

	var heroes_panel: PanelContainer = _make_panel()
	_page_content.add_child(heroes_panel)
	var heroes_body := VBoxContainer.new()
	heroes_panel.add_child(heroes_body)
	heroes_body.add_child(_make_label("Hero Recruitment", 20))
	heroes_body.add_child(_make_label("Generates and recruits a random hero without Tavern or cost requirements.", 16))
	heroes_body.add_child(_make_button("Recruit Random Hero", Callable(self, "_debug_recruit_hero"), false))


func _build_saves_page() -> void:
	_save_slot_labels.clear()
	_save_slot_name_inputs.clear()
	_save_slot_load_buttons.clear()
	_page_content.add_child(_make_label(_txt("save.description"), 16))
	for slot_info in GameManager.get_save_slot_metadata():
		_page_content.add_child(_make_save_slot_entry(slot_info))
	_refresh_saves_page_state(GameManager.get_save_slot_metadata())


func _build_saves_panel() -> void:
	_add_title("Save Vault")
	_add_text("Autosave runs during play. Manual saves and loads are available per slot.")
	for slot_info in GameManager.get_save_slot_metadata():
		_detail_content.add_child(_make_save_slot_entry(slot_info))


func _make_save_slot_entry(slot_info: Dictionary) -> PanelContainer:
	var entry: Dictionary = slot_info
	var panel: PanelContainer = _make_panel()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var slot_label: Label = _make_label(
		"%s%s" % [_txt("save.slot_heading", {"slot": int(entry.get("slot", 0))}), _txt("save.active_suffix") if bool(entry.get("active", false)) else ""],
		16
	)
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slot_label)
	var slot_index := int(entry.get("slot", 1))
	_save_slot_labels[slot_index] = slot_label
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.placeholder_text = _txt("save.name_placeholder")
	name_input.text = String(entry.get("name", ""))
	name_input.text_submitted.connect(Callable(self, "_on_save_slot_name_submitted").bind(slot_index, name_input))
	name_input.focus_exited.connect(Callable(self, "_on_save_slot_name_focus_exited").bind(slot_index, name_input))
	body.add_child(name_input)
	_save_slot_name_inputs[slot_index] = name_input
	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(_make_small_action_button(_txt("save.button_save"), Callable(self, "_save_to_slot").bind(slot_index)))
	var load_button := _make_small_action_button(_txt("save.button_load"), Callable(self, "_load_from_slot").bind(slot_index))
	load_button.disabled = not bool(entry.get("exists", false))
	action_row.add_child(load_button)
	_save_slot_load_buttons[slot_index] = load_button
	action_row.add_child(_make_small_action_button(_txt("save.button_reset"), Callable(self, "_reset_save_slot").bind(slot_index)))
	return panel


func _add_hero_entry(hero: Dictionary, assigned: bool) -> void:
	var panel: PanelContainer = _make_panel()
	_detail_content.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var assigned_slot: int = int(hero.get("assigned_slot", -1))
	var assigned_settlement_id: String = String(hero.get("assigned_settlement_id", "")).strip_edges()
	var work_stats: Dictionary = GameManager.get_hero_effective_work_stats(int(hero.get("uid", -1)))
	if work_stats.is_empty():
		work_stats = _as_dictionary(hero.get("work_stats", {}))
	body.add_child(_make_label(String(hero.get("name", "Unknown Hero")), 17))
	body.add_child(_make_rich_text_label(_format_work_stats_bbcode(work_stats), 13))
	if not assigned and assigned_slot >= 0 and not assigned_settlement_id.is_empty():
		var current_building: Dictionary = GameManager.get_settlement_building_definition(assigned_settlement_id, assigned_slot)
		var assignment_name := String(current_building.get("name", "another site"))
		if assigned_settlement_id != GameManager.active_settlement_id:
			assignment_name = "%s (%s)" % [assignment_name, String(GameManager.get_settlement_display_name(assigned_settlement_id))]
		body.add_child(_make_label(_txt("settlement.current_assignment", {"building": assignment_name}), 13))
	if _detail_mode == "settlement" and _selected_slot >= 0:
		if assigned:
			body.add_child(_make_small_action_button(_txt("hero.unassign"), Callable(self, "_unassign_hero").bind(int(hero.get("uid", -1)))))
		else:
			var button_text := _txt("hero.move_here") if assigned_slot >= 0 and not assigned_settlement_id.is_empty() else _txt("hero.assign")
			body.add_child(_make_small_action_button(button_text, Callable(self, "_assign_hero").bind(int(hero.get("uid", -1)), _selected_slot)))


func _build_selected_building(slot_index: int, building_id: String) -> void:
	GameManager.build_on_slot(slot_index, building_id)


func _upgrade_slot(slot_index: int) -> void:
	GameManager.upgrade_building(slot_index)


func _dismantle_slot(slot_index: int) -> void:
	GameManager.dismantle_building(slot_index)


func _assign_hero(hero_uid: int, slot_index: int) -> void:
	GameManager.assign_hero_to_slot(hero_uid, slot_index)


func _unassign_hero(hero_uid: int) -> void:
	GameManager.unassign_hero(hero_uid)


func _close_settlement_details() -> void:
	_selected_slot = -1
	GameManager.select_slot(-1)


func _on_save_slot_name_submitted(_submitted_text: String, slot_index: int, line_edit: LineEdit) -> void:
	GameManager.call_deferred("set_save_slot_name", slot_index, line_edit.text)


func _on_save_slot_name_focus_exited(slot_index: int, line_edit: LineEdit) -> void:
	GameManager.call_deferred("set_save_slot_name", slot_index, line_edit.text)


func _reset_save_slot(slot_index: int) -> void:
	GameManager.reset_save_slot(slot_index)


func _refresh_saves_page_state(slots: Array) -> void:
	for slot_info in slots:
		if slot_info is not Dictionary:
			continue
		var entry := slot_info as Dictionary
		var slot_index := int(entry.get("slot", 0))
		var label := _save_slot_labels.get(slot_index, null) as Label
		if label != null and is_instance_valid(label):
			label.text = "%s%s" % [_txt("save.slot_heading", {"slot": slot_index}), _txt("save.active_suffix") if bool(entry.get("active", false)) else ""]
		var input := _save_slot_name_inputs.get(slot_index, null) as LineEdit
		if input != null and is_instance_valid(input) and not input.has_focus():
			input.text = String(entry.get("name", ""))
		var load_button := _save_slot_load_buttons.get(slot_index, null) as Button
		if load_button != null and is_instance_valid(load_button):
			load_button.disabled = not bool(entry.get("exists", false))


func _recruit_from_tavern(slot_index: int) -> void:
	GameManager.recruit_random_hero(slot_index)


func _debug_grant_resources() -> void:
	GameManager.debug_grant_all_resources()


func _debug_recruit_hero() -> void:
	GameManager.debug_recruit_random_hero()


func _open_hero_detail(hero_uid: int) -> void:
	_selected_hero_uid = hero_uid
	_hero_detail_tab = "info"
	_hero_detail_selected_slot = ""
	_hero_detail_selected_equipment_uid = -1
	_hero_detail_context_panel = null
	_detail_mode = "hero_detail"
	_apply_mode_layout()
	_refresh_active_content()


func _back_to_heroes() -> void:
	_hero_detail_selected_slot = ""
	_hero_detail_selected_equipment_uid = -1
	_hero_detail_context_panel = null
	_detail_mode = "heroes"
	_apply_mode_layout()
	_refresh_active_content()


func _set_hero_detail_tab(tab_id: String) -> void:
	_hero_detail_tab = tab_id
	if tab_id != "equipment":
		_hero_detail_selected_slot = ""
		_hero_detail_selected_equipment_uid = -1
	_refresh_active_content()


func _get_selected_hero() -> Dictionary:
	for hero_data in _heroes_snapshot:
		var hero: Dictionary = hero_data
		if int(hero.get("uid", -1)) == _selected_hero_uid:
			return hero.duplicate(true)
	return {}


func _make_hero_tab_button(tab_id: String) -> Button:
	var button := _make_button(tab_id.capitalize(), Callable(self, "_set_hero_detail_tab").bind(tab_id), false)
	if tab_id == _hero_detail_tab:
		button.add_theme_stylebox_override("normal", _button_style(Color("3a2b25"), Color("d0a170"), 7))
		button.add_theme_stylebox_override("hover", _button_style(Color("3a2b25"), Color("d0a170"), 7))
		button.add_theme_stylebox_override("pressed", _button_style(Color("3a2b25"), Color("d0a170"), 7))
	return button


func _hero_class_color(hero_data: Dictionary) -> Color:
	match String(hero_data.get("class", "")):
		"Attacker":
			return Color("b76558")
		"Defender":
			return Color("6f8ea8")
		"Supporter":
			return Color("8f82b5")
		_:
			return Color("8d8478")


func _load_hero_texture(hero_data: Dictionary) -> Texture2D:
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


func _load_texture_from_path(path: String) -> Texture2D:
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


func _refresh_settlement_title() -> void:
	var settlement_name := GameManager.get_active_settlement_name()
	if settlement_name.is_empty():
		settlement_name = "Settlement"
	_settlement_title.text = settlement_name


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
	tile.custom_minimum_size = Vector2(122, 144)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_panel(tile, Color("171315") if occupied else Color("100d0f"), Color("d0a170") if _hero_detail_selected_slot == slot_key else (Color("8b6d57") if occupied else Color("675042")), 8)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(body)
	var slot_label := _make_label(_equipment_slot_label(slot_key), 13)
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
		icon.texture = _load_texture_from_path(String(current_definition.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)))
		if icon.texture == null:
			icon.texture = _load_texture_from_path(DataLoader.DEFAULT_CATALOG_ICON)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon)
		var name_label := _make_label(String(current_definition.get("name", "Occupied")), 12)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", Color("efe7db"))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(name_label)
	else:
		var empty_label := _make_label("Empty", 15)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		empty_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color("8f8178"))
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(empty_label)
		var hint_label := _make_label("No gear", 11)
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
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), Color("d0a170") if _hero_detail_selected_slot == slot_key else Color(0, 0, 0, 0), 8))
	button.add_theme_stylebox_override("hover", _button_style(Color(1, 1, 1, 0.03), Color("b88d68"), 8))
	button.add_theme_stylebox_override("pressed", _button_style(Color(1, 1, 1, 0.05), Color("d0a170"), 8))
	button.pressed.connect(Callable(self, "_select_hero_equipment_slot").bind(slot_key))
	tile.add_child(button)
	return tile


func _equipment_slot_label(slot_key: String) -> String:
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


func _hero_slot_equipment_uid(hero_data: Dictionary, slot_key: String) -> int:
	return int(String(_as_dictionary(hero_data.get("equipment", {})).get(slot_key, "")).strip_edges())


func _get_inventory_equipment_entries_for_slot(slot_key: String) -> Array:
	var entries: Array = []
	for equipment_entry in _as_array(_inventory_snapshot.get("equipment", [])):
		if equipment_entry is not Dictionary:
			continue
		var definition := DataLoader.get_equipment_definition(String((equipment_entry as Dictionary).get("definition_id", "")))
		if String(definition.get("slot", "")) == slot_key:
			entries.append((equipment_entry as Dictionary).duplicate(true))
	return entries


func _get_inventory_equipment_entry(equipment_uid: int) -> Dictionary:
	for equipment_entry in _as_array(_inventory_snapshot.get("equipment", [])):
		if equipment_entry is Dictionary and int((equipment_entry as Dictionary).get("uid", -1)) == equipment_uid:
			return (equipment_entry as Dictionary).duplicate(true)
	return {}


func _hero_name_by_uid(hero_uid: int) -> String:
	for hero_data in _heroes_snapshot:
		var hero := _as_dictionary(hero_data)
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


func _format_bonus_dict(values: Dictionary) -> String:
	if values.is_empty():
		return "none"
	var parts: Array[String] = []
	for key in values.keys():
		var amount := int(values[key])
		parts.append("%s %+d" % [String(key).capitalize().replace("_", " "), amount])
	return ", ".join(parts)


func _build_inventory_tile_content(parent: Control, definition: Dictionary, footer_text: String, footer_color: Color, title_color: Color, icon_size: int, title_font_size: int, footer_font_size: int, title_override: String = "") -> void:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(body)
	var name_label := _make_label(title_override if not title_override.is_empty() else String(definition.get("name", "Unknown")), title_font_size)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", title_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(name_label)
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
	var footer_label := _make_label(footer_text, footer_font_size)
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_label.add_theme_color_override("font_color", footer_color)
	footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(footer_label)


func _make_bonus_section(title: String, values: Dictionary, accent_color: Color) -> PanelContainer:
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
	var header := _make_label(title, 15)
	header.add_theme_color_override("font_color", accent_color)
	body.add_child(header)
	if values.is_empty():
		var empty := _make_label("none", 14)
		empty.add_theme_color_override("font_color", Color("b9afa4"))
		body.add_child(empty)
		return panel
	for key in values.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(row)
		var stat_label := _make_label(String(key).capitalize().replace("_", " "), 14)
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.add_theme_color_override("font_color", Color("c8bcae"))
		row.add_child(stat_label)
		var value_label := _make_label("%+d" % int(values[key]), 14)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", accent_color.lightened(0.15))
		row.add_child(value_label)
	return panel


func _make_tooltip_bonus_section(title: String, values: Dictionary, accent_color: Color) -> PanelContainer:
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
	var header := _make_tooltip_label(title, 15, accent_color, true)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)
	if values.is_empty():
		var empty := _make_tooltip_label("none", 14, Color("b9afa4"), false)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(empty)
		return panel
	for key in values.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		var stat_label := _make_tooltip_label(String(key).capitalize().replace("_", " "), 14, Color("c8bcae"), false)
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.clip_text = true
		row.add_child(stat_label)
		var value_label := _make_tooltip_label("%+d" % int(values[key]), 14, accent_color.lightened(0.15), true)
		value_label.custom_minimum_size = Vector2(34, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
	panel.update_minimum_size()
	return panel


func _make_tooltip_label(text: String, font_size: int, color: Color, accent: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_FILL
	_style_label(label, font_size, accent)
	label.add_theme_color_override("font_color", color)
	return label


func _show_equipment_hover_popup(equipment_uid: int) -> void:
	if _hero_detail_hover_popup == null or not is_instance_valid(_hero_detail_hover_popup) or _hero_detail_hover_popup_body == null or not is_instance_valid(_hero_detail_hover_popup_body):
		return
	var equipment_entry := _get_inventory_equipment_entry(equipment_uid)
	if equipment_entry.is_empty():
		return
	var definition := DataLoader.get_equipment_definition(String(equipment_entry.get("definition_id", "")))
	_clear_container(_hero_detail_hover_popup_body)
	var title := _make_tooltip_label(String(definition.get("name", "Unknown Equipment")), 16, Color("fff4e4"), true)
	_hero_detail_hover_popup_body.add_child(title)
	var combat_values := _as_dictionary(_as_dictionary(definition.get("bonuses", {})).get("stats", {}))
	var work_values := _as_dictionary(_as_dictionary(definition.get("bonuses", {})).get("work_stats", {}))
	_hero_detail_hover_popup_body.add_child(_make_tooltip_bonus_section("Combat", combat_values, Color("c77265")))
	_hero_detail_hover_popup_body.add_child(_make_tooltip_bonus_section("Work", work_values, Color("7fa283")))
	_set_mouse_filter_recursive(_hero_detail_hover_popup, Control.MOUSE_FILTER_IGNORE)
	_hero_detail_hover_popup_body.update_minimum_size()
	var popup_size := _get_equipment_hover_popup_size()
	_hero_detail_hover_popup.custom_minimum_size = popup_size
	_hero_detail_hover_popup.size = popup_size
	_position_equipment_hover_popup()
	_hero_detail_hover_popup.visible = true


func _hide_equipment_hover_popup() -> void:
	if _hero_detail_hover_popup == null or not is_instance_valid(_hero_detail_hover_popup):
		return
	_hero_detail_hover_popup.visible = false


func _position_equipment_hover_popup() -> void:
	if _hero_detail_hover_popup == null or not is_instance_valid(_hero_detail_hover_popup):
		return
	if _hero_detail_context_panel == null or not is_instance_valid(_hero_detail_context_panel):
		return
	var panel_rect := _hero_detail_context_panel.get_global_rect()
	var mouse_pos: Vector2 = _hero_detail_context_panel.get_viewport().get_mouse_position()
	var popup_size := _hero_detail_hover_popup.size
	if popup_size == Vector2.ZERO:
		popup_size = _get_equipment_hover_popup_size()
	var desired_pos := mouse_pos + Vector2(14, 14)
	if desired_pos.x + popup_size.x > panel_rect.position.x + panel_rect.size.x - 8.0:
		desired_pos.x = mouse_pos.x - popup_size.x - 14.0
	if desired_pos.y + popup_size.y > panel_rect.position.y + panel_rect.size.y - 8.0:
		desired_pos.y = panel_rect.position.y + panel_rect.size.y - popup_size.y - 8.0
	desired_pos.x = clampf(desired_pos.x, panel_rect.position.x + 8.0, max(panel_rect.position.x + 8.0, panel_rect.position.x + panel_rect.size.x - popup_size.x - 8.0))
	desired_pos.y = clampf(desired_pos.y, panel_rect.position.y + 8.0, max(panel_rect.position.y + 8.0, panel_rect.position.y + panel_rect.size.y - popup_size.y - 8.0))
	_hero_detail_hover_popup.global_position = desired_pos
	_hero_detail_hover_popup.size = popup_size


func _get_equipment_hover_popup_size() -> Vector2:
	if _hero_detail_hover_popup_body == null or not is_instance_valid(_hero_detail_hover_popup_body):
		return Vector2(280, 180)
	var content_size := _hero_detail_hover_popup_body.get_combined_minimum_size()
	var width := clampf(content_size.x + 20.0, 280.0, 420.0)
	var height := clampf(content_size.y + 20.0, 140.0, 360.0)
	return Vector2(width, height)


func _set_mouse_filter_recursive(node: Node, filter_mode: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter_mode
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter_mode)


func _select_hero_equipment_slot(slot_key: String) -> void:
	_hero_detail_browser_scroll_value = 0
	_hero_detail_selected_slot = slot_key
	_hero_detail_selected_equipment_uid = -1
	_hide_equipment_hover_popup()
	_refresh_hero_detail_context_panel()


func _select_equipment_entry(equipment_uid: int) -> void:
	_remember_hero_detail_browser_scroll()
	_hero_detail_selected_equipment_uid = equipment_uid
	_hide_equipment_hover_popup()
	if _hero_detail_browser_root == null or not is_instance_valid(_hero_detail_browser_root):
		_refresh_hero_detail_context_panel()
		return
	if _hero_detail_equipment_dialog != null and is_instance_valid(_hero_detail_equipment_dialog):
		_hero_detail_equipment_dialog.queue_free()
	var hero_data := _get_selected_hero()
	if hero_data.is_empty() or _hero_detail_selected_slot.is_empty():
		return
	var selected_entry := _get_inventory_equipment_entry(_hero_detail_selected_equipment_uid)
	if selected_entry.is_empty():
		return
	_hero_detail_equipment_dialog = _make_equipment_detail_dialog(hero_data, _hero_detail_selected_slot, selected_entry)
	_hero_detail_browser_root.add_child(_hero_detail_equipment_dialog)


func _close_equipment_browser() -> void:
	_hero_detail_browser_scroll_value = 0
	_hero_detail_selected_slot = ""
	_hero_detail_selected_equipment_uid = -1
	_hide_equipment_hover_popup()
	_refresh_hero_detail_context_panel()


func _close_equipment_dialog() -> void:
	_remember_hero_detail_browser_scroll()
	_hero_detail_selected_equipment_uid = -1
	if _hero_detail_equipment_dialog != null and is_instance_valid(_hero_detail_equipment_dialog):
		_hero_detail_equipment_dialog.queue_free()
	_hero_detail_equipment_dialog = null


func _refresh_hero_detail_context_panel() -> void:
	if _detail_mode != "hero_detail":
		return
	if _hero_detail_context_panel == null or not is_instance_valid(_hero_detail_context_panel):
		_refresh_active_content()
		return
	var hero_data := _get_selected_hero()
	if hero_data.is_empty():
		_refresh_active_content()
		return
	_build_hero_detail_context_panel(_hero_detail_context_panel, hero_data)


func _refresh_hero_detail_equipment_slots() -> void:
	if _detail_mode != "hero_detail" or _hero_detail_tab != "equipment":
		return
	if _hero_detail_equipment_slots_grid == null or not is_instance_valid(_hero_detail_equipment_slots_grid):
		return
	var hero_data := _get_selected_hero()
	if hero_data.is_empty():
		return
	_populate_hero_detail_equipment_slots(_hero_detail_equipment_slots_grid, hero_data)


func _populate_hero_detail_equipment_slots(grid: GridContainer, hero_data: Dictionary) -> void:
	_clear_container_immediately(grid)
	for slot_key in DataLoader.HERO_EQUIPMENT_KEYS:
		grid.add_child(_make_hero_equipment_slot_button(hero_data, slot_key))


func _refresh_hero_detail_equipment_ui_state() -> void:
	if _detail_mode != "hero_detail" or _hero_detail_tab != "equipment":
		return
	_refresh_hero_detail_equipment_slots()
	if _hero_detail_selected_slot.is_empty():
		return
	if _hero_detail_browser_root == null or not is_instance_valid(_hero_detail_browser_root):
		_refresh_hero_detail_context_panel()
		return
	_remember_hero_detail_browser_scroll()
	var hero_data := _get_selected_hero()
	if hero_data.is_empty():
		return
	var slot_entries := _get_inventory_equipment_entries_for_slot(_hero_detail_selected_slot)
	if slot_entries.size() != _hero_detail_equipment_tiles.size():
		_refresh_hero_detail_context_panel()
		return
	for equipment_entry in slot_entries:
		var entry := _as_dictionary(equipment_entry)
		var equipment_uid := int(entry.get("uid", -1))
		var tile: PanelContainer = _hero_detail_equipment_tiles.get(equipment_uid, null) as PanelContainer
		if tile == null or not is_instance_valid(tile):
			_refresh_hero_detail_context_panel()
			return
		_populate_equipment_browser_tile(tile, entry)
	if _hero_detail_selected_equipment_uid > 0:
		_select_equipment_entry(_hero_detail_selected_equipment_uid)
	call_deferred("_restore_hero_detail_browser_scroll")


func _equip_selected_equipment() -> void:
	if _hero_detail_selected_slot.is_empty() or _hero_detail_selected_equipment_uid <= 0:
		return
	_remember_hero_detail_browser_scroll()
	GameManager.equip_equipment_to_hero(_selected_hero_uid, _hero_detail_selected_slot, _hero_detail_selected_equipment_uid)


func _unequip_selected_hero_slot() -> void:
	if _hero_detail_selected_slot.is_empty():
		return
	_remember_hero_detail_browser_scroll()
	GameManager.unequip_hero_slot(_selected_hero_uid, _hero_detail_selected_slot)


func _remember_hero_detail_browser_scroll() -> void:
	if _hero_detail_equipment_list_scroll == null or not is_instance_valid(_hero_detail_equipment_list_scroll):
		return
	_hero_detail_browser_scroll_value = _hero_detail_equipment_list_scroll.scroll_vertical


func _restore_hero_detail_browser_scroll() -> void:
	if _hero_detail_equipment_list_scroll == null or not is_instance_valid(_hero_detail_equipment_list_scroll):
		return
	_hero_detail_equipment_list_scroll.scroll_vertical = _hero_detail_browser_scroll_value


func _hero_source_text(hero_data: Dictionary) -> String:
	var source := String(hero_data.get("source", "core"))
	if source == "mod":
		var mod_id := String(hero_data.get("mod_id", "")).strip_edges()
		return "Mod: %s" % (mod_id if not mod_id.is_empty() else "Unknown")
	return "Core"


func _make_hero_info_section(title: String, rows: Array, accent_color: Color) -> PanelContainer:
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
	var header := _make_label(title, 18)
	header.add_theme_color_override("font_color", accent_color)
	body.add_child(header)
	for row_data in rows:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var label := _make_label(String((row_data as Dictionary).get("label", "")), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("bfb1a2"))
		row.add_child(label)
		var value := _make_label(String((row_data as Dictionary).get("value", "")), 15)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override("font_color", Color("fff6ea"))
		row.add_child(value)
	return panel


func _save_active_slot() -> void:
	GameManager.save_game(GameManager.active_save_slot)


func _save_to_slot(slot_index: int) -> void:
	GameManager.save_game(slot_index)


func _load_from_slot(slot_index: int) -> void:
	GameManager.load_game(slot_index)


func _add_title(text: String) -> void:
	_detail_content.add_child(_make_label(text, 26))


func _add_detail_header(text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	_detail_content.add_child(row)
	var title := _make_label(text, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_make_small_nav_button("Close", Callable(self, "_close_settlement_details")))


func _add_section(text: String) -> void:
	_detail_content.add_child(_make_label(text, 20))


func _add_text(text: String) -> void:
	_detail_content.add_child(_make_label(text, 15))


func _add_button(text: String, callback: Callable, disabled: bool) -> void:
	_detail_content.add_child(_make_button(text, callback, disabled))


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, Color("181416"), Color("675042"), 8)
	return panel


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var effective_font_size := font_size if font_size >= 20 else font_size + 1
	_style_label(label, effective_font_size, font_size >= 20)
	return label


func _make_rich_text_label(bbcode_text: String, font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size if font_size >= 20 else font_size + 1)
	label.add_theme_color_override("default_color", Color("e6ddd3"))
	label.text = bbcode_text
	return label


func _make_button(text: String, callback: Callable, disabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(button)
	button.pressed.connect(callback)
	return button


func _make_small_nav_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(116, 30)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_font_size_override("font_size", 12)
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


func _make_small_action_button(text: String, callback: Callable) -> Button:
	var button := _make_small_nav_button(text, callback)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


func _format_resource_dict(values: Dictionary) -> String:
	if values.is_empty():
		return _txt("common.none")
	var parts: Array[String] = []
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		if values.has(resource_id) and int(values[resource_id]) != 0:
			parts.append("%s %d" % [resource_id.capitalize(), int(values[resource_id])])
	for resource_id in values.keys():
		if SettlementGameData.RESOURCE_ORDER.has(resource_id):
			continue
		parts.append("%s %d" % [String(resource_id).capitalize(), int(values[resource_id])])
	return ", ".join(parts)


func _format_resource_bbcode(values: Dictionary, style: String) -> String:
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
	for resource_id in values.keys():
		if SettlementGameData.RESOURCE_ORDER.has(resource_id) or int(values[resource_id]) == 0:
			continue
		var amount := int(values[resource_id])
		var signed_amount := amount
		if style == "cost":
			signed_amount = -abs(amount)
		elif style == "refund":
			signed_amount = abs(amount)
		var amount_text := "%+d" % signed_amount if style in ["cost", "refund"] else "%d" % signed_amount
		parts.append("[color=#e6ddd3]%s %s[/color]" % [String(resource_id).capitalize(), amount_text])
	return "  |  ".join(parts)


func _format_work_stats_bbcode(work_stats: Dictionary) -> String:
	var parts: Array[String] = []
	for stat_key in ["farming", "mining", "lumbering"]:
		parts.append("[color=%s]%s %d[/color]" % [String(WORK_STAT_COLORS.get(stat_key, "#e6ddd3")), _txt("work.%s" % stat_key, {}, stat_key.capitalize()), int(work_stats.get(stat_key, 0))])
	return "  |  ".join(parts)


func _txt(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	return DataLoader.get_ui_text(key, replacements, fallback)


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _clear_container_immediately(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _style_panel(panel: Control, bg_color: Color, border_color: Color, corner_radius: int) -> void:
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


func _style_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("faf5ef"))
	button.add_theme_color_override("font_hover_color", Color("fffaf4"))
	button.add_theme_color_override("font_pressed_color", Color("fff0dc"))
	button.add_theme_color_override("font_disabled_color", Color("9d9287"))
	button.add_theme_stylebox_override("normal", _button_style(Color("171315"), Color("6f5648"), 7))
	button.add_theme_stylebox_override("hover", _button_style(Color("261d1d"), Color("a88563"), 7))
	button.add_theme_stylebox_override("pressed", _button_style(Color("362925"), Color("d0a170"), 7))
	button.add_theme_stylebox_override("disabled", _button_style(Color("121012"), Color("4c3e3a"), 7))


func _style_label(label: Label, font_size: int, accent: bool) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff9f1") if accent else Color("efe7db"))


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
