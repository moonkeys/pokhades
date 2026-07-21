extends Node

## Version du jeu — affichée dans le menu principal et le lobby multi, et
## VÉRIFIÉE à la connexion (cf. Net._register) pour éviter de faire jouer
## ensemble deux builds différents (bugs de sync garantis sinon). À
## incrémenter à chaque changement qui touche au gameplay/réseau.
const VERSION := "0.5.0"

# ── Starters disponibles ─────────────────────────────────────────────
const STARTER_IDS: Array = [25, 570, 359, 725, 656, 390, 674, 559, 447]

var selected_starter_id: int = 25

const XP_MULTIPLIER := 12

# Table d'évolution du JEU (pid → niveau requis + forme suivante) — couvre
# toutes les lignées du casting (starters, pools, faunes de biome, recrues
# de grotte, roster de test). Les évolutions par pierre/échange/bonheur des
# jeux officiels reçoivent ici un NIVEAU (convention rogue-lite : le niveau
# est la seule monnaie de progression d'un Pokémon).
const EVOLUTIONS: Dictionary = {
	# ── Starters de la Rébellion ─────────────────────────────────────
	25:  {"level": 20, "evolves_to": 26},    # Pikachu → Raichu
	570: {"level": 20, "evolves_to": 571},   # Zorua → Zoroark
	725: {"level": 17, "evolves_to": 726},   # Flamiaou → Matoufeu
	726: {"level": 34, "evolves_to": 727},   # → Félinferno
	656: {"level": 16, "evolves_to": 657},   # Grenousse → Croâporal
	657: {"level": 36, "evolves_to": 658},   # → Amphinobi
	390: {"level": 14, "evolves_to": 391},   # Ouisticram → Chimpenfeu
	391: {"level": 36, "evolves_to": 392},   # → Simiabraz
	674: {"level": 32, "evolves_to": 675},   # Pandespiègle → Pandarbare
	559: {"level": 39, "evolves_to": 560},   # Baggiguane → Baggaïd
	447: {"level": 24, "evolves_to": 448},   # Riolu → Lucario (bonheur → niveau)
	# ── Lignées classiques (Pokédex, roster de test) ─────────────────
	1:   {"level": 16, "evolves_to": 2},     # Bulbizarre → Herbizarre
	2:   {"level": 32, "evolves_to": 3},     # → Florizarre
	4:   {"level": 16, "evolves_to": 5},     # Salamèche → Reptincel
	5:   {"level": 36, "evolves_to": 6},     # → Dracaufeu
	7:   {"level": 16, "evolves_to": 8},     # Carapuce → Carabaffe
	8:   {"level": 36, "evolves_to": 9},     # → Tortank
	32:  {"level": 16, "evolves_to": 33},    # Nidoran♂ → Nidorino
	33:  {"level": 36, "evolves_to": 34},    # → Nidoking (pierre)
	37:  {"level": 20, "evolves_to": 38},    # Goupix → Feunard (pierre)
	63:  {"level": 16, "evolves_to": 64},    # Abra → Kadabra
	64:  {"level": 40, "evolves_to": 65},    # → Alakazam (échange)
	92:  {"level": 25, "evolves_to": 93},    # Fantominus → Spectrum
	93:  {"level": 40, "evolves_to": 94},    # → Ectoplasma (échange)
	123: {"level": 40, "evolves_to": 212},   # Insécateur → Cizayox (échange)
	133: {"level": 20, "evolves_to": 134},   # Évoli → Aquali (pierre)
	175: {"level": 20, "evolves_to": 176},   # Togepi → Togetic (bonheur)
	176: {"level": 45, "evolves_to": 468},   # → Togekiss (pierre)
	215: {"level": 45, "evolves_to": 461},   # Farfuret → Dimoret (objet)
	280: {"level": 20, "evolves_to": 281},   # Tarsal → Kirlia
	281: {"level": 30, "evolves_to": 282},   # → Gardevoir
	258: {"level": 16, "evolves_to": 259},   # Gobou → Flobio
	259: {"level": 36, "evolves_to": 260},   # → Laggron
	# ── Rongeurs / insectes / oiseaux (pools de base) ────────────────
	399: {"level": 15, "evolves_to": 400},   # Keunotor → Castorno
	19:  {"level": 20, "evolves_to": 20},    # Rattata → Rattatac
	263: {"level": 20, "evolves_to": 264},   # Zigzaton → Linéon
	161: {"level": 15, "evolves_to": 162},   # Fouinette → Fouinar
	819: {"level": 24, "evolves_to": 820},   # Rongourmand → Rongrigou
	10:  {"level": 7,  "evolves_to": 11},    # Chenipan → Chrysacier
	11:  {"level": 10, "evolves_to": 12},    # → Papilusion
	13:  {"level": 7,  "evolves_to": 14},    # Aspicot → Coconfort
	14:  {"level": 10, "evolves_to": 15},    # → Dardargnan
	265: {"level": 7,  "evolves_to": 266},   # Chenipotte → Armulys
	266: {"level": 10, "evolves_to": 267},   # → Charmillon
	824: {"level": 10, "evolves_to": 825},   # Larvadar → Coléodôme
	825: {"level": 30, "evolves_to": 826},   # → Astronelle
	850: {"level": 28, "evolves_to": 851},   # Grillepattes → Scolocendre
	16:  {"level": 18, "evolves_to": 17},    # Roucool → Roucoups
	17:  {"level": 36, "evolves_to": 18},    # → Roucarnage
	396: {"level": 14, "evolves_to": 397},   # Étourmi → Étourvol
	397: {"level": 34, "evolves_to": 398},   # → Étouraptor
	661: {"level": 17, "evolves_to": 662},   # Passerouge → Braisillon
	662: {"level": 35, "evolves_to": 663},   # → Flambusard
	519: {"level": 21, "evolves_to": 520},   # Poichigeon → Colombeau
	520: {"level": 32, "evolves_to": 521},   # → Déflaisan
	403: {"level": 15, "evolves_to": 404},   # Lixy → Luxio
	404: {"level": 30, "evolves_to": 405},   # → Luxray
	261: {"level": 18, "evolves_to": 262},   # Medhyèna → Grahyèna
	191: {"level": 25, "evolves_to": 192},   # Tournegrin → Héliatronc (pierre)
	43:  {"level": 21, "evolves_to": 44},    # Mystherbe → Ortide
	44:  {"level": 36, "evolves_to": 45},    # → Rafflesia (pierre)
	# ── Faunes de biome ──────────────────────────────────────────────
	46:  {"level": 24, "evolves_to": 47},    # Paras → Parasect
	69:  {"level": 21, "evolves_to": 70},    # Chétiflor → Boustiflor
	70:  {"level": 40, "evolves_to": 71},    # → Empiflor (pierre)
	273: {"level": 14, "evolves_to": 274},   # Grainipiot → Pifeuil
	274: {"level": 36, "evolves_to": 275},   # → Tengalice (pierre)
	285: {"level": 23, "evolves_to": 286},   # Balignon → Chapignon
	204: {"level": 31, "evolves_to": 205},   # Pomdepik → Foretress
	540: {"level": 20, "evolves_to": 541},   # Larveyette → Couverdure
	541: {"level": 30, "evolves_to": 542},   # → Manternel
	194: {"level": 20, "evolves_to": 195},   # Axoloto → Maraiste
	88:  {"level": 38, "evolves_to": 89},    # Tadmorv → Grotadmorv
	23:  {"level": 22, "evolves_to": 24},    # Abo → Arbok
	41:  {"level": 22, "evolves_to": 42},    # Nosferapti → Nosferalto
	42:  {"level": 40, "evolves_to": 169},   # → Nostenfer (bonheur)
	270: {"level": 14, "evolves_to": 271},   # Nénupiot → Lombre
	271: {"level": 36, "evolves_to": 272},   # → Ludicolo (pierre)
	283: {"level": 22, "evolves_to": 284},   # Arakdo → Maskadra
	187: {"level": 18, "evolves_to": 188},   # Granivol → Floravol
	188: {"level": 27, "evolves_to": 189},   # → Cotovol
	415: {"level": 21, "evolves_to": 416},   # Apitrini → Apireine
	669: {"level": 19, "evolves_to": 670},   # Flabébé → Floette
	670: {"level": 38, "evolves_to": 671},   # → Florges (pierre)
	179: {"level": 15, "evolves_to": 180},   # Wattouat → Lainergie
	180: {"level": 30, "evolves_to": 181},   # → Pharamp
	659: {"level": 20, "evolves_to": 660},   # Sapereau → Excavarenne
	74:  {"level": 25, "evolves_to": 75},    # Racaillou → Gravalanch
	75:  {"level": 40, "evolves_to": 76},    # → Grolem (échange)
	66:  {"level": 28, "evolves_to": 67},    # Machoc → Machopeur
	67:  {"level": 44, "evolves_to": 68},    # → Mackogneur (échange)
	296: {"level": 24, "evolves_to": 297},   # Makuhita → Hariyama
	304: {"level": 32, "evolves_to": 305},   # Galekid → Galegon
	305: {"level": 42, "evolves_to": 306},   # → Galeking
	524: {"level": 25, "evolves_to": 525},   # Nodulithe → Géolithe
	525: {"level": 40, "evolves_to": 526},   # → Gigalithe (échange)
	744: {"level": 25, "evolves_to": 745},   # Rocabot → Lougaroc
	585: {"level": 34, "evolves_to": 586},   # Vivaldaim → Haydaim
	216: {"level": 30, "evolves_to": 217},   # Teddiursa → Ursaring
	163: {"level": 20, "evolves_to": 164},   # Hoothoot → Noarfang
	118: {"level": 33, "evolves_to": 119},   # Poissirène → Poissoroy
	129: {"level": 20, "evolves_to": 130},   # Magicarpe → Léviator
	54:  {"level": 33, "evolves_to": 55},    # Psykokwak → Akwakwak
	60:  {"level": 25, "evolves_to": 61},    # Ptitard → Têtarte
	61:  {"level": 40, "evolves_to": 62},    # → Tartard (pierre)
	79:  {"level": 37, "evolves_to": 80},    # Ramoloss → Flagadoss
	# ── Recrues de grotte (pseudo-légendaires & lignées rares) ───────
	147: {"level": 30, "evolves_to": 148},   # Minidraco → Draco
	148: {"level": 55, "evolves_to": 149},   # → Dracolosse
	246: {"level": 30, "evolves_to": 247},   # Embrylex → Ymphect
	247: {"level": 55, "evolves_to": 248},   # → Tyranocif
	371: {"level": 30, "evolves_to": 372},   # Draby → Drackhaus
	372: {"level": 50, "evolves_to": 373},   # → Drattak
	443: {"level": 24, "evolves_to": 444},   # Griknot → Carmache
	444: {"level": 48, "evolves_to": 445},   # → Carchacrok
	610: {"level": 38, "evolves_to": 611},   # Coupenotte → Incisache
	611: {"level": 48, "evolves_to": 612},   # → Tranchodon
	633: {"level": 50, "evolves_to": 634},   # Solochi → Diamat
	634: {"level": 64, "evolves_to": 635},   # → Trioxhydre
	704: {"level": 40, "evolves_to": 705},   # Mucuscule → Colimucus
	705: {"level": 50, "evolves_to": 706},   # → Muplodocus
	374: {"level": 20, "evolves_to": 375},   # Terhal → Métang
	375: {"level": 45, "evolves_to": 376},   # → Métalosse
	328: {"level": 35, "evolves_to": 329},   # Kraknoix → Vibraninf
	329: {"level": 45, "evolves_to": 330},   # → Libégon
	782: {"level": 35, "evolves_to": 783},   # Bébécaille → Écaïd
	783: {"level": 45, "evolves_to": 784},   # → Ékaïser
	885: {"level": 50, "evolves_to": 886},   # Fantyrm → Dispareptil
	886: {"level": 60, "evolves_to": 887},   # → Lanssorien
	996: {"level": 35, "evolves_to": 997},   # Frigodo → Cryodo
	997: {"level": 54, "evolves_to": 998},   # → Glaivodo
	# ── Lignées des CHAMPIONS D'ACTE (cf. PokePools.CHAMPION_TEAMS) —
	# manquaient pour que chaque vague de boss ait une paire évolué/sbire
	# de base cohérente (cf. CombatArena._spawn_room_enemies).
	95:  {"level": 30, "evolves_to": 208},   # Onix → Steelix
	111: {"level": 42, "evolves_to": 112},   # Rhinocorne → Rhinoféros
	100: {"level": 30, "evolves_to": 101},   # Voltorbe → Électrode
	81:  {"level": 30, "evolves_to": 82},    # Magnéti → Magnéton
	120: {"level": 20, "evolves_to": 121},   # Stari → Staross (pierre)
	116: {"level": 32, "evolves_to": 117},   # Hypotrempe → Tacle
	102: {"level": 20, "evolves_to": 103},   # Noeunoeuf → Noadkoko (pierre)
	109: {"level": 35, "evolves_to": 110},   # Smogo → Smogogo
	48:  {"level": 31, "evolves_to": 49},    # Mimitoss → Aéromite
	96:  {"level": 26, "evolves_to": 97},    # Soporifik → Hypnomade
	77:  {"level": 40, "evolves_to": 78},    # Ponyta → Galopa
	58:  {"level": 20, "evolves_to": 59},    # Caninos → Arcanin (pierre)
	50:  {"level": 26, "evolves_to": 51},    # Taupiqueur → Triopikeur
	29:  {"level": 16, "evolves_to": 30},    # Nidoran♀ → Nidorina
	30:  {"level": 36, "evolves_to": 31},    # → Nidoqueen (pierre)
	104: {"level": 28, "evolves_to": 105},   # Osselait → Ossatueur
	# ── Élargissement des viviers de biome (cf. PokePools.BIOME) ─────
	# Indispensable : à partir de l'acte 2, _pool_for_room remplace chaque
	# espèce par sa forme finale (final_evolution_of). Une espèce absente
	# d'ici reste à sa forme de base et sort largement sous-dimensionnée en
	# fin de run. Les espèces sans lignée (Tauros, Lokhlass, Séviper,
	# Scarabrute, Écrémeuh, Insolourdo, Bargantua, Limonde, Qwilfish,
	# Boumata) sont volontairement absentes : elles n'évoluent pas.
	203: {"level": 32, "evolves_to": 981},   # Girafarig → Farigiraf
	664: {"level": 9,  "evolves_to": 665},   # Lépidonille → Papilonette
	665: {"level": 12, "evolves_to": 666},   # → Prismillon
	590: {"level": 39, "evolves_to": 591},   # Trompignon → Gaulet
	742: {"level": 21, "evolves_to": 743},   # Bombydou → Rubombelle
	114: {"level": 30, "evolves_to": 465},   # Saquedeneu → Vortente
	21:  {"level": 20, "evolves_to": 22},    # Piafabec → Rapasdepic
	546: {"level": 28, "evolves_to": 547},   # Doudouvet → Farfaduvet (pierre)
	710: {"level": 33, "evolves_to": 711},   # Pitrouille → Banshitrouye
	708: {"level": 33, "evolves_to": 709},   # Brocélôme → Desséliande
	183: {"level": 18, "evolves_to": 184},   # Marill → Azumarill
	98:  {"level": 28, "evolves_to": 99},    # Krabby → Krabboss
	72:  {"level": 30, "evolves_to": 73},    # Tentacool → Tentacruel
	592: {"level": 40, "evolves_to": 593},   # Viskuse → Moyade
	339: {"level": 30, "evolves_to": 340},   # Barloche → Barbicha
	434: {"level": 34, "evolves_to": 435},   # Moufouette → Moufflair
	568: {"level": 36, "evolves_to": 569},   # Miamiasme → Miasmax
	438: {"level": 24, "evolves_to": 185},   # Manzaï → Simularbre
	557: {"level": 34, "evolves_to": 558},   # Crabicoque → Crabaraque
	837: {"level": 18, "evolves_to": 838},   # Charbi → Wagomine
	838: {"level": 34, "evolves_to": 839},   # → Monthracite
	622: {"level": 43, "evolves_to": 623},   # Gringolem → Golemastoc
	236: {"level": 20, "evolves_to": 237},   # Debugant → Kapoera
	155: {"level": 14, "evolves_to": 156},   # Héricendre → Feurisson
	156: {"level": 36, "evolves_to": 157},   # → Typhlosion
	255: {"level": 16, "evolves_to": 256},   # Poussifeu → Galifeu
	256: {"level": 36, "evolves_to": 257},   # → Braségali
	636: {"level": 59, "evolves_to": 637},   # Pyronille → Pyrax
	300: {"level": 25, "evolves_to": 301},   # Skitty → Delcatty (pierre)
	924: {"level": 25, "evolves_to": 925},   # Compagnol → Maushold
}

# ── Navigation dans les lignées d'évolution (combats de dresseur, boss) ──

## Pré-évolution DIRECTE de `pid` (l'espèce qui évolue vers lui), ou -1 si
## `pid` est déjà une forme de base.
static func pre_evolution_of(pid: int) -> int:
	for base_id in EVOLUTIONS:
		if EVOLUTIONS[base_id]["evolves_to"] == pid:
			return int(base_id)
	return -1


## Remonte la lignée jusqu'à la forme de base (ex : Golem → Geodude).
static func base_species_of(pid: int) -> int:
	var cur := pid
	var prev := pre_evolution_of(cur)
	while prev != -1:
		cur = prev
		prev = pre_evolution_of(cur)
	return cur


## Descend la lignée jusqu'à la forme finale (ex : Geodude → Golem).
static func final_evolution_of(pid: int) -> int:
	var cur := pid
	while EVOLUTIONS.has(cur):
		cur = int(EVOLUTIONS[cur]["evolves_to"])
	return cur


# ── Réglages audio (persistants, cf. save_game/apply_audio_settings) ────
var master_volume: float = 1.0   # 0..1
var sfx_volume:    float = 1.0   # 0..1
var audio_muted:   bool  = false

## Applique les réglages courants aux bus audio réels (cf. default_bus_
## layout.tres : bus 0 = Master, bus 1 = SFX). À appeler après tout
## changement (curseur bougé, mute togglé) — et une fois au démarrage.
func apply_audio_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	var sfx_idx     := AudioServer.get_bus_index("SFX")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(master_idx, audio_muted)
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_volume, 0.0001)))


# ── État du Hub ──────────────────────────────────────────────────────
var gold:             int        = 200
var run_count:        int        = 0
var is_first_run:     bool       = true
var unlocked_pokemon: Array[int] = []
var hub_team:         Array[int] = []
var owned_items:      Array[String] = []
var run_items:        Array         = []  # items ramassés pendant la run courante

# ── Inventaire d'objets tenus (Gromago) — persistant entre les runs ──────
# item_inventory : api → nb de copies LIBRES (non assignées).
# pokemon_item   : pid → api de l'objet tenu par ce Pokémon (une copie déjà
#                  consommée de l'inventaire).
# start_level_bonus : pid → niveaux de départ bonus (Super Bonbon).
var item_inventory:    Dictionary = {}
var pokemon_item:      Dictionary = {}
var start_level_bonus: Dictionary = {}

## Amélioration permanente : les baies au sol s'attirent vers le joueur
## (cf. BerryPickup). Achetée chez les Améliorations du hub.
var berry_magnet: bool = false
const BERRY_MAGNET_COST := 300


## En multijoueur, un INVITÉ pioche Pokémon/objets dans les déblocages de
## L'HÔTE (cf. Net.host_unlocked/host_items), pas les siens — un invité peut
## être tout nouveau, l'hôte avancé dans sa propre progression. L'hôte, lui,
## reste toujours sa propre référence.
func effective_unlocked_pokemon() -> Array:
	if Net.active and not Net.is_host():
		return Net.host_unlocked
	return unlocked_pokemon


func effective_item_inventory() -> Dictionary:
	if Net.active and not Net.is_host():
		return Net.host_items
	return item_inventory


func get_item_count(api: String) -> int:
	return int(item_inventory.get(api, 0))


## Achète une copie d'un objet du catalogue contre des Baies.
func buy_item(api: String) -> bool:
	var it := ItemCatalog.get_item(api)
	if it.is_empty() or not spend_gold(int(it["price"])):
		return false
	item_inventory[api] = get_item_count(api) + 1
	return true


func get_assigned_item(pid: int) -> String:
	return pokemon_item.get(pid, "")


## Assigne un objet tenu à `pid` (consomme une copie libre). Rend d'abord à
## l'inventaire l'objet précédemment tenu par ce Pokémon.
func assign_item(pid: int, api: String) -> bool:
	if get_item_count(api) <= 0:
		return false
	unassign_item(pid)
	item_inventory[api] = get_item_count(api) - 1
	pokemon_item[pid] = api
	return true


func unassign_item(pid: int) -> void:
	var cur: String = pokemon_item.get(pid, "")
	if cur != "":
		item_inventory[cur] = get_item_count(cur) + 1
		pokemon_item.erase(pid)


## Consomme un Super Bonbon de l'inventaire pour augmenter le niveau de
## départ de `pid` (plafonné à CANDY_MAX_BONUS). Retourne false si pas de
## bonbon ou plafond atteint.
func use_candy(pid: int) -> bool:
	if get_item_count("rare-candy") <= 0:
		return false
	var cur: int = int(start_level_bonus.get(pid, 0))
	if cur >= ItemCatalog.CANDY_MAX_BONUS:
		return false
	item_inventory["rare-candy"] = get_item_count("rare-candy") - 1
	start_level_bonus[pid] = cur + ItemCatalog.CANDY_LEVELS
	return true


func get_start_level_bonus(pid: int) -> int:
	return int(start_level_bonus.get(pid, 0))

# ── Améliorations permanentes achetées au hub ─────────────────────────
## 4 emplacements de capacités DÉBLOQUÉS D'OFFICE (retour joueurs). Le poids
## d'un build ne vient plus du NOMBRE de slots mais de la PUISSANCE des
## attaques qu'on y met (cf. move_weight) : emmener 4 attaques faibles ne coûte
## rien, empiler 4 grosses frappes coûte cher.
var move_slot_count:       int           = MOVE_SLOTS   # emplacements capacités
var team_slot_count:       int           = 1   # taille équipe (1-6)
var dash_charges_bought:   int           = 0   # charges de Dash (0-3) — 0 au départ
var purchased_move_names:  Array[String] = []  # capacités achetées chez le tuteur

# Moveset configuré par Pokémon depuis le Pokédex — persiste même hors équipe.
# pid:int -> Array[String] (api_name des capacités équipées, ordre = slots)
var move_loadouts: Dictionary = {}

const MOVE_SLOTS := 4   # tous les Pokémon ont 4 emplacements, d'office

## Cache api_name -> puissance, alimenté par PokemonAPI dès qu'une fiche est
## résolue. Le poids d'un build doit se calculer SYNCHRONEMENT (affichage du
## Pokédex, blocage du lancement de run) alors que les puissances arrivent en
## asynchrone : sans ce cache, le poids sauterait au fil des réponses réseau.
var move_power_cache: Dictionary = {}

func note_move_power(api_name: String, power: int) -> void:
	if api_name != "" and not move_power_cache.has(api_name):
		move_power_cache[api_name] = power


## Poids d'UNE capacité selon sa puissance : les attaques faibles (celles qu'on
## a d'office) sont GRATUITES, les grosses frappes coûtent jusqu'à 3.
## Puissance inconnue (fiche pas encore chargée) -> 0 : on n'invente pas un coût.
func move_weight(api_name: String) -> int:
	var p := int(move_power_cache.get(api_name, 0))
	if p <= 40:  return 0
	if p <= 70:  return 1
	if p <= 90:  return 2
	return 3


## Poids total des capacités équipées par `pid`.
func loadout_weight(pid: int) -> int:
	var total := 0
	for api in get_move_loadout(pid):
		total += move_weight(str(api))
	return total


## LOADOUT EFFECTIF — la règle UNIQUE partagée par le Pokédex (build) et la run
## (PokemonInstance.init_moves). Avant, le Pokédex ne mémorisait que les CT et
## la run recomplétait les attaques de base dans son propre ordre : le build
## affiché n'était pas celui joué (retour joueurs : « les attaques choisies ne
## sont pas les mêmes quand je lance la run »).
##
## `available` : toutes les capacités que CE Pokémon peut équiper (base + CT),
## en api_name. Si un loadout est enregistré, on le respecte à la lettre (filtré
## de ce qui n'est plus disponible) ; sinon on pré-équipe les 4 attaques les
## moins puissantes — les « gratuites », pour partir d'un build à poids nul que
## le joueur fait ensuite monter par choix.
func effective_loadout(pid: int, available: Array) -> Array:
	var out: Array = []
	for api in get_move_loadout(pid):
		if str(api) in available and not str(api) in out:
			out.append(str(api))
		if out.size() >= MOVE_SLOTS:
			break
	# COMPLÈTE jusqu'à 4 avec les attaques les plus FAIBLES encore disponibles.
	# Les emplacements sont gratuits (seule la puissance pèse) : laisser un slot
	# vide ne rapporterait rien au joueur, et un ancien loadout de 3 CT aurait
	# perdu un emplacement en silence. Tri STABLE (départage par nom) pour que
	# le Pokédex et la run choisissent exactement les mêmes.
	var pool: Array = available.duplicate()
	pool.sort_custom(func(a, b) -> bool:
		var pa := int(move_power_cache.get(str(a), 0))
		var pb := int(move_power_cache.get(str(b), 0))
		if pa == pb:
			return str(a) < str(b)
		return pa < pb)
	for api in pool:
		if out.size() >= MOVE_SLOTS:
			break
		if not str(api) in out:
			out.append(str(api))
	return out

## Les 4 emplacements sont acquis d'office — le coût d'un build passe par la
## PUISSANCE des attaques (cf. move_weight), pas par le nombre de slots.
func get_move_slots(_pid: int) -> int:
	return MOVE_SLOTS

const MOVE_SLOT_COSTS: Array[int] = [100, 200, 400]  # coût pour passer à 2, 3, 4 slots
const TEAM_SLOT_COSTS: Array[int] = [80, 120, 180, 250, 350]  # pour chaque slot ajouté
const DASH_CHARGE_COSTS: Array[int] = [60, 120, 200]  # coût des charges de Dash 1, 2, 3

# ── Système de poids de build (version simple, validée en plan) ────────
# Chaque Pokémon/objet tenu/CT équipée a un poids FIXE ; la somme ne doit
# pas dépasser `build_weight_cap` pour lancer une run (cf. HubWorld._start_
# run). Retour joueurs : encourager une compo équilibrée plutôt que 6
# pseudo-légendaires + items.
#
# ÉCONOMIE : le plafond se paie en ÉCLATS DE CHAMPION (lâchés uniquement par
# les boss, cf. CombatArena._reward_boss) et NON en baies — c'est la seule
# dépense de cette ressource, qui n'en avait aucune jusqu'ici. Revenu ≈ 13
# éclats par run complète → il faut ~2 runs abouties pour monter au max.
var build_weight_cap: int = 24
const WEIGHT_CAP_STEP  := 4     # gain par palier
const WEIGHT_CAP_MAX   := 40
const WEIGHT_CAP_COSTS: Array[int] = [2, 4, 7, 12]   # en ÉCLATS — 24→28→32→36→40

func spend_champion_shards(n: int) -> bool:
	if n <= 0 or champion_shards < n:
		return false
	champion_shards -= n
	return true

func buy_weight_cap(cost: int) -> bool:
	if build_weight_cap >= WEIGHT_CAP_MAX or not spend_champion_shards(cost):
		return false
	build_weight_cap = mini(build_weight_cap + WEIGHT_CAP_STEP, WEIGHT_CAP_MAX)
	return true

## Poids d'un Pokémon selon son stade d'évolution (base=3, stade2=5, stade
## final=8) — une lignée pleinement évoluée coûte plus cher à emmener.
static func pokemon_weight(pid: int) -> int:
	var stage := 0
	var cur := pid
	var prev := pre_evolution_of(cur)
	while prev != -1:
		stage += 1
		cur = prev
		prev = pre_evolution_of(cur)
	return 3 + stage * 2

const ITEM_WEIGHT := 2   # objet tenu (Gromago) — poids fixe
const MOVE_WEIGHT := 1   # CT achetée et équipée — poids fixe

## Poids total de l'équipe (hub_team) : Pokémon + objets tenus + CT
## équipées. Utilisé pour bloquer le lancement d'une run au-delà du cap.
func compute_team_weight() -> int:
	var total := 0
	for pid in hub_team:
		total += pokemon_weight(pid)
		if get_assigned_item(pid) != "":
			total += ITEM_WEIGHT
		# Les CAPACITÉS pèsent selon leur PUISSANCE (0 pour les faibles, jusqu'à
		# 3 pour une grosse frappe) — le build se paie en force de frappe, pas
		# en nombre d'emplacements.
		total += loadout_weight(pid)
	return total


## Capacités explicitement choisies pour ce Pokémon (vide si jamais configuré).
func get_move_loadout(pid: int) -> Array:
	return (move_loadouts.get(pid, []) as Array).duplicate()


## Remplace `old_api` par `new_api` dans le loadout de `pid`, À LA MÊME PLACE.
## C'est le chemin « slots pleins » du Pokédex : le joueur choisit explicitement
## quelle capacité céder sa place (avant, il fallait deviner qu'on devait
## d'abord retirer, puis équiper — retour joueurs).
## Loadout BRUT (get_move_loadout) tant que rien n'est sauvegardé est vide —
## mais l'écran affiche effective_loadout (les 4 attaques par défaut). Sans ce
## seed, retirer une carte affichée comme équipée partirait d'un tableau vide
## et ne ferait rien d'observable. `available` = toutes les capacités que ce
## Pokémon peut équiper (fourni par l'appelant, qui les a déjà sous la main).
func _seeded_loadout(pid: int, available: Array) -> Array:
	if move_loadouts.has(pid):
		return get_move_loadout(pid)
	return effective_loadout(pid, available)


func replace_move_in_loadout(pid: int, old_api: String, new_api: String, available: Array) -> void:
	var arr: Array = _seeded_loadout(pid, available)
	var idx := arr.find(old_api)
	if idx == -1 or new_api in arr:
		return
	arr[idx] = new_api
	move_loadouts[pid] = arr


## Équipe/déséquipe une capacité pour un Pokémon précis — 4 slots toujours.
func toggle_move_in_loadout(pid: int, api_name: String, available: Array) -> void:
	var arr: Array = _seeded_loadout(pid, available)
	if api_name in arr:
		arr.erase(api_name)
	elif arr.size() < MOVE_SLOTS:
		arr.append(api_name)
	move_loadouts[pid] = arr

# ── Catalogue boutique ────────────────────────────────────────────────
const SHOP_CATALOG: Array[Dictionary] = [
	{"id": "x_attack",  "name": "Capacité+",   "sym": "▲", "price": 80,  "desc": "+20% ATQ pour toute l'équipe cette run.",          "sym_color": Color(0.95, 0.50, 0.10)},
	{"id": "x_defend",  "name": "Défense+",    "sym": "▣", "price": 80,  "desc": "+20% DÉF pour toute l'équipe cette run.",          "sym_color": Color(0.30, 0.50, 0.90)},
	{"id": "x_speed",   "name": "Agilité+",    "sym": "★", "price": 80,  "desc": "+20% VIT pour toute l'équipe cette run.",          "sym_color": Color(0.88, 0.80, 0.10)},
	{"id": "boost_hp",  "name": "Vigueur",     "sym": "◆", "price": 100, "desc": "+20% PV max pour toute l'équipe cette run.",       "sym_color": Color(0.18, 0.70, 0.35)},
	{"id": "revive",    "name": "Rappel",      "sym": "✦", "price": 150, "desc": "Le premier KO de l'équipe est relevé à 50% PV.",   "sym_color": Color(0.90, 0.60, 0.10)},
	{"id": "exp_share", "name": "Partage XP",  "sym": "⊕", "price": 120, "desc": "+30% d'expérience gagnée pendant la run.",         "sym_color": Color(0.25, 0.55, 0.95)},
]

# ── Capacités Spéciales (CS) — débloquent le franchissement d'obstacles
# en run (eau, arbres à couper, rochers). Achat unique et permanent,
# puis assignées à un Pokémon de l'équipe (cf. CSAssignScreen).
const CS_CATALOG: Array[Dictionary] = [
	{"id": "cs_surf",  "name": "CS Surf",  "sym": "≈", "price": 250, "desc": "Permet de nager à travers l'eau une fois assignée à un Pokémon de l'équipe.",        "sym_color": Color(0.25, 0.55, 0.90), "permanent": true},
	{"id": "cs_coupe", "name": "CS Coupe", "sym": "✂", "price": 200, "desc": "Permet de couper les arbres bloquant l'accès à certains coffres.",                    "sym_color": Color(0.30, 0.70, 0.30), "permanent": true},
	{"id": "cs_force", "name": "CS Force", "sym": "⛰", "price": 220, "desc": "Permet de pousser/casser les rochers bloquant l'accès à certains coffres.",           "sym_color": Color(0.65, 0.45, 0.25), "permanent": true},
]

# pid:int -> "cs_surf"/"cs_coupe"/"cs_force" assigné à ce Pokémon (au plus 1 CS par Pokémon)
var cs_holders: Dictionary = {}

## CS possédées — stockage DÉDIÉ et permanent (toutes les runs). Ne surtout
## pas les mettre dans owned_items : celui-ci est consommé/vidé à chaque
## entrée en run (cf. CombatArena._apply_hub_items), ce qui effaçait les CS
## achetées — c'était le bug « la touche A ne fait rien ».
var owned_cs: Array[String] = []


func owns_cs(cs_id: String) -> bool:
	return cs_id in owned_cs


func buy_cs(cs_id: String, price: int) -> bool:
	if owns_cs(cs_id) or not spend_gold(price):
		return false
	owned_cs.append(cs_id)
	return true


## Assigne `cs_id` au Pokémon `pid` — un Pokémon ne peut tenir qu'une seule
## CS à la fois (remplace toute assignation précédente pour ce Pokémon),
## et une CS n'est tenue que par un seul Pokémon à la fois.
func assign_cs(cs_id: String, pid: int) -> void:
	for key in cs_holders.keys():
		if cs_holders[key] == pid:
			cs_holders.erase(key)
	cs_holders[cs_id] = pid


func get_cs_holder(cs_id: String) -> int:
	return cs_holders.get(cs_id, 0)


func get_pokemon_cs(pid: int) -> String:
	for key in cs_holders.keys():
		if cs_holders[key] == pid:
			return key
	return ""

# ── Taille d'équipe (achetable) ───────────────────────────────────────
func get_max_team_size() -> int:
	return team_slot_count

func get_next_unlock_threshold() -> int:
	return 999  # gardé pour compatibilité

# ── Helpers ───────────────────────────────────────────────────────────
func reset_run_items() -> void:
	run_items.clear()

func add_run_item(item: Dictionary) -> void:
	run_items.append(item)

func unlock_pokemon(id: int) -> void:
	if id not in unlocked_pokemon:
		unlocked_pokemon.append(id)


# ── Mode test ───────────────────────────────────────────────────────────
# Débloque tout pour tester en conditions réelles sans avoir à farmer :
# roster large, toutes les CS, emplacements/équipe au max, Baies à gogo,
# aimant à baies. Déclenché par le bouton « MODE TEST » de l'accueil.
# Formes de BASE uniquement (les évolutions se gagnent par le niveau /
# Super Bonbons — cf. is_team_selectable).
const TEST_ROSTER: Array[int] = [
	25, 4, 7, 1, 447, 443, 280, 258, 63, 92,   # Pikachu, Salamèche, Carapuce, Bulbizarre, Riolu, Griknot, Tarsal, Gobou, Abra, Fantominus
	147, 129, 143, 246, 215, 123, 371, 359, 133, 175,  # Minidraco, Magicarpe, Ronflex, Embrylex, Farfuret, Insécateur, Draby, Absol, Évoli, Togepi
]

func enable_test_mode(starter_id: int) -> void:
	selected_starter_id = starter_id
	for pid in TEST_ROSTER:
		unlock_pokemon(pid)
	unlock_pokemon(starter_id)
	# Équipe de départ : le starter + 3 premiers du roster (distincts)
	hub_team = [starter_id]
	for pid in TEST_ROSTER:
		if pid != starter_id and hub_team.size() < 4:
			hub_team.append(pid)
	# Toutes les CS + monnaie + emplacements max
	for cs: Dictionary in CS_CATALOG:
		if cs["id"] not in owned_cs:
			owned_cs.append(cs["id"])
	gold             = 9999
	move_slot_count  = 4
	team_slot_count  = 6
	dash_charges_bought = 3
	berry_magnet     = true
	is_first_run     = false


# ── Déblocage par victoires cumulées ────────────────────────────────────
const UNLOCK_DEFEAT_THRESHOLD := 20

var defeat_counts: Dictionary = {}   # pid:int -> int (victoires cumulées contre cette espèce)


func get_defeat_count(pid: int) -> int:
	return defeat_counts.get(pid, 0)


## Compte une victoire contre cette espèce. Débloque automatiquement le Pokémon
## une fois le seuil atteint — seules les formes de base sont recrutables.
## Retourne true si ce KO vient de déclencher le déblocage.
func record_defeat(pid: int, is_base_form: bool = true) -> bool:
	defeat_counts[pid] = get_defeat_count(pid) + 1
	if is_base_form and pid not in unlocked_pokemon and defeat_counts[pid] >= UNLOCK_DEFEAT_THRESHOLD:
		unlock_pokemon(pid)
		return true
	return false


# ── Champions vaincus : badges (gloire) + éclats (ressource) + recrutement ──
## Badges gagnés (un par champion battu au moins une fois) — pure gloire,
## affichés dans le hub. `champion_shards` = ressource lâchée par les boss,
## réservée à l'augmentation de capacité du système de build (cf. #37).
var champion_badges:  Array[String] = []   # noms de champions battus
var champion_shards:  int = 0

## Enregistre une victoire de boss. Retourne true si c'est la PREMIÈRE fois
## qu'on bat ce champion (→ badge accordé + recrutement proposé en run).
func record_champion_win(champ_name: String) -> bool:
	var first := champ_name not in champion_badges
	if first:
		champion_badges.append(champ_name)
	return first


func add_champion_shards(n: int) -> void:
	champion_shards = maxi(0, champion_shards + n)


## Pokédollars (₽) — monnaie DE RUN : gagnée en libérant des salles,
## dépensée dans la boutique de fin de salle, remise à zéro à chaque départ
## de run. La monnaie PERSISTANTE du hub est `gold`, affichée "Baies".
var run_money: int = 0

func add_run_money(amount: int) -> void:
	run_money = max(0, run_money + amount)

func spend_run_money(amount: int) -> bool:
	if run_money < amount:
		return false
	run_money -= amount
	return true


func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

func get_run_team() -> Array[int]:
	if hub_team.is_empty():
		return [selected_starter_id]
	return hub_team


## Une espèce est sélectionnable comme MEMBRE D'ÉQUIPE seulement si c'est
## une forme de DÉPART : les évolutions s'obtiennent par le niveau (Super
## Bonbons → get_effective_start), jamais en les choisissant directement —
## un Florizarre niveau 10 n'a pas de sens.
##   - cible d'évolution de la table du jeu (EVOLUTIONS) → refusé ;
##   - clé d'EVOLUTIONS (ex. Pikachu, traité comme départ ici) → accepté ;
##   - sinon on suit l'API (`api_base_form` = PokemonData.is_base_form).
func is_team_selectable(pid: int, api_base_form: bool) -> bool:
	for k in EVOLUTIONS:
		if int(EVOLUTIONS[k]["evolves_to"]) == pid:
			return false
	if EVOLUTIONS.has(pid):
		return true
	return api_base_form


## Niveau + forme de DÉPART d'un Pokémon d'équipe, une fois appliqués les
## Super Bonbons (niveaux bonus) puis la chaîne d'évolution jusqu'au niveau
## atteint. Retourne {"base": pid, "id": forme finale, "level": niveau}.
## `base` reste l'id original (clé de pokemon_item pour l'objet tenu).
func get_effective_start(pid: int, base_level: int) -> Dictionary:
	var level := base_level + get_start_level_bonus(pid)
	var id := pid
	while EVOLUTIONS.has(id) and level >= int(EVOLUTIONS[id]["level"]):
		id = int(EVOLUTIONS[id]["evolves_to"])
	return {"base": pid, "id": id, "level": level}


# ── Sauvegarde persistante (user://save.json) ─────────────────────────
## Sans ça, toute la progression (Pokémon débloqués, équipe, objets,
## améliorations…) repartait de zéro à chaque lancement du jeu — retour
## joueur : on devait rechoisir son starter à CHAQUE relance, pas
## seulement la toute première fois. `run_money`/`run_items` ne sont PAS
## sauvés : propres à la run en cours, remis à zéro à chaque départ (déjà
## le comportement voulu, cf. commentaires plus haut).
const SAVE_PATH := "user://save.json"

## Remaps clavier du joueur : action_id → keycode. Vide = tout par défaut.
## Source unique de vérité des touches : cf. Controls (scripts/ui/Controls.gd).
var key_bindings: Dictionary = {}

func _ready() -> void:
	load_game()
	apply_audio_settings()
	Controls.apply()   # construit l'InputMap (défauts + remaps sauvegardés)


func save_game() -> void:
	var data := {
		"selected_starter_id": selected_starter_id,
		"gold":                gold,
		"run_count":           run_count,
		"is_first_run":        is_first_run,
		"unlocked_pokemon":    unlocked_pokemon,
		"hub_team":            hub_team,
		"owned_items":         owned_items,
		"item_inventory":      item_inventory,
		"pokemon_item":        _stringify_keys(pokemon_item),
		"start_level_bonus":   _stringify_keys(start_level_bonus),
		"berry_magnet":        berry_magnet,
		"move_slot_count":     move_slot_count,
		"team_slot_count":     team_slot_count,
		"dash_charges_bought": dash_charges_bought,
		"purchased_move_names": purchased_move_names,
		"move_loadouts":       _stringify_keys(move_loadouts),
		"move_power_cache":    move_power_cache,
		"cs_holders":          cs_holders,
		"owned_cs":            owned_cs,
		"defeat_counts":       _stringify_keys(defeat_counts),
		"champion_badges":     champion_badges,
		"champion_shards":     champion_shards,
		"build_weight_cap":    build_weight_cap,
		"key_bindings":        key_bindings,
		"master_volume":       master_volume,
		"sfx_volume":          sfx_volume,
		"audio_muted":         audio_muted,
		"story":               StoryManager.to_dict(),
		"missions":            MissionManager.to_dict(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameManager: échec d'écriture de la sauvegarde (%s)" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed

	selected_starter_id  = int(d.get("selected_starter_id", selected_starter_id))
	gold                 = int(d.get("gold", gold))
	run_count            = int(d.get("run_count", run_count))
	is_first_run         = bool(d.get("is_first_run", is_first_run))
	unlocked_pokemon.assign(d.get("unlocked_pokemon", []))
	hub_team.assign(d.get("hub_team", []))
	owned_items.assign(d.get("owned_items", []))
	item_inventory       = d.get("item_inventory", {})
	pokemon_item         = _intify_keys(d.get("pokemon_item", {}))
	start_level_bonus    = _intify_keys(d.get("start_level_bonus", {}))
	berry_magnet         = bool(d.get("berry_magnet", berry_magnet))
	move_slot_count      = int(d.get("move_slot_count", move_slot_count))
	team_slot_count      = int(d.get("team_slot_count", team_slot_count))
	dash_charges_bought  = int(d.get("dash_charges_bought", dash_charges_bought))
	purchased_move_names.assign(d.get("purchased_move_names", []))
	move_loadouts        = _intify_keys(d.get("move_loadouts", {}))
	move_power_cache     = d.get("move_power_cache", {})
	move_slot_count      = maxi(move_slot_count, MOVE_SLOTS)   # 4 slots d'office
	cs_holders           = d.get("cs_holders", {})
	owned_cs.assign(d.get("owned_cs", []))
	defeat_counts        = _intify_keys(d.get("defeat_counts", {}))
	champion_badges.assign(d.get("champion_badges", []))
	champion_shards      = int(d.get("champion_shards", champion_shards))
	build_weight_cap     = int(d.get("build_weight_cap", build_weight_cap))
	key_bindings         = d.get("key_bindings", {})
	master_volume        = float(d.get("master_volume", master_volume))
	sfx_volume           = float(d.get("sfx_volume", sfx_volume))
	audio_muted          = bool(d.get("audio_muted", audio_muted))
	StoryManager.from_dict(d.get("story", {}))
	MissionManager.from_dict(d.get("missions", {}))


## JSON n'autorise que des clés-chaînes — nos dictionnaires pid→… utilisent
## des clés int côté jeu. Aller-retour transparent à la sauvegarde/chargement.
func _stringify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


func _intify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out


## Sauvegarde de sécurité si le joueur quitte sans repasser par le Hub
## (fermeture de la fenêtre pendant une run, Alt+F4…).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


## Efface la sauvegarde et remet toute la progression à zéro (équivalent
## d'une toute première partie). Utilisé par le bouton "Réinitialiser" des
## Paramètres — le joueur doit ensuite être renvoyé à l'écran titre pour
## repasser par le choix du starter.
func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	selected_starter_id  = 25
	gold                  = 200
	run_count             = 0
	is_first_run          = true
	unlocked_pokemon      = []
	hub_team              = []
	owned_items           = []
	item_inventory        = {}
	pokemon_item          = {}
	start_level_bonus     = {}
	berry_magnet          = false
	move_slot_count       = MOVE_SLOTS
	team_slot_count       = 1
	dash_charges_bought   = 0
	purchased_move_names  = []
	move_loadouts         = {}
	move_power_cache      = {}
	cs_holders            = {}
	owned_cs              = []
	defeat_counts         = {}
	champion_badges       = []
	champion_shards       = 0
	build_weight_cap      = 24
	key_bindings          = {}
	StoryManager.reset()
	MissionManager.reset()
