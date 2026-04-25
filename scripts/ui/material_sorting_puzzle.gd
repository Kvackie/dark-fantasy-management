extends Control


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const RETURN_MODE := "craft"

const REQUIRED_SORTS := 5
const MAX_FAILED_STRIKES := 5
const MATERIALS := ["Iron", "Timber", "Crystal", "Leather", "Coal", "Gem"]

var _target_material := ""
var _feedback_label: Label = null
var _progress_label: Label = null
var _target_label: Label = null
var _return_button: Button = null
var _successful_sorts := 0
var _failed_strikes := 0
var _completed := false


func _ready() -> void:
	_build_ui()
	_new_target()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_text_panel("Material Sorting", 34, Color("f0d0a8"), Rect2(30, 20, 430, 64))
	_add_text_panel("Pick the requested material from the tray. Wrong picks reduce craft quality.", 18, Color("cbbba9"), Rect2(30, 94, 470, 104))
	_feedback_label = _make_label("Choose the matching material.", 22, Color("f0d0a8"))
	var feedback_panel := _make_text_panel(_feedback_label)
	_set_centered_rect(feedback_panel, Vector2(580, 56), 0.5)
	feedback_panel.offset_top -= 106.0
	feedback_panel.offset_bottom -= 106.0
	add_child(feedback_panel)
	_target_label = _make_label("", 30, Color("fff4e4"))
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var target_panel := _make_text_panel(_target_label)
	_set_centered_rect(target_panel, Vector2(420, 72), 0.5)
	target_panel.offset_top -= 30.0
	target_panel.offset_bottom -= 30.0
	add_child(target_panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_set_centered_rect(grid, Vector2(540, 150), 0.5)
	grid.offset_top += 82.0
	grid.offset_bottom += 82.0
	add_child(grid)
	for material in MATERIALS:
		var button := UIScreenHelpers.make_small_action_button(String(material), Callable(self, "_choose_material").bind(String(material)))
		button.custom_minimum_size = Vector2(160, 58)
		grid.add_child(button)
	_progress_label = _make_label(_progress_text(), 20, Color("e6ddd3"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progress_panel := _make_text_panel(_progress_label)
	_set_centered_rect(progress_panel, Vector2(420, 52), 0.78)
	add_child(progress_panel)
	_return_button = UIScreenHelpers.make_small_action_button("Leave", Callable(self, "_return_to_main"))
	_return_button.anchor_left = 1.0
	_return_button.anchor_right = 1.0
	_return_button.offset_left = -158.0
	_return_button.offset_top = 24.0
	_return_button.offset_right = -24.0
	_return_button.offset_bottom = 76.0
	add_child(_return_button)


func _new_target() -> void:
	_target_material = String(MATERIALS[randi_range(0, MATERIALS.size() - 1)])
	_target_label.text = "Find: %s" % _target_material


func _choose_material(material: String) -> void:
	if _completed:
		_return_to_main()
		return
	if material == _target_material:
		_successful_sorts += 1
		_feedback_label.text = "Correct material."
		if _successful_sorts >= REQUIRED_SORTS:
			_finish_puzzle(true, "Materials sorted. Crafting complete.")
			return
		_new_target()
	else:
		_failed_strikes += 1
		_feedback_label.text = "Wrong material. Check the request."
		_progress_label.text = _progress_text()
		if _failed_strikes >= MAX_FAILED_STRIKES:
			_finish_puzzle(false, "Crafting failed. Materials were consumed.")
			return
	_progress_label.text = _progress_text()


func _finish_puzzle(success: bool, message: String) -> void:
	_completed = true
	GameManager.complete_requested_crafting(success, _failed_strikes, MAX_FAILED_STRIKES)
	_feedback_label.text = message
	_return_button.text = "Return"


func _progress_text() -> String:
	return "Sort %d / %d   Miss %d / %d" % [_successful_sorts, REQUIRED_SORTS, _failed_strikes, MAX_FAILED_STRIKES]


func _return_to_main() -> void:
	GameManager.request_ui_mode_after_scene_load(RETURN_MODE)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _add_text_panel(text: String, font_size: int, color: Color, rect: Rect2) -> void:
	var panel := _make_text_panel(_make_label(text, font_size, color))
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_left = rect.position.x
	panel.offset_top = rect.position.y
	panel.offset_right = rect.position.x + rect.size.x
	panel.offset_bottom = rect.position.y + rect.size.y
	add_child(panel)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := UIScreenHelpers.make_label(text, font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_text_panel(label: Label) -> PanelContainer:
	var panel := UIScreenHelpers.make_panel()
	UIScreenHelpers.style_panel(panel, Color("120f10", 0.74), Color("675042", 0.55), 8)
	panel.add_child(label)
	return panel


func _set_centered_rect(control: Control, size: Vector2, anchor_y: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = anchor_y
	control.anchor_bottom = anchor_y
	control.offset_left = -size.x * 0.5
	control.offset_right = size.x * 0.5
	control.offset_top = -size.y * 0.5
	control.offset_bottom = size.y * 0.5
