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
# Boss de palier — toutes les 5 salles
const BOSSES:    Array[int] = [143, 123, 128, 24, 22, 862]

# ── Grotte (arène de demi-boss) ──────────────────────────────────────────
# Sbires d'élite (plus faibles que le demi-boss)
const CAVE_ELITE: Array[int] = [217, 229, 359, 297, 342]
# Demi-boss — espèces NON ÉVOLUÉES recrutables : les battre débloque l'espèce
const CAVE_DEMIBOSS: Array[int] = [147, 246, 371, 443, 610, 633, 704]  # Minidraco, Embrylex, Draby, Griknot, Coupenotte, Solochi, Mucuscule

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
