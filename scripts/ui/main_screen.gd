extends Control

const SettlementGameData = preload("res://scripts/game/settlement_game.gd")
const OverviewScreenScript = preload("res://scripts/ui/overview_screen.gd")
const HeroesScreenScript = preload("res://scripts/ui/heroes_screen.gd")
const InventoryScreenScript = preload("res://scripts/ui/inventory_screen.gd")
const WorldScreenScene = preload("res://scenes/ui/world_screen.tscn")
const SavesScreenScript = preload("res://scripts/ui/saves_screen.gd")
const HeroDetailScreenScene = preload("res://scenes/ui/hero_detail_screen.tscn")
const ResourceBadgeScene = preload("res://scenes/widgets/resource_badge.tscn")
const SettlementSlotScene = preload("res://scenes/widgets/settlement_slot.tscn")
const MainScreenNavigation = preload("res://scripts/ui/main_screen_navigation.gd")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const UITheme = preload("res://resources/themes/ui_theme.tres")

const MODE_OVERVIEW := MainScreenNavigation.MODE_OVERVIEW
const MODE_RECRUIT := MainScreenNavigation.MODE_RECRUIT
const MODE_SAVES := MainScreenNavigation.MODE_SAVES
const MODE_WORLD := MainScreenNavigation.MODE_WORLD
const MODE_HEROES := MainScreenNavigation.MODE_HEROES
const MODE_INVENTORY := MainScreenNavigation.MODE_INVENTORY
const MODE_HERO_DETAIL := MainScreenNavigation.MODE_HERO_DETAIL
const MODE_DEBUG := MainScreenNavigation.MODE_DEBUG

const RESOURCE_ID_WOOD := "wood"
const RESOURCE_ID_FOOD := "food"
const RESOURCE_ID_STONE := "stone"
const RESOURCE_ID_GOLD := "gold"
const RESOURCE_ID_HEROES := "heroes"
const RESOURCE_ID_GEMS := "gems"
const RESOURCE_ID_CRYSTALS := "crystals"

const RESOURCE_ICONS := {
	RESOURCE_ID_WOOD: "res://assets/resources/wood.png",
	RESOURCE_ID_FOOD: "res://assets/resources/food.png",
	RESOURCE_ID_STONE: "res://assets/resources/metal.png",
	RESOURCE_ID_GOLD: "res://assets/resources/coins.png",
	RESOURCE_ID_HEROES: "res://assets/resources/population.png",
	RESOURCE_ID_GEMS: "res://assets/resources/gems.png",
	RESOURCE_ID_CRYSTALS: "res://assets/resources/crystals.png",
}

const RESOURCE_TEXT_COLORS := {
	RESOURCE_ID_WOOD: "#b98b60",
	RESOURCE_ID_FOOD: "#d4a25c",
	RESOURCE_ID_STONE: "#b7bcc7",
	RESOURCE_ID_GOLD: "#f0cc66",
	RESOURCE_ID_HEROES: "#d8778f",
	RESOURCE_ID_GEMS: "#73b5ff",
	RESOURCE_ID_CRYSTALS: "#7dd7ff",
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
@onready var _recruit_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/RecruitButton")
@onready var _background: TextureRect = get_node("Background")
@onready var _shell: Control = get_node("Shell")
@onready var _settlement_panel: Control = get_node("Shell/MainRow/SettlementPanel")
@onready var _details_panel_node: Control = get_node("Shell/MainRow/DetailsPanel")
@onready var _bottom_bar: Control = get_node("Shell/BottomBar")
@onready var _world_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/WorldButton")
@onready var _overview_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/OverviewButton")
@onready var _heroes_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/HeroesButton")
@onready var _inventory_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/InventoryButton")
@onready var _debug_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/DebugButton")
@onready var _saves_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/SavesButton")
@onready var _back_button: Button = get_node("Shell/BottomBar/BottomBarMargin/NavRow/BackButton")

var _resource_badges: Dictionary = {}
var _slot_widgets: Array = []
var _selected_slot: int = -1
var _detail_mode: String = MODE_OVERVIEW
var _selected_hero_uid: int = -1
var _navigation := MainScreenNavigation.new()
var _active_page_screen: Control = null
var _scene_backed_page_screens: Dictionary = {}
var _slots_snapshot: Array = []
var _heroes_snapshot: Array = []
var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}
var _resource_values: Dictionary = {}
var _resource_yields: Dictionary = {}
var _recruit_market_snapshot: Dictionary = {}


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
		GameManager.reset_new_game()
		GameManager.emit_state()
	else:
		_selected_slot = GameManager.selected_slot
	_sync_top_bar_yields_after_state_load()
	_refresh_recruit_nav_visibility()


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
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.offset_left = 0.0
	_background.offset_top = 0.0
	_background.offset_right = 0.0
	_background.offset_bottom = 0.0
	_background.custom_minimum_size = Vector2.ZERO
	_background.texture = null
	_background.visible = false
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.offset_left = 0.0
	_shell.offset_top = 0.0
	_shell.offset_right = 0.0
	_shell.offset_bottom = 0.0
	_settlement_panel.size_flags_stretch_ratio = 1.6
	_details_panel_node.size_flags_stretch_ratio = 1.0


func _apply_theme() -> void:
	var chrome_nodes: Array = [
		_top_bar,
		_settlement_panel,
		_details_panel_node,
		_bottom_bar,
	]
	for chrome in chrome_nodes:
		_style_panel(chrome, Color("211a1c"), Color("7a5e4b"), 10)
	var bottom_buttons: Array = [
		_world_button,
		_overview_button,
		_recruit_button,
		_heroes_button,
		_inventory_button,
		_debug_button,
		_saves_button,
		_back_button,
	]
	for button in bottom_buttons:
		_style_button(button)
	_style_label(_settlement_title, 24, true)
	_style_label(_page_title, 24, true)
	_settlement_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _apply_ui_text_bundle() -> void:
	_world_button.text = _txt("nav.world")
	_overview_button.text = _txt("nav.settlements")
	_recruit_button.text = _txt("nav.recruit", {}, "Recruit")
	_heroes_button.text = _txt("nav.heroes")
	_inventory_button.text = _txt("nav.inventory")
	_debug_button.text = _txt("nav.debug")
	_saves_button.text = _txt("nav.saves")
	_back_button.text = _txt("nav.home")


func _wire_navigation() -> void:
	_navigation.connect_navigation(
		self,
		{
			MODE_WORLD: _world_button,
			MODE_OVERVIEW: _overview_button,
			MODE_RECRUIT: _recruit_button,
			MODE_HEROES: _heroes_button,
			MODE_INVENTORY: _inventory_button,
			MODE_DEBUG: _debug_button,
			MODE_SAVES: _saves_button,
		},
		_back_button
	)


func _connect_game_manager() -> void:
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.settlement_changed.connect(_on_settlement_changed)
	GameManager.active_settlement_changed.connect(_on_active_settlement_changed)
	GameManager.world_changed.connect(_on_world_changed)
	GameManager.heroes_changed.connect(_on_heroes_changed)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.recruit_market_changed.connect(_on_recruit_market_changed)
	GameManager.selection_changed.connect(_on_selection_changed)
	GameManager.save_slots_changed.connect(_on_save_slots_changed)
	GameManager.save_loaded.connect(_on_save_loaded)
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
	for slot_index in GameManager.get_settlement_plot_count(GameManager.active_settlement_id):
		var slot_button: Button = SettlementSlotScene.instantiate()
		slot_button.slot_index = slot_index
		slot_button.slot_selected.connect(_on_slot_selected)
		_grid_container.add_child(slot_button)
		_slot_widgets.append(slot_button)


func _set_detail_mode(mode: String) -> void:
	_apply_navigation_change(_navigation.request_mode(mode, _selected_slot))


func _on_back_pressed() -> void:
	_apply_navigation_change(_navigation.request_back_to_world())


func _request_navigation_mode(mode: String) -> void:
	_set_detail_mode(mode)


func _request_navigation_back() -> void:
	_on_back_pressed()


func _apply_navigation_change(change: Dictionary) -> void:
	if change.is_empty():
		return
	var apply_mode_before_selection_sync := bool(change.get("apply_mode_before_selection_sync", false))
	if apply_mode_before_selection_sync and change.has("mode"):
		_detail_mode = String(change.get("mode", _detail_mode))
	if change.has("selected_slot"):
		_selected_slot = int(change.get("selected_slot", _selected_slot))
	if bool(change.get("sync_selected_slot", false)):
		GameManager.select_slot(_selected_slot)
	if not apply_mode_before_selection_sync and change.has("mode"):
		_detail_mode = String(change.get("mode", _detail_mode))
	_apply_mode_layout()
	if bool(change.get("refresh_grid", false)):
		_refresh_grid()
	if bool(change.get("refresh_content", true)):
		_refresh_active_content()


func _on_slot_selected(slot_index: int) -> void:
	_apply_navigation_change(_navigation.request_settlement_from_slot())
	GameManager.select_slot(slot_index)


func _on_resources_changed() -> void:
	_resource_values = GameManager.get_resource_snapshot()
	_refresh_resource_badges()


func _on_settlement_changed() -> void:
	_slots_snapshot = GameManager.get_slots_snapshot()
	_refresh_settlement_title()
	_refresh_resource_yields()
	_refresh_grid()
	if not _refresh_active_page_screen():
		_refresh_active_content()


func _on_active_settlement_changed(_settlement_id: String) -> void:
	_slots_snapshot = GameManager.get_slots_snapshot()
	_refresh_settlement_title()
	_refresh_resource_yields()
	_refresh_active_page_screen()
	_refresh_active_content()


func _on_world_changed() -> void:
	_refresh_resource_yields()
	if _detail_mode == MODE_WORLD:
		return
	if not _refresh_active_page_screen():
		_refresh_active_content()


func _on_heroes_changed() -> void:
	_heroes_snapshot = GameManager.get_heroes_snapshot()
	_resource_values[RESOURCE_ID_HEROES] = _heroes_snapshot.size()
	_refresh_resource_badges()
	_refresh_resource_yields()
	if _detail_mode == MODE_WORLD:
		return
	if not _refresh_active_page_screen():
		_refresh_active_content()


func _on_inventory_changed() -> void:
	_inventory_snapshot = GameManager.get_inventory_snapshot()
	if _detail_mode == MODE_INVENTORY or _detail_mode == MODE_HERO_DETAIL:
		if not _refresh_active_page_screen():
			_refresh_active_content()


func _on_recruit_market_changed() -> void:
	_recruit_market_snapshot = GameManager.get_recruit_market_snapshot()
	_refresh_recruit_nav_visibility()
	if _detail_mode == MODE_RECRUIT:
		_refresh_active_content()


func _refresh_resource_yields() -> void:
	_resource_yields.clear()
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		_resource_yields[resource_id] = 0
	var production := GameManager.get_owned_settlement_production_preview()
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



func _on_save_slots_changed() -> void:
	if _detail_mode == MODE_SAVES:
		_refresh_saves_page_state(GameManager.get_save_slot_metadata())


func _on_save_loaded(_slot_index: int) -> void:
	_selected_slot = GameManager.selected_slot
	_sync_top_bar_yields_after_state_load()


func _on_tick_processed(_tick_count: int, _production_delta: Dictionary) -> void:
	_refresh_resource_yields()


func _sync_top_bar_yields_after_state_load() -> void:
	_refresh_resource_yields.call_deferred()


func _refresh_recruit_nav_visibility() -> void:
	var unlocked := bool(_recruit_market_snapshot.get("unlocked", false))
	_recruit_button.visible = unlocked
	if not unlocked:
		_apply_navigation_change(_navigation.request_recruit_fallback(_detail_mode))


func _refresh_grid() -> void:
	if _slots_snapshot.is_empty():
		_slots_snapshot = GameManager.get_slots_snapshot()
	if _slot_widgets.size() != _slots_snapshot.size():
		_build_grid()
	for slot_index in range(_slot_widgets.size()):
		var slot_data: Dictionary = _slots_snapshot[slot_index] if slot_index < _slots_snapshot.size() else {}
		var building_definition: Dictionary = {}
		if not String(slot_data.get("building_id", "")).is_empty():
			building_definition = GameManager.get_slot_building_definition(slot_index)
		_slot_widgets[slot_index].set_view(slot_data, building_definition, slot_index == _selected_slot)


func _refresh_detail_panel() -> void:
	_clear_container(_detail_content)
	match _detail_mode:
		MainScreenNavigation.MODE_SETTLEMENT:
			_build_settlement_detail_panel()
		_:
			pass


func _refresh_active_content() -> void:
	if _is_full_page_mode():
		_refresh_page_content()
	else:
		_refresh_detail_panel()


func _refresh_active_page_screen() -> bool:
	return _refresh_scene_backed_page_screen()


func _refresh_page_content() -> void:
	if _mount_scene_backed_page_screen():
		return
	_hide_scene_backed_page_screens()
	_clear_transient_page_content()
	_active_page_screen = null
	match _detail_mode:
		MODE_RECRUIT:
			_build_recruit_page()
		MODE_DEBUG:
			_build_debug_page()


func _apply_mode_layout() -> void:
	var layout := _navigation.build_layout(_detail_mode, _selected_slot)
	_top_bar.visible = bool(layout.get("show_top_bar", false))
	_details_panel.visible = bool(layout.get("show_details_panel", false))
	_settlement_title.visible = bool(layout.get("show_settlement_title", false))
	_settlement_scroll.visible = bool(layout.get("show_settlement_scroll", false))
	_page_root.visible = bool(layout.get("show_page_root", false))
	_page_title.visible = bool(layout.get("show_page_title", false))
	_page_scroll.vertical_scroll_mode = int(layout.get("page_scroll_mode", ScrollContainer.SCROLL_MODE_AUTO)) as ScrollContainer.ScrollMode
	if bool(layout.get("reset_page_scroll", false)):
		_page_scroll.scroll_vertical = 0
	var page_title_key := String(layout.get("page_title_key", ""))
	var page_title_fallback := String(layout.get("page_title_fallback", ""))
	_page_title.text = _txt(page_title_key, {}, page_title_fallback) if not page_title_key.is_empty() else page_title_fallback


func _is_full_page_mode() -> bool:
	return _navigation.is_full_page_mode(_detail_mode)


func _is_scene_backed_page_mode(mode: String) -> bool:
	match mode:
		MODE_OVERVIEW, MODE_WORLD, MODE_HEROES, MODE_INVENTORY, MODE_SAVES, MODE_HERO_DETAIL:
			return true
		_:
			return false


func _mount_scene_backed_page_screen() -> bool:
	if not _is_scene_backed_page_mode(_detail_mode):
		return false
	_hide_scene_backed_page_screens(_detail_mode)
	_clear_transient_page_content()
	var screen := _get_or_create_scene_backed_page_screen(_detail_mode)
	if screen == null:
		return false
	_active_page_screen = screen
	screen.visible = true
	_set_scene_backed_page_screen_inputs(screen)
	screen.refresh()
	return true


func _get_or_create_scene_backed_page_screen(mode: String) -> Control:
	var cached_screen: Control = _scene_backed_page_screens.get(mode, null) as Control
	if cached_screen != null and is_instance_valid(cached_screen):
		return cached_screen
	var screen := _instantiate_scene_backed_page_screen(mode)
	if screen == null:
		return null
	_scene_backed_page_screens[mode] = screen
	_page_content.add_child(screen)
	_setup_scene_backed_page_screen(screen, mode)
	return screen


func _instantiate_scene_backed_page_screen(mode: String) -> Control:
	match mode:
		MODE_OVERVIEW:
			return _create_simple_page_screen("OverviewScreen", OverviewScreenScript)
		MODE_WORLD:
			return WorldScreenScene.instantiate()
		MODE_HEROES:
			return _create_simple_page_screen("HeroesScreen", HeroesScreenScript)
		MODE_INVENTORY:
			return _create_simple_page_screen("InventoryScreen", InventoryScreenScript)
		MODE_SAVES:
			return _create_simple_page_screen("SavesScreen", SavesScreenScript)
		MODE_HERO_DETAIL:
			return HeroDetailScreenScene.instantiate()
		_:
			return null


func _create_simple_page_screen(node_name: String, script_resource: Script) -> VBoxContainer:
	var screen := VBoxContainer.new()
	screen.name = node_name
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_theme_constant_override("separation", 12)
	screen.set_script(script_resource)
	return screen


func _setup_scene_backed_page_screen(screen: Control, mode: String) -> void:
	screen.visible = false
	match mode:
		MODE_OVERVIEW:
			screen.settlement_selected.connect(_open_settlement)
		MODE_WORLD:
			screen.settlement_selected.connect(_open_settlement)
		MODE_HEROES:
			screen.hero_selected.connect(_open_hero_detail)
		MODE_SAVES:
			screen.save_requested.connect(_save_to_slot)
			screen.load_requested.connect(_load_from_slot)
			screen.reset_requested.connect(_reset_save_slot)
			screen.save_name_submitted.connect(_on_save_slot_name_submitted)
			screen.save_name_focus_exited.connect(_on_save_slot_name_focus_exited)
		MODE_HERO_DETAIL:
			screen.back_requested.connect(_back_to_heroes)


func _set_scene_backed_page_screen_inputs(screen: Control) -> void:
	match _detail_mode:
		MODE_OVERVIEW:
			screen.set_settlements_snapshot(GameManager.get_owned_settlement_definitions())
		MODE_WORLD:
			screen.set_world_snapshot(GameManager.get_world_snapshot())
		MODE_HEROES:
			screen.set_heroes_snapshot(_heroes_snapshot)
		MODE_INVENTORY:
			screen.set_inventory_snapshot(_inventory_snapshot)
		MODE_SAVES:
			screen.set_slots(GameManager.get_save_slot_metadata())
		MODE_HERO_DETAIL:
			screen.set_selected_hero_uid(_selected_hero_uid)
			screen.set_heroes_snapshot(_heroes_snapshot)
			screen.set_inventory_snapshot(_inventory_snapshot)


func _refresh_scene_backed_page_screen() -> bool:
	if not _is_scene_backed_page_mode(_detail_mode):
		return false
	if _active_page_screen == null or not is_instance_valid(_active_page_screen):
		return false
	_set_scene_backed_page_screen_inputs(_active_page_screen)
	_active_page_screen.refresh()
	return true


func _hide_scene_backed_page_screens(except_mode: String = "") -> void:
	for mode in _scene_backed_page_screens.keys():
		var screen: Control = _scene_backed_page_screens.get(mode, null) as Control
		if screen == null or not is_instance_valid(screen):
			continue
		screen.visible = String(mode) == except_mode


func _clear_transient_page_content() -> void:
	for child in _page_content.get_children():
		if child is Control and _scene_backed_page_screens.values().has(child):
			continue
		_page_content.remove_child(child)
		child.queue_free()


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
	var production_preview: Dictionary = GameManager.get_slot_production_preview(slot_index)
	if not production_preview.is_empty():
		_detail_content.add_child(_make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("settlement.production", {"production": ""}).trim_suffix(" "), _format_resource_bbcode(production_preview, "refund")], 15))

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


func _build_recruit_page() -> void:
	var market_state := _recruit_market_snapshot if not _recruit_market_snapshot.is_empty() else GameManager.get_recruit_market_snapshot()
	if not bool(market_state.get("unlocked", false)):
		_page_content.add_child(_make_label("Build a Veil Tavern in any owned settlement to unlock the Recruit market.", 17))
		return
	var summary_panel := _make_panel()
	summary_panel.custom_minimum_size = Vector2(0, 92)
	_page_content.add_child(summary_panel)
	var summary_body := HBoxContainer.new()
	summary_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_body.add_theme_constant_override("separation", 18)
	summary_panel.add_child(summary_body)
	var left_summary := VBoxContainer.new()
	left_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_theme_constant_override("separation", 4)
	summary_body.add_child(left_summary)
	var summary_label := _make_label(_txt("recruit.available_heroes", {"count": int(market_state.get("offer_capacity", 0))}, "Available Heroes: %d" % int(market_state.get("offer_capacity", 0))), 19)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_child(summary_label)
	var refresh_cost := _make_rich_text_label("[color=#d8d1c6]%s[/color] %s" % [_txt("recruit.refresh_cost", {"cost": ""}, "Refresh Cost:").trim_suffix(" "), _format_resource_bbcode(_as_dictionary(market_state.get("refresh_cost", {})), "cost")], 13)
	refresh_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_summary.add_child(refresh_cost)
	var action_column := VBoxContainer.new()
	action_column.size_flags_horizontal = Control.SIZE_SHRINK_END
	action_column.alignment = BoxContainer.ALIGNMENT_CENTER
	action_column.add_theme_constant_override("separation", 4)
	summary_body.add_child(action_column)
	var refresh_button := _make_small_action_button(_txt("recruit.refresh_heroes", {}, "Refresh Heroes"), Callable(self, "_refresh_recruit_market"))
	refresh_button.custom_minimum_size = Vector2(160, 0)
	refresh_button.disabled = not GameManager.can_afford(_as_dictionary(market_state.get("refresh_cost", {})))
	action_column.add_child(refresh_button)
	var tavern_label := _make_label(_txt("recruit.taverns_owned", {"count": int(market_state.get("tavern_count", 0))}, "Taverns Owned: %d" % int(market_state.get("tavern_count", 0))), 13)
	tavern_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tavern_label.custom_minimum_size = Vector2(160, 0)
	tavern_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tavern_label.size_flags_horizontal = Control.SIZE_FILL
	tavern_label.add_theme_color_override("font_color", Color("cbbba9"))
	action_column.add_child(tavern_label)
	var offers := _as_array(market_state.get("offers", []))
	if offers.is_empty():
		_page_content.add_child(_make_label("No heroes are currently waiting. Refresh the market to draw a new slate.", 17))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_page_content.add_child(grid)
	for offer_entry in offers:
		var offer_data := _as_dictionary(offer_entry)
		grid.add_child(_make_recruit_offer_card(offer_data, _as_dictionary(offer_data.get("recruit_cost", {}))))


func _make_recruit_offer_card(offer_data: Dictionary, recruit_cost: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 236)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, Color("151214"), Color("78614e"), 10)
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
	portrait.texture = _load_hero_texture(offer_data)
	portrait_holder.add_child(portrait)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_text.add_theme_constant_override("separation", 4)
	header_row.add_child(header_text)
	var hero_name := _make_label(String(offer_data.get("name", "Unknown Hero")), 18)
	hero_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	header_text.add_child(hero_name)
	var hero_meta := _make_label("Lv.%d  |  %s" % [int(offer_data.get("level", 1)), String(offer_data.get("class", "Hero"))], 14)
	hero_meta.add_theme_color_override("font_color", Color("cbbba9"))
	header_text.add_child(hero_meta)

	var stats := _as_dictionary(offer_data.get("stats", {}))
	var work_stats := _as_dictionary(offer_data.get("work_stats", {}))
	body.add_child(_make_rich_text_label(_format_recruit_combat_stats_bbcode(stats), 13))
	body.add_child(_make_rich_text_label(_format_work_stats_bbcode(work_stats), 13))
	var cost_label := _make_rich_text_label("[color=#d8d1c6]Recruit Cost:[/color] %s" % _format_resource_bbcode(recruit_cost, "cost"), 13)
	body.add_child(cost_label)
	var recruit_button := _make_button("Recruit Hero", Callable(self, "_recruit_offer").bind(int(offer_data.get("offer_id", -1))), not GameManager.can_afford(recruit_cost))
	body.add_child(recruit_button)
	return panel


func _open_settlement(settlement_id: String) -> void:
	if not GameManager.set_active_settlement(settlement_id):
		return
	_apply_navigation_change(_navigation.request_open_settlement())


func _build_inventory_entries(items: Array, equipment: Array) -> Array:
	return UIScreenHelpers.build_inventory_entries(items, equipment)


func _make_inventory_slot(entry: Dictionary) -> PanelContainer:
	return UIScreenHelpers.make_inventory_slot(entry)


func _inventory_equipment_footer(entry: Dictionary, definition: Dictionary) -> String:
	if int(entry.get("equipped_hero_uid", -1)) > 0:
		return "Equipped"
	return UIScreenHelpers.equipment_slot_label(String(definition.get("slot", "")))


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
	heroes_body.add_child(_make_label("Adds 100 experience to every recruited hero.", 16))
	heroes_body.add_child(_make_button("Grant 100 XP All Heroes", Callable(self, "_debug_grant_hero_experience"), false))


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
	if _active_page_screen == null or not is_instance_valid(_active_page_screen):
		return
	if _detail_mode != MODE_SAVES:
		return
	_active_page_screen.set_slots(slots)
	_active_page_screen.refresh()


func _refresh_recruit_market() -> void:
	GameManager.refresh_recruit_offers()


func _recruit_offer(offer_id: int) -> void:
	GameManager.recruit_hero_from_offer(offer_id)


func _debug_grant_resources() -> void:
	GameManager.debug_grant_all_resources()


func _debug_recruit_hero() -> void:
	GameManager.debug_recruit_random_hero()


func _debug_grant_hero_experience() -> void:
	GameManager.debug_grant_all_hero_experience()


func _open_hero_detail(hero_uid: int) -> void:
	_selected_hero_uid = hero_uid
	_apply_navigation_change(_navigation.request_hero_detail())


func _back_to_heroes() -> void:
	_selected_hero_uid = -1
	_apply_navigation_change(_navigation.request_heroes())


func _load_hero_texture(hero_data: Dictionary) -> Texture2D:
	return UIScreenHelpers.load_hero_texture(hero_data)


func _refresh_settlement_title() -> void:
	var settlement_name := GameManager.get_active_settlement_name()
	if settlement_name.is_empty():
		settlement_name = "Settlement"
	_settlement_title.text = settlement_name


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


func _make_danger_button(text: String, callback: Callable) -> Button:
	var button := _make_small_nav_button(text, callback)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_color_override("font_color", Color("f2d8d4"))
	button.add_theme_color_override("font_hover_color", Color("fff0ed"))
	button.add_theme_color_override("font_pressed_color", Color("fff7f5"))
	button.add_theme_stylebox_override("normal", _button_style(Color("2a1415"), Color("8a4c49"), 6))
	button.add_theme_stylebox_override("hover", _button_style(Color("34191a"), Color("b76558"), 6))
	button.add_theme_stylebox_override("pressed", _button_style(Color("421d1d"), Color("d17a6d"), 6))
	button.add_theme_stylebox_override("disabled", _button_style(Color("1a1011"), Color("4a2f31"), 6))
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


func _format_recruit_combat_stats_bbcode(stats: Dictionary) -> String:
	var parts: Array[String] = [
		"[color=#d8847b]HP %d[/color]" % int(stats.get("health", 0)),
		"[color=#c8b8d9]SAN %d[/color]" % int(stats.get("sanity", 0)),
		"[color=#d0a170]ATK %d[/color]" % int(stats.get("attack", 0)),
		"[color=#88a8c8]DEF %d[/color]" % int(stats.get("defense", 0)),
		"[color=#f0c96c]CRIT %d%%[/color]" % int(stats.get("critical_chance", 0)),
		"[color=#e5b86f]CRIT DMG %d%%[/color]" % int(stats.get("critical_damage", 0)),
	]
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
