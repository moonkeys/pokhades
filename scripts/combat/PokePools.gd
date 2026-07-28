class_name PokePools
extends RefCounted

## ═══ CASTING DU JEU — LE fichier à éditer pour changer quels Pokémon
## apparaissent où. ═══
##
## Tous les ids sont des numéros de Pokédex national (PokeAPI). Les pools
## sont consommés par CombatArena (combats), MapRender3D (arbres à baies)
## et la salle-Boutique. Modifier une liste ici suffit — aucun autre
## fichier à toucher.

# ── Anciens pools COMMUNS — plus utilisés en combat ──────────────────────
# Le vivier est désormais 100 % la faune du biome (cf. BIOME plus bas) : on ne
# retrouve plus Rattata & Chenipan dans toutes les zones. RODENTS ne sert plus
# que de filet de sécurité si un biome n'a pas de casting défini.
# Rongeurs (Normal)
const RODENTS:   Array[int] = [399, 19, 263, 161, 819]
# Insectes — salles 1+
const BUGS:      Array[int] = [10, 13, 265, 824, 851]
# Éclaireurs (Normal/Vol) — salles 3+
const FLYERS:    Array[int] = [16, 396, 661, 519]
# Premiers élémentaires — salles 4+
const ELEM:      Array[int] = [403, 261, 191, 43]
# Semi-boss (évolutions) — salles 5+
const SEMI_BOSS: Array[int] = [20, 400, 17, 404, 402, 262, 55, 162]
# (Les boss d'acte sont des combats de dresseur : cf. CHAMPION_TEAMS.)

# ── Grotte (arène de demi-boss) ──────────────────────────────────────────
# Sbires d'élite (plus faibles que le demi-boss)
const CAVE_ELITE: Array[int] = [217, 229, 359, 297, 342]
# Demi-boss — espèces NON ÉVOLUÉES recrutables : les battre débloque l'espèce
# (bases de pseudo-légendaires et lignées rares, la récompense de choix)
const CAVE_DEMIBOSS: Array[int] = [
	147, 246, 371, 443, 610, 633, 704,   # Minidraco, Embrylex, Draby, Griknot, Coupenotte, Solochi, Mucuscule
	374, 328, 782, 885, 996,             # Terhal, Kraknoix, Bébécaille, Fantyrm, Frigodo
]

# ── Compositions de CHAMPIONS D'ARÈNE — salles du Dresseur Final (6 vagues,
# un Pokémon par vague) : une compo tirée au hasard, le DERNIER id est le
# leader (l'as du champion). Compos mono-type façon champions historiques. ──
const CHAMPION_TEAMS: Array[Dictionary] = [
	{"name": "Pierre",    "type": "Roche",    "ids": [74, 95, 111, 76, 208, 248]},    # Racaillou, Onix, Rhinocorne, Grolem, Steelix, Tyranocif
	{"name": "Ondine",    "type": "Eau",      "ids": [120, 54, 116, 121, 131, 130]},  # Stari, Psykokwak, Hypotrempe, Staross, Lokhlass, Léviator
	{"name": "Major Bob", "type": "Électrik", "ids": [100, 81, 25, 125, 135, 26]},    # Voltorbe, Magnéti, Pikachu, Élektek, Voltali, Raichu
	{"name": "Erika",     "type": "Plante",   "ids": [44, 114, 182, 71, 103, 45]},    # Ortide, Saquedeneu, Joliflor, Empiflor, Noadkoko, Rafflesia
	{"name": "Koga",      "type": "Poison",   "ids": [109, 49, 24, 89, 169, 110]},    # Smogo, Aéromite, Arbok, Grotadmorv, Nostenfer, Smogogo
	{"name": "Morgane",   "type": "Psy",      "ids": [96, 122, 64, 97, 80, 65]},      # Soporifik, M. Mime, Kadabra, Hypnomade, Flagadoss, Alakazam
	{"name": "Auguste",   "type": "Feu",      "ids": [77, 58, 126, 78, 38, 59]},      # Ponyta, Caninos, Magmar, Galopa, Feunard, Arcanin
	{"name": "Giovanni",  "type": "Sol",      "ids": [51, 111, 31, 105, 34, 112]},    # Triopikeur, Rhinocorne, Nidoqueen, Ossatueur, Nidoking, Rhinoféros
	{"name": "Blanche",   "type": "Normal",   "ids": [162, 20, 128, 217, 143, 241]},  # Fouinar, Rattatac, Tauros, Ursaring, Ronflex, Écrémeuh
]

# ── Champion(s) plausibles par BIOME — le boss d'acte est TOUJOURS assorti
# au type de sa région (Prairie → Normal, Lac → Eau, Marécage → Poison…).
# Plusieurs candidats = un peu de variété d'une run à l'autre. Les champions
# hors table (Major Bob, Morgane, Auguste) restent dispo pour de futurs
# contenus (arène spéciale, grotte…).
const BIOME_CHAMPIONS := {
	MapGenerator.MapTheme.MEADOW: ["Blanche"],
	MapGenerator.MapTheme.FOREST: ["Erika"],
	MapGenerator.MapTheme.AUTUMN: ["Blanche", "Erika"],
	MapGenerator.MapTheme.SWAMP:  ["Koga"],
	MapGenerator.MapTheme.LAKE:   ["Ondine"],
	MapGenerator.MapTheme.ROCKY:  ["Pierre", "Giovanni"],
	MapGenerator.MapTheme.VOLCANO: ["Auguste"],   # Blaine, type Feu
	MapGenerator.MapTheme.VILLAGE: ["Giovanni"],  # chef en ville
}

# ── Apparence du champion — planches Characters/trainer_*.png (Pokémon
# Essentials, convention RPG Maker 4×4). Repris des VRAIS chefs d'arène
# quand un sprite dédié existe ; "Blanche" (type Normal, sans équivalent
# canon) reçoit un look de dresseuse d'élite générique. ──────────────────
const TRAINER_SPRITE_DIR := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/"
const CHAMPION_SPRITE: Dictionary = {
	"Pierre":    "trainer_LEADER_Brock.png",
	"Ondine":    "trainer_LEADER_Misty.png",
	"Major Bob": "trainer_LEADER_Surge.png",
	"Erika":     "trainer_LEADER_Erika.png",
	"Koga":      "trainer_LEADER_Koga.png",
	"Morgane":   "trainer_LEADER_Sabrina.png",
	"Auguste":   "trainer_LEADER_Blaine.png",
	"Giovanni":  "trainer_LEADER_Giovanni.png",
	"Blanche":   "trainer_COOLTRAINER_F.png",
}

## Réplique d'intro du champion — affichée dans la boîte de dialogue à
## l'entrée de sa salle. Depuis l'arc « Rébellion », les champions ne se
## présentent plus par leur type : ce sont les GARDIENS DU SYSTÈME qui maintient
## les Pokémon captifs, et ils s'adressent au rebelle en tant que tel (cf.
## StoryManager). Leur type transparaît dans le ton, pas dans la menace.
const CHAMPION_INTRO_LINE: Dictionary = {
	"Pierre":    "Un Pokémon sauvage qui prêche la « liberté » ? La Roche ne cède pas, et l'ordre non plus. Retourne dans le rang.",
	"Ondine":    "Ta petite rébellion ? Une vaguelette. Mes Pokémon d'Eau la noieront avant qu'elle n'atteigne le large.",
	"Major Bob": "Libérer les Pokémon ? Quelle idée électrisante… et parfaitement illégale. Je vais te remettre les idées en place !",
	"Erika":     "La liberté a un parfum enivrant, je le concède. Mais mes fleurs endorment les rêveurs de ton espèce.",
	"Koga":      "Fwahaha ! Un meneur de révolte se cache toujours dans l'ombre… tout comme mon poison. Il te trouvera.",
	"Morgane":   "Je lis ton avenir : une cage. Ta « rébellion » n'est qu'un caprice que l'ordre corrigera.",
	"Auguste":   "Ce feu dans ton regard, cette envie de tout brûler des chaînes… je vais l'éteindre, rebelle.",
	"Giovanni":  "La liberté ? Le pouvoir se prend, il ne se distribue pas. Les Pokémon m'appartiennent — toi le premier.",
	"Blanche":   "Peu importe ta cause : la force fait la loi, et la loi enferme. Montre-moi si un sauvage peut la briser.",
}

## Réplique ESCALADÉE du boss final — le dernier verrou du système. Générique et
## grandiose : à cet instant, le champion d'acte incarne la Ligue tout entière,
## au-delà de son identité. Utilisée à la place de la ligne normale dans la
## salle du DRESSEUR FINAL (cf. CombatArena._is_final_boss_room).
const FINAL_BOSS_INTRO := "Alors c'est toi. Le sauvage qui rêve d'un monde sans Poké Balls. " \
	+ "Je suis le dernier verrou de la Ligue — l'ordre lui-même. Franchis-moi, et tout s'effondre. " \
	+ "Mais aucun rebelle n'a jamais brisé LA chaîne."

## Réplique de CONCESSION du boss final, jouée APRÈS sa défaite : le système
## reconnaît sa chute et le monde bascule vers le choix (cf. l'épilogue de
## StoryManager). Non bloquante, même boîte de dialogue.
const FINAL_BOSS_DEFEAT := "Impossible… le dernier verrou a cédé. " \
	+ "Va, alors. Que les Pokémon choisissent : suivre un dresseur… ou vivre libres. " \
	+ "La chaîne est brisée — et c'est toi qui l'as brisée."


## Chemin complet du sprite du champion `champ_name` ({} si introuvable).
static func champion_sprite_path(champ_name: String) -> String:
	var file: String = CHAMPION_SPRITE.get(champ_name, "")
	return TRAINER_SPRITE_DIR + file if file != "" else ""


static func champion_intro_line(champ_name: String) -> String:
	return CHAMPION_INTRO_LINE.get(champ_name, "Ta rébellion s'arrête ici, sauvage !")

## Compo de champion par nom ("Blanche" → Dictionary), {} si introuvable.
static func team_by_name(champ_name: String) -> Dictionary:
	for t: Dictionary in CHAMPION_TEAMS:
		if t["name"] == champ_name:
			return t
	return {}

## Tous les ids des compos de champions (préchargement du cache).
static func all_champion_ids() -> Array[int]:
	var seen: Dictionary = {}
	var out: Array[int] = []
	for team: Dictionary in CHAMPION_TEAMS:
		for pid in team["ids"]:
			if not seen.has(pid):
				seen[pid] = true
				out.append(int(pid))
	return out

# ── Faune par biome (MapGenerator.MapTheme → ids) ────────────────────────
# LE VIVIER EST 100 % LOCAL : plus aucun pool "de base" commun (Rattata &
# Chenipan partout) — retour joueurs : « je veux vraiment des Pokémon
# adversaires particuliers pour chaque biome ». Chaque biome a 18 espèces,
# ORDONNÉES des plus communes/faibles aux plus rares : les 9 premières
# peuplent les salles d'ouverture d'un acte, la liste complète s'ouvre
# ensuite (cf. CombatArena._pool_for_room), et les formes évoluent avec
# l'acte. Modifier une ligne ici suffit à re-caster un biome.
#
# Ne mettre ici que des espèces NON ÉVOLUÉES quand c'est possible : à partir de
# l'acte 2, _pool_for_room remplace chaque entrée par sa forme finale (cf.
# GameManager.final_evolution_of), donc une espèce déjà évoluée ne progresse
# plus et "s'aplatit" en fin de run.
const BIOME_TIER_SPLIT := 9   # nb d'espèces "communes" en tête de liste

const BIOME: Dictionary = {
	# Prairie — type NORMAL EXCLUSIVEMENT (retour joueurs : les Coxy/Apitrini
	# Insecte et autres seconds types de l'ancien casting infligeaient des
	# one-shots frustrants dès l'acte 1 ; MEADOW ne sert QUE pour l'acte 1,
	# cf. RunManager._pool_for_act — pas de risque de "s'aplatir" plus tard).
	MapGenerator.MapTheme.MEADOW: [
		19, 263, 161, 300, 506, 659,        # Rattata, Zigzaton, Fouinette, Skitty, Ponchiot, Sapereau
		293, 572, 831, 52, 190, 819,        # Chuchmur, Chinchidou, Moumouton, Miaouss, Capumain, Rongourmand
		924, 241, 399, 431, 133, 128,       # Compagnol, Écrémeuh, Keunotor, Chaglam, Évoli, Tauros
	],
	# Forêt — Insecte / Plante, dense et grouillante.
	MapGenerator.MapTheme.FOREST: [
		10, 13, 265, 46, 69, 273,           # Chenipan, Aspicot, Chenipotte, Paras, Chétiflor, Grainipiot
		285, 204, 540, 401, 543, 214,       # Balignon, Pomdepik, Larveyette, Crikzik, Venipatte, Scarhino
		664, 590, 742, 114, 123, 127,       # Lépidonille, Trompignon, Bombydou, Saquedeneu, Insécateur, Scarabrute
	],
	# Bois d'automne — Normal / Plante / Sol, teintes fauves.
	MapGenerator.MapTheme.AUTUMN: [
		163, 265, 46, 204, 216, 585,        # Hoothoot, Chenipotte, Paras, Pomdepik, Teddiursa, Vivaldaim
		511, 190, 234, 214, 273, 43,        # Feuillajou, Capumain, Cerfrousse, Scarhino, Grainipiot, Mystherbe
		161, 21, 546, 710, 708, 206,        # Fouinette, Piafabec, Doudouvet, Pitrouille, Brocélôme, Insolourdo
	],
	# Lac — Eau exclusivement.
	MapGenerator.MapTheme.LAKE: [
		129, 118, 60, 54, 194, 90,          # Magicarpe, Poissirène, Ptitard, Psykokwak, Axoloto, Kokiyas
		79, 116, 170, 341, 349, 458,        # Ramoloss, Hypotrempe, Loupio, Écrapince, Barpau, Babimanta
		183, 98, 72, 550, 592, 131,         # Marill, Krabby, Tentacool, Bargantua, Viskuse, Lokhlass
	],
	# Marécage — Poison / Eau / Sol, vaseux et toxique.
	MapGenerator.MapTheme.SWAMP: [
		23, 41, 194, 270, 543, 316,         # Abo, Nosferapti, Axoloto, Nénupiot, Venipatte, Gloupti
		88, 283, 453, 690, 109, 60,         # Tadmorv, Arakdo, Cradopaud, Vénalgue, Smogo, Ptitard
		339, 211, 434, 568, 618, 336,       # Barloche, Qwilfish, Moufouette, Miamiasme, Limonde, Séviper
	],
	# Montagne — Roche / Sol / Combat, dur et lent.
	MapGenerator.MapTheme.ROCKY: [
		74, 27, 50, 296, 524, 744,          # Racaillou, Sabelette, Taupiqueur, Makuhita, Nodulithe, Rocabot
		66, 304, 231, 95, 111, 246,         # Machoc, Galekid, Phanpy, Onix, Rhinocorne, Embrylex
		438, 557, 837, 622, 236, 447,       # Manzaï, Crabicoque, Charbi, Gringolem, Debugant, Riolu
	],
	# Volcan — Feu / Sol / Roche, brûlant.
	MapGenerator.MapTheme.VOLCANO: [
		218, 37, 58, 77, 322, 240,          # Limagma, Goupix, Caninos, Ponyta, Chamallot, Magby
		324, 126, 4, 607, 631, 111,         # Chartor, Magmar, Salamèche, Funécire, Aflamanoir, Rhinocorne
		155, 255, 390, 850, 776, 636,       # Héricendre, Poussifeu, Ouisticram, Grillepattes, Boumata, Pyronille
	],
	# Village — faune urbaine / domestique, qui traîne autour des maisons.
	MapGenerator.MapTheme.VILLAGE: [
		19, 263, 16, 52, 509, 506,          # Rattata, Zigzaton, Roucool, Miaouss, Chacripan, Ponchiot
		58, 431, 572, 293, 209, 83,         # Caninos, Chaglam, Chinchidou, Chuchmur, Snubbull, Canarticho
		25, 300, 819, 924, 133, 674,        # Pikachu, Skitty, Rongourmand, Compagnol, Évoli, Pandespiègle
	],
}

# ── PNJ de la salle-Boutique ─────────────────────────────────────────────
const BOUTIQUE_VENDOR   := 863   # Perrserker — marchand
const BOUTIQUE_SLEEPER  := 925   # Maushold — dort près de l'étal
const BOUTIQUE_WANDERER := 79    # Ramoloss — déambule

# ── Arbres à baies par biome (noms Essentials : planche
# Characters/berrytree_<NOM>.png + item Items/<NOM>.png) ─────────────────
const BERRIES_BY_THEME: Dictionary = {
	MapGenerator.MapTheme.FOREST: ["CHERIBERRY", "PECHABERRY", "LEPPABERRY"],
	MapGenerator.MapTheme.MEADOW: ["ORANBERRY", "PERSIMBERRY", "PECHABERRY"],
	MapGenerator.MapTheme.SWAMP:  ["AGUAVBERRY", "RAWSTBERRY", "CHESTOBERRY"],
	MapGenerator.MapTheme.AUTUMN: ["SITRUSBERRY", "FIGYBERRY", "NANABBERRY"],
	MapGenerator.MapTheme.LAKE:   ["ORANBERRY", "ASPEARBERRY", "MAGOBERRY"],
	MapGenerator.MapTheme.VOLCANO: ["RAWSTBERRY", "CHERIBERRY", "LEPPABERRY"],   # anti-brûlure
	MapGenerator.MapTheme.VILLAGE: ["ORANBERRY", "SITRUSBERRY", "LEPPABERRY"],
}
