extends Control


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const RETURN_MODE := "craft"

const REQUIRED_PUMPS := 5
const MAX_FAILED_STRIKES := 5
const BEAT_SECONDS := 1.15
const HIT_WINDOW := 0.12
const BAR_SIZE := Vector2(620, 46)

var _bar: Control = null
var _marker: ColorRect = null
var _feedback_label: Label = null
var _progress_label: Label = null
var _pump_button: Button = null
var _phase := 0.0
var _successful_pumps := 0
var _failed_strikes := 0
var _started := false
var _completed := false
var _was_in_hit_window := false
var _hit_current_beat := false


func _ready() -> void:
	_build_ui()
	_update_display()


func _process(delta: float) -> void:
	if not _started or _completed:
		return
	_phase = fmod(_phase + (delta / BEAT_SECONDS), 1.0)
	_update_missed_beat()
	_update_display()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_text_panel("Bellows Rhythm", 34, Color("f0d0a8"), Rect2(30, 20, 430, 64))
	_add_text_panel("Pump the bellows when the marker passes through the red beat window.", 18, Color("cbbba9"), Rect2(30, 94, 470, 104))
	_feedback_label = _make_label("Wait for the beat.", 22, Color("f0d0a8"))
	var feedback_panel := _make_text_panel(_feedback_label)
	_set_centered_rect(feedback_panel, Vector2(560, 56), 0.5)
	feedback_panel.offset_top -= 82.0
	feedback_panel.offset_bottom -= 82.0
	add_child(feedback_panel)
	_bar = Control.new()
	_set_centered_rect(_bar, BAR_SIZE, 0.5)
	_bar.offset_top += 24.0
	_bar.offset_bottom += 24.0
	_bar.pivot_offset = BAR_SIZE * 0.5
	add_child(_bar)
	var fill := TextureRect.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.texture = _make_rhythm_texture()
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
	_pump_button = UIScreenHelpers.make_small_action_button("Start", Callable(self, "_on_action_pressed"))
	var pump_callable := Callable(self, "_on_action_pressed")
	if _pump_button.pressed.is_connected(pump_callable):
		_pump_button.pressed.disconnect(pump_callable)
	_pump_button.button_down.connect(_on_action_pressed)
	_pump_button.custom_minimum_size = Vector2(260, 84)
	_pump_button.add_theme_font_size_override("font_size", 34)
	_set_centered_rect(_pump_button, Vector2(260, 84), 0.78)
	add_child(_pump_button)
	var leave_button := UIScreenHelpers.make_small_action_button("Leave", Callable(self, "_return_to_main"))
	leave_button.anchor_left = 1.0
	leave_button.anchor_right = 1.0
	leave_button.offset_left = -158.0
	leave_button.offset_top = 24.0
	leave_button.offset_right = -24.0
	leave_button.offset_bottom = 76.0
	add_child(leave_button)


func _on_action_pressed() -> void:
	if _completed:
		_return_to_main()
		return
	if not _started:
		_started = true
		_pump_button.text = "Pump"
		_feedback_label.text = "Wait for the beat."
		return
	_on_pump()


func _on_pump() -> void:
	var distance: float = abs(_phase - 0.5)
	if distance <= HIT_WINDOW:
		_hit_current_beat = true
		_successful_pumps += 1
		_feedback_label.text = "Strong pump. Keep rhythm."
		_progress_label.text = _progress_text()
		if _successful_pumps >= REQUIRED_PUMPS:
			_finish_puzzle(true, "Bellows rhythm held. Crafting complete.")
			return
	else:
		_add_miss()
		_feedback_label.text = "Off rhythm. Wait for the beat."
		if _failed_strikes >= MAX_FAILED_STRIKES:
			_finish_puzzle(false, "Crafting failed. Materials were consumed.")
			return


func _update_missed_beat() -> void:
	var in_window: bool = abs(_phase - 0.5) <= HIT_WINDOW
	if in_window and not _was_in_hit_window:
		_hit_current_beat = false
	if not in_window and _was_in_hit_window and not _hit_current_beat:
		_add_miss()
		_feedback_label.text = "Missed beat. Pump inside the red window."
		if _failed_strikes >= MAX_FAILED_STRIKES:
			_finish_puzzle(false, "Crafting failed. Materials were consumed.")
	_was_in_hit_window = in_window


func _add_miss() -> void:
	_failed_strikes += 1
	_progress_label.text = _progress_text()


func _update_display() -> void:
	if _marker != null:
		_marker.position.x = (_phase * BAR_SIZE.x) - (_marker.size.x * 0.5)
	if _bar != null:
		var pulse: float = 1.0 - min(abs(_phase - 0.5) / 0.5, 1.0)
		_bar.scale = Vector2(1.0 + pulse * 0.04, 1.0 + pulse * 0.22)


func _finish_puzzle(success: bool, message: String) -> void:
	_completed = true
	GameManager.complete_requested_crafting(success, _failed_strikes, MAX_FAILED_STRIKES)
	_feedback_label.text = message
	_pump_button.text = "Return"


func _progress_text() -> String:
	return "Pump %d / %d   Miss %d / %d" % [_successful_pumps, REQUIRED_PUMPS, _failed_strikes, MAX_FAILED_STRIKES]


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


func _make_rhythm_texture() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5 - HIT_WINDOW, 0.5, 0.5 + HIT_WINDOW, 1.0])
	gradient.colors = PackedColorArray([Color("8f4d2d", 0.62), Color("ff8a2f", 0.92), Color("ff1f1f"), Color("ff8a2f", 0.92), Color("8f4d2d", 0.62)])
	var texture := GradientTexture1D.new()
	texture.width = 256
	texture.gradient = gradient
	return texture
