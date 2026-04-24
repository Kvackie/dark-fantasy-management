extends RefCounted


static func world_zone_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


static func world_state_priority(state: String) -> int:
	match state:
		"fog":
			return 1
		"discovered":
			return 2
		"clearing":
			return 3
		"cleared":
			return 4
		"claimed":
			return 5
		_:
			return 0


static func zone_distance(x: int, y: int) -> int:
	return max(abs(x), abs(y))


static func normalize_zone_requirements(value: Variant, default_work_stat_keys: Array) -> Dictionary:
	var source := _as_dictionary(value)
	var normalized := {
		"level": max(0, int(source.get("level", 0))),
		"sanity": max(0, int(source.get("sanity", 0))),
		"attack": max(0, int(source.get("attack", 0))),
		"defense": max(0, int(source.get("defense", 0))),
	}
	for stat_key_variant in default_work_stat_keys:
		var stat_key := String(stat_key_variant)
		normalized[stat_key] = max(0, int(source.get(stat_key, 0)))
	return normalized


static func get_zone_clear_duration(world_config: Dictionary, zone_override: Dictionary, zone: Dictionary) -> int:
	if zone_override.has("clear_duration"):
		return max(1, int(zone_override.get("clear_duration", 1)))
	return max(1, int(world_config.get("default_clear_duration", 3)))


static func generate_zone_requirements(world_config: Dictionary, x: int, y: int, default_work_stat_keys: Array) -> Dictionary:
	var requirement_config := _as_dictionary(world_config.get("clear_requirements", {}))
	var distance := zone_distance(x, y)
	var safe_radius: int = max(0, int(requirement_config.get("safe_radius", 2)))
	var scaled_distance: int = max(0, distance - safe_radius)
	return normalize_zone_requirements({
		"attack": int(requirement_config.get("attack_base", 0)) + scaled_distance * int(requirement_config.get("attack_growth", 3)),
		"defense": int(requirement_config.get("defense_base", 0)) + scaled_distance * int(requirement_config.get("defense_growth", 2)),
	}, default_work_stat_keys)


static func get_zone_sanity_loss(world_config: Dictionary, zone: Dictionary) -> int:
	var requirement_config := _as_dictionary(world_config.get("clear_requirements", {}))
	var distance := zone_distance(int(zone.get("x", 0)), int(zone.get("y", 0)))
	var safe_radius: int = max(0, int(requirement_config.get("safe_radius", 2)))
	var scaled_distance: int = max(0, distance - safe_radius)
	return max(0, int(requirement_config.get("sanity_loss_base", 0)) + scaled_distance * int(requirement_config.get("sanity_loss_growth", 1)))


static func get_zone_experience_reward(world_config: Dictionary, zone: Dictionary) -> int:
	var reward_config := _as_dictionary(world_config.get("clear_rewards", {}))
	var distance := zone_distance(int(zone.get("x", 0)), int(zone.get("y", 0)))
	var safe_radius: int = max(0, int(_as_dictionary(world_config.get("clear_requirements", {})).get("safe_radius", 2)))
	var scaled_distance: int = max(0, distance - safe_radius)
	return max(0, int(reward_config.get("experience_base", 2)) + scaled_distance * int(reward_config.get("experience_growth", 1)))


static func get_zone_clear_reward_table(world_config: Dictionary, zone: Dictionary) -> Dictionary:
	var reward_config := _as_dictionary(world_config.get("clear_rewards", {}))
	var distance := zone_distance(int(zone.get("x", 0)), int(zone.get("y", 0)))
	for table_entry in _as_array(reward_config.get("tables", [])):
		var table := _as_dictionary(table_entry)
		var min_distance := int(table.get("min_distance", 0))
		var max_distance := int(table.get("max_distance", 999999))
		if distance < min_distance or distance > max_distance:
			continue
		return table.duplicate(true)
	return {}


static func reward_entry_succeeds(world_seed: int, zone: Dictionary, entry: Dictionary) -> bool:
	var chance := clampi(int(entry.get("chance", 100)), 0, 100)
	if chance >= 100:
		return true
	if chance <= 0:
		return false
	return _coord_random_range(world_seed, int(zone.get("x", 0)), int(zone.get("y", 0)), JSON.stringify(entry).hash(), 1, 100) <= chance


static func roll_reward_quantity(world_seed: int, zone: Dictionary, entry: Dictionary, salt: int) -> int:
	var min_quantity: int = max(0, int(entry.get("min", entry.get("amount", 0))))
	var max_quantity: int = max(min_quantity, int(entry.get("max", min_quantity)))
	return _coord_random_range(world_seed, int(zone.get("x", 0)), int(zone.get("y", 0)), salt, min_quantity, max_quantity)


static func determine_zone_biome(world_seed: int, world_config: Dictionary, x: int, y: int) -> String:
	if x == 0 and y == 0:
		return "neutral"
	var seed_value := int((x * 92821) + (y * 68917) + (world_seed * 13))
	var roll: int = abs(seed_value)
	var special_biome := roll_special_biome(world_config, roll)
	if not special_biome.is_empty():
		return special_biome
	if roll % 20 <= 2:
		return "neutral"
	var biome_roll: int = int(float(roll) / 10.0) % 4
	match biome_roll:
		0:
			return "forest"
		1:
			return "mountain"
		2:
			return "plains"
		_:
			return "mixed"


static func roll_special_biome(world_config: Dictionary, roll: int) -> String:
	var special_biomes := _as_dictionary(world_config.get("special_biomes", {}))
	var biome_ids := special_biomes.keys()
	biome_ids.sort()
	for biome_id_variant in biome_ids:
		var biome_id := String(biome_id_variant).strip_edges().to_lower()
		if biome_id.is_empty():
			continue
		var biome_config := _as_dictionary(special_biomes.get(biome_id, {}))
		var spawn_chance: int = max(0, int(biome_config.get("spawn_chance", 0)))
		if spawn_chance > 0 and roll % spawn_chance == 0:
			return biome_id
	return ""


static func generate_zone_name(world_seed: int, world_config: Dictionary, x: int, y: int) -> String:
	var name_config := _as_dictionary(world_config.get("name_generation", {}))
	var prefixes := _as_array(name_config.get("prefixes", []))
	var suffixes := _as_array(name_config.get("suffixes", []))
	var articles := _as_array(name_config.get("articles", []))
	var prefix := String(prefixes[_coord_random_index(world_seed, x, y, 11, prefixes.size())]) if not prefixes.is_empty() else "Ashen"
	var suffix := String(suffixes[_coord_random_index(world_seed, x, y, 23, suffixes.size())]) if not suffixes.is_empty() else "Reach"
	var article := String(articles[_coord_random_index(world_seed, x, y, 37, articles.size())]) if not articles.is_empty() else ""
	var parts: Array[String] = []
	if not article.is_empty():
		parts.append(article)
	parts.append(prefix)
	parts.append(suffix)
	return " ".join(parts)


static func generate_claim_cost(world_seed: int, world_config: Dictionary, x: int, y: int) -> Dictionary:
	var claim_config: Dictionary = _as_dictionary(world_config.get("claim_cost", {}))
	var base: Dictionary = _as_dictionary(claim_config.get("base", {}))
	var step: Dictionary = _as_dictionary(claim_config.get("distance_step", {}))
	var variance: Dictionary = _as_dictionary(claim_config.get("variance", {}))
	var distance: int = max(abs(x), abs(y))
	var cost: Dictionary = {}
	for resource_id_variant in base.keys():
		var resource_id := String(resource_id_variant)
		var amount: int = int(base.get(resource_id, 0)) + int(step.get(resource_id, 0)) * distance
		var variance_amount: int = int(variance.get(resource_id, 0))
		if variance_amount > 0:
			amount += _coord_random_range(world_seed, x, y, resource_id.hash(), 0, variance_amount)
		cost[resource_id] = max(amount, 0)
	return cost


static func _coord_random_index(world_seed: int, x: int, y: int, salt: int, size: int) -> int:
	if size <= 0:
		return 0
	return abs(_coord_hash(world_seed, x, y, salt)) % size


static func _coord_random_range(world_seed: int, x: int, y: int, salt: int, min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	return min_value + (abs(_coord_hash(world_seed, x, y, salt)) % (max_value - min_value + 1))


static func _coord_hash(world_seed: int, x: int, y: int, salt: int) -> int:
	return int(world_seed) ^ (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
