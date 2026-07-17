extends Node

const BASE_URL := "https://pokeapi.co/api/v2"
const _CACHE_DIR := "user://cache/pokeapi/"

var _cache:      Dictionary = {}
var _move_cache: Dictionary = {}
var _item_cache: Dictionary = {}

## Téléchargement complet pour jouer HORS-LIGNE ensuite — une fois fait
## avec du réseau, tout est en cache disque (user://cache/pokeapi/) et le
## jeu n'a plus jamais besoin d'internet (cf. get_pokemon/get_move : cache
## disque vérifié AVANT toute requête HTTP). Ré-exécutable sans risque :
## les espèces déjà en cache ne redéclenchent aucune requête.
signal prefetch_progress(done: int, total: int)
signal prefetch_finished

func prefetch_all() -> void:
	var ids := _all_species_ids()
	var total := ids.size()
	if total == 0:
		prefetch_finished.emit()
		return
	var counter := [0]
	for id in ids:
		get_pokemon(id, func(_data: Dictionary) -> void:
			counter[0] += 1
			prefetch_progress.emit(counter[0], total)
			if counter[0] >= total:
				_prefetch_moves()
		)


## Toutes les espèces effectivement utilisables dans une run ou en combat
## (mêmes viviers que CombatArena._preload_all) + toute la table d'évolution.
func _all_species_ids() -> Array[int]:
	var ids: Dictionary = {}
	for pid in GameManager.STARTER_IDS:
		ids[int(pid)] = true
	for k in GameManager.EVOLUTIONS:
		ids[int(k)] = true
		ids[int(GameManager.EVOLUTIONS[k]["evolves_to"])] = true
	for arr: Array in [PokePools.RODENTS, PokePools.BUGS, PokePools.FLYERS, PokePools.ELEM,
			PokePools.SEMI_BOSS, PokePools.CAVE_ELITE, PokePools.CAVE_DEMIBOSS]:
		for pid in arr:
			ids[int(pid)] = true
	for theme in PokePools.BIOME:
		for pid in (PokePools.BIOME[theme] as Array):
			ids[int(pid)] = true
	for pid in PokePools.all_champion_ids():
		ids[int(pid)] = true
	var out: Array[int] = []
	for k in ids:
		out.append(int(k))
	return out


## Phase 2 : toutes les attaques du movepool complet de chaque espèce déjà
## en cache — sans ça, une attaque jamais rencontrée exigerait quand même
## une requête réseau la première fois qu'un Pokémon tente de l'apprendre.
func _prefetch_moves() -> void:
	var names: Dictionary = {}
	for key in _cache:
		var d: Dictionary = _cache[key]
		for nm in (d.get("learnable_moves", []) as Array):
			names[str(nm)] = true
	var list := names.keys()
	var total := list.size()
	if total == 0:
		prefetch_finished.emit()
		return
	var counter := [0]
	for nm in list:
		get_move(str(nm), func(_d: Dictionary) -> void:
			counter[0] += 1
			prefetch_progress.emit(counter[0], total)
			if counter[0] >= total:
				prefetch_finished.emit()
		)


func get_pokemon(id_or_name: Variant, callback: Callable) -> void:
	var key := str(id_or_name).to_lower()

	if _cache.has(key):
		if callback.is_valid(): callback.call(_cache[key])
		return

	var disk := _read_json_cache(_disk_path("pokemon", key))
	# Invalide les caches d'avant l'ajout du movepool complet (learnable_moves)
	if not disk.is_empty() and disk.has("learnable_moves"):
		_cache[key] = disk
		_cache[str(disk.get("id", 0))] = disk
		if callback.is_valid(): callback.call(disk)
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
		if callback.is_valid(): callback.call({})
		http.queue_free()


func _fetch_species(poke_json: Dictionary, cache_key: String, callback: Callable) -> void:
	var species_url: String = poke_json.get("species", {}).get("url", "")

	if species_url.is_empty():
		var data: Dictionary = _build_data(poke_json, str(poke_json.get("name", "")), true)
		_store(cache_key, data)
		if callback.is_valid(): callback.call(data)
		return

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(result, code, _h, body):
		if not is_instance_valid(self):
			http.queue_free()
			return
		var name_fr: String  = poke_json.get("name", "")
		var is_base_form := true   # pas d'évolution antérieure = forme de base

		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var species_data: Dictionary = json.get_data()
				is_base_form = species_data.get("evolves_from_species") == null
				for entry in species_data.get("names", []):
					if entry.get("language", {}).get("name", "") == "fr":
						name_fr = entry["name"]
						break

		http.queue_free()
		var data := _build_data(poke_json, name_fr, is_base_form)
		_store(cache_key, data)
		if callback.is_valid(): callback.call(data)
	)

	http.request(species_url)


func _store(key: String, data: Dictionary) -> void:
	_cache[key] = data
	_cache[str(data.get("id", 0))] = data
	_write_json_cache(_disk_path("pokemon", key), data)
	_write_json_cache(_disk_path("pokemon", str(data.get("id", 0))), data)


func get_move(move_name: String, callback: Callable) -> void:
	if _move_cache.has(move_name):
		if callback.is_valid(): callback.call(_move_cache[move_name])
		return

	var disk := _read_json_cache(_disk_path("move", move_name))
	# Invalidation : les caches d'avant l'ajout de name_fr, puis de desc_fr/
	# accuracy/pp (popup d'infos du Pokédex), n'ont pas ces clés — on les
	# re-télécharge une fois.
	if not disk.is_empty() and disk.has("name_fr") and disk.has("desc_fr"):
		_move_cache[move_name] = disk
		if callback.is_valid(): callback.call(disk)
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
		# Nom localisé français (tableau `names` de PokeAPI)
		var name_fr: String = ""
		for entry in d.get("names", []):
			if entry.get("language", {}).get("name", "") == "fr":
				name_fr = entry.get("name", "")
				break
		# Description française : dernier flavor text FR disponible (les entrées
		# sont triées par génération — la dernière est la plus récente).
		var desc_fr: String = ""
		for fte in d.get("flavor_text_entries", []):
			if fte.get("language", {}).get("name", "") == "fr":
				desc_fr = str(fte.get("flavor_text", "")).replace("\n", " ")
		var move_data := {
			"name":         move_name,
			"name_fr":      name_fr,
			"type":         d.get("type", {}).get("name", "normal"),
			"power":        d.get("power"),
			"accuracy":     d.get("accuracy"),
			"pp":           d.get("pp"),
			"damage_class": d.get("damage_class", {}).get("name", "physical"),
			"desc_fr":      desc_fr,
		}
		_move_cache[move_name] = move_data
		_write_json_cache(_disk_path("move", move_name), move_data)
		if callback.is_valid(): callback.call(move_data)
		http.queue_free()
	)
	http.request("%s/move/%s" % [BASE_URL, move_name])


func get_item(api_name: String, callback: Callable) -> void:
	if _item_cache.has(api_name):
		if callback.is_valid(): callback.call(_item_cache[api_name])
		return

	var disk := _read_json_cache(_disk_path("item", api_name))
	if not disk.is_empty():
		_item_cache[api_name] = disk
		if callback.is_valid(): callback.call(disk)
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
		_write_json_cache(_disk_path("item", api_name), item_data)
		if callback.is_valid(): callback.call(item_data)
		http.queue_free()
	)
	http.request("%s/item/%s" % [BASE_URL, api_name])


func _build_data(json: Dictionary, name_fr: String, is_base_form: bool = true) -> Dictionary:
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
	# Movepool COMPLET (tous modes d'apprentissage) — sert à valider qu'une
	# attaque appartient bien au Pokémon (cf. PokemonData.learnable_moves).
	var learnable: Array = []
	for m in json.get("moves", []):
		var mname: String = m["move"]["name"]
		learnable.append(mname)
		if seen.has(mname):
			continue
		for vg in m.get("version_group_details", []):
			if vg.get("move_learn_method", {}).get("name", "") == "level-up":
				var lv: int = int(vg.get("level_learned_at", 0))
				level_up_moves.append({"level": lv, "name": mname})
				seen[mname] = true
				break
		if level_up_moves.size() >= 20:
			pass   # on continue à collecter le movepool complet
	level_up_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["level"]) < int(b["level"])
	)
	if level_up_moves.size() > 20:
		level_up_moves = level_up_moves.slice(0, 20)

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
		"learnable_moves": learnable,
		"is_base_form":   is_base_form,
	}


# ── Cache disque (user://) — évite de retélécharger d'une session à l'autre ──

func _disk_path(subdir: String, key: String) -> String:
	var safe_key := key.replace("/", "_").replace("\\", "_")
	return "%s%s/%s.json" % [_CACHE_DIR, subdir, safe_key]


func _read_json_cache(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.get_data()
	return data if data is Dictionary else {}


func _write_json_cache(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
