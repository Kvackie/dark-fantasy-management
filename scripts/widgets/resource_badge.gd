extends PanelContainer

@onready var _icon_rect: TextureRect = get_node("Margin/HBox/Icon")
@onready var _name_label: Label = get_node("Margin/HBox/TextColumn/Name")
@onready var _value_label: Label = get_node("Margin/HBox/TextColumn/Value")
@onready var _yield_label: Label = get_node("Margin/HBox/TextColumn/Yield")


func _ready() -> void:
	custom_minimum_size = Vector2(110, 60)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_rect.custom_minimum_size = Vector2(34, 34)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_name_label.add_theme_font_size_override("font_size", 14)
	_value_label.add_theme_font_size_override("font_size", 20)
	_yield_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color("f1ece6"))
	_value_label.add_theme_color_override("font_color", Color("fffaf2"))
	_yield_label.modulate = Color(1, 1, 1)


func set_badge(resource_id: String, amount: int, per_tick_yield: int, icon_path: String) -> void:
	_name_label.text = resource_id.capitalize()
	_value_label.text = str(amount)
	if per_tick_yield == 0:
		_yield_label.text = ""
		_yield_label.visible = false
	else:
		_yield_label.text = "%+d/t" % per_tick_yield
		_yield_label.add_theme_color_override("font_color", Color("7edc9a") if per_tick_yield > 0 else Color("eb7d7d"))
		_yield_label.visible = true
	if ResourceLoader.exists(icon_path):
		_icon_rect.texture = load(icon_path)
