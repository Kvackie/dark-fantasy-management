extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")


signal save_requested(slot_index: int)
signal load_requested(slot_index: int)
signal reset_requested(slot_index: int)
signal save_name_submitted(submitted_text: String, slot_index: int, line_edit: LineEdit)
signal save_name_focus_exited(slot_index: int, line_edit: LineEdit)


var _slots: Array = []
var _save_slot_labels: Dictionary = {}
var _save_slot_name_inputs: Dictionary = {}
var _save_slot_load_buttons: Dictionary = {}


func set_slots(slots: Array) -> void:
	_slots = slots.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	_save_slot_labels.clear()
	_save_slot_name_inputs.clear()
	_save_slot_load_buttons.clear()
	add_child(UIScreenHelpers.make_label(UIScreenHelpers.txt("save.description"), 16))
	for slot_info in _slots:
		add_child(_make_save_slot_entry(slot_info))
	for slot_info in _slots:
		if slot_info is not Dictionary:
			continue
		var entry := slot_info as Dictionary
		var slot_index := int(entry.get("slot", 0))
		var label := _save_slot_labels.get(slot_index, null) as Label
		if label != null and is_instance_valid(label):
			label.text = "%s%s" % [UIScreenHelpers.txt("save.slot_heading", {"slot": slot_index}), UIScreenHelpers.txt("save.active_suffix") if bool(entry.get("active", false)) else ""]
		var input := _save_slot_name_inputs.get(slot_index, null) as LineEdit
		if input != null and is_instance_valid(input) and not input.has_focus():
			input.text = String(entry.get("name", ""))
		var load_button := _save_slot_load_buttons.get(slot_index, null) as Button
		if load_button != null and is_instance_valid(load_button):
			load_button.disabled = not bool(entry.get("exists", false))


func _make_save_slot_entry(slot_info: Dictionary) -> PanelContainer:
	var entry: Dictionary = slot_info
	var panel: PanelContainer = UIScreenHelpers.make_panel()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var slot_label: Label = UIScreenHelpers.make_label(
		"%s%s" % [UIScreenHelpers.txt("save.slot_heading", {"slot": int(entry.get("slot", 0))}), UIScreenHelpers.txt("save.active_suffix") if bool(entry.get("active", false)) else ""],
		16
	)
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slot_label)
	var slot_index := int(entry.get("slot", 1))
	_save_slot_labels[slot_index] = slot_label
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.placeholder_text = UIScreenHelpers.txt("save.name_placeholder")
	name_input.text = String(entry.get("name", ""))
	name_input.text_submitted.connect(_on_name_submitted.bind(slot_index, name_input))
	name_input.focus_exited.connect(_on_name_focus_exited.bind(slot_index, name_input))
	body.add_child(name_input)
	_save_slot_name_inputs[slot_index] = name_input
	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	body.add_child(action_row)
	action_row.add_child(UIScreenHelpers.make_small_action_button(UIScreenHelpers.txt("save.button_save"), _on_save_requested.bind(slot_index)))
	var load_button: Button = UIScreenHelpers.make_small_action_button(UIScreenHelpers.txt("save.button_load"), _on_load_requested.bind(slot_index))
	load_button.disabled = not bool(entry.get("exists", false))
	action_row.add_child(load_button)
	_save_slot_load_buttons[slot_index] = load_button
	action_row.add_child(UIScreenHelpers.make_small_action_button(UIScreenHelpers.txt("save.button_reset"), _on_reset_requested.bind(slot_index)))
	return panel


func _on_name_submitted(submitted_text: String, slot_index: int, line_edit: LineEdit) -> void:
	emit_signal("save_name_submitted", submitted_text, slot_index, line_edit)


func _on_name_focus_exited(slot_index: int, line_edit: LineEdit) -> void:
	emit_signal("save_name_focus_exited", slot_index, line_edit)


func _on_save_requested(slot_index: int) -> void:
	emit_signal("save_requested", slot_index)


func _on_load_requested(slot_index: int) -> void:
	emit_signal("load_requested", slot_index)


func _on_reset_requested(slot_index: int) -> void:
	emit_signal("reset_requested", slot_index)
