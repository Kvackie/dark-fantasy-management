extends Control


const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const WorldScreenHelpers = preload("res://scripts/ui/world_screen_helpers.gd")
const SettlementGameData = preload("res://scripts/game/settlement_game.gd")

signal settlement_selected(settlement_id: String)

@onready var _view_host: Control = get_node("ViewHost")
@onready var _modal_overlay: ColorRect = get_node("ModalOverlay")
@onready var _popup_panel: PanelContainer = get_node("ModalOverlay/DialogCenter/PopupPanel")
@onready var _popup_title: Label = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupHeader/PopupTitle")
@onready var _popup_subtitle: Label = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupHeader/PopupSubtitle")
@onready var _popup_scroll: ScrollContainer = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupContentFrame/PopupContentMargin/PopupScroll")
@onready var _popup_body: VBoxContainer = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupContentFrame/PopupContentMargin/PopupScroll/PopupBody")
@onready var _popup_footer: HBoxContainer = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupFooter")
@onready var _hero_hover_panel: PanelContainer = get_node("ModalOverlay/HeroHoverPanel")
@onready var _hero_hover_scroll: ScrollContainer = get_node("ModalOverlay/HeroHoverPanel/HoverMargin/HoverFrame/HoverFrameMargin/HoverScroll")
@onready var _hero_hover_body: VBoxContainer = get_node("ModalOverlay/HeroHoverPanel/HoverMargin/HoverFrame/HoverFrameMargin/HoverScroll/HoverBody")
@onready var _popup_content_frame: PanelContainer = get_node("ModalOverlay/DialogCenter/PopupPanel/PopupMargin/PopupShell/PopupContentFrame")
@onready var _hero_hover_frame: PanelContainer = get_node("ModalOverlay/HeroHoverPanel/HoverMargin/HoverFrame")

var _world_view: Control = null
var _world_snapshot: Dictionary = {}
var _selected_zone_key: String = ""
var _selected_hero_uids: Array = []
var _start_clearing_button: Button = null
var _start_clearing_status_label: Label = null
var _clearing_time_label: Label = null
var _countdown_refresh_elapsed: float = 0.0
var _popup_zone_state: String = ""


func _ready() -> void:
	_ensure_world_view()
	GameManager.world_changed.connect(_on_world_changed)
	GameManager.heroes_changed.connect(_on_heroes_changed)
	GameManager.active_settlement_changed.connect(_on_active_settlement_changed)
	_popup_panel.visible = true
	_modal_overlay.visible = false
	_hero_hover_panel.visible = false
	_style_dialog_shell()
	_apply_responsive_layout()
	_layout_hover_panel()
	if _world_snapshot.is_empty():
		_world_snapshot = GameManager.get_world_snapshot()
	refresh()


func set_world_snapshot(world_snapshot: Dictionary) -> void:
	_world_snapshot = world_snapshot.duplicate(true)


func refresh() -> void:
	_refresh_world_view_snapshot()
	_refresh_popup()


func center_on_origin() -> void:
	_ensure_world_view()
	if _world_view != null and is_instance_valid(_world_view) and _world_view.has_method("center_on_origin"):
		_world_view.center_on_origin()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_responsive_layout()
		_layout_hover_panel()


func _process(delta: float) -> void:
	if _selected_zone_key.is_empty():
		return
	var zone := GameManager.get_world_zone(_selected_zone_key)
	if String(zone.get("state", "")) != "clearing":
		return
	_countdown_refresh_elapsed += delta
	if _countdown_refresh_elapsed < 0.25:
		return
	_countdown_refresh_elapsed = 0.0
	_update_clearing_popup_time(zone)


func _ensure_world_view() -> void:
	if _world_view != null and is_instance_valid(_world_view):
		return
	var world_view := WorldViewScene.instantiate()
	world_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_view.zone_selected.connect(_on_zone_selected)
	world_view.settlement_selected.connect(_on_settlement_selected)
	_view_host.add_child(world_view)
	_world_view = world_view


func _on_world_changed() -> void:
	set_world_snapshot(GameManager.get_world_snapshot())
	_refresh_world_view_snapshot()
	_sync_popup_after_world_change()


func _on_heroes_changed() -> void:
	if _selected_zone_key.is_empty():
		return
	if _popup_zone_state == "discovered":
		_refresh_popup(true)
		return
	if _popup_zone_state == "clearing":
		_refresh_start_clearing_state(GameManager.get_world_zone(_selected_zone_key))


func _on_active_settlement_changed(_settlement_id: String) -> void:
	set_world_snapshot(GameManager.get_world_snapshot())
	_refresh_world_view_snapshot()


func _on_zone_selected(zone_key: String) -> void:
	_selected_zone_key = zone_key
	_selected_hero_uids.clear()
	_refresh_popup()


func _on_settlement_selected(settlement_id: String) -> void:
	_close_popup()
	emit_signal("settlement_selected", settlement_id)


func _refresh_popup(preserve_scroll: bool = false) -> void:
	_start_clearing_button = null
	_start_clearing_status_label = null
	_clearing_time_label = null
	if _selected_zone_key.is_empty():
		_modal_overlay.visible = false
		_hide_hero_hover_popup()
		return
	var zone := GameManager.get_world_zone(_selected_zone_key)
	if zone.is_empty():
		_popup_zone_state = ""
		_selected_zone_key = ""
		if _world_view != null and is_instance_valid(_world_view) and _world_view.has_method("clear_zone_selection"):
			_world_view.clear_zone_selection()
		_modal_overlay.visible = false
		_hide_hero_hover_popup()
		return
	_clear_container_immediately(_popup_body)
	_clear_container_immediately(_popup_footer)
	var popup_scroll_vertical := _popup_scroll.scroll_vertical if preserve_scroll else 0
	_popup_scroll.scroll_vertical = 0
	_hide_hero_hover_popup()
	_modal_overlay.visible = true
	_layout_hover_panel()
	_popup_zone_state = String(zone.get("state", ""))
	match String(zone.get("state", "")):
		"discovered":
			_build_discovered_popup(zone)
		"clearing":
			_build_clearing_popup(zone)
		"cleared":
			_build_cleared_popup(zone)
		"claimed":
			_build_claimed_popup(zone)
		_:
			_close_popup()
	if _modal_overlay.visible:
		_popup_scroll.set_deferred("scroll_vertical", popup_scroll_vertical)


func _build_discovered_popup(zone: Dictionary) -> void:
	var requirements := _as_dictionary(zone.get("requirements", {}))
	_set_popup_header(
		DataLoader.get_ui_text("world.title_discovered", {}, "Uncleared Zone"),
		"%s  |  %s" % [_format_zone_time_label(_get_zone_display_total_seconds(zone), "Clearing Time"), _format_zone_requirements(requirements)]
	)
	_start_clearing_status_label = _make_popup_label("", 14, false)
	_popup_body.add_child(_start_clearing_status_label)
	_popup_body.add_child(_make_popup_label(DataLoader.get_ui_text("world.party_limit", {"count": int(_as_dictionary(_world_snapshot.get("config", {})).get("max_clearing_party", 3))}, "Select heroes"), 15, false))
	var heroes := GameManager.get_available_heroes_for_world_zone(String(zone.get("key", "")))
	if heroes.is_empty():
		_popup_body.add_child(_make_popup_label(DataLoader.get_ui_text("world.no_available_heroes", {}, "No idle heroes are available."), 15, false))
	else:
		for hero_data in heroes:
			_popup_body.add_child(_make_hero_checkbox(hero_data))
	var start_button := _make_popup_button(DataLoader.get_ui_text("world.button_begin_clearing", {}, "Begin Clearing"), Callable(self, "_start_selected_zone_clearing"))
	_start_clearing_button = start_button
	_refresh_start_clearing_state(zone)
	_popup_footer.add_child(start_button)
	_popup_footer.add_child(_make_popup_button(DataLoader.get_ui_text("world.button_close", {}, "Close"), Callable(self, "_close_popup")))


func _build_clearing_popup(zone: Dictionary) -> void:
	var requirements := _as_dictionary(zone.get("requirements", {}))
	_set_popup_header(
		DataLoader.get_ui_text("world.title_clearing", {}, "Clearing Zone"),
		"%s  |  %s" % [_format_zone_time_label(_get_zone_display_remaining_seconds(zone), "Time Remaining"), _format_zone_requirements(requirements)]
	)
	_clearing_time_label = _make_popup_label(_format_zone_time_label(_get_zone_display_remaining_seconds(zone), "Time Remaining"), 15, false)
	_popup_body.add_child(_clearing_time_label)
	_popup_footer.add_child(_make_popup_button(DataLoader.get_ui_text("world.button_close", {}, "Close"), Callable(self, "_close_popup")))


func _build_cleared_popup(zone: Dictionary) -> void:
	var zone_name := String(zone.get("generated_name", "Cleared Zone"))
	var claim_cost := _as_dictionary(zone.get("claim_cost", {}))
	var requirements := _as_dictionary(zone.get("requirements", {}))
	_set_popup_header(
		DataLoader.get_ui_text("world.title_cleared", {}, "Cleared Zone"),
		zone_name
	)
	_popup_body.add_child(_make_popup_label(zone_name, 18, false))
	_popup_body.add_child(_make_popup_label(_format_zone_requirements(requirements), 15, false))
	if bool(zone.get("no_settlement", false)):
		_popup_body.add_child(_make_popup_label("Special area. No settlement can be founded here.", 15, false))
	_popup_body.add_child(_make_popup_label(DataLoader.get_ui_text("world.claim_cost", {}, "Claim Cost"), 15, false))
	_popup_body.add_child(_make_popup_label(_format_resource_dict(claim_cost), 15, false))
	var claim_button_text := "Claim Area" if bool(zone.get("no_settlement", false)) else DataLoader.get_ui_text("world.button_claim", {}, "Claim Settlement")
	var claim_button := _make_popup_button(claim_button_text, Callable(self, "_claim_selected_zone"))
	claim_button.disabled = not GameManager.can_afford(claim_cost)
	_popup_footer.add_child(claim_button)
	_popup_footer.add_child(_make_popup_button(DataLoader.get_ui_text("world.button_close", {}, "Close"), Callable(self, "_close_popup")))


func _build_claimed_popup(zone: Dictionary) -> void:
	if not bool(zone.get("no_settlement", false)):
		_close_popup()
		return
	var zone_name := String(zone.get("generated_name", "Claimed Area"))
	var reward := _as_dictionary(zone.get("claimed_reward", {}))
	var reward_text := WorldScreenHelpers.format_claimed_reward_text(reward)
	_set_popup_header(zone_name, "Claimed Special Area")
	_popup_body.add_child(_make_popup_label(zone_name, 18, false))
	_popup_body.add_child(_make_popup_label("Special area. No settlement can be founded here.", 15, false))
	_popup_body.add_child(_make_popup_label(reward_text, 15, false))
	_popup_footer.add_child(_make_popup_button(DataLoader.get_ui_text("world.button_close", {}, "Close"), Callable(self, "_close_popup")))


func _make_hero_checkbox(hero_data: Dictionary) -> CheckBox:
	var hero_uid := int(hero_data.get("uid", -1))
	var checkbox := CheckBox.new()
	checkbox.text = String(hero_data.get("name", "Unknown Hero"))
	checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkbox.add_theme_font_size_override("font_size", 16)
	checkbox.add_theme_color_override("font_color", Color("ece2d6"))
	checkbox.add_theme_color_override("font_hover_color", Color("fff6ea"))
	checkbox.mouse_entered.connect(Callable(self, "_show_hero_hover_popup").bind(hero_data, checkbox))
	checkbox.mouse_exited.connect(Callable(self, "_hide_hero_hover_popup"))
	checkbox.button_pressed = _selected_hero_uids.has(hero_uid)
	checkbox.toggled.connect(Callable(self, "_on_hero_checkbox_toggled").bind(hero_uid, checkbox))
	return checkbox


func _on_hero_checkbox_toggled(pressed: bool, hero_uid: int, _checkbox: CheckBox) -> void:
	if pressed:
		if _selected_hero_uids.has(hero_uid):
			return
		_selected_hero_uids.append(hero_uid)
	else:
		_selected_hero_uids.erase(hero_uid)
	_refresh_start_clearing_state(GameManager.get_world_zone(_selected_zone_key))


func _start_selected_zone_clearing() -> void:
	if _selected_zone_key.is_empty():
		return
	if GameManager.start_zone_clearing(_selected_zone_key, _selected_hero_uids):
		_selected_hero_uids.clear()


func _claim_selected_zone() -> void:
	if _selected_zone_key.is_empty():
		return
	if GameManager.claim_world_zone(_selected_zone_key):
		_close_popup()


func _close_popup() -> void:
	_selected_zone_key = ""
	_popup_zone_state = ""
	_selected_hero_uids.clear()
	_start_clearing_button = null
	_modal_overlay.visible = false
	_hide_hero_hover_popup()
	if _world_view != null and is_instance_valid(_world_view) and _world_view.has_method("clear_zone_selection"):
		_world_view.clear_zone_selection()


func _make_popup_label(text: String, font_size: int, accent: bool) -> Label:
	return WorldScreenHelpers.make_popup_label(text, font_size, accent)


func _make_popup_button(text: String, callback: Callable) -> Button:
	return WorldScreenHelpers.make_popup_button(text, callback)


func _format_resource_dict(values: Dictionary) -> String:
	return WorldScreenHelpers.format_resource_dict(values)


func _format_zone_requirements(requirements: Dictionary) -> String:
	return WorldScreenHelpers.format_zone_requirements(requirements)


func _refresh_start_clearing_state(zone: Dictionary) -> void:
	if _start_clearing_button == null or not is_instance_valid(_start_clearing_button):
		return
	if zone.is_empty():
		_start_clearing_button.disabled = true
		return
	var preview := GameManager.get_world_zone_party_preview(String(zone.get("key", "")), _selected_hero_uids)
	var totals := _as_dictionary(preview.get("totals", {}))
	var requirements := _as_dictionary(preview.get("requirements", {}))
	var status_text := "Party ATK %d/%d  |  DEF %d/%d" % [int(totals.get("attack", 0)), int(requirements.get("attack", 0)), int(totals.get("defense", 0)), int(requirements.get("defense", 0))]
	if _selected_hero_uids.is_empty():
		_start_clearing_button.disabled = true
	elif not bool(preview.get("meets_requirements", false)):
		status_text += "\nParty is too weak to begin clearing."
		_start_clearing_button.disabled = true
	else:
		status_text += "\nParty meets requirements."
		_start_clearing_button.disabled = false
	if _start_clearing_status_label != null and is_instance_valid(_start_clearing_status_label):
		_start_clearing_status_label.text = status_text


func _get_zone_display_total_seconds(zone: Dictionary) -> float:
	return float(int(zone.get("clear_duration", 0))) * SettlementGameData.TICK_SECONDS


func _get_zone_display_remaining_seconds(zone: Dictionary) -> float:
	var clear_end_unix := float(zone.get("clear_end_unix", 0.0))
	if clear_end_unix > 0.0:
		return max(0.0, clear_end_unix - Time.get_unix_time_from_system())
	return float(int(zone.get("ticks_remaining", 0))) * SettlementGameData.TICK_SECONDS


func _format_zone_time_label(total_seconds: float, label_text: String) -> String:
	return WorldScreenHelpers.format_zone_time_label(total_seconds, label_text)


func _update_clearing_popup_time(zone: Dictionary) -> void:
	var requirements := _as_dictionary(zone.get("requirements", {}))
	_popup_subtitle.text = "%s  |  %s" % [_format_zone_time_label(_get_zone_display_remaining_seconds(zone), "Time Remaining"), _format_zone_requirements(requirements)]
	if _clearing_time_label != null and is_instance_valid(_clearing_time_label):
		_clearing_time_label.text = _format_zone_time_label(_get_zone_display_remaining_seconds(zone), "Time Remaining")


func _refresh_world_view_snapshot() -> void:
	_ensure_world_view()
	if _world_view != null and is_instance_valid(_world_view):
		_world_view.set_world_snapshot(_world_snapshot)


func _sync_popup_after_world_change() -> void:
	if _selected_zone_key.is_empty():
		return
	var zone := GameManager.get_world_zone(_selected_zone_key)
	if zone.is_empty():
		_refresh_popup(true)
		return
	var zone_state := String(zone.get("state", ""))
	if zone_state != _popup_zone_state:
		_refresh_popup(true)
		return
	if zone_state == "clearing":
		_update_clearing_popup_time(zone)
		return
	if zone_state == "cleared":
		_refresh_popup(true)


func _as_dictionary(value: Variant) -> Dictionary:
	return UIScreenHelpers.as_dictionary(value)


func _as_array(value: Variant) -> Array:
	return UIScreenHelpers.as_array(value)


func _set_popup_header(title_text: String, subtitle_text: String) -> void:
	_popup_title.text = title_text
	_popup_subtitle.text = subtitle_text


func _apply_responsive_layout() -> void:
	var width := get_viewport_rect().size.x
	_popup_panel.custom_minimum_size = Vector2(clampf(width * 0.94, 380.0, 760.0), 0)


func _style_dialog_shell() -> void:
	WorldScreenHelpers.apply_dialog_shell_style(_popup_panel, _popup_content_frame, _hero_hover_frame, _hero_hover_panel, _popup_title, _popup_subtitle)


func _show_hero_hover_popup(hero_data: Dictionary, _source_control: Control) -> void:
	_clear_container_immediately(_hero_hover_body)
	_hero_hover_scroll.scroll_vertical = 0
	_hero_hover_panel.size = Vector2.ZERO
	_hero_hover_panel.custom_minimum_size = Vector2.ZERO
	_hero_hover_panel.offset_left = 0.0
	_hero_hover_panel.offset_top = 0.0
	_hero_hover_panel.offset_right = 0.0
	_hero_hover_panel.offset_bottom = 0.0
	var hero_uid := int(hero_data.get("uid", -1))
	var combat_stats := GameManager.get_hero_effective_stats(hero_uid)
	_hero_hover_body.add_child(_make_hover_label(String(hero_data.get("name", "Unknown Hero")), 20, true))
	_hero_hover_body.add_child(_make_colored_stat_line("Class", String(hero_data.get("class", "Hero")), Color("#b58ad1")))
	_hero_hover_body.add_child(_make_colored_stat_line("Level", str(int(hero_data.get("level", 1))), Color("#d0a170")))
	_hero_hover_body.add_child(_make_colored_stat_line("Health", "%d/%d" % [int(combat_stats.get("current_health", combat_stats.get("health", 0))), int(combat_stats.get("max_health", combat_stats.get("health", 0)))], Color("#d97777")))
	_hero_hover_body.add_child(_make_colored_stat_line("Sanity", "%d/%d" % [int(combat_stats.get("current_sanity", combat_stats.get("sanity", 0))), int(combat_stats.get("max_sanity", combat_stats.get("sanity", 0)))], Color("#90b3d7")))
	_hero_hover_body.add_child(_make_colored_stat_line("Attack", str(int(combat_stats.get("attack", 0))), Color("#df8c66")))
	_hero_hover_body.add_child(_make_colored_stat_line("Defense", str(int(combat_stats.get("defense", 0))), Color("#8fb7cb")))
	_hero_hover_body.add_child(_make_colored_stat_line("Critical Chance", str(int(combat_stats.get("critical_chance", 0))), Color("#d8ba69")))
	_hero_hover_body.add_child(_make_colored_stat_line("Critical Damage", str(int(combat_stats.get("critical_damage", 0))), Color("#c66f62")))
	_hero_hover_panel.visible = true
	_layout_hover_panel()


func _hide_hero_hover_popup() -> void:
	_hero_hover_panel.visible = false
	_layout_hover_panel()


func _make_colored_stat_line(label_text: String, value_text: String, accent_color: Color) -> HBoxContainer:
	return WorldScreenHelpers.make_colored_stat_line(label_text, value_text, accent_color)


func _make_hover_label(text: String, font_size: int, accent: bool) -> Label:
	return WorldScreenHelpers.make_hover_label(text, font_size, accent)


func _layout_hover_panel() -> void:
	if not is_node_ready():
		return
	if not _hero_hover_panel.visible:
		return
	var popup_rect := _popup_panel.get_global_rect()
	var overlay_rect := _modal_overlay.get_global_rect()
	var hover_width: float = snappedf(popup_rect.size.x * 0.52, 1.0)
	var hover_height: float = snappedf(popup_rect.size.y, 1.0)
	_hero_hover_panel.custom_minimum_size = Vector2(hover_width, hover_height)
	_hero_hover_panel.size = Vector2(hover_width, hover_height)
	_hero_hover_panel.offset_right = hover_width
	_hero_hover_panel.offset_bottom = hover_height
	var target_x := popup_rect.position.x + popup_rect.size.x + 16.0
	if target_x + hover_width > overlay_rect.position.x + overlay_rect.size.x - 12.0:
		target_x = overlay_rect.position.x + overlay_rect.size.x - hover_width - 12.0
	var target_y := clampf(popup_rect.position.y, overlay_rect.position.y + 12.0, overlay_rect.position.y + overlay_rect.size.y - hover_height - 12.0)
	_hero_hover_panel.global_position = Vector2(target_x, target_y)
	_hero_hover_panel.position = Vector2(target_x - overlay_rect.position.x, target_y - overlay_rect.position.y)


func _clear_container_immediately(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
