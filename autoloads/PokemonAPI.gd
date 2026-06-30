extends Node

const BASE_URL := "https://pokeapi.co/api/v2"

var _cache:      Dictionary = {}
var _move_cache: Dictionary = {}
var _item_cache: Dictionary = {}


func get_pokemon(id_or_name: Variant, callback: Callable) -> void:
	var key := str(id_or_name).to_lower()

	if _cache.has(key):
		callback.call(_cache[key])
		return

	_fetch_pokemon(key, callback)


func _fetch_pokemon(query: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(result, code, _h, body):
		if not is_instance_valid(self):
			http.queue_free()
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("PokemonAPI: échec pour '%s' (code %d)" % [query, code])
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return

		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return

		var poke_json: Dictionary = json.get_data()
		http.queue_free()
		_fetch_species(poke_json, query, callback)
	)

	var err := http.request("%s/pokemon/%s" % [BASE_URL, query])
	if err != OK:
		push_error("PokemonAPI: impossible d'envoyer la requête pour '%s'" % query)
		callback.call({})
		http.queue_free()


func _fetch_species(poke_json: Dictionary, cache_key: String, callback: Callable) -> void:
	var species_url: String = poke_json.get("species", {}).get("url", "")

	if species_url.is_empty():
		var data: Dictionary = _build_data(poke_json, str(poke_json.get("name", "")))
		_store(cache_key, data)
		callback.call(data)
		return

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(result, code, _h, body):
		if not is_instance_valid(self):
			http.queue_free()
			return
		var name_fr: String = poke_json.get("name", "")

		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				for entry in json.get_data().get("names", []):
					if entry.get("language", {}).get("name", "") == "fr":
						name_fr = entry["name"]
						break

		http.queue_free()
		var data := _build_data(poke_json, name_fr)
		_store(cache_key, data)
		if callback.is_valid(): callback.call(data)
	)

	http.request(species_url)


func _store(key: String, data: Dictionary) -> void:
	_cache[key] = data
	_cache[str(data.get("id", 0))] = data


func get_move(move_name: String, callback: Callable) -> void:
	if _move_cache.has(move_name):
		callback.call(_move_cache[move_name])
		return

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		if not is_instance_valid(self):
			http.queue_free()
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return
		var d: Dictionary = json.get_data()
		var move_data := {
			"name":         move_name,
			"type":         d.get("type", {}).get("name", "normal"),
			"power":        d.get("power"),
			"damage_class": d.get("damage_class", {}).get("name", "physical"),
		}
		_move_cache[move_name] = move_data
		if callback.is_valid(): callback.call(move_data)
		http.queue_free()
	)
	http.request("%s/move/%s" % [BASE_URL, move_name])


func get_item(api_name: String, callback: Callable) -> void:
	if _item_cache.has(api_name):
		callback.call(_item_cache[api_name])
		return

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		if not is_instance_valid(self):
			http.queue_free()
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			if callback.is_valid(): callback.call({})
			http.queue_free()
			return
		var d: Dictionary = json.get_data()

		var name_fr: String = d.get("name", api_name).replace("-", " ").capitalize()
		for entry in d.get("names", []):
			if entry.get("language", {}).get("name", "") == "fr":
				name_fr = entry["name"]
				break

		var item_data := {
			"api_name":   api_name,
			"name_fr":    name_fr,
			"sprite_url": d.get("sprites", {}).get("default", ""),
		}
		_item_cache[api_name] = item_data
		if callback.is_valid(): callback.call(item_data)
		http.queue_free()
	)
	http.request("%s/item/%s" % [BASE_URL, api_name])


func _build_data(json: Dictionary, name_fr: String) -> Dictionary:
	var stats := {}
	for entry in json.get("stats", []):
		stats[entry["stat"]["name"]] = entry["base_stat"]

	var types: Array = []
	for t in json.get("types", []):
		types.append(t["type"]["name"])

	# Extrait les attaques apprises par montée de niveau, avec le niveau requis
	# On déduplique par nom et on trie par niveau croissant
	var level_up_moves: Array = []
	var seen: Dictionary = {}
	for m in json.get("moves", []):
		var mname: String = m["move"]["name"]
		if seen.has(mname):
			continue
		for vg in m.get("version_group_details", []):
			if vg.get("move_learn_method", {}).get("name", "") == "level-up":
				var lv: int = int(vg.get("level_learned_at", 0))
				level_up_moves.append({"level": lv, "name": mname})
				seen[mname] = true
				break
		if level_up_moves.size() >= 20:
			break
	level_up_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["level"]) < int(b["level"])
	)

	var sprites: Dictionary = json.get("sprites", {})
	var sprite_url: String = sprites.get("front_default", "")

	return {
		"id":             int(json.get("id", 0)),
		"name_en":        json.get("name", ""),
		"name_fr":        name_fr,
		"types":          types,
		"stats":          stats,
		"sprite_url":     sprite_url,
		"level_up_moves": level_up_moves,
	}
