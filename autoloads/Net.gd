extends Node

## Cœur multijoueur — ENet haut niveau, hôte = serveur autoritaire.
## L'hôte partage un CODE (IPv4 publique encodée en base36, port fixe) ;
## pas de compte, pas de serveur central. UPnP tente d'ouvrir le port
## automatiquement ; à défaut, le code encode l'IP locale (partie en LAN).
##
## Registre des joueurs répliqué depuis l'hôte : peer_id → {name, pid, ready}.
## `pid` = Pokémon choisi dans le lobby (parmi les débloqués du Pokédex).

const PORT        := 24565
const MAX_PLAYERS := 6
const CODE_CHARS  := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # base32 sans ambigus (0/O, 1/I)

var active:    bool = false    # une partie multijoueur est en cours (lobby ou run)
var in_run:    bool = false    # la run a démarré
var base_seed: int  = 0        # graine partagée — dérive toutes les maps de la run
## Deux codes distincts (l'UPnP peut mettre plusieurs secondes à répondre) :
## - `join_code` = IP locale, à utiliser quand tous les joueurs sont sur le
##   MÊME réseau (Wi-Fi/LAN) — ne dépend d'aucune box/port-forwarding.
## - `join_code_public` = IP publique (rempli seulement si l'UPnP réussit),
##   à utiliser pour rejoindre depuis un autre réseau. Certaines box ne
##   supportent pas le "NAT loopback" : un joueur du MÊME réseau qui utilise
##   le code public peut alors échouer à se connecter — d'où la séparation.
var join_code:        String = ""
var join_code_public:  String = ""
var players:   Dictionary = {} # peer_id → {"name": String, "pid": int, "ready": bool}

## Catalogue de l'HÔTE (Pokémon débloqués + inventaire d'objets), diffusé aux
## invités à leur connexion — cf. GameManager.effective_unlocked_pokemon() :
## un invité choisit son équipe/ses objets dans les déblocages de l'hôte, pas
## les siens (qui n'ont pas de sens dans une partie qu'il n'héberge pas).
var host_unlocked: Array      = []
var host_items:    Dictionary = {}

## Pool PARTAGÉ de rappels d'équipe (façon Hades) — retour joueurs : « pouvoir
## partager ses rappels avec ses partenaires ». Un Pokémon sans charge propre
## (cf. GameManager.pokemon_revives, TeamMember._try_auto_revive) pioche ici
## avant de tomber K.O. Chaque pair garde sa PROPRE copie du compteur,
## initialisée IDENTIQUEMENT (déterministe depuis roster.size(), même
## principe que base_seed) et resynchronisée par diffusion à chaque
## consommation — optimiste plutôt qu'un aller-retour réseau à chaque K.O.
## (qui rendrait take_damage() asynchrone, avec effet domino sur tous ses
## appelants). Risque accepté : deux K.O. simultanés à la toute dernière
## charge peuvent la consommer chacun de leur côté — un filet de sécurité
## n'a pas besoin d'une exactitude parfaite au joueur près.
const TEAM_REVIVE_PER_PLAYER := 1
var team_revive_pool: int = 0

@rpc("any_peer", "call_remote", "reliable")
func _net_sync_revive_pool(n: int) -> void:
	team_revive_pool = n

## Consomme une charge du pool d'équipe si disponible — renvoie true si le
## Pokémon appelant peut être ranimé. Synchrone (pas d'aller-retour réseau) :
## voir le commentaire de team_revive_pool ci-dessus.
func consume_team_revive() -> bool:
	if team_revive_pool <= 0:
		return false
	team_revive_pool -= 1
	if in_run:
		_net_sync_revive_pool.rpc(team_revive_pool)
	return true

var _upnp_thread: Thread = null

signal players_changed
signal game_starting
signal join_failed(reason: String)
signal server_closed


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		reset()
		join_failed.emit("Connexion impossible — vérifie le code.")
	)
	multiplayer.server_disconnected.connect(func() -> void:
		reset()
		server_closed.emit()
	)


func is_host() -> bool:
	return not active or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


## Graine déterministe de la zone `depth` — identique sur tous les pairs,
## sans RPC supplémentaire à chaque transition.
func zone_seed(depth: int) -> int:
	var h := hash("%d:%d" % [base_seed, depth])
	return h if h != 0 else 1


## Ordre stable des joueurs (hôte d'abord, puis par peer_id croissant) —
## sert d'index de spawn/HUD identique sur tous les pairs.
func player_order() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


# ── Hébergement ────────────────────────────────────────────────────────

func host_game(player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active  = true
	in_run  = false
	players = {1: {"name": player_name, "pid": GameManager.selected_starter_id, "item": "", "ready": false}}
	host_unlocked = GameManager.unlocked_pokemon.duplicate()
	host_items    = GameManager.item_inventory.duplicate()
	join_code = _encode_ip(_local_ipv4())
	join_code_public = ""
	players_changed.emit()
	_try_upnp_async()
	return OK


## UPnP en thread (le blocage réseau peut prendre plusieurs secondes) :
## ouvre le port et remplace le code par l'IP publique si ça réussit.
func _try_upnp_async() -> void:
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(func() -> void:
		var upnp := UPNP.new()
		if upnp.discover() != UPNP.UPNP_RESULT_SUCCESS:
			return
		if not upnp.get_gateway() or not upnp.get_gateway().is_valid_gateway():
			return
		upnp.add_port_mapping(PORT, PORT, "Pokhades", "UDP")
		upnp.add_port_mapping(PORT, PORT, "Pokhades", "TCP")
		var ip := upnp.query_external_address()
		if ip != "":
			call_deferred("_set_public_code", ip)
	)


func _set_public_code(ip: String) -> void:
	join_code_public = _encode_ip(ip)
	players_changed.emit()


# ── Rejoindre ──────────────────────────────────────────────────────────

func join_game(code: String, player_name: String) -> Error:
	var ip := _decode_ip(code.strip_edges().to_upper())
	if ip == "":
		join_failed.emit("Code invalide.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		join_failed.emit("Connexion impossible.")
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	in_run = false
	players = {}
	_pending_name = player_name
	return OK


var _pending_name: String = ""

func _on_connected() -> void:
	_register.rpc_id(1, _pending_name, GameManager.selected_starter_id, GameManager.VERSION)


# ── Registre (autorité : hôte) ─────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass   # on attend son _register (avec son nom)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		_sync_players.rpc(players)
		players_changed.emit()


## Rejoint deux builds différents = bugs de sync garantis (structures de
## données réseau qui peuvent avoir changé) — l'hôte VÉRIFIE la version de
## chaque arrivant et le refuse proprement sinon (cf. GameManager.VERSION).
@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, pid: int, client_version: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if client_version != GameManager.VERSION:
		_reject_version.rpc_id(sender, GameManager.VERSION, client_version)
		return
	if players.size() >= MAX_PLAYERS:
		return
	players[sender] = {"name": player_name, "pid": pid, "item": "", "ready": false}
	_sync_players.rpc(players)
	_sync_catalog.rpc_id(sender, host_unlocked, host_items)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_players(data: Dictionary) -> void:
	players = data
	players_changed.emit()


## Reçu par le CLIENT quand l'hôte a refusé sa connexion pour cause de
## version différente (cf. _register) — message explicite plutôt qu'un
## simple timeout/déconnexion incompréhensible.
@rpc("authority", "call_remote", "reliable")
func _reject_version(host_version: String, my_version: String) -> void:
	reset()
	join_failed.emit("Versions différentes (hôte : %s, toi : %s) — mets à jour le jeu." % [host_version, my_version])


## Envoyé UNE FOIS par l'hôte à chaque invité qui rejoint — cf. host_unlocked
## ci-dessus. Sur l'hôte lui-même, host_unlocked/host_items sont déjà les
## bonnes valeurs (remplies dans host_game()), pas besoin de ce RPC.
@rpc("authority", "call_remote", "reliable")
func _sync_catalog(unlocked: Array, items: Dictionary) -> void:
	host_unlocked = unlocked
	host_items    = items


## Un joueur change son Pokémon, son objet tenu (api du catalogue, "" =
## aucun) ou son état "prêt" — transite par l'hôte.
func set_my_choice(pid: int, item: String, ready: bool) -> void:
	if multiplayer.is_server():
		_apply_choice(1, pid, item, ready)
	else:
		_request_choice.rpc_id(1, pid, item, ready)


@rpc("any_peer", "call_remote", "reliable")
func _request_choice(pid: int, item: String, ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_apply_choice(multiplayer.get_remote_sender_id(), pid, item, ready)


func _apply_choice(id: int, pid: int, item: String, ready: bool) -> void:
	if not players.has(id):
		return
	players[id]["pid"]   = pid
	players[id]["item"]  = item
	players[id]["ready"] = ready
	_sync_players.rpc(players)
	players_changed.emit()


func all_ready() -> bool:
	if players.size() < 2:
		return false
	for id in players:
		if not players[id]["ready"]:
			return false
	return true


# ── Lancement ──────────────────────────────────────────────────────────

func start_game() -> void:
	if not multiplayer.is_server() or not all_ready():
		return
	var s := randi()
	_begin.rpc(s, players)
	_begin(s, players)


@rpc("authority", "call_remote", "reliable")
func _begin(s: int, roster: Dictionary) -> void:
	base_seed = s if s != 0 else 1
	players   = roster
	in_run    = true
	team_revive_pool = players.size() * TEAM_REVIVE_PER_PLAYER
	# start_run() ICI, sur CHAQUE pair, AVANT le changement de scène : la 1re
	# zone se génère dans le _ready() du Map (enfant de CombatArena), qui
	# s'exécute AVANT celui de l'arène elle-même — si le reset de
	# rooms_cleared/la séquence de biomes attendait _ready(), chaque pair
	# pouvait lire un rooms_cleared resté à sa PROPRE valeur précédente
	# (RunManager est un singleton par PROCESSUS) : deux joueurs généraient
	# alors deux maps différentes pour ce qui devait être la même 1re salle
	# (retour joueurs : « les 2 joueurs doivent être sur la même map »).
	# base_seed est déjà identique sur tous les pairs (RPC ci-dessus) donc ce
	# reset produit la MÊME séquence partout.
	RunManager.inst().start_run()
	game_starting.emit()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")


# ── Fin de run (défaite en multi) ──────────────────────────────────────
# SEUL L'HÔTE décide de la suite (cf. écran de défaite multi) : réessayer
# (nouvelle run, même équipe/objets déjà choisis — pas de repassage par le
# lobby) ou retour au Hub PARTAGÉ (tout le monde y reste connecté et s'y
# balade ensemble, cf. HubWorld._build_multiplayer_avatars). Diffusé à tous
# les pairs pour rester synchronisés.

func request_retry() -> void:
	if not multiplayer.is_server():
		return
	var s := randi()
	_retry.rpc(s)
	_retry(s)


@rpc("authority", "call_remote", "reliable")
func _retry(s: int) -> void:
	base_seed = s if s != 0 else 1
	in_run    = true
	team_revive_pool = players.size() * TEAM_REVIVE_PER_PLAYER
	RunManager.inst().start_run()   # cf. _begin() — reset AVANT le changement de scène
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")


func request_return_hub() -> void:
	if not multiplayer.is_server():
		return
	_return_hub.rpc()
	_return_hub()


@rpc("authority", "call_remote", "reliable")
func _return_hub() -> void:
	in_run = false
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


func reset() -> void:
	active  = false
	in_run  = false
	players = {}
	join_code = ""
	join_code_public = ""
	host_unlocked = []
	host_items    = {}
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


# ── Code de partie ⇄ IPv4 ──────────────────────────────────────────────
# IPv4 (32 bits) → 7 caractères en base32 maison (alphabet sans ambigus).

func _encode_ip(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v: int = 0
	for p in parts:
		v = v * 256 + int(p)
	var out := ""
	for i in 7:
		out = CODE_CHARS[v % 32] + out
		v /= 32
	return out


func _decode_ip(code: String) -> String:
	if code.length() != 7:
		return ""
	var v: int = 0
	for c in code:
		var idx := CODE_CHARS.find(c)
		if idx == -1:
			return ""
		v = v * 32 + idx
	var parts: Array[String] = []
	for i in 4:
		parts.push_front(str(v % 256))
		v /= 256
	return ".".join(parts)


## IPv4 locale non-loopback (LAN) — fallback quand l'UPnP échoue.
func _local_ipv4() -> String:
	for addr in IP.get_local_addresses():
		if addr.count(".") == 3 and not addr.begins_with("127.") and not addr.begins_with("169.254"):
			return addr
	return "127.0.0.1"
