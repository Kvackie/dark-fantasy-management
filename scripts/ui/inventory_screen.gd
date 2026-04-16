extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const TAB_ITEMS := "items"
const TAB_EQUIPMENT := "equipment"


var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}
var _active_tab: String = TAB_ITEMS


func set_inventory_snapshot(inventory_snapshot: Dictionary) -> void:
	_inventory_snapshot = inventory_snapshot.duplicate(true)


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	var items: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("items", []))
	var equipment: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("equipment", []))
	add_child(UIScreenHelpers.make_label("Recovered supplies, relics, and equipment are stored here for later use.", 16))
	add_child(_make_tab_row(items.size(), equipment.size()))
	var entries: Array = _build_active_tab_entries(items, equipment)
	if entries.is_empty():
		add_child(UIScreenHelpers.make_label(_empty_tab_text(), 18))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	add_child(grid)
	for entry in entries:
		grid.add_child(UIScreenHelpers.make_inventory_slot(entry))


func _make_tab_row(item_count: int, equipment_count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_tab_button("Items %d" % item_count, TAB_ITEMS))
	row.add_child(_make_tab_button("Equipment %d" % equipment_count, TAB_EQUIPMENT))
	return row


func _make_tab_button(text: String, tab: String) -> Button:
	var button := UIScreenHelpers.make_small_action_button(text, Callable(self, "_set_active_tab").bind(tab))
	button.disabled = _active_tab == tab
	return button


func _build_active_tab_entries(items: Array, equipment: Array) -> Array:
	if _active_tab == TAB_EQUIPMENT:
		return UIScreenHelpers.build_inventory_entries([], equipment)
	return UIScreenHelpers.build_inventory_entries(items, [])


func _empty_tab_text() -> String:
	if _active_tab == TAB_EQUIPMENT:
		return "No equipment has been recovered yet."
	return "No items have been recovered yet."


func _set_active_tab(tab: String) -> void:
	if _active_tab == tab:
		return
	_active_tab = tab
	refresh()
