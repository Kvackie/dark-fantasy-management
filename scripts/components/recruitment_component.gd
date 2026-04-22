extends RefCounted


static func roll_hero_definition() -> Dictionary:
	return roll_weighted_hero_definition(DataLoader.get_all_heroes())


static func hero_definition_has_gem_cost(hero_definition: Dictionary) -> bool:
	for cost_entry in _as_array(hero_definition.get("recruit_cost", [])):
		var entry := _as_dictionary(cost_entry)
		if String(entry.get("resource", "")).strip_edges() == "gems":
			return true
	return false


static func build_recruitable_hero_pool(include_gem_cost_heroes: bool) -> Array:
	var recruitable_pool: Array = []
	for hero_definition in DataLoader.get_all_heroes():
		var hero_data: Dictionary = hero_definition
		if not include_gem_cost_heroes and hero_definition_has_gem_cost(hero_data):
			continue
		recruitable_pool.append(hero_data)
	return recruitable_pool


static func roll_weighted_hero_definition(roster: Array) -> Dictionary:
	if roster.is_empty():
		return {}
	var total_weight: int = 0
	for hero_definition in roster:
		var hero_data: Dictionary = hero_definition
		total_weight += max(1, int(hero_data.get("recruitment_weight", 1)))
	var roll: int = randi_range(1, total_weight)
	var cursor: int = 0
	for hero_definition in roster:
		var hero_data: Dictionary = hero_definition
		cursor += max(1, int(hero_data.get("recruitment_weight", 1)))
		if roll <= cursor:
			return hero_data.duplicate(true)
	return (roster[0] as Dictionary).duplicate(true)


static func resolve_recruit_cost(hero_definition: Dictionary, hero_level: int) -> Dictionary:
	var resolved_cost: Dictionary = {}
	for cost_entry in _as_array(hero_definition.get("recruit_cost", [])):
		var entry := _as_dictionary(cost_entry)
		var resource_id := String(entry.get("resource", "")).strip_edges()
		if resource_id.is_empty():
			continue
		var base_amount := 0
		if entry.has("min_amount") or entry.has("max_amount"):
			var min_amount := int(entry.get("min_amount", 0))
			var max_amount := int(entry.get("max_amount", min_amount))
			if max_amount < min_amount:
				var swap_amount := min_amount
				min_amount = max_amount
				max_amount = swap_amount
			base_amount = randi_range(min_amount, max_amount)
		else:
			base_amount = int(entry.get("amount", 0))
		var final_amount: int = max(0, base_amount + max(hero_level - 1, 0) * int(entry.get("per_level", 0)))
		if final_amount <= 0:
			continue
		resolved_cost[resource_id] = int(resolved_cost.get(resource_id, 0)) + final_amount
	return resolved_cost


static func normalize_resolved_recruit_cost(value: Variant) -> Dictionary:
	var normalized_cost: Dictionary = {}
	var source_cost := _as_dictionary(value)
	for resource_id in source_cost.keys():
		normalized_cost[String(resource_id)] = max(0, int(source_cost.get(resource_id, 0)))
	return normalized_cost


static func create_recruit_offer(hero_definition: Dictionary, offer_id: int) -> Dictionary:
	var hero_level := clampi(int(hero_definition.get("level", 1)), 1, 9999)
	var offer_data: Dictionary = {
		"offer_id": offer_id,
		"definition_id": String(hero_definition.get("id", "")),
		"name": String(hero_definition.get("name", "Unknown Hero")),
		"class": String(hero_definition.get("class", "Supporter")),
		"level": hero_level,
		"recruit_cost": resolve_recruit_cost(hero_definition, hero_level),
		"stats": _normalize_runtime_stats(hero_definition.get("stats", {}), DataLoader.DEFAULT_HERO_STATS),
		"work_stats": _normalize_runtime_stats(hero_definition.get("work_stats", {}), DataLoader.DEFAULT_HERO_WORK_STATS),
		"source": String(hero_definition.get("source", "core")),
		"mod_id": String(hero_definition.get("mod_id", "")),
	}
	return offer_data


static func generate_recruit_offer_batch_from_pool_with_exclusions(hero_pool: Array, offer_count: int, excluded_definition_ids: Array, start_offer_id: int) -> Dictionary:
	var offers: Array = []
	var next_offer_id: int = start_offer_id
	if offer_count <= 0 or hero_pool.is_empty():
		return {"offers": offers, "next_offer_id": next_offer_id}
	var used_definition_ids: Dictionary = {}
	for definition_id in excluded_definition_ids:
		used_definition_ids[String(definition_id)] = true
	while offers.size() < offer_count:
		var weighted_pool: Array = []
		for entry in hero_pool:
			var hero_definition: Dictionary = entry
			var definition_id := String(hero_definition.get("id", ""))
			if used_definition_ids.has(definition_id):
				continue
			weighted_pool.append(hero_definition)
		if weighted_pool.is_empty():
			weighted_pool = hero_pool
		var selected_definition := roll_weighted_hero_definition(weighted_pool)
		if selected_definition.is_empty():
			break
		offers.append(create_recruit_offer(selected_definition, next_offer_id))
		next_offer_id += 1
		used_definition_ids[String(selected_definition.get("id", ""))] = true
	return {"offers": offers, "next_offer_id": next_offer_id}


static func generate_recruit_offer_batch_with_exclusions(offer_count: int, excluded_definition_ids: Array, start_offer_id: int) -> Dictionary:
	return generate_recruit_offer_batch_from_pool_with_exclusions(DataLoader.get_all_heroes(), offer_count, excluded_definition_ids, start_offer_id)


static func generate_recruit_offer_batch(offer_count: int, start_offer_id: int) -> Dictionary:
	return generate_recruit_offer_batch_with_exclusions(offer_count, [], start_offer_id)


static func get_recruit_offer_definition_ids(offers: Array) -> Array:
	var definition_ids: Array = []
	for offer_entry in offers:
		var offer_data: Dictionary = offer_entry
		var definition_id := String(offer_data.get("definition_id", "")).strip_edges()
		if definition_id.is_empty():
			continue
		definition_ids.append(definition_id)
	return definition_ids


static func find_recruit_offer_index(offers: Array, offer_id: int) -> int:
	for offer_index in range(offers.size()):
		var offer_data: Dictionary = offers[offer_index]
		if int(offer_data.get("offer_id", -1)) == offer_id:
			return offer_index
	return -1


static func normalize_loaded_recruit_market_offers(value: Variant) -> Array:
	var normalized_offers: Array = []
	if value is not Array:
		return normalized_offers
	for offer_entry in value:
		if offer_entry is not Dictionary:
			continue
		var offer_data: Dictionary = (offer_entry as Dictionary).duplicate(true)
		var definition_id := String(offer_data.get("definition_id", "")).strip_edges()
		if definition_id.is_empty():
			continue
		var hero_definition := DataLoader.get_hero_definition(definition_id)
		normalized_offers.append({
			"offer_id": max(1, int(offer_data.get("offer_id", normalized_offers.size() + 1))),
			"definition_id": definition_id,
			"name": String(offer_data.get("name", hero_definition.get("name", "Unknown Hero"))),
			"class": String(offer_data.get("class", hero_definition.get("class", "Supporter"))),
			"level": clampi(int(offer_data.get("level", 1)), 1, 9999),
			"recruit_cost": normalize_resolved_recruit_cost(offer_data.get("recruit_cost", resolve_recruit_cost(hero_definition, clampi(int(offer_data.get("level", 1)), 1, 9999)))),
			"stats": _normalize_runtime_stats(offer_data.get("stats", {}), hero_definition.get("stats", DataLoader.DEFAULT_HERO_STATS)),
			"work_stats": _normalize_runtime_stats(offer_data.get("work_stats", {}), hero_definition.get("work_stats", DataLoader.DEFAULT_HERO_WORK_STATS)),
			"source": String(offer_data.get("source", hero_definition.get("source", "core"))),
			"mod_id": String(offer_data.get("mod_id", hero_definition.get("mod_id", ""))),
		})
	return normalized_offers


static func _normalize_runtime_stats(value: Variant, fallback_value: Variant) -> Dictionary:
	var source_data: Dictionary = _as_dictionary(value)
	var fallback: Dictionary = _as_dictionary(fallback_value)
	if fallback.is_empty():
		fallback = DataLoader.DEFAULT_HERO_STATS
	var normalized: Dictionary = {}
	for stat_key in fallback.keys():
		normalized[stat_key] = int(source_data.get(stat_key, fallback[stat_key]))
	return normalized


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}
