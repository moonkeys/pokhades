class_name PokePools
extends RefCounted

## ═══ CASTING DU JEU — LE fichier à éditer pour changer quels Pokémon
## apparaissent où. ═══
##
## Tous les ids sont des numéros de Pokédex national (PokeAPI). Les pools
## sont consommés par CombatArena (combats), MapRender3D (arbres à baies)
## et la salle-Boutique. Modifier une liste ici suffit — aucun autre
## fichier à toucher.

# ── Pools ennemis de base (toutes zones, par palier de salle) ────────────
# Rongeurs (Normal) — salles 1+
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
]

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

# ── Faune par biome (MapGenerator.MapTheme → ids) — mélangée au pool de
# base en double pondération : la population locale domine sans exclure
# les espèces communes. ──────────────────────────────────────────────────
const BIOME: Dictionary = {
	MapGenerator.MapTheme.FOREST: [46, 69, 273, 285, 204, 540],   # Paras, Chétiflor, Grainipiot, Balignon, Pomdepik, Larveyette
	MapGenerator.MapTheme.SWAMP:  [194, 88, 23, 41, 270, 283],    # Axoloto, Tadmorv, Abo, Nosferapti, Nénupiot, Arakdo
	MapGenerator.MapTheme.MEADOW: [187, 415, 669, 179, 659],      # Granivol, Apitrini, Flabébé, Wattouat, Sapereau
	MapGenerator.MapTheme.ROCKY:  [74, 66, 296, 304, 524, 744],   # Racaillou, Machoc, Makuhita, Galekid, Nodulithe, Rocabot
	MapGenerator.MapTheme.AUTUMN: [585, 216, 46, 163, 204],       # Vivaldaim, Teddiursa, Paras, Hoothoot, Pomdepik
	MapGenerator.MapTheme.LAKE:   [118, 129, 194, 54, 60, 79],    # Poissirène, Magicarpe, Axoloto, Psykokwak, Ptitard, Ramoloss
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
}
