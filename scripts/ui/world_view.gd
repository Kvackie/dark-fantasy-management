extends Control

signal settlement_selected(settlement_id)

@onready var _node_button: Button = get_node("Center/NodeColumn/SettlementButton")

var _settlement_id: String = ""
var _pending_settlement_definition: Dictionary = {}


func _ready() -> void:
	_node_button.pressed.connect(_on_settlement_button_pressed)
	_apply_node_style()
	if not _pending_settlement_definition.is_empty():
		_apply_settlement_definition(_pending_settlement_definition)


func set_settlements(settlement_definitions: Array) -> void:
	var settlement_definition: Dictionary = {}
	if not settlement_definitions.is_empty() and settlement_definitions[0] is Dictionary:
		settlement_definition = (settlement_definitions[0] as Dictionary).duplicate(true)
	_set_settlement_definition(settlement_definition)


func _set_settlement_definition(settlement_definition: Dictionary) -> void:
	_pending_settlement_definition = settlement_definition.duplicate(true)
	if not is_node_ready():
		return
	_apply_settlement_definition(_pending_settlement_definition)


func _apply_settlement_definition(settlement_definition: Dictionary) -> void:
	_settlement_id = String(settlement_definition.get("id", "")).strip_edges()
	var settlement_name := String(settlement_definition.get("name", DataLoader.get_ui_text("common.no_settlement", {}, "No Settlement"))).strip_edges()
	_node_button.disabled = _settlement_id.is_empty()
	_node_button.text = settlement_name if not settlement_name.is_empty() else DataLoader.get_ui_text("common.no_settlement", {}, "No Settlement")


func _on_settlement_button_pressed() -> void:
	if _settlement_id.is_empty():
		return
	emit_signal("settlement_selected", _settlement_id)


func _apply_node_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2e8b57")
	normal.border_color = Color("7fd489")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate()
	hover.bg_color = Color("39a766")
	hover.border_color = Color("9bf0a3")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("26714a")
	pressed.border_color = Color("7fd489")
	var disabled := normal.duplicate()
	disabled.bg_color = Color("2a4233")
	disabled.border_color = Color("4d6b57")
	_node_button.add_theme_stylebox_override("normal", normal)
	_node_button.add_theme_stylebox_override("hover", hover)
	_node_button.add_theme_stylebox_override("pressed", pressed)
	_node_button.add_theme_stylebox_override("disabled", disabled)
	_node_button.add_theme_font_size_override("font_size", 18)
	_node_button.add_theme_color_override("font_color", Color("f3f5e8"))
	_node_button.add_theme_color_override("font_hover_color", Color("ffffff"))
	_node_button.add_theme_color_override("font_pressed_color", Color("e7f3df"))
	_node_button.add_theme_color_override("font_disabled_color", Color("bdd1c1"))
