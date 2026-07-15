class_name TeamStatsOverlay
extends CanvasLayer

## Fiche d'équipe en temps réel (touche Tab) — montre les stats EFFECTIVES
## de chaque membre avec toutes les améliorations (objet tenu, bonus de
## run), ses PV et ses attaques équipées. NE MET PAS le jeu en pause : le
## but est de constater l'impact de sa progression en pleine action.
## Se referme d'un nouvel appui sur Tab (géré par CombatArena).

const CARD_W := 236.0
const CARD_H := 240.0


func setup(team: Array) -> void:
	layer = 20

	var live: Array = []
	for m in team:
		if is_instance_valid(m):
			live.append(m)
	if live.is_empty():
		return

	var vp := get_viewport().get_visible_rect().size
	var gap := 12.0
	# Rangée horizontale : à 5-6 Pokémon elle dépassait des bords de l'écran.
	# On calcule un facteur d'échelle pour qu'elle tienne toujours (marge 48 px).
	var natural := live.size() * (CARD_W + gap) - gap
	var s := minf(1.0, (vp.x - 48.0) / maxf(natural, 1.0))
	var step := (CARD_W + gap) * s
	var total_w := live.size() * step - gap * s
	var x0 := (vp.x - total_w) * 0.5

	for i in live.size():
		var card := _build_card(live[i].pokemon_instance)
		card.position = Vector2(x0 + i * step, 64.0)
		add_child(card)
		# Apparition en préservant l'échelle `s` (UiKit.pop_in forcerait scale=1
		# et referait déborder la rangée).
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(s, s) * 0.92
		card.modulate.a = 0.0
		var tw := card.create_tween().set_parallel(true)
		tw.tween_property(card, "scale", Vector2(s, s), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.04)
		tw.tween_property(card, "modulate:a", 1.0, 0.14).set_delay(i * 0.04)


func _build_card(inst: PokemonInstance) -> Panel:
	var card := Panel.new()
	card.size = Vector2(CARD_W, CARD_H)
	card.add_theme_stylebox_override("panel",
		UiKit.style(Color(0.89, 0.76, 0.53, 0.94), UiKit.WOOD_EDGE, 10, 3))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture        = inst.portrait_texture
		tex.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.position       = Vector2(6, 6)
		tex.size           = Vector2(40, 40)
		card.add_child(tex)

	UiKit.label(card, inst.data.name_fr.capitalize(), Vector2(52, 6), 15, UiKit.TEXT_DARK, CARD_W - 60)
	UiKit.label(card, "Niv. %d   ·   %d / %d PV" % [inst.level, inst.current_hp, inst.max_hp],
		Vector2(52, 28), 12, UiKit.TEXT_DARK.lightened(0.2), CARD_W - 60)

	# Stats effectives — le multiplicateur cumule bonus de run + objet tenu ;
	# affiché en VERT avec le % quand il y a un boost (l'impact se voit).
	var y := 54.0
	for row: Array in [
		["Attaque", inst.data.attack,  inst.attack_mult],
		["Défense", inst.data.defense, inst.defense_mult],
		["Vitesse", inst.data.speed,   inst.speed_mult],
	]:
		var base_v: int = row[1]
		var mult: float = row[2]
		var eff := int(round(base_v * mult))
		UiKit.label(card, str(row[0]), Vector2(10, y), 12, UiKit.TEXT_DARK, 76)
		var boosted := mult > 1.001
		var txt := str(eff) + ("  (+%d%%)" % int(round((mult - 1.0) * 100.0)) if boosted else "")
		UiKit.label(card, txt, Vector2(88, y), 12,
			UiKit.GREEN_DARK if boosted else UiKit.TEXT_DARK, CARD_W - 96)
		y += 20.0

	# Objet tenu
	var held := "Aucun objet"
	if not inst.held_item.is_empty():
		held = "Tient : %s" % str(inst.held_item.get("name_fr", inst.held_item.get("api_name", "?")))
	UiKit.label(card, held, Vector2(10, y + 2), 11, UiKit.TEXT_DARK.lightened(0.25), CARD_W - 20)
	y += 24.0

	# Attaques équipées (nom + pastille de type)
	for md: MoveData in inst.equipped_moves:
		UiKit.type_badge(card, Vector2(10, y), md.type, 14.0)
		UiKit.label(card, md.display_name, Vector2(66, y - 2), 11, UiKit.TEXT_DARK, CARD_W - 74)
		y += 20.0
		if y > CARD_H - 18.0:
			break

	return card
