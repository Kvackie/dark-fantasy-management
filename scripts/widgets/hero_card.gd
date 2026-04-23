extends PanelContainer

signal selected(hero_uid)

const FALLBACK_TEXTURE = preload("res://icon.svg")

var _hero_data: Dictionary = {}
var _hovered: bool = false
var _accent_color: Color = Color("8d8478")
var _has_portrait: bool = false

@onready var _art: TextureRect = get_node("Art")
@onready var _tint: ColorRect = get_node("Tint")
@onready var _fallback_stack: VBoxContainer = get_node("Center/FallbackStack")
@onready var _fallback_icon: TextureRect = get_node("Center/FallbackStack/FallbackIcon")
@onready var _fallback_label: Label = get_node("Center/FallbackStack/FallbackLabel")
@onready var _level_badge: PanelContainer = get_node("Chrome/LevelBadge")
@onready var _level_label: Label = get_node("Chrome/LevelBadge/LevelLabel")
@onready var _name_bar: PanelContainer = get_node("Chrome/NameBar")
@onready var _name_label: Label = get_node("Chrome/NameBar/NameMargin/NameLabel")


func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(164, 388)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color("fff9f1"))
	_fallback_icon.texture = FALLBACK_TEXTURE
	_fallback_icon.custom_minimum_size = Vector2(118, 118)
	_fallback_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fallback_label.add_theme_font_size_override("font_size", 22)
	_fallback_label.add_theme_color_override("font_color", Color("f3e7d4"))
	_fallback_stack.add_theme_constant_override("separation", 10)
	_level_label.add_theme_font_size_override("font_size", 18)
	_level_label.add_theme_color_override("font_color", Color("fff9f1"))
	_refresh_card_style()
	if not _hero_data.is_empty():
		_apply_hero_data()


func set_hero(hero_data: Dictionary) -> void:
	_hero_data = hero_data.duplicate(true)
	if is_node_ready():
		_apply_hero_data()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("selected", int(_hero_data.get("uid", -1)))
		accept_event()


func _apply_hero_data() -> void:
	var hero_data: Dictionary = _hero_data
	var hero_definition: Dictionary = DataLoader.get_hero_definition(String(hero_data.get("definition_id", "")))
	var hero_class: String = String(hero_data.get("class", hero_definition.get("class", "Hero")))
	var class_color: Color = _class_color(hero_class)
	_accent_color = class_color
	_name_label.text = String(hero_data.get("name", "Unknown Hero"))
	_level_label.text = "Lv.%d" % int(hero_data.get("level", 1))
	_fallback_label.text = hero_class.to_upper()

	var portrait_path := String(hero_definition.get("portrait_path", ""))
	var portrait_texture: Texture2D = null
	if not portrait_path.is_empty() and portrait_path != DataLoader.DEFAULT_HERO_IMAGE:
		portrait_texture = _load_texture_from_path(portrait_path)
	_has_portrait = portrait_texture != null
	if portrait_texture != null:
		_art.texture = portrait_texture
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_art.self_modulate = Color(1, 1, 1, 1)
		_fallback_stack.visible = false
	else:
		_art.texture = null
		_art.self_modulate = Color(1, 1, 1, 1)
		_fallback_icon.self_modulate = class_color.lightened(0.25)
		_fallback_stack.visible = true
	_refresh_banner_styles()
	_refresh_card_style()


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_card_style()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_card_style()


func _refresh_card_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171214") if not _hovered else Color("1b1518")
	style.border_color = Color("7e6049") if not _hovered else _accent_color.lightened(0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.22) if not _hovered else Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.18)
	style.shadow_size = 8 if not _hovered else 12
	add_theme_stylebox_override("panel", style)
	if _has_portrait:
		_tint.color = Color(0.0, 0.0, 0.0, 0.04 if not _hovered else 0.07)
	else:
		_tint.color = Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.36 if not _hovered else 0.42)
	_refresh_banner_styles()
	if _art.texture != null:
		_art.self_modulate = Color(1, 1, 1, 1) if not _hovered else Color(1.04, 1.04, 1.04, 1)
	if _fallback_stack.visible:
		_fallback_icon.self_modulate = _accent_color.lightened(0.25 if not _hovered else 0.35)
		_fallback_label.self_modulate = Color(1, 1, 1, 1) if not _hovered else Color(1.04, 1.04, 1.04, 1)


func _refresh_banner_styles() -> void:
	var name_color := Color(_accent_color.r * 0.24, _accent_color.g * 0.24, _accent_color.b * 0.24, 0.96)
	var level_color := Color(_accent_color.r * 0.18, _accent_color.g * 0.18, _accent_color.b * 0.18, 0.94)
	if _hovered:
		name_color = name_color.lightened(0.08)
		level_color = level_color.lightened(0.1)
	_name_bar.add_theme_stylebox_override("panel", _bar_style(name_color, 0, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.34 if not _hovered else 0.54)))
	_level_badge.add_theme_stylebox_override("panel", _bar_style(level_color, 0, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.26 if not _hovered else 0.42)))


func _class_color(hero_class: String) -> Color:
	match hero_class:
		"Attacker":
			return Color("b76558")
		"Defender":
			return Color("6f8ea8")
		"Supporter":
			return Color("8f82b5")
		_:
			return Color("8d8478")


func _load_texture_from_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return load(path)
		return null
	if path.begins_with("user://") or path.is_absolute_path():
		if not FileAccess.file_exists(path):
			return null
		var image := Image.new()
		if image.load(path) != OK:
			return null
		return ImageTexture.create_from_image(image)
	return null


func _bar_style(color: Color, radius: int = 12, border_color: Color = Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_top = 2
	style.content_margin_right = 4
	style.content_margin_bottom = 2
	return style
