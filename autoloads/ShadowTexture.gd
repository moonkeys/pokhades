extends Node

## Texture radiale (dégradé noir → transparent) partagée par toutes les
## ombres "blob" du jeu — évite de régénérer un GradientTexture2D par
## instance (personnages, arbres, rochers...).
var _tex: GradientTexture2D = null


func get_texture() -> GradientTexture2D:
	if _tex == null:
		_tex = _build()
	return _tex


func _build() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.42))
	grad.set_color(1, Color(0, 0, 0, 0.0))

	var tex := GradientTexture2D.new()
	tex.gradient  = grad
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = 64
	tex.height    = 64
	return tex


## Crée un Sprite2D "ombre" prêt à l'emploi — à ajouter en premier enfant
## (derrière le sprite du personnage/décor) et à repositionner légèrement
## sous les pieds. `size` est la taille finale de l'ellipse en pixels.
func make_shadow_sprite(size: Vector2) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = get_texture()
	spr.scale   = size / 64.0
	spr.z_as_relative = true
	spr.z_index = -1
	return spr
