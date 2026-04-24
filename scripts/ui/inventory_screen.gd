extends VBoxContainer


const UIScreenHelpers = preload("res://scripts/ui/ui_screen_helpers.gd")
const TAB_ITEMS := "items"
const TAB_EQUIPMENT := "equipment"
const INVENTORY_HEADER_META := "inventory_header"


var _inventory_snapshot: Dictionary = {"items": [], "equipment": []}
var _active_tab: String = TAB_ITEMS
var _fixed_header_container: VBoxContainer = null


func set_inventory_snapshot(inventory_snapshot: Dictionary) -> void:
	_inventory_snapshot = inventory_snapshot.duplicate(true)


func set_fixed_header_container(container: VBoxContainer) -> void:
	_fixed_header_container = container


func refresh() -> void:
	UIScreenHelpers.clear_container(self)
	_clear_fixed_header()
	var items: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("items", []))
	var equipment: Array = UIScreenHelpers.as_array(_inventory_snapshot.get("equipment", []))
	_add_header_child(UIScreenHelpers.make_label("Recovered supplies, relics, and equipment are stored here for later use.", 16))
	_add_header_child(_make_tab_row(items.size(), equipment.size()))
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
	button.custom_minimum_size += Vector2(4, 4)
	button.add_theme_font_size_override("font_size", 20)
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


func _clear_fixed_header() -> void:
	if _fixed_header_container == null or not is_instance_valid(_fixed_header_container):
		return
	for child in _fixed_header_container.get_children():
		if not bool(child.get_meta(INVENTORY_HEADER_META, false)):
			continue
		_fixed_header_container.remove_child(child)
		child.queue_free()


func _add_header_child(node: Control) -> void:
	if _fixed_header_container == null or not is_instance_valid(_fixed_header_container):
		add_child(node)
		return
	node.set_meta(INVENTORY_HEADER_META, true)
	_fixed_header_container.add_child(node)
	var scroll_index := _fixed_header_container.get_child_count() - 1
	for index in _fixed_header_container.get_child_count():
		if _fixed_header_container.get_child(index) is ScrollContainer:
			scroll_index = index
			break
	_fixed_header_container.move_child(node, scroll_index)
