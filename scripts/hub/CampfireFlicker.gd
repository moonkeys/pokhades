class_name CampfireFlicker
extends OmniLight3D

## Scintillement de feu de camp — attaché aux OmniLight3D des feux générés
## par HubMap (le script persiste avec la scène sauvegardée). Volontairement
## PAS @tool : lumière stable dans l'éditeur, flamme vivante en jeu.

var _t: float = 0.0
var _base_energy: float = 0.0


func _ready() -> void:
	_base_energy = light_energy
	_t = randf() * TAU   # déphase les feux entre eux


func _process(delta: float) -> void:
	_t += delta
	# Deux sinus non harmoniques + un léger bruit : vacillement irrégulier
	# crédible sans générateur aléatoire par frame.
	var flicker := sin(_t * 9.0) * 0.10 + sin(_t * 23.0 + 1.7) * 0.06
	light_energy = _base_energy * (1.0 + flicker)
