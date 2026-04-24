extends Node


const HERO_MODS_ROOT := "user://mods/heroes"
const ITEM_MODS_ROOT := "user://mods/items"
const EQUIPMENT_MODS_ROOT := "user://mods/equipment"

const TEMPLATE_HERO_MOD_ID := "template_hero"
const TEMPLATE_ITEM_MOD_ID := "template_item"
const TEMPLATE_EQUIPMENT_MOD_ID := "template_equipment"


func _ready() -> void:
	_ensure_mod_roots()
	_seed_template_mods()


func _ensure_mod_roots() -> void:
	for root_path in [HERO_MODS_ROOT, ITEM_MODS_ROOT, EQUIPMENT_MODS_ROOT]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
		if error != OK and error != ERR_ALREADY_EXISTS:
			push_warning("Failed to create mod directory: %s" % root_path)


func _seed_template_mods() -> void:
	_seed_template_hero_mod()
	_seed_template_item_mod()
	_seed_template_equipment_mod()


func _seed_template_hero_mod() -> void:
	var template_folder := HERO_MODS_ROOT.path_join(TEMPLATE_HERO_MOD_ID)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(template_folder))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Failed to create template hero directory: %s" % template_folder)
		return
	var template_hero: Dictionary = {
		"schema_version": 1,
		"id": "template_hero",
		"name": "Template Hero",
		"class": "Supporter",
		"description": "Example mod hero definition. Copy this folder, edit hero.json, and optionally add portrait.png or icon.png.",
		"level": 1,
		"experience": 0,
		"recruitment_weight": 1,
		"recruit_cost": [
			{
				"resource": "food",
				"amount": "12-18",
				"per_level": 2,
			},
			{
				"resource": "gold",
				"min_amount": 20,
				"max_amount": 28,
				"per_level": 3,
			},
			{
				"resource": "gems",
				"amount": 1,
			},
		],
		"stats": {
			"health": 96,
			"sanity": 102,
			"attack": 11,
			"defense": 10,
			"critical_chance": 6,
			"critical_damage": 145,
		},
		"work_stats": {
			"farming": 2,
			"mining": 1,
			"lumbering": 3,
		},
		"stat_growth": {
			"health": 3,
			"sanity": 2,
			"attack": 1,
			"defense": 1,
			"critical_chance": 1,
			"critical_damage": 1,
		},
		"work_stat_growth": {
			"farming": 1,
			"mining": 1,
			"lumbering": 1,
		},
	}
	_write_text_file_if_missing(template_folder.path_join("hero.json"), JSON.stringify(template_hero, "\t"))
	_write_text_file_if_missing(template_folder.path_join("README.txt"), _template_hero_mod_readme())


func _seed_template_item_mod() -> void:
	var template_folder := ITEM_MODS_ROOT.path_join(TEMPLATE_ITEM_MOD_ID)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(template_folder))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Failed to create template item directory: %s" % template_folder)
		return
	var template_item: Dictionary = {
		"items": [
			{
				"schema_version": 1,
				"id": "template_item_rations",
				"name": "Template Rations",
				"max_stack": 100000,
			},
			{
				"schema_version": 1,
				"id": "template_item_tonic",
				"name": "Template Tonic",
				"max_stack": 25,
			},
		],
	}
	_write_text_file_if_missing(template_folder.path_join("item.json"), JSON.stringify(template_item, "\t"))
	_write_text_file_if_missing(template_folder.path_join("README.txt"), _template_item_mod_readme())


func _seed_template_equipment_mod() -> void:
	var template_folder := EQUIPMENT_MODS_ROOT.path_join(TEMPLATE_EQUIPMENT_MOD_ID)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(template_folder))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Failed to create template equipment directory: %s" % template_folder)
		return
	var template_equipment: Dictionary = {
		"schema_version": 1,
		"id": "template_equipment",
		"name": "Template Equipment",
		"slot": "amulet",
		"bonuses": {
			"stats": {
				"sanity": 4,
			},
			"work_stats": {
				"farming": 1,
			},
		},
	}
	_write_text_file_if_missing(template_folder.path_join("equipment.json"), JSON.stringify(template_equipment, "\t"))
	_write_text_file_if_missing(template_folder.path_join("README.txt"), _template_equipment_mod_readme())


func _template_hero_mod_readme() -> String:
	return "Hero Mod Folder\n\n" + \
		"Required:\n" + \
		"- hero.json\n\n" + \
		"Hero fields:\n" + \
		"- id\n" + \
		"- name\n" + \
		"- class\n" + \
		"- description\n" + \
		"- level (optional; defaults to 1)\n" + \
		"- experience (optional; defaults to minimum for the current level)\n" + \
		"- recruitment_weight\n" + \
		"- recruit_cost (array; supports amount, min_amount/max_amount, and per_level)\n" + \
		"- stats\n" + \
		"- work_stats\n" + \
		"- stat_growth (optional; per-level combat stat gains)\n" + \
		"- work_stat_growth (optional; per-level work stat gains)\n\n" + \
		"Growth fields can be either fixed values like 2 or ranges like \"1-3\" or {\"min\": 1, \"max\": 3}.\n\n" + \
		"Optional:\n" + \
		"- portrait.png\n" + \
		"- icon.png\n\n" + \
		"Valid classes:\n" + \
		"- Attacker\n" + \
		"- Defender\n" + \
		"- Supporter\n\n" + \
		"Folder structure:\n" + \
		"user://mods/heroes/your_hero_mod/\n" + \
		"  hero.json\n" + \
		"  portrait.png   (optional)\n" + \
		"  icon.png       (optional)\n"


func _template_item_mod_readme() -> String:
	return "Item Mod Folder\n\n" + \
		"Required:\n" + \
		"- item.json\n\n" + \
		"Optional:\n" + \
		"- icon.png\n\n" + \
		"item.json can contain either one item object or an items array.\n\n" + \
		"Item fields:\n" + \
		"- id (optional; generated per entry if omitted)\n" + \
		"- name\n" + \
		"- max_stack (optional, defaults to 100000)\n" + \
		"- icon_path (optional)\n\n" + \
		"Folder structure:\n" + \
		"user://mods/items/your_item_mod/\n" + \
		"  item.json\n" + \
		"  icon.png   (optional)\n"


func _template_equipment_mod_readme() -> String:
	return "Equipment Mod Folder\n\n" + \
		"Required:\n" + \
		"- equipment.json\n\n" + \
		"Optional:\n" + \
		"- icon.png\n\n" + \
		"equipment.json can contain either one equipment object or an equipment array.\n\n" + \
		"Valid slots:\n" + \
		"- head\n" + \
		"- chest\n" + \
		"- gloves\n" + \
		"- boots\n" + \
		"- amulet\n" + \
		"- ring\n\n" + \
		"Equipment fields:\n" + \
		"- id (optional; generated per entry if omitted)\n" + \
		"- name\n" + \
		"- slot\n" + \
		"- icon_path (optional)\n\n" + \
		"Bonuses format:\n" + \
		"- bonuses.stats.<combat_stat>\n" + \
		"- bonuses.work_stats.<work_stat>\n\n" + \
		"Folder structure:\n" + \
		"user://mods/equipment/your_equipment_mod/\n" + \
		"  equipment.json\n" + \
		"  icon.png   (optional)\n"


func _write_text_file_if_missing(path: String, content: String) -> void:
	if FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to create file: %s" % path)
		return
	file.store_string(content)
	file.close()
