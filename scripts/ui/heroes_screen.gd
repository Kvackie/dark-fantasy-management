extends VBoxContainer


const HeroCardScene = preload("res://scenes/widgets/hero_card.tscn")
const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")

signal hero_selected(hero_uid: int)


var _heroes_snapshot: Array = []


func set_heroes_snapshot(heroes_snapshot: Array) -> void:
	_heroes_snapshot = heroes_snapshot.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	add_child(UIScreenHelpers.make_label("All recruited heroes are gathered here. Portrait art will be used automatically when available.", 18))
	if _heroes_snapshot.is_empty():
		add_child(UIScreenHelpers.make_label("No heroes recruited yet. Build a Veil Tavern to unlock Recruit, or use the Debug menu.", 19))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 18)
	add_child(grid)
	for hero_data in _heroes_snapshot:
		var card: PanelContainer = HeroCardScene.instantiate()
		card.set_hero(hero_data)
		card.selected.connect(_on_card_selected)
		grid.add_child(card)


func _on_card_selected(hero_uid: int) -> void:
	emit_signal("hero_selected", hero_uid)
