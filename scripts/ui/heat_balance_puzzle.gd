extends Control


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const RETURN_MODE := "craft"

const REQUIRED_SECONDS := 4.0
const MAX_FAILED_STRIKES := 5
const BAR_SIZE := Vector2(620, 46)
const SAFE_MIN := 0.42
const SAFE_MAX := 0.58

var _bar: Control = null
var _marker: ColorRect = null
var _feedback_label: Label = null
var _progress_label: Label = null
var _finish_button: Button = null
var _start_button: Button = null
var _stoke_button: Button = null
var _vent_button: Button = null
var _heat := 0.5
var _held_seconds := 0.0
var _failed_strikes := 0
var _outside_seconds := 0.0
var _started := false
var _completed := false


func _ready() -> void:
	_build_ui()
	_update_display()


func _process(delta: float) -> void:
	if not _started or _completed:
		return
	_heat = clampf(_heat - (0.07 * delta), 0.0, 1.0)
	if _is_heat_safe():
		_held_seconds += delta
		_outside_seconds = 0.0
		_feedback_label.text = "Stable heat. Hold it there."
		if _held_seconds >= REQUIRED_SECONDS:
			_finish_puzzle(true, "Heat balanced. Crafting complete.")
			return
	else:
		_outside_seconds += delta
		_feedback_label.text = "Heat is drifting. Correct it."
		if _outside_seconds >= 0.8:
			_failed_strikes += 1
			_outside_seconds = 0.0
			_update_display()
			if _failed_strikes >= MAX_FAILED_STRIKES:
				_finish_puzzle(false, "Crafting failed. Materials were consumed.")
				return
	_update_display()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_text_panel("Heat Balance", 34, Color("f0d0a8"), Rect2(30, 20, 400, 64))
	_add_text_panel("Keep the forge heat inside the safe center band. Use Stoke and Vent to control it.", 18, Color("cbbba9"), Rect2(30, 94, 440, 104))
	_feedback_label = _make_label("Balance the heat.", 22, Color("f0d0a8"))
	var feedback_panel := _make_text_panel(_feedback_label)
	_set_centered_rect(feedback_panel, Vector2(560, 56), 0.5)
	feedback_panel.offset_top -= 82.0
	feedback_panel.offset_bottom -= 82.0
	add_child(feedback_panel)
	_bar = Control.new()
	_set_centered_rect(_bar, BAR_SIZE, 0.5)
	_bar.offset_top += 24.0
	_bar.offset_bottom += 24.0
	add_child(_bar)
	var fill := TextureRect.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.texture = _make_heat_texture()
	_bar.add_child(fill)
	_marker = ColorRect.new()
	_marker.color = Color("f7efe3")
	_marker.size = Vector2(10, BAR_SIZE.y + 18)
	_marker.position.y = -9.0
	_bar.add_child(_marker)
	_progress_label = _make_label(_progress_text(), 20, Color("e6ddd3"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progress_panel := _make_text_panel(_progress_label)
	_set_centered_rect(progress_panel, Vector2(420, 52), 0.5)
	progress_panel.offset_top += 96.0
	progress_panel.offset_bottom += 96.0
	add_child(progress_panel)
	_start_button = UIScreenHelpers.make_small_action_button("Start", Callable(self, "_start_puzzle"))
	_start_button.custom_minimum_size = Vector2(220, 68)
	_start_button.add_theme_font_size_override("font_size", 30)
	_set_centered_rect(_start_button, Vector2(220, 68), 0.72)
	add_child(_start_button)
	_stoke_button = UIScreenHelpers.make_small_action_button("Stoke", Callable(self, "_adjust_heat").bind(0.09))
	_stoke_button.disabled = true
	_set_centered_rect(_stoke_button, Vector2(180, 68), 0.84)
	_stoke_button.offset_left -= 100.0
	_stoke_button.offset_right -= 100.0
	add_child(_stoke_button)
	_vent_button = UIScreenHelpers.make_small_action_button("Vent", Callable(self, "_adjust_heat").bind(-0.09))
	_vent_button.disabled = true
	_set_centered_rect(_vent_button, Vector2(180, 68), 0.84)
	_vent_button.offset_left += 100.0
	_vent_button.offset_right += 100.0
	add_child(_vent_button)
	_finish_button = UIScreenHelpers.make_small_action_button("Leave", Callable(self, "_return_to_main"))
	_finish_button.anchor_left = 1.0
	_finish_button.anchor_right = 1.0
	_finish_button.offset_left = -158.0
	_finish_button.offset_top = 24.0
	_finish_button.offset_right = -24.0
	_finish_button.offset_bottom = 76.0
	add_child(_finish_button)


func _adjust_heat(delta: float) -> void:
	if not _started:
		return
	if _completed:
		_return_to_main()
		return
	_heat = clampf(_heat + delta, 0.0, 1.0)
	_update_display()


func _start_puzzle() -> void:
	_started = true
	_feedback_label.text = "Stable heat. Hold it there."
	_start_button.visible = false
	_stoke_button.disabled = false
	_vent_button.disabled = false


func _is_heat_safe() -> bool:
	return _heat >= SAFE_MIN and _heat <= SAFE_MAX


func _update_display() -> void:
	if _marker != null and _bar != null:
		_marker.position.x = (_heat * BAR_SIZE.x) - (_marker.size.x * 0.5)
	if _progress_label != null:
		_progress_label.text = _progress_text()


func _finish_puzzle(success: bool, message: String) -> void:
	_completed = true
	GameManager.complete_requested_crafting(success, _failed_strikes, MAX_FAILED_STRIKES)
	_feedback_label.text = message
	_finish_button.text = "Return"


func _progress_text() -> String:
	return "Stable %.1fs / %.1fs   Miss %d / %d" % [_held_seconds, REQUIRED_SECONDS, _failed_strikes, MAX_FAILED_STRIKES]


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


func _make_heat_texture() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, SAFE_MIN, 0.5, SAFE_MAX, 1.0])
	gradient.colors = PackedColorArray([Color("c44d3c"), Color("d08b4f"), Color("74c476"), Color("d08b4f"), Color("c44d3c")])
	var texture := GradientTexture1D.new()
	texture.width = 256
	texture.gradient = gradient
	return texture
