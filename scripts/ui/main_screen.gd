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
const MainScreenPageCoordinator = preload("res://scripts/ui/main_screen_page_coordinator.gd")
const MainScreenSettlementBuilders = preload("res://scripts/ui/main_screen_settlement_builders.gd")
const MainScreenViewBuilders = preload("res://scripts/ui/main_screen_view_builders.gd")
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

const SCENE_BACKED_PAGE_MODES := [MODE_OVERVIEW, MODE_WORLD, MODE_HEROES, MODE_INVENTORY, MODE_SAVES, MODE_HERO_DETAIL]

const MAIN_MENU_ROOT := "root"
const MAIN_MENU_SAVES := "saves"
const MAIN_MENU_MODS := "mods"
const MAIN_MENU_MODS_CATEGORY := "mods_category"

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
@onready var _nav_row: HBoxContainer = get_node("Shell/BottomBar/BottomBarMargin/NavRow")
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
var _main_menu_overlay: ColorRect = null
var _main_menu_panel: PanelContainer = null
var _main_menu_title: Label = null
var _main_menu_content: VBoxContainer = null
var _main_menu_confirmation_overlay: ColorRect = null
var _main_menu_confirmation_message: Label = null
var _main_menu_confirmation_confirm_button: Button = null
var _main_menu_mode: String = MAIN_MENU_ROOT
var _main_menu_mod_category: String = ""
var _main_menu_pending_action: String = ""
var _main_menu_pending_slot: int = -1
var _zone_reward_toast: PanelContainer = null
var _zone_reward_toast_title: Label = null
var _zone_reward_toast_body: Label = null
var _zone_reward_toast_tween: Tween = null


func _ready() -> void:
	theme = UITheme
	_configure_root_layout()
	_apply_theme()
	_apply_ui_text_bundle()
	_wire_navigation()
	_build_resource_bar()
	_build_grid()
	_connect_game_manager()
	_setup_zone_reward_toast()
	_setup_main_menu_overlay()
	_refresh_settlement_title()
	_apply_mode_layout()
	_apply_responsive_layout()
	_show_main_menu()
	_refresh_recruit_nav_visibility()


func _configure_root_layout() -> void:
	custom_minimum_size = Vector2.ZERO
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_responsive_layout()


func _apply_theme() -> void:
	var chrome_nodes: Array = [
		_top_bar,
		_settlement_panel,
		_details_panel_node,
		_bottom_bar,
	]
	for chrome in chrome_nodes:
		UIScreenHelpers.style_panel(chrome, Color("211a1c"), Color("7a5e4b"), 10)
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
		UIScreenHelpers.style_button(button)
		button.add_theme_font_size_override("font_size", 23)
	UIScreenHelpers.style_label(_settlement_title, 24, true)
	UIScreenHelpers.style_label(_page_title, 24, true)
	_settlement_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var width := viewport_size.x
	var height := viewport_size.y
	var narrow_width := width < 900.0
	var compact_width := width < 1280.0
	var wide_width := width >= 1900.0
	_settlement_panel.size_flags_stretch_ratio = 1.5 if compact_width else (1.9 if wide_width else 1.7)
	_details_panel_node.size_flags_stretch_ratio = 1.05 if compact_width else (1.2 if wide_width else 1.1)
	_details_panel_node.custom_minimum_size = Vector2(280, 0) if compact_width else (Vector2(430, 0) if wide_width else Vector2(360, 0))
	_grid_container.columns = 2 if narrow_width else (3 if compact_width else 4)
	_top_bar.custom_minimum_size = Vector2(0, 78) if compact_width else (Vector2(0, 92) if wide_width else Vector2(0, 82))
	_bottom_bar.custom_minimum_size = Vector2(0, 70) if compact_width else (Vector2(0, 84) if wide_width else Vector2(0, 74))
	_nav_row.add_theme_constant_override("separation", 10 if compact_width else (14 if wide_width else 12))
	var nav_button_height := 48 if compact_width else (60 if wide_width else 52)
	for button in [_world_button, _overview_button, _recruit_button, _heroes_button, _inventory_button, _debug_button, _saves_button, _back_button]:
		button.custom_minimum_size.y = nav_button_height
	var title_font_size := 26 if compact_width else (32 if wide_width else 28)
	UIScreenHelpers.style_label(_settlement_title, title_font_size, true)
	UIScreenHelpers.style_label(_page_title, title_font_size, true)
	if _main_menu_panel != null and is_instance_valid(_main_menu_panel):
		_main_menu_panel.custom_minimum_size = Vector2(clampf(width * 0.94, 420.0, 920.0), clampf(height * 0.88, 520.0, 980.0))
	if _main_menu_confirmation_overlay != null and is_instance_valid(_main_menu_confirmation_overlay):
		var confirmation_panel := _main_menu_confirmation_overlay.get_child(0).get_child(0) as PanelContainer
		if confirmation_panel != null and is_instance_valid(confirmation_panel):
			confirmation_panel.custom_minimum_size = Vector2(clampf(width * 0.88, 340.0, 520.0), 0)


func _apply_ui_text_bundle() -> void:
	_world_button.text = _txt("nav.world")
	_overview_button.text = _txt("nav.settlements")
	_recruit_button.text = _txt("nav.recruit", {}, "Recruit")
	_heroes_button.text = _txt("nav.heroes")
	_inventory_button.text = _txt("nav.inventory")
	_debug_button.text = _txt("nav.debug")
	_saves_button.text = _txt("nav.saves")
	_back_button.text = _txt("nav.home", {}, "Main Menu")


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
	GameManager.zone_reward_notification_added.connect(_on_zone_reward_notification_added)


func _setup_zone_reward_toast() -> void:
	if _zone_reward_toast != null and is_instance_valid(_zone_reward_toast):
		return
	var toast := PanelContainer.new()
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.anchor_left = 0.5
	toast.anchor_top = 0.02
	toast.anchor_right = 0.5
	toast.anchor_bottom = 0.02
	toast.offset_left = -230.0
	toast.offset_top = 0.0
	toast.offset_right = 230.0
	toast.offset_bottom = 120.0
	UIScreenHelpers.style_panel(toast, Color("1b1718", 0.96), Color("8f6e54"), 12)
	add_child(toast)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	toast.add_child(body)
	_zone_reward_toast_title = UIScreenHelpers.make_label("", 18)
	body.add_child(_zone_reward_toast_title)
	_zone_reward_toast_body = UIScreenHelpers.make_label("", 14)
	_zone_reward_toast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_zone_reward_toast_body)
	_zone_reward_toast = toast


func _build_resource_bar() -> void:
	UIScreenHelpers.clear_container(_resources_row)
	_resource_badges.clear()
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		var badge: PanelContainer = ResourceBadgeScene.instantiate()
		_resources_row.add_child(badge)
		_resource_badges[resource_id] = badge
	_resource_values = {}
	_resource_yields = {}
	_refresh_resource_badges()


func _build_grid() -> void:
	UIScreenHelpers.clear_container(_grid_container)
	_slot_widgets.clear()
	for slot_index in GameManager.get_settlement_plot_count(GameManager.active_settlement_id):
		var slot_button: Button = SettlementSlotScene.instantiate()
		slot_button.slot_index = slot_index
		slot_button.slot_selected.connect(_on_slot_selected)
		_grid_container.add_child(slot_button)
		_slot_widgets.append(slot_button)


func _request_navigation_mode(mode: String) -> void:
	_apply_navigation_change(_navigation.request_mode(mode, _selected_slot))


func _request_navigation_back() -> void:
	_show_main_menu()


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
		if _is_full_page_mode():
			_refresh_page_content()
		else:
			_refresh_detail_panel()


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
	if _is_full_page_mode():
		if _detail_mode == MODE_OVERVIEW:
			_refresh_scene_backed_page_screen()
	else:
		_refresh_detail_panel()


func _on_active_settlement_changed(_settlement_id: String) -> void:
	_slots_snapshot = GameManager.get_slots_snapshot()
	_refresh_settlement_title()
	_refresh_resource_yields()
	if _is_full_page_mode():
		if _detail_mode == MODE_OVERVIEW:
			_refresh_scene_backed_page_screen()
	else:
		_refresh_detail_panel()


func _on_world_changed() -> void:
	_refresh_resource_yields()
	if _detail_mode == MODE_WORLD:
		return
	if _detail_mode == MODE_OVERVIEW:
		_refresh_scene_backed_page_screen()


func _on_heroes_changed() -> void:
	_heroes_snapshot = GameManager.get_heroes_snapshot()
	_resource_values[RESOURCE_ID_HEROES] = _heroes_snapshot.size()
	_refresh_resource_badges()
	_refresh_resource_yields()
	if _detail_mode == MODE_WORLD:
		return
	if _is_full_page_mode():
		if _detail_mode in [MODE_HEROES, MODE_HERO_DETAIL, MODE_OVERVIEW]:
			_refresh_scene_backed_page_screen()
	else:
		_refresh_detail_panel()


func _on_inventory_changed() -> void:
	_inventory_snapshot = GameManager.get_inventory_snapshot()
	if _detail_mode == MODE_INVENTORY or _detail_mode == MODE_HERO_DETAIL:
		if not _refresh_scene_backed_page_screen():
			if _is_full_page_mode():
				_refresh_page_content()
			else:
				_refresh_detail_panel()


func _on_recruit_market_changed() -> void:
	_recruit_market_snapshot = GameManager.get_recruit_market_snapshot()
	_refresh_recruit_nav_visibility()
	if _detail_mode == MODE_RECRUIT:
		if _is_full_page_mode():
			_refresh_page_content()
		else:
			_refresh_detail_panel()


func _refresh_resource_yields() -> void:
	_resource_yields.clear()
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		_resource_yields[resource_id] = 0.0
	var production := GameManager.get_resource_yield_preview()
	for resource_id in production.keys():
		_resource_yields[resource_id] = float(_resource_yields.get(resource_id, 0.0)) + float(production[resource_id])
	_refresh_resource_badges()


func _refresh_resource_badges() -> void:
	for resource_id in SettlementGameData.RESOURCE_ORDER:
		if _resource_badges.has(resource_id):
			_resource_badges[resource_id].set_badge(
				resource_id,
				int(_resource_values.get(resource_id, 0)),
				float(_resource_yields.get(resource_id, 0.0)),
				String(RESOURCE_ICONS.get(resource_id, ""))
			)


func _on_selection_changed(slot_index: int) -> void:
	_selected_slot = slot_index
	_apply_mode_layout()
	_refresh_grid()
	if not _is_full_page_mode():
		_refresh_detail_panel()



func _on_save_slots_changed() -> void:
	if _detail_mode == MODE_SAVES:
		_refresh_saves_page_state(GameManager.get_save_slot_metadata())


func _on_save_loaded(_slot_index: int) -> void:
	_enter_game_session()


func _enter_game_session() -> void:
	_resource_values = GameManager.get_resource_snapshot()
	_slots_snapshot = GameManager.get_slots_snapshot()
	_heroes_snapshot = GameManager.get_heroes_snapshot()
	_inventory_snapshot = GameManager.get_inventory_snapshot()
	_recruit_market_snapshot = GameManager.get_recruit_market_snapshot()
	_detail_mode = MODE_WORLD
	_selected_slot = -1
	GameManager.select_slot(-1)
	_apply_mode_layout()
	_refresh_resource_badges()
	_refresh_settlement_title()
	_refresh_grid()
	_refresh_recruit_nav_visibility()
	if _is_full_page_mode():
		_refresh_page_content()
	else:
		_refresh_detail_panel()
	_refresh_resource_yields.call_deferred()
	var world_screen := _scene_backed_page_screens.get(MODE_WORLD, null) as Control
	if world_screen != null and is_instance_valid(world_screen) and world_screen.has_method("center_on_origin"):
		world_screen.center_on_origin()
	_hide_main_menu()


func _on_tick_processed(_tick_count: int, _production_delta: Dictionary) -> void:
	_refresh_resource_yields()


func _on_zone_reward_notification_added(reward_notification: Dictionary) -> void:
	if _zone_reward_toast == null or not is_instance_valid(_zone_reward_toast):
		return
	_zone_reward_toast_title.text = String(reward_notification.get("title", "Zone Cleared"))
	var lines: Array[String] = []
	for line in UIScreenHelpers.as_array(reward_notification.get("lines", [])):
		lines.append(String(line))
	_zone_reward_toast_body.text = "\n".join(lines)
	if _zone_reward_toast_tween != null and is_instance_valid(_zone_reward_toast_tween):
		_zone_reward_toast_tween.kill()
	_zone_reward_toast.modulate = Color(1, 1, 1, 0)
	_zone_reward_toast.visible = true
	_zone_reward_toast_tween = create_tween()
	_zone_reward_toast_tween.tween_property(_zone_reward_toast, "modulate:a", 1.0, 0.18)
	_zone_reward_toast_tween.tween_interval(3.6)
	_zone_reward_toast_tween.tween_property(_zone_reward_toast, "modulate:a", 0.0, 0.3)
	_zone_reward_toast_tween.finished.connect(func() -> void:
		if _zone_reward_toast != null and is_instance_valid(_zone_reward_toast):
			_zone_reward_toast.visible = false
	)


func _setup_main_menu_overlay() -> void:
	if _main_menu_overlay != null and is_instance_valid(_main_menu_overlay):
		return
	_main_menu_overlay = ColorRect.new()
	_main_menu_overlay.visible = false
	_main_menu_overlay.color = Color(0, 0, 0, 0.74)
	_main_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu_overlay.offset_left = 0.0
	_main_menu_overlay.offset_top = 0.0
	_main_menu_overlay.offset_right = 0.0
	_main_menu_overlay.offset_bottom = 0.0
	add_child(_main_menu_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	_main_menu_overlay.add_child(center)
	_main_menu_panel = UIScreenHelpers.make_panel()
	_main_menu_panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(_main_menu_panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_main_menu_panel.add_child(body)
	_main_menu_title = UIScreenHelpers.make_label("Main Menu", 28)
	_main_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_main_menu_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_main_menu_content = VBoxContainer.new()
	_main_menu_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_menu_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_menu_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_main_menu_content)
	_setup_main_menu_confirmation_overlay()


func _setup_main_menu_confirmation_overlay() -> void:
	if _main_menu_confirmation_overlay != null and is_instance_valid(_main_menu_confirmation_overlay):
		return
	_main_menu_confirmation_overlay = ColorRect.new()
	_main_menu_confirmation_overlay.visible = false
	_main_menu_confirmation_overlay.color = Color(0, 0, 0, 0.55)
	_main_menu_confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu_confirmation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu_confirmation_overlay.offset_left = 0.0
	_main_menu_confirmation_overlay.offset_top = 0.0
	_main_menu_confirmation_overlay.offset_right = 0.0
	_main_menu_confirmation_overlay.offset_bottom = 0.0
	_main_menu_overlay.add_child(_main_menu_confirmation_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	_main_menu_confirmation_overlay.add_child(center)
	var panel := UIScreenHelpers.make_panel()
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	_main_menu_confirmation_message = UIScreenHelpers.make_label("", 16)
	_main_menu_confirmation_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_main_menu_confirmation_message)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(UIScreenHelpers.make_small_action_button("Back", Callable(self, "_hide_main_menu_confirmation")))
	_main_menu_confirmation_confirm_button = UIScreenHelpers.make_small_action_button("Confirm", Callable(self, "_confirm_main_menu_action"))
	action_row.add_child(_main_menu_confirmation_confirm_button)


func _show_main_menu(mode: String = MAIN_MENU_ROOT, mod_category: String = "") -> void:
	_setup_main_menu_overlay()
	_main_menu_mode = mode
	_main_menu_mod_category = mod_category
	_main_menu_overlay.visible = true
	_shell.visible = false
	_apply_responsive_layout()
	_refresh_main_menu()


func _hide_main_menu() -> void:
	if _main_menu_overlay != null and is_instance_valid(_main_menu_overlay):
		_main_menu_overlay.visible = false
	_shell.visible = true


func _refresh_main_menu() -> void:
	_main_menu_title.text = MainScreenViewBuilders.build_main_menu(
		_main_menu_content,
		get_viewport_rect().size.x,
		_main_menu_mode,
		_main_menu_mod_category,
		{
			"start_new_game": Callable(self, "_start_new_game_from_menu"),
			"continue_game": Callable(self, "_continue_from_main_menu"),
			"open_saves": Callable(self, "_open_main_menu_saves"),
			"open_mods": Callable(self, "_open_main_menu_mods"),
			"open_mod_category": Callable(self, "_open_main_menu_mod_category"),
			"back_to_root": Callable(self, "_back_to_main_menu_root"),
			"exit_game": Callable(self, "_exit_from_main_menu"),
			"prompt_load_save": Callable(self, "_prompt_main_menu_load_save"),
			"prompt_delete_save": Callable(self, "_prompt_main_menu_delete_save"),
		}
	)


func _start_new_game_from_menu() -> void:
	var slot_index := GameManager.get_next_new_save_slot()
	GameManager.reset_new_game()
	GameManager.emit_state()
	GameManager.save_game(slot_index)
	_enter_game_session()


func _continue_from_main_menu() -> void:
	var slot_index := GameManager.get_last_played_save_slot()
	if slot_index <= 0:
		return
	GameManager.load_game(slot_index)


func _open_main_menu_saves() -> void:
	_show_main_menu(MAIN_MENU_SAVES)


func _open_main_menu_mods() -> void:
	_show_main_menu(MAIN_MENU_MODS)


func _open_main_menu_mod_category(category: String) -> void:
	_show_main_menu(MAIN_MENU_MODS_CATEGORY, category)


func _back_to_main_menu_root() -> void:
	_show_main_menu(MAIN_MENU_ROOT)


func _exit_from_main_menu() -> void:
	get_tree().quit()


func _prompt_main_menu_load_save(slot_index: int) -> void:
	var save_name := String(GameManager.get_save_slot_summary(slot_index).get("name", "Unnamed Save"))
	_show_main_menu_confirmation("load_save", slot_index, "Load %s?\nUnsaved progress will be lost." % save_name, "Load")


func _prompt_main_menu_delete_save(slot_index: int) -> void:
	var save_name := String(GameManager.get_save_slot_summary(slot_index).get("name", "Unnamed Save"))
	_show_main_menu_confirmation("delete_save", slot_index, "Delete %s?\nThis cannot be undone." % save_name, "Delete")


func _show_main_menu_confirmation(action: String, slot_index: int, message: String, confirm_text: String) -> void:
	_main_menu_pending_action = action
	_main_menu_pending_slot = slot_index
	_main_menu_confirmation_message.text = message
	_main_menu_confirmation_confirm_button.text = confirm_text
	_main_menu_confirmation_overlay.visible = true


func _hide_main_menu_confirmation() -> void:
	if _main_menu_confirmation_overlay != null and is_instance_valid(_main_menu_confirmation_overlay):
		_main_menu_confirmation_overlay.visible = false
	_main_menu_pending_action = ""
	_main_menu_pending_slot = -1


func _confirm_main_menu_action() -> void:
	match _main_menu_pending_action:
		"load_save":
			GameManager.load_game(_main_menu_pending_slot)
		"delete_save":
			GameManager.reset_save_slot(_main_menu_pending_slot)
			_refresh_main_menu()
	_hide_main_menu_confirmation()


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
	UIScreenHelpers.clear_container(_detail_content)
	match _detail_mode:
		MainScreenNavigation.MODE_SETTLEMENT:
			_build_settlement_detail_panel()
		_:
			pass


func _refresh_page_content() -> void:
	if _mount_scene_backed_page_screen():
		return
	MainScreenPageCoordinator.hide_scene_backed_page_screens(_scene_backed_page_screens)
	MainScreenPageCoordinator.clear_transient_page_content(_page_content, _scene_backed_page_screens)
	_active_page_screen = null
	match _detail_mode:
		MODE_RECRUIT:
			MainScreenViewBuilders.build_recruit_page(_page_content, _recruit_market_snapshot if not _recruit_market_snapshot.is_empty() else GameManager.get_recruit_market_snapshot(), {
				"refresh_recruit_market": Callable(GameManager, "refresh_recruit_offers"),
				"recruit_offer": Callable(GameManager, "recruit_hero_from_offer"),
			})
		MODE_DEBUG:
			MainScreenViewBuilders.build_debug_page(_page_content, {
				"debug_grant_resources": Callable(GameManager, "debug_grant_all_resources"),
				"debug_recruit_hero": Callable(GameManager, "debug_recruit_random_hero"),
				"debug_grant_hero_experience": Callable(GameManager, "debug_grant_all_hero_experience"),
			})


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


func _mount_scene_backed_page_screen() -> bool:
	var result := MainScreenPageCoordinator.mount_scene_backed_page_screen(
		_page_content,
		_scene_backed_page_screens,
		_detail_mode,
		SCENE_BACKED_PAGE_MODES,
		Callable(self, "_instantiate_scene_backed_page_screen"),
		Callable(self, "_setup_scene_backed_page_screen"),
		Callable(self, "_set_scene_backed_page_screen_inputs")
	)
	if not bool(result.get("mounted", false)):
		return false
	_active_page_screen = result.get("screen", null) as Control
	return _active_page_screen != null


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
			screen.save_requested.connect(Callable(GameManager, "save_game"))
			screen.save_name_submitted.connect(_on_save_slot_name_submitted)
			screen.save_name_focus_exited.connect(_on_save_slot_name_focus_exited)
		MODE_HERO_DETAIL:
			screen.back_requested.connect(_back_to_heroes)


func _set_scene_backed_page_screen_inputs(screen: Control) -> void:
	match _detail_mode:
		MODE_OVERVIEW:
			screen.set_settlements_snapshot(_build_overview_settlement_snapshot())
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
	return MainScreenPageCoordinator.refresh_scene_backed_page_screen(
		_active_page_screen,
		_detail_mode,
		SCENE_BACKED_PAGE_MODES,
		Callable(self, "_set_scene_backed_page_screen_inputs")
	)


func _build_settlement_detail_panel() -> void:
	MainScreenSettlementBuilders.build_settlement_detail(
		_detail_content,
		_selected_slot,
		_detail_mode,
		_heroes_snapshot,
		{
			"close_settlement_details": Callable(self, "_close_settlement_details"),
			"build_selected_building": Callable(self, "_build_selected_building"),
			"upgrade_slot": Callable(self, "_upgrade_slot"),
			"dismantle_slot": Callable(self, "_dismantle_slot"),
			"assign_hero": Callable(self, "_assign_hero"),
			"unassign_hero": Callable(self, "_unassign_hero"),
		}
	)


func _open_settlement(settlement_id: String) -> void:
	if not GameManager.set_active_settlement(settlement_id):
		return
	_apply_navigation_change(_navigation.request_open_settlement())

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


func _refresh_saves_page_state(slots: Array) -> void:
	if _active_page_screen == null or not is_instance_valid(_active_page_screen):
		return
	if _detail_mode != MODE_SAVES:
		return
	_active_page_screen.set_slots(slots)
	_active_page_screen.refresh()

func _open_hero_detail(hero_uid: int) -> void:
	_selected_hero_uid = hero_uid
	_apply_navigation_change(_navigation.request_hero_detail())


func _back_to_heroes() -> void:
	_selected_hero_uid = -1
	_apply_navigation_change(_navigation.request_heroes())

func _refresh_settlement_title() -> void:
	var settlement_name := GameManager.get_active_settlement_name()
	if settlement_name.is_empty():
		settlement_name = "Settlement"
	_settlement_title.text = settlement_name


func _build_overview_settlement_snapshot() -> Array:
	var entries: Array = []
	for settlement_definition in GameManager.get_owned_settlement_definitions():
		var entry := UIScreenHelpers.as_dictionary(settlement_definition)
		var settlement_id := String(entry.get("id", ""))
		entries.append({
			"settlement_id": settlement_id,
			"name": String(entry.get("name", "Unknown Settlement")),
			"icon_path": String(entry.get("icon_path", DataLoader.DEFAULT_CATALOG_ICON)),
			"built_plot_count": GameManager.get_settlement_built_plot_count(settlement_id),
			"plot_count": GameManager.get_settlement_plot_count(settlement_id),
			"is_active": settlement_id == GameManager.active_settlement_id,
		})
	return entries
func _txt(key: String, replacements: Dictionary = {}, fallback: String = "") -> String:
	return DataLoader.get_ui_text(key, replacements, fallback)


func _clear_container_immediately(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
