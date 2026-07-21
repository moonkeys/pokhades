class_name NpcDialogue
extends RefCounted

## Petites répliques de PNJ — LE fichier à éditer pour changer ce que dit un
## PNJ du Hub ou de la salle-Boutique en run (cf. NpcDialogueScreen). Clé =
## HubNPC.npc_id. Chaque entrée est une séquence FIXE de 2-3 phrases (mini
## dialogue), dans le droit fil de la Rébellion (cf. StoryManager) : chaque
## PNJ a un rôle et un avis sur le mouvement.

const LINES: Dictionary = {
	"start": [
		"Prêt à repartir ? Chaque salle nettoyée est un pas de plus pour la rébellion.",
		"Là-bas, les dresseurs ne nous feront pas de cadeaux.",
		"Mais nous non plus.",
	],
	"shop": [
		"Bienvenue ! Ici, on soigne les corps ET le moral.",
		"Les Pokémon libérés méritent le meilleur repos avant de repartir en expédition.",
		"Dis-moi ce qu'il te faut.",
	],
	"pokedex": [
		"J'archive chaque Pokémon libéré ou rencontré — la mémoire de la rébellion.",
		"Certains ne sont encore que des rumeurs de victoire… d'autres déjà des alliés.",
		"Consulte les registres quand tu veux.",
	],
	"upgrades": [
		"La force seule ne suffit pas contre la Ligue. Il faut aussi la stratégie.",
		"Investis dans tes capacités, et chaque combat te coûtera moins cher.",
		"Voyons ce que je peux améliorer.",
	],
	"gromago": [
		"Pssst. J'ai deux trois trucs qui ne posent pas de questions.",
		"Où je les ai trouvés ? Mystère et boule de gomme.",
		"Jette un œil, ça vaut le détour.",
	],
	"moves": [
		"Une bonne capacité bien choisie vaut mieux qu'une armée mal préparée.",
		"Je peux t'enseigner tout un éventail de techniques, contre quelques Baies.",
		"Voyons ce qui te manque.",
	],
	"story": [
		"Tu sens cette rage qui monte ? C'est la mienne — et bientôt la tienne.",
		"Chaque Pokémon libéré est une chaîne en moins sur ce monde.",
		"Viens, je vais te raconter où nous en sommes.",
	],
	"rumors": [
		"J'ai fait le tour des environs — les rumeurs volent vite, avec des ailes comme les miennes.",
		"Certaines valent la peine d'être suivies… et grassement récompensées.",
		"Jette un œil au tableau.",
	],
	"boutique_vendor": [
		"Ah, un rebelle affamé de provisions ! Tu es au bon endroit.",
		"Potions, Rappels, capacités rares… tout ce qu'il faut pour tenir une salle de plus.",
		"Qu'est-ce qui te ferait plaisir ?",
	],
	"boutique_sleeper": [
		"Zzz… encore cinq minutes…",
		"Zzz… les Poké Balls… n'existent plus… zzz…",
	],
	"boutique_wanderer": [
		"Oh… bonjour… ou bonsoir… je ne sais plus trop.",
		"Tu cherches quelque chose ? Moi aussi, je crois.",
		"…Enfin bref.",
	],
}

## PNJ à VARIANTES : contrairement aux PNJ fixes ci-dessus (un seul, toujours
## le même texte), les Pokémon LIBÉRÉS qui déambulent dans le hub (cf.
## HubWorld.FREED_ROAM_SPOTS) sont nombreux et partagent le même npc_id
## "reserve" — un tirage parmi ces séquences évite d'entendre exactement la
## même réplique à chacun d'entre eux.
const _VARIANTS: Dictionary = {
	"reserve": [
		[
			"Libre… ça fait un drôle d'effet, tu sais.",
			"Je me demande encore parfois si je rêve.",
			"Merci de m'avoir donné le choix.",
		],
		[
			"Ici, personne ne me retient dans une Poké Ball.",
			"Je vais où je veux, quand je veux.",
			"C'est ça, la rébellion, non ?",
		],
		[
			"Certains dresseurs étaient gentils, tu sais.",
			"Mais gentil ou pas, une cage reste une cage.",
			"Je préfère largement ici.",
		],
		[
			"Tu devrais voir la clairière à l'est, elle est magnifique en cette saison.",
			"On s'y retrouve souvent, entre libérés.",
		],
	],
}

const _DEFAULT: Array[String] = ["…"]


## Séquence de répliques pour `npc_id` — jamais vide (retombe sur un "…" muet
## plutôt que de planter l'appelant si un id n'a pas encore de texte). Un id à
## variantes (cf. _VARIANTS) en tire une au hasard à chaque appel.
static func lines_for(npc_id: String) -> Array:
	if _VARIANTS.has(npc_id):
		var variants: Array = _VARIANTS[npc_id]
		return variants[randi() % variants.size()]
	var lines: Array = LINES.get(npc_id, [])
	return lines if not lines.is_empty() else _DEFAULT
