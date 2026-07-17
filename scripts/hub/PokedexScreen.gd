class_name PokedexScreen
extends CanvasLayer

signal closed
## Émis dès que l'équipe/le poids changent. Le bandeau du hub (« Équipe 3/6 ·
## Poids 19/40 ») n'était rafraîchi qu'à l'OUVERTURE du hub et à la FERMETURE
## d'un écran : il restait donc figé pendant qu'on composait son équipe ici,
## juste au-dessus (retour joueurs). Cf. HubWorld._open_npc_screen.
signal team_changed

const C_BG      := Color(0.04, 0.03, 0.02, 0.82)
const C_PANEL   := Color(0.10, 0.075, 0.045, 0.96)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.96, 0.92, 0.80)
const C_DIM     := Color(0.62, 0.55, 0.42)
const C_GOLD    := Color(0.92, 0.72, 0.25)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)
const C_CARD    := Color(0.16, 0.12, 0.07, 0.95)
const C_CARD_SEL:= Color(0.26, 0.21, 0.12)
const C_GOOD    := Color(0.38, 0.82, 0.45)
const C_BAR_BG  := Color(0, 0, 0, 0.55)

const STAT_NAMES: Array[String] = ["PV", "Attaque", "Défense", "Atq. Sp.", "Déf. Sp.", "Vitesse"]
const STAT_COLORS: Array[Color] = [
	Color(0.80, 0.24, 0.18), Color(0.85, 0.52, 0.14), Color(0.78, 0.62, 0.18),
	Color(0.58, 0.34, 0.78), Color(0.24, 0.54, 0.84), Color(0.20, 0.70, 0.74),
]

var _sorted_ids:   Array  = []
var _selected_pid: int    = -1
var _loaded_data:  Dictionary = {}   # pid -> PokemonData
var _portraits:    Dictionary = {}   # pid -> Texture2D
var _card_panels:  Dictionary = {}   # pid -> Button (carte de grille focalisable)
var _card_tex:     Dictionary = {}   # pid -> TextureRect
var _card_ph:      Dictionary = {}   # pid -> ColorRect

## ScrollContainer de la grille — mémorisé pour faire défiler jusqu'à la carte
## focalisée (navigation aux flèches et sélection depuis la bande d'équipe).
var _grid_scroll:     ScrollContainer = null
var _detail_root:     Control = null
var _team_strip_root: Control = null


func _ready() -> void:
	# Union des Pokémon débloqués ET de ceux simplement "aperçus" en combat
	# (compteur de victoires en cours, pas encore au seuil de déblocage).
	var id_set: Dictionary = {}
	for pid in GameManager.unlocked_pokemon:
		id_set[pid] = true
	for pid in GameManager.defeat_counts:
		id_set[pid] = true
	_sorted_ids = id_set.keys()
	_sorted_ids.sort()
	if not _sorted_ids.is_empty():
		_selected_pid = _sorted_ids[0]
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	_fetch_all()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(100, 50), Vector2(1080, 620))
	add_child(panel)
	UiKit.banner(panel, "Pokédex & Équipe")
	UiKit.pop_in(panel)
	var count_str := "%d débloqués  •  %d aperçus" % [GameManager.unlocked_pokemon.size(), _sorted_ids.size()]
	_lbl(panel, count_str, 0, 64, 1080, 22, 13, C_DIM, true)

	if _sorted_ids.is_empty():
		_lbl(panel,
			"Aucun Pokémon libéré pour l'instant.\n\nTermine une run pour en recruter !",
			0, 280, 1080, 80, 18, C_DIM, true)
	else:
		_build_team_strip(panel)
		_build_grid(panel)
		_build_detail_panel(panel)

	# Pied de page : mémorisé pour être rafraîchi EN DIRECT (le poids ne se
	# mettait à jour qu'en quittant le menu — retour joueurs).
	_prg_lbl = _lbl(panel, "", 0, 590, 1080, 20, 12, C_DIM, true)
	_refresh_progress()

	var close := UiKit.button("✕  Fermer", Vector2(160, 38), false)
	close.position = Vector2(24, 578)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


# ── Équipe actuelle (bande au-dessus de la grille) ──────────────────────

## Poids de build + slots, recalculés À CHAQUE changement (ajout/retrait d'un
## Pokémon, CT équipée, objet tenu) — avant, l'affichage était figé à
## l'ouverture du menu et ne bougeait qu'en le quittant.
var _prg_lbl: Label = null

## FILET DE FOCUS — à appeler (en deferred) après toute reconstruction.
## Les rafraîchissements de cet écran détruisent des boutons, y compris CELUI
## qui a le focus : cliquer « Retirer » ou « Bonbon » reconstruit le détail où
## vit le bouton pressé, et le focus meurt avec lui — la navigation aux flèches
## s'arrête net. queue_free ne libère qu'en fin de frame, d'où le deferred :
## on ne peut constater la perte qu'après.
func _ensure_focus_alive() -> void:
	if get_viewport() == null:
		return
	if get_viewport().gui_get_focus_owner() == null:
		MenuNav.focus_first(self)


func _refresh_progress() -> void:
	if not is_instance_valid(_prg_lbl):
		return
	var w   := GameManager.compute_team_weight()
	var cap := GameManager.build_weight_cap
	var over := w > cap
	_prg_lbl.text = "%d Pokémon libérés  •  Équipe %d / %d  •  Capacités %d / 4 slots  •  ⚖ Poids de build %d / %d%s" % [
		GameManager.unlocked_pokemon.size(),
		GameManager.hub_team.size(), GameManager.get_max_team_size(),
		GameManager.move_slot_count,
		w, cap,
		"   ✖ TROP LOURD — la run ne peut pas démarrer" if over else "",
	]
	_prg_lbl.add_theme_color_override("font_color",
		Color(0.92, 0.35, 0.30) if over else C_DIM)
	# Ce point est déjà LE passage obligé de tout changement d'équipe/poids —
	# on s'y branche plutôt que de dupliquer l'émission sur chaque bouton.
	team_changed.emit()


## Sprite PMD ANIMÉ (animation "idle") centré sur `center`, mis à l'échelle
## pour tenir dans un carré de `box` pixels.
##
## AnimatedSprite2D et non TextureRect : les planches PMD ont déjà une anim
## "idle" toute faite (cf. PMDSprites), et un AnimatedSprite2D est centré sur sa
## position par défaut — ce qui règle du même coup le cadrage. Les portraits
## statiques posés en haut-gauche d'un TextureRect débordaient de leur carré
## (retour joueurs : « les poke ne sont pas centrés »).
##
## Le chargement est ASYNCHRONE (cache disque, réseau au 1er appel) : le parent
## peut avoir été libéré entre-temps par un _refresh — d'où le garde-fou.
func _add_idle_sprite(parent: Control, pid: int, box: float, center: Vector2) -> void:
	var wref: WeakRef = weakref(parent)
	PMDSprites.get_walk_sprites(pid, parent, func(res: Dictionary) -> void:
		var par: Control = wref.get_ref()
		if res.is_empty() or par == null:
			return
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames  = res.frames
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var fs: Vector2i = res.frame_size
		var big := maxf(float(fs.x), float(fs.y))
		var s := 1.0 if big <= 0.0 else box / big
		spr.scale = Vector2.ONE * s

		# AnimatedSprite2D centre la FRAME sur sa position — or les planches PMD
		# ont une marge vide sous le personnage (cf. PMDSprites.foot_row, la
		# rangée du pixel opaque le plus bas). Centrer la frame décalait donc le
		# Pokémon vers le haut du carré. On recentre sur le CONTENU VISIBLE.
		var h := float(fs.y)
		var foot := float(res.get("foot_row", fs.y - 1))
		spr.position = center + Vector2(0.0, (h - foot) * 0.5 * s)

		par.add_child(spr)
		spr.play("idle")
	)


## Taille d'un carré d'équipe. 40 px était trop petit pour lire un sprite
## (retour joueurs) ; 68 tient encore dans la largeur de la colonne (6 × 68 +
## 5 × 8 = 448 < 456).
const TEAM_SLOT := 68.0
const TEAM_GAP  := 8.0

func _build_team_strip(panel: Panel) -> void:
	_lbl(panel, "ÉQUIPE ACTUELLE", 16, 84, 300, 18, 11, C_DIM)
	_team_strip_root = Control.new()
	_team_strip_root.position = Vector2(16, 102)
	_team_strip_root.size     = Vector2(456, TEAM_SLOT)
	panel.add_child(_team_strip_root)
	_refresh_team_strip()


func _refresh_team_strip() -> void:
	if not is_instance_valid(_team_strip_root): return
	for c in _team_strip_root.get_children():
		c.queue_free()

	var max_n := GameManager.get_max_team_size()
	var sw  := TEAM_SLOT
	var gap := TEAM_GAP
	for i in max_n:
		# Button et non Panel : les carrés d'équipe doivent être atteignables aux
		# flèches comme le reste de l'écran (retour joueurs). Un slot VIDE reste
		# un Panel — rien à y sélectionner, il ne doit pas capter le focus.
		var filled := i < GameManager.hub_team.size()
		var slot: Control = Button.new() if filled else Panel.new()
		slot.position = Vector2(i * (sw + gap), 0)
		slot.size     = Vector2(sw, sw)

		if filled:
			var pid: int = GameManager.hub_team[i]
			_style_team_slot(slot as Button)
			# Sprite ANIMÉ centré (cf. _add_idle_sprite) au lieu du portrait
			# statique, qui débordait du carré par le bas.
			_add_idle_sprite(slot, pid, sw - 14.0, Vector2(sw * 0.5, sw * 0.5 - 4.0))
			# Poids de CE Pokémon (espèce + objet tenu + CT équipées) — on lit
			# la composition du build d'un coup d'œil.
			var pw := GameManager.pokemon_weight(pid)
			if GameManager.get_assigned_item(pid) != "":
				pw += GameManager.ITEM_WEIGHT
			pw += GameManager.get_move_loadout(pid).size() * GameManager.MOVE_WEIGHT
			var wl := Label.new()
			wl.text = str(pw)
			wl.position = Vector2(0, sw - 15)
			wl.size     = Vector2(sw - 3, 14)
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			wl.add_theme_font_size_override("font_size", UiKit.scaled_font(10))
			wl.add_theme_color_override("font_color", C_GOLD)
			wl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			wl.add_theme_constant_override("shadow_offset_y", 1)
			wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(wl)

			var capture_pid := pid
			var btn := slot as Button
			btn.pressed.connect(func() -> void: _reveal(capture_pid))
			# Sélection au FOCUS, comme dans la grille : parcourir son équipe aux
			# flèches met la fiche à jour ET fait défiler la liste jusqu'à la
			# carte correspondante, qui est souvent hors écran.
			btn.focus_entered.connect(func() -> void: _reveal(capture_pid))
		else:
			_style(slot as Panel, Color(0.16, 0.12, 0.07), C_BORDER, 6)

		_team_strip_root.add_child(slot)

	_refresh_progress()   # ajout/retrait d'un Pokémon → poids recalculé
	call_deferred("_ensure_focus_alive")


## Style des carrés d'équipe (Button vert, liseré doré au focus) — même logique
## que _apply_card_style : un Button ignore la stylebox "panel".
func _style_team_slot(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color     = Color(0.13, 0.24, 0.13).lightened(0.08 if state in ["hover", "focus"] else 0.0)
		sb.border_color = C_GOLD_LT if state == "focus" else C_GOOD
		sb.set_border_width_all(3 if state == "focus" else 2)
		sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state, sb)


## Sélectionne `pid` ET fait défiler la grille jusqu'à sa carte — le chemin
## bande d'équipe → fiche. La carte est souvent hors écran (la grille liste
## tout le Pokédex), d'où le scroll explicite.
func _reveal(pid: int) -> void:
	_select(pid)
	if is_instance_valid(_grid_scroll) and _card_panels.has(pid):
		_grid_scroll.ensure_control_visible(_card_panels[pid] as Control)


# ── Grille (gauche, triée par n° de Pokédex) ───────────────────────────

func _build_grid(panel: Panel) -> void:
	var scroll := ScrollContainer.new()
	_grid_scroll = scroll
	# Décalée de 144 à 178 : la bande d'équipe est passée de 40 à 68 px de haut
	# (cf. TEAM_SLOT) et la recouvrait.
	scroll.position = Vector2(16, 178)
	scroll.size     = Vector2(456, 392)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	const CARD_W := 218
	const CARD_H := 76
	const GAP    := 8
	var cols := 2
	var rows := ceili(float(_sorted_ids.size()) / cols)

	var content := Control.new()
	content.custom_minimum_size = Vector2(456, rows * (CARD_H + GAP))
	scroll.add_child(content)

	for i in _sorted_ids.size():
		var pid: int = _sorted_ids[i]
		var col := i % cols
		var row := i / cols
		_build_entry(content, pid, col * (CARD_W + GAP), row * (CARD_H + GAP), CARD_W, CARD_H)


func _build_entry(parent: Control, pid: int, x: int, y: int, w: int, h: int) -> void:
	var unlocked := pid in GameManager.unlocked_pokemon

	# Button et non Panel : un Panel n'est PAS focalisable, donc les flèches
	# n'avaient rien à parcourir dans la grille — tout l'écran ne comptait que
	# 4 boutons (retour joueurs : « je ne peux pas naviguer dans la liste »).
	var card := Button.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	card.focus_mode = Control.FOCUS_ALL
	_apply_card_style(card, pid == _selected_pid)
	_card_panels[pid] = card
	parent.add_child(card)

	var ph := ColorRect.new()
	ph.name     = "PH"
	ph.position = Vector2(6, 6)
	ph.size     = Vector2(56, 56)
	ph.color    = Color(0.20, 0.17, 0.12)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_ph[pid] = ph
	card.add_child(ph)

	var tex_r := TextureRect.new()
	tex_r.position     = Vector2(6, 6)
	tex_r.size         = Vector2(56, 56)
	tex_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_r.modulate     = Color.BLACK if not unlocked else Color.WHITE
	_card_tex[pid] = tex_r
	if _portraits.has(pid):
		tex_r.texture = _portraits[pid]
		ph.visible = false
	card.add_child(tex_r)

	if pid in GameManager.hub_team:
		var badge := _PokeballBadge.new()
		badge.size     = Vector2(20, 20)
		badge.position = Vector2(w - 24, 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)

	_lbl(card, "#%d" % pid, 68, 4, w - 74, 18, 11, C_GOLD)
	var name_lbl := _lbl(card, "…", 68, 20, w - 74, 22, 14, C_TEXT)
	name_lbl.name = "NameLbl"
	if _loaded_data.has(pid):
		name_lbl.text = (_loaded_data[pid] as PokemonData).name_fr.to_upper()

	if unlocked:
		var type_row := Control.new()
		type_row.name = "TypeRow"
		type_row.position = Vector2(68, 44)
		card.add_child(type_row)
		if _loaded_data.has(pid):
			_fill_type_row(type_row, (_loaded_data[pid] as PokemonData).types)
	else:
		var prog := _lbl(card, "%d / %d victoires" % [GameManager.get_defeat_count(pid), GameManager.UNLOCK_DEFEAT_THRESHOLD],
			68, 46, w - 74, 16, 10, C_DIM)
		prog.name = "ProgLbl"

	var capture_pid := pid
	card.pressed.connect(func() -> void: _select(capture_pid))
	# Sélection au FOCUS : parcourir la liste aux flèches met à jour la fiche
	# en direct, sans avoir à valider chaque entrée.
	card.focus_entered.connect(func() -> void:
		_select(capture_pid)
		if is_instance_valid(_grid_scroll):
			_grid_scroll.ensure_control_visible(card)
	)


# ── Badge Pokéball (membre actuel de l'équipe) ──────────────────────────

class _PokeballBadge extends Control:
	func _draw() -> void:
		var s := size.x
		var c := Vector2(s, s) * 0.5
		var r := s * 0.5 - 1.0
		draw_colored_polygon(_half(c, r, true),  Color(0.85, 0.16, 0.12))
		draw_colored_polygon(_half(c, r, false), Color(0.97, 0.97, 0.95))
		draw_arc(c, r, 0, TAU, 28, Color(0.10, 0.08, 0.06), 1.6, true)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.10, 0.08, 0.06), 1.6)
		draw_circle(c, r * 0.32, Color(0.97, 0.97, 0.95))
		draw_arc(c, r * 0.32, 0, TAU, 16, Color(0.10, 0.08, 0.06), 1.3, true)

	func _half(c: Vector2, r: float, top: bool) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var a0 := -PI if top else 0.0
		var a1 := 0.0 if top else PI
		for i in 17:
			var t := a0 + (a1 - a0) * float(i) / 16.0
			pts.append(c + Vector2(cos(t), sin(t)) * r)
		return pts


func _fill_type_row(row: Control, types: Array) -> void:
	for c in row.get_children():
		c.queue_free()
	var tx := 0.0
	for t in types:
		var pill := UiKit.type_badge(row, Vector2(tx, 0), str(t), 18.0)
		tx += pill.size.x + 4.0


func _select(pid: int) -> void:
	if pid == _selected_pid: return
	_selected_pid = pid
	for id in _sorted_ids:
		if _card_panels.has(id):
			_apply_card_style(_card_panels[id] as Button, id == pid)
	_refresh_detail()


## Un Button ne lit PAS la stylebox "panel" : il lui faut normal/hover/pressed/
## focus. Sans "focus", la carte survolée aux flèches ne se distinguerait pas.
func _apply_card_style(card: Button, selected: bool) -> void:
	var bg     := C_CARD_SEL if selected else C_CARD
	var border := C_GOLD if selected else C_BORDER
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color     = bg.lightened(0.10) if state in ["hover", "focus"] else bg
		sb.border_color = C_GOLD_LT if state == "focus" else border
		sb.set_border_width_all(3 if state == "focus" else 2)
		sb.set_corner_radius_all(8)
		card.add_theme_stylebox_override(state, sb)


# ── Panneau détail (droite) ─────────────────────────────────────────────

func _build_detail_panel(panel: Panel) -> void:
	var frame := Panel.new()
	frame.position = Vector2(488, 82)
	frame.size     = Vector2(576, 488)
	_style(frame, Color(0.16, 0.12, 0.07, 0.95), C_BORDER, 8)
	panel.add_child(frame)

	# Contenu SCROLLABLE : stats + attaques de base + CT peuvent dépasser la
	# hauteur du cadre (retour joueurs : on ne pouvait pas scroller la liste
	# d'attaques). Un ScrollContainer clippe au cadre ; _detail_root grandit
	# selon son contenu (_refresh_detail fixe sa hauteur mini).
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(490, 84)
	scroll.size     = Vector2(572, 484)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_detail_root = Control.new()
	_detail_root.custom_minimum_size = Vector2(556, 484)
	scroll.add_child(_detail_root)

	_refresh_detail()


func _refresh_detail_locked(pd: PokemonData) -> void:
	_detail_root.add_child(_lbl_node("#%d  %s" % [_selected_pid, pd.name_fr.to_upper()],
		122, 14, 430, 30, 20, C_DIM))

	if not pd.is_base_form:
		_detail_root.add_child(_lbl_node(
			"Forme évoluée — non recrutable directement.\nLes évolutions se font en jouant une run, pas au recrutement.",
			16, 124, 544, 50, 13, C_DIM))
		return

	_detail_root.add_child(_lbl_node("Pas encore recruté", 122, 48, 430, 20, 13, C_DIM))

	var count: int     = GameManager.get_defeat_count(_selected_pid)
	var threshold: int  = GameManager.UNLOCK_DEFEAT_THRESHOLD
	var remaining: int  = maxi(0, threshold - count)

	_detail_root.add_child(_lbl_node(
		"%d / %d victoires" % [count, threshold], 16, 124, 250, 22, 16, C_TEXT))

	var bar := ProgressBar.new()
	bar.position = Vector2(16, 150)
	bar.size     = Vector2(544, 18)
	bar.max_value = threshold
	bar.value     = count
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = C_GOLD; fill.set_corner_radius_all(5)
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = C_BAR_BG; bbg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bbg)
	_detail_root.add_child(bar)

	var msg := "Encore %d victoire%s pour le recruter !" % [remaining, "s" if remaining > 1 else ""]
	_detail_root.add_child(_lbl_node(msg, 16, 178, 544, 24, 13, C_DIM))


## Ligne "objet tenu" : icône + nom de l'objet assigné à `pid`, bouton pour
## cycler parmi les objets possédés (dont « Aucun »), et bouton Super Bonbon.
func _build_item_row(pid: int, x: int, y: int) -> void:
	var held := GameManager.get_assigned_item(pid)

	# Icône (si un objet est tenu)
	if held != "":
		var tex := ItemCatalog.icon(held)
		if tex != null:
			var icon := TextureRect.new()
			icon.texture        = tex
			icon.position       = Vector2(x, y)
			icon.size           = Vector2(30, 30)
			icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_detail_root.add_child(icon)

	var item_name := "Aucun objet"
	if held != "":
		item_name = str(ItemCatalog.get_item(held).get("name", held))
	var bonus_now := GameManager.get_start_level_bonus(pid)
	if bonus_now > 0:
		item_name += "   ·   Départ +%d niv" % bonus_now
	_detail_root.add_child(_lbl_node("Objet : " + item_name, x + 34, y + 4, 300, 22, 13, C_TEXT))

	# Bouton d'ouverture du CHOIX d'objet — un vrai menu (cf. _open_item_picker)
	# et non plus un cycle aveugle : avec 8+ objets possédés, « Changer » qui
	# saute au suivant obligeait à cliquer en boucle sans voir la liste.
	var cap_pid := pid
	var cyc := Button.new()
	cyc.text     = "Changer"
	cyc.position = Vector2(x + 250, y)
	cyc.size     = Vector2(90, 30)
	cyc.add_theme_font_size_override("font_size", UiKit.scaled_font(12))
	_style_button(cyc, Color(0.34, 0.28, 0.16), C_GOLD_LT)
	cyc.pressed.connect(func() -> void: _open_item_picker(cap_pid))
	_detail_root.add_child(cyc)

	# Super Bonbon — l'icône de l'objet en personne (rare-candy.png), le stock,
	# et l'effet en toutes lettres : « +5 niv ».
	var candies := GameManager.get_item_count("rare-candy")
	var bonus := GameManager.get_start_level_bonus(pid)
	# Compact : grosse icône, texte court — l'ancienne version à rallonge
	# (« Niv.+N | Bonbon (+5) ×12 ») débordait du panneau (retour joueurs).
	# Le bonus en cours s'affiche dans la ligne d'objet, pas dans le bouton.
	var candy := Button.new()
	candy.icon = load("res://assets/items/rare-candy.png")
	candy.expand_icon = false
	candy.add_theme_constant_override("icon_max_width", 30)
	candy.tooltip_text = "Super Bonbon : +%d niveaux de départ" % ItemCatalog.CANDY_LEVELS
	candy.text     = "×%d  +%d niv" % [candies, ItemCatalog.CANDY_LEVELS]
	candy.position = Vector2(x + 396, y - 3)
	candy.size     = Vector2(132, 36)
	candy.disabled = candies <= 0 or bonus >= ItemCatalog.CANDY_MAX_BONUS
	candy.add_theme_font_size_override("font_size", UiKit.scaled_font(11))
	_style_button(candy, Color(0.60, 0.28, 0.42) if not candy.disabled else Color(0.55, 0.48, 0.38), Color.WHITE)
	candy.pressed.connect(func() -> void:
		if GameManager.use_candy(cap_pid):
			Sfx.play("levelup", -4.0)
			_refresh_detail()
	)
	_detail_root.add_child(candy)


## MENU de choix d'objet : « Aucun » + chaque objet possédé (icône, nom, stock
## restant, poids), navigable aux flèches, Échap pour refermer sans choisir.
##
## Son MenuNav est ajouté APRÈS celui de l'écran : _unhandled_input remonte en
## ordre inverse de l'arbre, donc c'est LUI qui consomme Échap tant que le menu
## est ouvert — sans ça, Échap fermerait tout le Pokédex.
var _item_picker: CanvasLayer = null

func _open_item_picker(pid: int) -> void:
	if is_instance_valid(_item_picker):
		_item_picker.queue_free()
	var pick := CanvasLayer.new()
	pick.layer = 30
	_item_picker = pick
	add_child(pick)

	var close_pick := func() -> void:
		pick.queue_free()
		_item_picker = null
		_refresh_detail()
		_refresh_team_strip()   # l'objet pèse : le carré d'équipe bouge aussi
	pick.add_child(MenuNav.make(close_pick))

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.02, 0.01, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	pick.add_child(veil)

	var held := GameManager.get_assigned_item(pid)
	var options: Array = [""]
	for it: Dictionary in ItemCatalog.held_items():
		var api: String = it["api"]
		if api == held or GameManager.get_item_count(api) > 0:
			options.append(api)

	var row_h := 48.0
	var ph := 96.0 + options.size() * (row_h + 6.0)
	var panel := UiKit.main_panel(Vector2(420, maxf(40.0, 340.0 - ph * 0.5)), Vector2(440, ph))
	pick.add_child(panel)
	UiKit.banner(panel, "Objet tenu")

	for i in options.size():
		var api: String = options[i]
		var btn := Button.new()
		btn.position = Vector2(24, 84 + i * (row_h + 6.0))
		btn.size     = Vector2(392, row_h)
		btn.add_theme_font_size_override("font_size", UiKit.scaled_font(13))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if api == "":
			btn.text = "     Aucun objet  (⚖ 0)"
		else:
			var it := ItemCatalog.get_item(api)
			var stock := GameManager.get_item_count(api)
			btn.text = "     %s   ×%d  (⚖ %d)" % [str(it.get("name", api)), stock, GameManager.ITEM_WEIGHT]
			# L'EFFET en jeu sur la ligne même (retour joueurs) — c'est lui
			# qu'on compare, pas les noms.
			var fx := _lbl_node(str(it.get("desc", "")), 44, 26, 330, 14, 10, C_GOLD_LT)
			fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(fx)
			var tex := ItemCatalog.icon(api)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = false
				btn.add_theme_constant_override("icon_max_width", 26)
		var selected := api == held
		_style_button(btn, C_CARD_SEL if selected else Color(0.22, 0.17, 0.10),
			C_GOLD if selected else C_TEXT)
		var cap_api := api
		btn.pressed.connect(func() -> void:
			if cap_api == "":
				GameManager.unassign_item(pid)
			else:
				GameManager.assign_item(pid, cap_api)
			close_pick.call()
		)
		panel.add_child(btn)

	MenuNav.focus_first(panel)


func _refresh_detail() -> void:
	_refresh_progress()   # CT équipée / objet tenu → le poids bouge en direct
	call_deferred("_ensure_focus_alive")
	if not is_instance_valid(_detail_root): return
	for ch in _detail_root.get_children():
		ch.queue_free()
	_detail_root.custom_minimum_size.y = 484   # défaut ; étendu selon le contenu plus bas

	if _selected_pid < 0:
		return

	if not _loaded_data.has(_selected_pid):
		_detail_root.add_child(_lbl_node("Chargement…", 0, 220, 576, 30, 16, C_DIM, true))
		return

	var pd: PokemonData = _loaded_data[_selected_pid]
	var unlocked := _selected_pid in GameManager.unlocked_pokemon

	# Portrait (silhouette noire si non débloqué)
	var p_bg := ColorRect.new()
	p_bg.position = Vector2(16, 12)
	p_bg.size     = Vector2(96, 96)
	p_bg.color    = Color(0.20, 0.17, 0.12)
	_detail_root.add_child(p_bg)

	if unlocked:
		# Débloqué : sprite ANIMÉ en idle (cf. _add_idle_sprite). Le portrait
		# statique servait juste d'illustration ; l'animation rend la fiche
		# vivante et montre le Pokémon tel qu'on le verra en jeu.
		var holder := Control.new()
		holder.position = Vector2(16, 12)
		holder.size     = Vector2(96, 96)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_root.add_child(holder)
		_add_idle_sprite(holder, _selected_pid, 84.0, Vector2(48, 48))
	else:
		# Non débloqué : on garde le portrait STATIQUE en silhouette noire — le
		# but est justement de ne pas révéler l'espèce.
		var tex := TextureRect.new()
		tex.position     = Vector2(16, 12)
		tex.size         = Vector2(96, 96)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.modulate     = Color.BLACK
		if _portraits.has(_selected_pid):
			tex.texture = _portraits[_selected_pid]
		_detail_root.add_child(tex)

	if not unlocked:
		_refresh_detail_locked(pd)
		return

	# Nom + types + POIDS de ce Pokémon (espèce + objet + slots), recalculé à
	# chaque _refresh_detail — donc en direct après tout changement d'objet ou
	# de slots (retour joueurs : le poids était figé).
	_detail_root.add_child(_lbl_node("#%d  %s" % [_selected_pid, pd.name_fr.to_upper()],
		122, 14, 300, 30, 20, C_GOLD))
	var w_species := GameManager.pokemon_weight(_selected_pid)
	var w_item := GameManager.ITEM_WEIGHT if GameManager.get_assigned_item(_selected_pid) != "" else 0
	var w_slots := (GameManager.get_move_slots(_selected_pid) - 1) * GameManager.MOVE_WEIGHT
	_detail_root.add_child(_lbl_node("⚖ %d" % (w_species + w_item + w_slots),
		428, 14, 70, 24, 15, C_GOLD_LT))
	# Décomposition : chaque source de poids a sa valeur (retour joueurs :
	# « afficher la valeur de chaque poids partout »).
	_detail_root.add_child(_lbl_node("esp. %d · obj. %d · slots %d" % [w_species, w_item, w_slots],
		370, 38, 130, 16, 9, C_DIM))

	var type_row := Control.new()
	type_row.position = Vector2(122, 48)
	_detail_root.add_child(type_row)
	_fill_type_row(type_row, pd.types)

	# Ajout / retrait de l'équipe — les formes ÉVOLUÉES ne sont pas
	# sélectionnables : on part de la forme de base, qui évolue par le
	# niveau (Super Bonbons, cf. GameManager.get_effective_start).
	var selectable := GameManager.is_team_selectable(_selected_pid, pd.is_base_form)
	var in_team := _selected_pid in GameManager.hub_team
	var team_btn := Button.new()
	team_btn.position = Vector2(424, 14)
	team_btn.size     = Vector2(136, 36)
	if in_team:
		team_btn.text = "✕ Retirer"
		_style_button(team_btn, Color(0.78, 0.30, 0.24), Color.WHITE)
	else:
		var can_add := GameManager.hub_team.size() < GameManager.get_max_team_size() \
			and selectable
		team_btn.text     = "+ Ajouter"
		team_btn.disabled = not can_add
		_style_button(team_btn, C_GOOD if can_add else Color(0.62, 0.56, 0.46), Color.WHITE)
	var capture_pid := _selected_pid
	var capture_selectable := selectable
	team_btn.pressed.connect(func() -> void:
		if capture_pid in GameManager.hub_team:
			GameManager.hub_team.erase(capture_pid)
		elif capture_selectable and GameManager.hub_team.size() < GameManager.get_max_team_size():
			GameManager.hub_team.append(capture_pid)
		_refresh_detail()
		_refresh_team_strip()
	)
	_detail_root.add_child(team_btn)

	if not selectable and not in_team:
		var hint := _lbl_node("Forme évoluée — pars de sa forme de base : elle évoluera avec le niveau (Super Bonbons).",
			424, 52, 140, 60, 9, C_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_root.add_child(hint)

	# Objet tenu (assignable uniquement ici, cf. cahier des charges) + Super Bonbon
	_build_item_row(_selected_pid, 122, 82)

	# Stats
	var sy0 := 122
	for i in 6:
		var sy := sy0 + i * 24
		_detail_root.add_child(_lbl_node(STAT_NAMES[i], 16, sy, 76, 18, 12, C_TEXT))
		_detail_root.add_child(_lbl_node(str([pd.hp, pd.attack, pd.defense,
			pd.sp_attack, pd.sp_defense, pd.speed][i]), 92, sy, 34, 18, 12, C_TEXT, false, true))

		var bar := ProgressBar.new()
		bar.position = Vector2(132, sy + 2)
		bar.size     = Vector2(420, 13)
		bar.max_value = 190
		bar.value     = [pd.hp, pd.attack, pd.defense, pd.sp_attack, pd.sp_defense, pd.speed][i]
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = STAT_COLORS[i]; fill.set_corner_radius_all(4)
		var bbg := StyleBoxFlat.new()
		bbg.bg_color = C_BAR_BG; bbg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bbg)
		_detail_root.add_child(bar)

	# Séparateur
	var sep := ColorRect.new()
	sep.position = Vector2(16, 272)
	sep.size     = Vector2(544, 2)
	sep.color    = C_BORDER
	_detail_root.add_child(sep)

	var loadout := GameManager.get_move_loadout(_selected_pid)
	var slots := GameManager.get_move_slots(_selected_pid)

	# ── ATTAQUES DE BASE ──────────────────────────────────────────────
	# Celles que le Pokémon connaît DÉJÀ à son niveau de départ (montée en
	# niveau PokéAPI). Avant, on n'affichait que les CT achetées : sans CT, le
	# joueur lisait « aucune capacité » alors que son Pokémon sait se battre.
	# Les slots libres sont remplis automatiquement par ces attaques
	# (cf. PokemonInstance.init_moves) — d'où l'indication "auto".
	var start_lv: int = int(GameManager.get_effective_start(_selected_pid, 10).get("level", 10))
	var base_moves: Array = []
	for lm: Dictionary in pd.level_up_moves:
		if int(lm.get("level", 1)) <= start_lv:
			base_moves.append(lm)
	base_moves.reverse()   # les plus récemment apprises d'abord (les plus fortes)

	_detail_root.add_child(_lbl_node(
		"── ATTAQUES DE BASE (niv. %d) — remplissent les slots libres ──" % start_lv,
		16, 280, 544, 20, 13, C_DIM))
	if base_moves.is_empty():
		_detail_root.add_child(_lbl_node("Aucune (données d'attaques non chargées)",
			16, 302, 544, 20, 12, C_DIM))
	else:
		var free_slots := maxi(0, slots - loadout.size())
		var bx := 16
		for i in mini(base_moves.size(), 4):
			var lm: Dictionary = base_moves[i]
			var nm := str(lm.get("name", "")).replace("-", " ").capitalize()
			var auto := i < free_slots   # sera équipée d'office au départ
			# Button : atteignable aux flèches, [I] ou Entrée = popup d'infos.
			var bcard := Button.new()
			bcard.position = Vector2(bx, 302)
			bcard.size     = Vector2(130, 44)
			bcard.focus_mode = Control.FOCUS_ALL
			_style_move_card(bcard, auto)
			var cap_api_b := str(lm.get("name", ""))
			var cap_nm_b  := nm
			bcard.pressed.connect(func() -> void: _open_move_info(cap_api_b, cap_nm_b))
			bcard.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventKey and (event as InputEventKey).pressed \
						and (event as InputEventKey).keycode == KEY_I:
					_open_move_info(cap_api_b, cap_nm_b)
					get_viewport().set_input_as_handled()
			)
			_detail_root.add_child(bcard)
			bcard.add_child(_lbl_node(nm, 5, 3, 120, 18, 11, C_TEXT))
			# Type + puissance RÉELS, chargés en async (PokéAPI, cache disque) —
			# `level_up_moves` ne contient que {level, name}, il n'y a donc rien
			# à afficher tant que la fiche du move n'est pas résolue. L'ancien
			# libellé "auto" n'apprenait rien au joueur (retour joueurs) : la
			# bordure verte suffit à signaler l'équipement d'office.
			var pow_lbl := _lbl_node("…", 62, 24, 64, 16, 10, C_DIM)
			bcard.add_child(pow_lbl)
			var w_card: WeakRef = weakref(bcard)
			var w_pow: WeakRef = weakref(pow_lbl)
			PokemonAPI.get_move(str(lm.get("name", "")), func(md: Dictionary) -> void:
				var c2: Control = w_card.get_ref()
				if md.is_empty() or c2 == null:
					return
				var t := str(md.get("type", ""))
				if t != "":
					UiKit.type_badge(c2, Vector2(5, 23), t, 16.0)
				var p2: Label = w_pow.get_ref()
				if p2 != null:
					var pv: Variant = md.get("power")
					p2.text = ("%d pui." % int(pv)) if pv != null else "statut"
			)
			bx += 136

	# ── CT ACHETÉES ───────────────────────────────────────────────────
	_detail_root.add_child(_lbl_node(
		"── CT ACHETÉES — %d / %d équipées  ·  [I] détails ──" % [loadout.size(), slots],
		16, 350, 430, 20, 13, C_DIM))

	# Réglage du nombre de SLOTS de CE Pokémon (− / +). Chaque slot au-delà du
	# premier pèse MOVE_WEIGHT sur le build (cf. GameManager.compute_team_weight)
	# — moins de slots = un Pokémon plus léger. Borné par l'achat global du hub.
	var slot_pid := _selected_pid
	for d: Array in [["−", -1, 448], ["+", 1, 522]]:
		var sb := Button.new()
		sb.text     = str(d[0])
		sb.position = Vector2(int(d[2]), 346)
		sb.size     = Vector2(28, 26)
		sb.add_theme_font_size_override("font_size", UiKit.scaled_font(14))
		var delta: int = d[1]
		sb.disabled = (delta < 0 and slots <= 1) \
			or (delta > 0 and slots >= GameManager.move_slot_count)
		_style_button(sb, Color(0.34, 0.28, 0.16), C_GOLD_LT)
		sb.pressed.connect(func() -> void:
			GameManager.set_move_slots(slot_pid, GameManager.get_move_slots(slot_pid) + delta)
			_refresh_detail()
			_refresh_team_strip()   # le poids du carré d'équipe bouge aussi
		)
		_detail_root.add_child(sb)
	_detail_root.add_child(_lbl_node("%d slot%s (⚖%d)" % [slots, "s" if slots > 1 else "",
		(slots - 1) * GameManager.MOVE_WEIGHT], 478, 350, 44, 20, 11, C_GOLD_LT))

	# On n'affiche QUE ce que CE Pokémon peut apprendre. Les CT hors movepool
	# étaient listées grisées avec "✗ Hors movepool" : elles remplissaient la
	# grille de cartes inutilisables et noyaient les vraies options (retour
	# joueurs). `_hidden_ct` sert juste à l'expliquer plutôt qu'à les faire
	# disparaître sans un mot.
	var purchasable: Array = []
	var hidden_ct := 0
	for m: Dictionary in MoveShopScreen.MOVE_LIST:
		if not str(m.get("api", "")) in GameManager.purchased_move_names:
			continue
		if pd.can_learn(str(m.get("api", ""))):
			purchasable.append(m)
		else:
			hidden_ct += 1

	if purchasable.is_empty():
		var why := "Aucune CT achetée — direction le Tuteur de capacités ! (les attaques de base ci-dessus suffisent pour partir)"
		if hidden_ct > 0:
			why = "Aucune de tes %d CT n'est apprenable par ce Pokémon (hors movepool)." % hidden_ct
		_detail_root.add_child(_lbl_node(why, 16, 374, 544, 34, 12, C_DIM))
		return

	var mx := 16
	var my := 374
	var col_w := 178
	for m: Dictionary in purchasable:
		var api: String   = str(m.get("api", ""))
		var label: String = str(m.get("label", api))
		var mtype: String  = str(m.get("type", "normal"))
		var equipped := api in loadout

		# Button focalisable (flèches + Entrée), comme la grille — et support de
		# la touche [I] pour la popup d'infos (cf. _open_move_info).
		var card := Button.new()
		card.position = Vector2(mx, my)
		card.size     = Vector2(col_w - 6, 66)
		card.focus_mode = Control.FOCUS_ALL
		_style_move_card(card, equipped)
		_detail_root.add_child(card)

		var tpill := TypeIcon.make_pill(mtype, 70.0, 16.0, 8)
		tpill.position = Vector2(4, 4)
		tpill.mouse_filter = Control.MOUSE_FILTER_IGNORE   # le clic doit atteindre le bouton
		card.add_child(tpill)

		var full := loadout.size() >= GameManager.get_move_slots(_selected_pid)
		card.add_child(_lbl_node(label, 4, 24, col_w - 14, 18, 11, C_TEXT))
		# L'EFFET visible sur la carte même (retour joueurs) : effet maison
		# s'il existe, sinon puissance réelle chargée en async. L'action
		# (équiper/retirer/remplacer) reste sur la ligne du dessous.
		var fx_line := _move_house_effect(api)
		var fx_lbl := _lbl_node(fx_line if fx_line != "" else "…", 4, 38, col_w - 14, 13, 9, C_GOLD_LT)
		card.add_child(fx_lbl)
		if fx_line == "":
			var w_fx: WeakRef = weakref(fx_lbl)
			PokemonAPI.get_move(api, func(md: Dictionary) -> void:
				var l2: Label = w_fx.get_ref()
				if md.is_empty() or l2 == null:
					return
				var pv2: Variant = md.get("power")
				var av2: Variant = md.get("accuracy")
				l2.text = "pui. %s · préc. %s" % [
					str(int(pv2)) if pv2 != null else "—",
					("%d%%" % int(av2)) if av2 != null else "—"]
			)
		if equipped:
			card.add_child(_lbl_node("✓ Équipée · Entrée : retirer", 4, 50, col_w - 14, 13, 9, C_GOOD))
		elif full:
			# Slots pleins : Entrée ouvre le CHOIX de la capacité à remplacer.
			card.add_child(_lbl_node("Entrée : remplacer…", 4, 50, col_w - 14, 13, 9, C_DIM))
		else:
			card.add_child(_lbl_node("Entrée : équiper", 4, 50, col_w - 14, 13, 9, C_DIM))

		var move_pid := _selected_pid
		var capture_api := api
		var capture_lbl := label
		card.pressed.connect(func() -> void:
			if not (capture_api in GameManager.get_move_loadout(move_pid)) \
					and GameManager.get_move_loadout(move_pid).size() >= GameManager.get_move_slots(move_pid):
				_open_replace_picker(move_pid, capture_api, capture_lbl)
			else:
				GameManager.toggle_move_in_loadout(move_pid, capture_api)
				_refresh_detail()
		)
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventKey and (event as InputEventKey).pressed \
					and (event as InputEventKey).keycode == KEY_I:
				_open_move_info(capture_api, capture_lbl)
				get_viewport().set_input_as_handled()
		)

		mx += col_w
		if mx + col_w > 560:
			mx = 16
			my += 72

	# Hauteur du contenu → le ScrollContainer sait jusqu'où défiler.
	_detail_root.custom_minimum_size.y = maxf(484.0, my + 66.0)


## Effet MAISON d'une CT (MoveShopScreen.MOVE_LIST) en toutes lettres — c'est
## ce que fait réellement la capacité dans CE jeu. "" si pas d'effet spécial.
func _move_house_effect(api: String) -> String:
	for m: Dictionary in MoveShopScreen.MOVE_LIST:
		if str(m.get("api", "")) != api:
			continue
		var fx: Dictionary = m.get("effect", {})
		match str(fx.get("kind", "")):
			"status":
				var nm: String = {"poison": "empoisonne", "paralysis": "paralyse",
					"burn": "brûle", "sleep": "endort"}.get(str(fx.get("status", "")), "altère")
				return "Effet : %s la cible" % nm
			"heal_team": return "Effet : soigne l'équipe de %d %%" % int(float(fx.get("pct", 0.0)) * 100)
			"heal_self": return "Effet : se soigne de %d %%" % int(float(fx.get("pct", 0.0)) * 100)
		return ""
	return ""


## Style d'une carte de capacité (Button) — équipée = vert, focus = liseré or.
func _style_move_card(card: Button, equipped: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var bg := C_CARD_SEL if equipped else C_CARD
		sb.bg_color     = bg.lightened(0.08) if state in ["hover", "focus"] else bg
		sb.border_color = C_GOLD_LT if state == "focus" else (C_GOOD if equipped else C_BORDER)
		sb.set_border_width_all(3 if state == "focus" else 2)
		sb.set_corner_radius_all(6)
		card.add_theme_stylebox_override(state, sb)


## CHOIX de la capacité à remplacer quand les slots sont pleins : liste les
## équipées, en choisir une la fait céder sa place à `new_api` (même slot).
## Même mécanique de sur-popup que le sélecteur d'objet : son MenuNav consomme
## Échap tant qu'elle est ouverte.
var _replace_picker: CanvasLayer = null

func _open_replace_picker(pid: int, new_api: String, new_label: String) -> void:
	if is_instance_valid(_replace_picker):
		_replace_picker.queue_free()
	var pick := CanvasLayer.new()
	pick.layer = 30
	_replace_picker = pick
	add_child(pick)

	var close_pick := func() -> void:
		pick.queue_free()
		_replace_picker = null
		_refresh_detail()
	pick.add_child(MenuNav.make(close_pick))

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.02, 0.01, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	pick.add_child(veil)

	var equipped: Array = GameManager.get_move_loadout(pid)
	var ph := 110.0 + equipped.size() * 50.0
	var panel := UiKit.main_panel(Vector2(400, maxf(40.0, 340.0 - ph * 0.5)), Vector2(480, ph))
	pick.add_child(panel)
	UiKit.banner(panel, "Remplacer par %s" % new_label)
	_lbl(panel, "Quelle capacité cède sa place ?", 0, 62, 480, 20, 12, C_DIM, true)

	for i in equipped.size():
		var old_api: String = equipped[i]
		var btn := Button.new()
		btn.position = Vector2(24, 90 + i * 50.0)
		btn.size     = Vector2(432, 44)
		btn.add_theme_font_size_override("font_size", UiKit.scaled_font(13))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "  " + old_api.replace("-", " ").capitalize()
		_style_button(btn, Color(0.22, 0.17, 0.10), C_TEXT)
		# Nom français + type dès que la fiche du move arrive.
		var fx_line := _move_house_effect(old_api)
		var fx_lbl := _lbl_node(fx_line, 16, 27, 290, 14, 9, C_GOLD_LT)
		fx_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(fx_lbl)
		var w_btn: WeakRef = weakref(btn)
		var w_fx2: WeakRef = weakref(fx_lbl)
		PokemonAPI.get_move(old_api, func(md: Dictionary) -> void:
			var b2: Button = w_btn.get_ref()
			if md.is_empty() or b2 == null:
				return
			var frn := str(md.get("name_fr", ""))
			if frn != "":
				b2.text = "  " + frn
			UiKit.type_badge(b2, Vector2(316, 12), str(md.get("type", "normal")), 18.0)
			var f2: Label = w_fx2.get_ref()
			if f2 != null and f2.text == "":
				var pv3: Variant = md.get("power")
				f2.text = ("pui. %d" % int(pv3)) if pv3 != null else "statut"
		)
		var cap_old := old_api
		btn.pressed.connect(func() -> void:
			GameManager.replace_move_in_loadout(pid, cap_old, new_api)
			close_pick.call()
		)
		panel.add_child(btn)

	MenuNav.focus_first(panel)


## POPUP D'INFOS d'une attaque ([I] sur une carte) : nom FR, type, puissance,
## précision, PP, classe de dégâts et description officielle — la carte de la
## grille est bien trop petite pour tout ça (retour joueurs : « trop condensé,
## on ne voit rien »). L'effet spécial des CT du tuteur (MoveShopScreen) est
## affiché en plus quand il existe : c'est LUI la vraie mécanique en jeu.
var _move_info: CanvasLayer = null

func _open_move_info(api: String, fallback_label: String) -> void:
	if is_instance_valid(_move_info):
		_move_info.queue_free()
	var pop := CanvasLayer.new()
	pop.layer = 31
	_move_info = pop
	add_child(pop)

	var close_pop := func() -> void:
		pop.queue_free()
		_move_info = null
		call_deferred("_ensure_focus_alive")
	pop.add_child(MenuNav.make(close_pop))

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.02, 0.01, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop.add_child(veil)

	var panel := UiKit.main_panel(Vector2(340, 150), Vector2(600, 420))
	pop.add_child(panel)
	UiKit.banner(panel, fallback_label)

	var body := _lbl(panel, "Chargement…", 32, 84, 536, 260, 14, C_TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Effet maison de la CT (soin, statut garanti…) — prioritaire sur le texte
	# officiel, c'est ce que fait RÉELLEMENT la capacité dans CE jeu.
	var house_fx := ""
	for m: Dictionary in MoveShopScreen.MOVE_LIST:
		if str(m.get("api", "")) == api:
			house_fx = str(m.get("desc", ""))
			break

	var w_panel: WeakRef = weakref(panel)
	var w_body: WeakRef = weakref(body)
	PokemonAPI.get_move(api, func(md: Dictionary) -> void:
		var pn: Panel = w_panel.get_ref()
		var bd: Label = w_body.get_ref()
		if pn == null or bd == null:
			return
		if md.is_empty():
			bd.text = "Fiche introuvable (hors ligne ?)"
			return
		var frn := str(md.get("name_fr", ""))
		if frn != "":
			UiKit.banner(pn, frn)
		UiKit.type_badge(pn, Vector2(32, 84), str(md.get("type", "normal")), 24.0)
		var pv: Variant = md.get("power")
		var av: Variant = md.get("accuracy")
		var ppv: Variant = md.get("pp")
		var klass: String = {"physical": "Physique", "special": "Spéciale", "status": "Statut"} \
			.get(str(md.get("damage_class", "")), "?")
		var lines: Array[String] = []
		lines.append("Puissance : %s      Précision : %s      PP : %s" % [
			str(int(pv)) if pv != null else "—",
			("%d %%" % int(av)) if av != null else "—",
			str(int(ppv)) if ppv != null else "—"])
		lines.append("Classe : %s" % klass)
		if house_fx != "":
			lines.append("")
			lines.append("★ Effet dans Pokhades : %s" % house_fx)
		var desc := str(md.get("desc_fr", ""))
		if desc != "":
			lines.append("")
			lines.append(desc)
		bd.position = Vector2(32, 124)
		bd.text = "\n".join(lines)
	)

	var ok := UiKit.button("Fermer  (Échap)", Vector2(220, 40), false)
	ok.position = Vector2(190, 356)
	ok.pressed.connect(close_pop)
	panel.add_child(ok)
	MenuNav.focus_first(panel)


# ── Chargement API ────────────────────────────────────────────────────

func _fetch_all() -> void:
	for pid in _sorted_ids:
		PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
			if data.is_empty(): return
			var pd := PokemonData.from_api(data)
			_loaded_data[pid] = pd
			if _card_panels.has(pid):
				# Button depuis la conversion de la grille (navigation aux
				# flèches) — ce callback arrive en ASYNCHRONE, le typage Panel
				# d'origine ne plantait donc qu'à l'ouverture de l'écran.
				var card: Button = _card_panels[pid]
				var nm := card.get_node_or_null("NameLbl")
				if nm: (nm as Label).text = pd.name_fr.to_upper()
				var tr := card.get_node_or_null("TypeRow")
				if tr: _fill_type_row(tr as Control, pd.types)
				var prog := card.get_node_or_null("ProgLbl")
				if prog and not pd.is_base_form:
					(prog as Label).text = "Forme évoluée — non recrutable"
			if pid == _selected_pid:
				_refresh_detail()
			if not pd.sprite_url.is_empty():
				_fetch_portrait(pid, pd.sprite_url)
		)


func _fetch_portrait(pid: int, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res: int, code: int, _h, body: PackedByteArray) -> void:
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200: return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK: return
		var new_tex: Texture2D = ImageTexture.create_from_image(img)
		_portraits[pid] = new_tex
		if _card_tex.has(pid):
			var ct: TextureRect = _card_tex[pid]
			ct.texture = new_tex
			if _card_ph.has(pid):
				(_card_ph[pid] as ColorRect).visible = false
		# PAS de _refresh_team_strip ici. La bande d'équipe affichait jadis ces
		# portraits ; elle est passée aux sprites PMD animés et n'en dépend
		# plus. Le garder reconstruisait la bande À CHAQUE portrait reçu
		# (~140 fois à l'ouverture) — et chaque reconstruction détruisait le
		# carré focalisé : le focus mourait ~1,5 s après l'ouverture et les
		# flèches devenaient inertes (retour joueurs, reproduit par
		# smoke_pokedex : focus t=1.25s OK, t=1.50s null).
		if pid == _selected_pid:
			_refresh_detail()
	)
	http.request(url)


# ── Helpers ───────────────────────────────────────────────────────────


func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(bg.r, bg.g, bg.b, 0.55)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.6))
	btn.add_theme_font_size_override("font_size", UiKit.scaled_font(13))

func _lbl(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := _lbl_node(text, x, y, w, h, fs, color, centered)
	parent.add_child(l)
	return l


func _lbl_node(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.14); s.shadow_size = 3
	p.add_theme_stylebox_override("panel", s)
