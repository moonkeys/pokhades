class_name SunflowerField
extends Node2D

# Champ de tournesols animé "vent" — remplace les tiles statiques HubMap
# Positionner à la tile (col, row) * 16 pour aligner avec la grille

const COLS := 3
const ROWS := 3
const T    := 16.0  # taille d'une tile en pixels

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for row in ROWS:
		for col in COLS:
			var cx := col * T + T * 0.5
			var cy := row * T + T * 0.5
			var phase := float(row * COLS + col) * 0.45

			# Tige verte
			var sway := sin(_t * 1.6 + phase) * 2.2
			var stem_top := Vector2(cx + sway, cy - 2)
			var stem_bot := Vector2(cx, cy + 6)
			draw_line(stem_bot, stem_top, Color(0.25, 0.55, 0.18), 2.0)

			# Pétales jaunes (couche de mouvement — légèrement transparentes)
			draw_circle(stem_top, 4.5, Color(0.95, 0.78, 0.08, 0.55))

			# Centre brun
			draw_circle(stem_top, 2.0, Color(0.40, 0.22, 0.06, 0.70))
