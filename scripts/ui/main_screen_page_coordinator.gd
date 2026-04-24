extends RefCounted


static func is_scene_backed_page_mode(mode: String, scene_modes: Array) -> bool:
	return scene_modes.has(mode)


static func mount_scene_backed_page_screen(page_content: VBoxContainer, scene_backed_page_screens: Dictionary, mode: String, scene_modes: Array, instantiate_callback: Callable, setup_callback: Callable, input_callback: Callable) -> Dictionary:
	if not is_scene_backed_page_mode(mode, scene_modes):
		return {"mounted": false}
	hide_scene_backed_page_screens(scene_backed_page_screens, mode)
	clear_transient_page_content(page_content, scene_backed_page_screens)
	var screen := get_or_create_scene_backed_page_screen(page_content, scene_backed_page_screens, mode, instantiate_callback, setup_callback)
	if screen == null:
		return {"mounted": false}
	screen.visible = true
	input_callback.call(screen)
	screen.refresh()
	return {
		"mounted": true,
		"screen": screen,
	}


static func get_or_create_scene_backed_page_screen(page_content: VBoxContainer, scene_backed_page_screens: Dictionary, mode: String, instantiate_callback: Callable, setup_callback: Callable) -> Control:
	var cached_screen: Control = scene_backed_page_screens.get(mode, null) as Control
	if cached_screen != null and is_instance_valid(cached_screen):
		return cached_screen
	var screen: Control = instantiate_callback.call(mode) as Control
	if screen == null:
		return null
	scene_backed_page_screens[mode] = screen
	page_content.add_child(screen)
	setup_callback.call(screen, mode)
	return screen


static func refresh_scene_backed_page_screen(active_page_screen: Control, mode: String, scene_modes: Array, input_callback: Callable) -> bool:
	if not is_scene_backed_page_mode(mode, scene_modes):
		return false
	if active_page_screen == null or not is_instance_valid(active_page_screen):
		return false
	input_callback.call(active_page_screen)
	active_page_screen.refresh()
	return true


static func hide_scene_backed_page_screens(scene_backed_page_screens: Dictionary, except_mode: String = "") -> void:
	for mode_variant in scene_backed_page_screens.keys():
		var screen: Control = scene_backed_page_screens.get(mode_variant, null) as Control
		if screen == null or not is_instance_valid(screen):
			continue
		screen.visible = String(mode_variant) == except_mode


static func clear_transient_page_content(page_content: VBoxContainer, scene_backed_page_screens: Dictionary) -> void:
	for child in page_content.get_children():
		if child is Control and scene_backed_page_screens.values().has(child):
			continue
		page_content.remove_child(child)
		child.queue_free()
