extends Control


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const RETURN_MODE := "craft"

const RUNE_COUNT := 3
const RUNE_STEPS := 6
const MAX_FAILED_STRIKES := 5

var _feedback_label: Label = null
var _progress_label: Label = null
var _return_button: Button = null
var _rune_labels: Array[Label] = []
var _current: Array[int] = []
var _targets: Array[int] = []
var _failed_strikes := 0
var _completed := false


func _ready() -> void:
	_build_state()
	_build_ui()
	_update_display()


func _build_state() -> void:
	_current.clear()
	_targets.clear()
	for _index in range(RUNE_COUNT):
		_current.append(randi_range(0, RUNE_STEPS - 1))
		_targets.append(randi_range(0, RUNE_STEPS - 1))


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_text_panel("Rune Alignment", 34, Color("f0d0a8"), Rect2(30, 20, 430, 64))
	_add_text_panel("Rotate each rune until its current mark matches the target mark, then press Align.", 18, Color("cbbba9"), Rect2(30, 94, 500, 104))
	_feedback_label = _make_label("Align all three runes.", 22, Color("f0d0a8"))
	var feedback_panel := _make_text_panel(_feedback_label)
	_set_centered_rect(feedback_panel, Vector2(560, 56), 0.5)
	feedback_panel.offset_top -= 114.0
	feedback_panel.offset_bottom -= 114.0
	add_child(feedback_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_set_centered_rect(row, Vector2(650, 160), 0.5)
	row.offset_top += 6.0
	row.offset_bottom += 6.0
	add_child(row)
	for rune_index in range(RUNE_COUNT):
		var panel := UIScreenHelpers.make_panel()
		panel.custom_minimum_size = Vector2(190, 150)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIScreenHelpers.style_panel(panel, Color("120f10", 0.78), Color("675042", 0.65), 8)
		row.add_child(panel)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		panel.add_child(body)
		var label := _make_label("", 22, Color("fff4e4"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(label)
		_rune_labels.append(label)
		var button := UIScreenHelpers.make_small_action_button("Rotate", Callable(self, "_rotate_rune").bind(rune_index))
		button.custom_minimum_size = Vector2(150, 42)
		body.add_child(button)
	_progress_label = _make_label(_progress_text(), 20, Color("e6ddd3"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progress_panel := _make_text_panel(_progress_label)
	_set_centered_rect(progress_panel, Vector2(420, 52), 0.5)
	progress_panel.offset_top += 126.0
	progress_panel.offset_bottom += 126.0
	add_child(progress_panel)
	var align_button := UIScreenHelpers.make_small_action_button("Align", Callable(self, "_submit_alignment"))
	align_button.custom_minimum_size = Vector2(260, 84)
	align_button.add_theme_font_size_override("font_size", 34)
	_set_centered_rect(align_button, Vector2(260, 84), 0.82)
	add_child(align_button)
	_return_button = UIScreenHelpers.make_small_action_button("Leave", Callable(self, "_return_to_main"))
	_return_button.anchor_left = 1.0
	_return_button.anchor_right = 1.0
	_return_button.offset_left = -158.0
	_return_button.offset_top = 24.0
	_return_button.offset_right = -24.0
	_return_button.offset_bottom = 76.0
	add_child(_return_button)


func _rotate_rune(rune_index: int) -> void:
	if _completed:
		_return_to_main()
		return
	_current[rune_index] = (_current[rune_index] + 1) % RUNE_STEPS
	_update_display()


func _submit_alignment() -> void:
	if _completed:
		_return_to_main()
		return
	for rune_index in range(RUNE_COUNT):
		if _current[rune_index] != _targets[rune_index]:
			_failed_strikes += 1
			_feedback_label.text = "Runes are not aligned. Adjust and try again."
			_update_display()
			if _failed_strikes >= MAX_FAILED_STRIKES:
				_finish_puzzle(false, "Crafting failed. Materials were consumed.")
				return
			return
	_finish_puzzle(true, "Runes aligned. Crafting complete.")


func _update_display() -> void:
	for rune_index in range(_rune_labels.size()):
		_rune_labels[rune_index].text = "Rune %d\nCurrent: %d\nTarget: %d" % [rune_index + 1, _current[rune_index] + 1, _targets[rune_index] + 1]
	if _progress_label != null:
		_progress_label.text = _progress_text()


func _finish_puzzle(success: bool, message: String) -> void:
	_completed = true
	GameManager.complete_requested_crafting(success, _failed_strikes, MAX_FAILED_STRIKES)
	_feedback_label.text = message
	_return_button.text = "Return"


func _progress_text() -> String:
	return "Failed alignments %d / %d" % [_failed_strikes, MAX_FAILED_STRIKES]


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
