extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")


signal save_requested(slot_index: int)
signal save_name_submitted(submitted_text: String, slot_index: int, line_edit: LineEdit)
signal save_name_focus_exited(slot_index: int, line_edit: LineEdit)


var _slots: Array = []
var _save_slot_name_inputs: Dictionary = {}
var _confirmation_overlay: ColorRect = null
var _confirmation_message: Label = null
var _confirmation_confirm_button: Button = null
var _pending_action: String = ""
var _pending_slot_index: int = -1


func set_slots(slots: Array) -> void:
	_slots = slots.duplicate(true)


func refresh() -> void:
	for child in get_children():
		if child == _confirmation_overlay:
			continue
		child.queue_free()
	_save_slot_name_inputs.clear()
	_ensure_confirmation_dialog()
	add_child(UIScreenHelpers.make_label(UIScreenHelpers.txt("save.description"), 16))
	for slot_info in _slots:
		add_child(_make_save_slot_entry(slot_info))
	for slot_info in _slots:
		if slot_info is not Dictionary:
			continue
		var entry := slot_info as Dictionary
		var slot_index := int(entry.get("slot", 0))
		var input := _save_slot_name_inputs.get(slot_index, null) as LineEdit
		if input != null and is_instance_valid(input) and not input.has_focus():
			input.text = String(entry.get("name", ""))


func _ensure_confirmation_dialog() -> void:
	if _confirmation_overlay != null and is_instance_valid(_confirmation_overlay):
		return
	_confirmation_overlay = ColorRect.new()
	_confirmation_overlay.visible = false
	_confirmation_overlay.color = Color(0, 0, 0, 0.55)
	_confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirmation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.offset_left = 0.0
	_confirmation_overlay.offset_top = 0.0
	_confirmation_overlay.offset_right = 0.0
	_confirmation_overlay.offset_bottom = 0.0
	_confirmation_overlay.top_level = true
	add_child(_confirmation_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	_confirmation_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("1a1517")
	panel_style.border_color = Color("b08961")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	_confirmation_message = UIScreenHelpers.make_label("", 16)
	_confirmation_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_confirmation_message)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(UIScreenHelpers.make_small_action_button(UIScreenHelpers.txt("save.button_close"), Callable(self, "_hide_confirmation")))
	_confirmation_confirm_button = UIScreenHelpers.make_small_action_button("Confirm", Callable(self, "_on_confirmation_confirmed"))
	action_row.add_child(_confirmation_confirm_button)


func _make_save_slot_entry(slot_info: Dictionary) -> PanelContainer:
	var entry: Dictionary = slot_info
	var panel: PanelContainer = UIScreenHelpers.make_panel()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var autosave_timestamp := String(entry.get("autosave_timestamp", "")).strip_edges()
	var slot_index := int(entry.get("slot", 1))
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.custom_minimum_size = Vector2(0, 42)
	name_input.add_theme_font_size_override("font_size", 16)
	name_input.placeholder_text = UIScreenHelpers.txt("save.slot_heading", {"slot": slot_index})
	name_input.text = String(entry.get("name", ""))
	name_input.text_submitted.connect(_on_name_submitted.bind(slot_index, name_input))
	name_input.focus_exited.connect(_on_name_focus_exited.bind(slot_index, name_input))
	body.add_child(name_input)
	_save_slot_name_inputs[slot_index] = name_input
	if not autosave_timestamp.is_empty():
		body.add_child(UIScreenHelpers.make_label("Last Autosave %s" % autosave_timestamp, 14))
	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(UIScreenHelpers.make_small_action_button(UIScreenHelpers.txt("save.button_save"), _on_save_requested.bind(slot_index)))
	return panel


func _on_name_submitted(submitted_text: String, slot_index: int, line_edit: LineEdit) -> void:
	emit_signal("save_name_submitted", submitted_text, slot_index, line_edit)


func _on_name_focus_exited(slot_index: int, line_edit: LineEdit) -> void:
	emit_signal("save_name_focus_exited", slot_index, line_edit)


func _on_save_requested(slot_index: int) -> void:
	_show_confirmation("save", slot_index)
func _show_confirmation(action: String, slot_index: int) -> void:
	_ensure_confirmation_dialog()
	_pending_action = action
	_pending_slot_index = slot_index
	match action:
		"save":
			_confirmation_message.text = "Save to slot %d?\n" % slot_index
			_confirmation_confirm_button.text = UIScreenHelpers.txt("save.button_save")
		_:
			_confirmation_message.text = "Continue?"
			_confirmation_confirm_button.text = "Confirm"
	_confirmation_overlay.visible = true


func _on_confirmation_confirmed() -> void:
	match _pending_action:
		"save":
			emit_signal("save_requested", _pending_slot_index)
	_hide_confirmation()


func _hide_confirmation() -> void:
	if _confirmation_overlay != null and is_instance_valid(_confirmation_overlay):
		_confirmation_overlay.visible = false
	_pending_action = ""
	_pending_slot_index = -1
