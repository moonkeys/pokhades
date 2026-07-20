class_name MoveData
extends RefCounted

var api_name:     String = ""       # ex: "thunder-shock"
var display_name: String = ""       # ex: "Thunder Shock"
var type:         String = "normal"
var power:        int    = 0        # 0 = attaque de statut (pas utilisée en combat)
var damage_class: String = "physical"  # physical / special / status
var level_learned: int  = 1
## Effet réel des CT de statut (soin, altération garantie) — cf.
## MoveShopScreen.MOVE_LIST "effect" et TeamMember._use_status_move().
## Vide pour les attaques normales (dégâts + tirage de statut par type).
var effect: Dictionary = {}

# ── Portée & cadence PROPRES À CHAQUE ATTAQUE ─────────────────────────
# Avant, tout le monde partageait une portée unique (4.0 en mêlée, 9.0 à
# distance) et un cooldown unique (0.7 s) : aucune raison de préférer une
# attaque à une autre, et on pouvait toutes les enchaîner. Désormais chaque
# move a sa portée, sa portée MINIMALE éventuelle et sa cadence, dérivées de
# sa classe et de sa puissance (cf. tune()) :
#   - physique : corps à corps, portée courte, frappe rapide
#   - spécial  : tir, longue portée qui grandit avec la puissance ; les GROSSES
#                frappes exigent du recul (range_min) et sont lentes
#   - statut   : longue portée utilitaire, cadence très lente
var range_min: float = 0.0    # > 0 : ne peut PAS être lancée de trop près
var range_max: float = 4.0
var cooldown:  float = 0.7    # secondes, avant mise à l'échelle par la Vitesse


## Recalcule portée/cadence depuis `power` + `damage_class`. À appeler après
## avoir rempli ces deux champs (tous les sites de création de MoveData).
func tune() -> void:
	var p := clampf(float(power), 0.0, 120.0) / 120.0   # 0..1
	# Cadences RALLONGÉES (passe d'équilibrage, avec la ténacité ennemie) :
	# le spam permanent rendait chaque coup insignifiant — un coup doit être
	# une DÉCISION, et l'intervalle laisse aux ennemis le temps d'exister
	# (retour joueurs : « trop facile », « plus de cooldown »).
	match damage_class:
		"special":
			range_max = 7.0 + p * 4.0        # 7.0 → 11.0
			range_min = 3.0 if power >= 90 else 0.0
			cooldown  = 1.30 + p * 1.10      # 1.30 → 2.40 (avant : 0.90 → 1.70)
		"status":
			range_max = 8.0
			range_min = 0.0
			cooldown  = 4.0                  # avant : 3.0
		_:  # physique
			range_max = 3.4 + p * 1.2        # 3.4 → 4.6
			range_min = 0.0
			cooldown  = 0.85 + p * 1.05      # 0.85 → 1.90 (avant : 0.55 → 1.30)
