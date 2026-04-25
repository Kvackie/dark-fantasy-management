extends Control


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const RETURN_MODE := "craft"

const REQUIRED_STRIKES := 3
const MAX_FAILED_STRIKES := 5
const MARKER_WIDTH := 26.0
const TARGET_WIDTH := 92.0
const BAR_SIZE := Vector2(620, 52)
const STRIKE_PAUSE_SECONDS := 0.45
const RED_ZONE_START_RATIO := 0.25
const RED_ZONE_END_RATIO := 0.75
const REQUIRED_MARKER_OVERLAP_RATIO := 0.5

var _bar: Control = null
var _target: TextureRect = null
var _marker: Control = null
var _feedback_label: Label = null
var _progress_label: Label = null
var _strike_button: Button = null
var _target_x := 0.0
var _marker_t := 0.0
var _marker_direction := 1.0
var _successful_strikes := 0
var _failed_strikes := 0
var _completed := false
var _strike_paused := false
var _cost_consumed := false


func _ready() -> void:
	_build_ui()
	_reset_round.call_deferred()


func _process(delta: float) -> void:
	if _completed or _strike_paused or _bar == null or not is_instance_valid(_bar):
		return
	_marker_t += delta * 0.92 * _marker_direction
	if _marker_t >= 1.0:
		_marker_t = 1.0
		_marker_direction = -1.0
	elif _marker_t <= 0.0:
		_marker_t = 0.0
		_marker_direction = 1.0
	_update_marker_position()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := _make_label("Timing Strike", 34, Color("f0d0a8"))
	var title_panel := _make_text_panel(title)
	title_panel.anchor_left = 0.0
	title_panel.anchor_top = 0.0
	title_panel.offset_left = 30.0
	title_panel.offset_top = 20.0
	title_panel.offset_right = 430.0
	title_panel.offset_bottom = 84.0
	add_child(title_panel)
	var instructions_label := _make_label("Watch the circle move across the bar. \nPress Strike when its center is inside the red zone. \nLand %d clean strikes before %d misses." % [REQUIRED_STRIKES, MAX_FAILED_STRIKES], 18, Color("cbbba9"))
	var instructions_panel := _make_text_panel(instructions_label)
	instructions_panel.anchor_left = 0.0
	instructions_panel.anchor_top = 0.0
	instructions_panel.offset_left = 30.0
	instructions_panel.offset_top = 94.0
	instructions_panel.offset_right = 470.0
	instructions_panel.offset_bottom = 220.0
	add_child(instructions_panel)
	_feedback_label = _make_label("Time your strike.", 22, Color("f0d0a8"))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var feedback_panel := _make_text_panel(_feedback_label)
	_set_centered_rect(feedback_panel, Vector2(560, 56), 0.5)
	feedback_panel.offset_top -= 82.0
	feedback_panel.offset_bottom -= 82.0
	add_child(feedback_panel)
	_bar = Control.new()
	_set_centered_rect(_bar, BAR_SIZE, 0.5)
	_bar.offset_top += 36.0
	_bar.offset_bottom += 36.0
	_bar.clip_contents = false
	add_child(_bar)
	var bar_fill := ColorRect.new()
	bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_fill.color = Color("211819", 0.92)
	_bar.add_child(bar_fill)
	_target = TextureRect.new()
	_target.size = BAR_SIZE
	_target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_target.stretch_mode = TextureRect.STRETCH_SCALE
	_bar.add_child(_target)
	_marker = _make_circle_marker()
	_bar.add_child(_marker)
	_marker.position.y = (BAR_SIZE.y - MARKER_WIDTH) * 0.5
	_progress_label = _make_label(_progress_text(), 20, Color("e6ddd3"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progress_panel := _make_text_panel(_progress_label)
	_set_centered_rect(progress_panel, Vector2(320, 52), 0.5)
	progress_panel.offset_top += 96.0
	progress_panel.offset_bottom += 96.0
	add_child(progress_panel)
	_strike_button = UIScreenHelpers.make_small_action_button("Strike", Callable(self, "_on_strike_pressed"))
	var strike_callable := Callable(self, "_on_strike_pressed")
	if _strike_button.pressed.is_connected(strike_callable):
		_strike_button.pressed.disconnect(strike_callable)
	_strike_button.button_down.connect(_on_strike_pressed)
	_strike_button.custom_minimum_size = Vector2(260, 84)
	_strike_button.add_theme_font_size_override("font_size", 34)
	_set_centered_rect(_strike_button, Vector2(260, 84), 0.78)
	add_child(_strike_button)
	var leave_button := UIScreenHelpers.make_small_action_button("Leave", Callable(self, "_return_to_main"))
	leave_button.anchor_left = 1.0
	leave_button.anchor_right = 1.0
	leave_button.offset_left = -158.0
	leave_button.offset_top = 24.0
	leave_button.offset_right = -24.0
	leave_button.offset_bottom = 76.0
	leave_button.add_theme_font_size_override("font_size", 20)
	add_child(leave_button)


func _reset_round() -> void:
	if _bar == null or _bar.size.x <= 0.0:
		return
	var max_x: float = max(0.0, _bar.size.x - TARGET_WIDTH)
	_target_x = randf_range(0.0, max_x)
	_target.position = Vector2.ZERO
	_target.texture = _make_hot_zone_texture()
	_marker_t = randf()
	_marker_direction = 1.0 if randf() >= 0.5 else -1.0
	_update_marker_position()


func _update_marker_position() -> void:
	if _marker == null or _bar == null:
		return
	var max_center_x: float = max(0.0, _bar.size.x)
	_marker.position.x = (_marker_t * max_center_x) - (MARKER_WIDTH * 0.5)


func _on_strike_pressed() -> void:
	if _strike_paused:
		return
	if _completed:
		_return_to_main()
		return
	_strike_paused = true
	_strike_button.disabled = true
	var marker_left := _marker.position.x
	var marker_right := _marker.position.x + MARKER_WIDTH
	var red_zone_start := _target_x + (TARGET_WIDTH * RED_ZONE_START_RATIO)
	var red_zone_end := _target_x + (TARGET_WIDTH * RED_ZONE_END_RATIO)
	var overlap_width: float = min(marker_right, red_zone_end) - max(marker_left, red_zone_start)
	if overlap_width >= MARKER_WIDTH * REQUIRED_MARKER_OVERLAP_RATIO:
		_successful_strikes += 1
		_progress_label.text = _progress_text()
		_feedback_label.text = "Clean strike. Keep the rhythm."
		_flash_feedback(Color("74c476", 0.34))
		if _successful_strikes >= REQUIRED_STRIKES:
			_finish_puzzle(true, "Crafting puzzle complete.", Color("74c476", 0.34))
			return
		_resume_after_strike_pause()
	else:
		_failed_strikes += 1
		_progress_label.text = _progress_text()
		_feedback_label.text = "Glancing blow. Wait for the hot zone."
		_flash_feedback(Color("cf4f4f", 0.34))
		if _failed_strikes >= MAX_FAILED_STRIKES:
			_finish_puzzle(false, "Crafting failed. Materials were consumed.", Color("cf4f4f", 0.34))
			return
		_resume_after_strike_pause()


func _resume_after_strike_pause() -> void:
	await get_tree().create_timer(STRIKE_PAUSE_SECONDS).timeout
	if _completed:
		return
	_reset_round()
	_strike_paused = false
	_strike_button.disabled = false


func _finish_puzzle(success: bool, message: String, flash_color: Color) -> void:
	_completed = true
	_strike_paused = false
	_complete_crafting(success)
	_feedback_label.text = message
	_strike_button.text = "Return"
	_strike_button.disabled = false
	_flash_feedback(flash_color)


func _complete_crafting(success: bool) -> void:
	if _cost_consumed:
		return
	_cost_consumed = true
	GameManager.complete_requested_crafting(success, _failed_strikes, MAX_FAILED_STRIKES)


func _progress_text() -> String:
	return "Strike %d / %d   Miss %d / %d" % [_successful_strikes, REQUIRED_STRIKES, _failed_strikes, MAX_FAILED_STRIKES]


func _return_to_main() -> void:
	GameManager.request_ui_mode_after_scene_load(RETURN_MODE)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


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


func _make_circle_marker() -> PanelContainer:
	var marker := PanelContainer.new()
	marker.custom_minimum_size = Vector2(MARKER_WIDTH, MARKER_WIDTH)
	marker.size = Vector2(MARKER_WIDTH, MARKER_WIDTH)
	UIScreenHelpers.style_panel(marker, Color("f7efe3"), Color("d23a2f"), int(MARKER_WIDTH * 0.5))
	return marker


func _set_centered_rect(control: Control, size: Vector2, anchor_y: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = anchor_y
	control.anchor_bottom = anchor_y
	control.offset_left = -size.x * 0.5
	control.offset_right = size.x * 0.5
	control.offset_top = -size.y * 0.5
	control.offset_bottom = size.y * 0.5


func _make_hot_zone_texture() -> GradientTexture1D:
	var red_start := clampf((_target_x + (TARGET_WIDTH * RED_ZONE_START_RATIO)) / BAR_SIZE.x, 0.0, 1.0)
	var red_center := clampf((_target_x + (TARGET_WIDTH * 0.5)) / BAR_SIZE.x, 0.0, 1.0)
	var red_end := clampf((_target_x + (TARGET_WIDTH * RED_ZONE_END_RATIO)) / BAR_SIZE.x, 0.0, 1.0)
	var orange_start := clampf(red_start - 0.16, 0.0, 1.0)
	var orange_end := clampf(red_end + 0.16, 0.0, 1.0)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, orange_start, red_start, red_center, red_end, orange_end, 1.0])
	gradient.colors = PackedColorArray([
		Color("d08b4f", 0.34),
		Color("d08b4f", 0.5),
		Color("e06b35", 0.68),
		Color("d23a2f", 0.96),
		Color("e06b35", 0.68),
		Color("d08b4f", 0.5),
		Color("d08b4f", 0.34),
	])
	var texture := GradientTexture1D.new()
	texture.width = 256
	texture.gradient = gradient
	return texture


func _flash_feedback(color: Color) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.22)
	tween.finished.connect(flash.queue_free)
