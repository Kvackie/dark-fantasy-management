extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")


var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}


func set_inventory_snapshot(inventory_snapshot: Dictionary) -> void:
	_inventory_snapshot = inventory_snapshot.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	var items: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("items", []))
	var equipment: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("equipment", []))
	add_child(UIScreenHelpers.make_label("Recovered supplies, relics, and equipment are stored here for later use.", 16))
	add_child(UIScreenHelpers.make_label("Item Stacks %d  |  Equipment %d" % [items.size(), equipment.size()], 16))
	var entries: Array = UIScreenHelpers.build_inventory_entries(items, equipment)
	if entries.is_empty():
		add_child(UIScreenHelpers.make_label("No inventory has been recovered yet.", 18))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	add_child(grid)
	for entry in entries:
		grid.add_child(UIScreenHelpers.make_inventory_slot(entry))
