extends RefCounted


const MODE_SETTLEMENT := "settlement"
const MODE_OVERVIEW := "overview"
const MODE_RECRUIT := "recruit"
const MODE_SAVES := "saves"
const MODE_WORLD := "world"
const MODE_HEROES := "heroes"
const MODE_INVENTORY := "inventory"
const MODE_HERO_DETAIL := "hero_detail"
const MODE_DEBUG := "debug"

const _FULL_PAGE_MODES := {
	MODE_OVERVIEW: true,
	MODE_RECRUIT: true,
	MODE_SAVES: true,
	MODE_WORLD: true,
	MODE_HEROES: true,
	MODE_INVENTORY: true,
	MODE_HERO_DETAIL: true,
	MODE_DEBUG: true,
}


func connect_navigation(target: Object, mode_buttons: Dictionary, back_button: BaseButton) -> void:
	for mode in mode_buttons.keys():
		var button := mode_buttons[mode] as BaseButton
		if button == null:
			continue
		button.pressed.connect(Callable(target, "_request_navigation_mode").bind(String(mode)))
	if back_button != null:
		back_button.pressed.connect(Callable(target, "_request_navigation_back"))


func request_mode(mode: String, selected_slot: int) -> Dictionary:
	var change := {
		"mode": mode,
		"refresh_grid": false,
		"refresh_content": true,
	}
	if mode != MODE_SETTLEMENT and selected_slot != -1:
		change["selected_slot"] = -1
		change["sync_selected_slot"] = true
	return change


func request_back_to_world() -> Dictionary:
	return {
		"mode": MODE_WORLD,
		"selected_slot": -1,
		"sync_selected_slot": true,
		"refresh_grid": true,
		"refresh_content": true,
	}


func request_settlement_from_slot() -> Dictionary:
	return {
		"mode": MODE_SETTLEMENT,
		"refresh_grid": false,
		"refresh_content": false,
	}


func request_open_settlement() -> Dictionary:
	return {
		"mode": MODE_SETTLEMENT,
		"selected_slot": -1,
		"sync_selected_slot": true,
		"apply_mode_before_selection_sync": true,
		"refresh_grid": true,
		"refresh_content": true,
	}


func request_hero_detail() -> Dictionary:
	return {
		"mode": MODE_HERO_DETAIL,
		"refresh_grid": false,
		"refresh_content": true,
	}


func request_heroes() -> Dictionary:
	return {
		"mode": MODE_HEROES,
		"refresh_grid": false,
		"refresh_content": true,
	}


func request_recruit_fallback(current_mode: String) -> Dictionary:
	if current_mode != MODE_RECRUIT:
		return {}
	return request_heroes()


func build_layout(mode: String, selected_slot: int) -> Dictionary:
	var full_page_mode := is_full_page_mode(mode)
	return {
		"show_top_bar": mode == MODE_SETTLEMENT or full_page_mode,
		"show_details_panel": mode == MODE_SETTLEMENT and selected_slot != -1,
		"show_settlement_title": mode == MODE_SETTLEMENT,
		"show_settlement_scroll": mode == MODE_SETTLEMENT,
		"show_page_root": full_page_mode,
		"show_page_title": mode != MODE_HERO_DETAIL and mode != MODE_WORLD and mode != MODE_RECRUIT,
		"page_scroll_mode": ScrollContainer.SCROLL_MODE_DISABLED if mode == MODE_HERO_DETAIL or mode == MODE_WORLD else ScrollContainer.SCROLL_MODE_AUTO,
		"reset_page_scroll": mode == MODE_HERO_DETAIL or mode == MODE_WORLD,
		"page_title_key": _page_title_key(mode),
		"page_title_fallback": _page_title_fallback(mode),
	}


func is_full_page_mode(mode: String) -> bool:
	return bool(_FULL_PAGE_MODES.get(mode, false))


func _page_title_key(mode: String) -> String:
	match mode:
		MODE_OVERVIEW:
			return "page.settlements"
		MODE_RECRUIT:
			return "page.recruit"
		MODE_SAVES:
			return "page.save_vault"
		MODE_HEROES:
			return "page.hero_inventory"
		MODE_INVENTORY:
			return "page.inventory"
		MODE_DEBUG:
			return "page.debug"
		_:
			return ""


func _page_title_fallback(mode: String) -> String:
	if mode == MODE_RECRUIT:
		return "Recruit"
	return ""
