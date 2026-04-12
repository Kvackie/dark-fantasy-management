extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")


signal settlement_selected(settlement_id: String)


var _settlements_snapshot: Array = []


func set_settlements_snapshot(settlements_snapshot: Array) -> void:
	_settlements_snapshot = settlements_snapshot.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	if _settlements_snapshot.is_empty():
		add_child(UIScreenHelpers.make_label(UIScreenHelpers.txt("overview.no_settlements"), 16))
		return
	var owned_grid := GridContainer.new()
	owned_grid.columns = 4
	owned_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned_grid.add_theme_constant_override("h_separation", 12)
	owned_grid.add_theme_constant_override("v_separation", 12)
	add_child(owned_grid)
	for settlement_definition in _settlements_snapshot:
		var entry := UIScreenHelpers.as_dictionary(settlement_definition)
		var settlement_id := String(entry.get("id", ""))
		owned_grid.add_child(UIScreenHelpers.make_overview_settlement_tile(entry, Callable(self, "_on_settlement_pressed").bind(settlement_id)))


func _on_settlement_pressed(settlement_id: String) -> void:
	emit_signal("settlement_selected", settlement_id)
