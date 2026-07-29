# Pokhades — Bible de Direction Artistique

> **Conte gothique-lumineux, héroïque.** Un monde d'ombre profonde traversé de
> couleurs qui rayonnent, où la tension permanente entre mignon et inquiétant
> EST l'identité. Le héros de la Rébellion — chaleur de **braise** — s'enfonce
> dans un monde froid et magique — lueur de **cyan spectral** — qu'il vient
> réchauffer et libérer. Plus on avance, plus le monde se tord et s'assombrit.

Ce document est la **référence unique**. Avant d'ajouter/valider un asset, une
couleur ou un réglage : vérifier qu'il respecte ces règles. Une DA
reconnaissable = un jeu de règles limité, appliqué **partout, sans exception**.

> **Historique des décisions** (pour ne pas y revenir) : pistes écartées après
> test — pixelisation / diorama HD-2D (les sprites sont déjà pixel, ça les
> abîme) ; peint-Ghibli lissé (trop lisse, pas vivant). Références retenues
> lignée **Don't Starve / Hollow Knight** (cute-gothique dessiné) mais au
> service d'une **aventure héroïque**, pas de la survie-angoisse.

---

## 1. La vision en une phrase

> Un conte gothique-lumineux où la braise du héros réchauffe un monde froid et
> magique, et où formes, lumière et sol se tordent à mesure que le danger
> monte.

Si un choix ne se justifie pas par cette phrase, il sort de la DA.

---

## 2. Les 4 piliers reconnaissables

Dans l'ordre de priorité (le n°1 est la **signature déclarée**).

### Pilier 1 — La palette À SENS (braise ↔ cyan)
On reconnaît Pokhades à sa **couleur**, et cette couleur **veut dire quelque
chose** :
- **Braise (orange chaud) = NOUS.** Le joueur, son feu, son foyer, la
  Rébellion, la vie, l'action. Le seul chaud saturé du jeu.
- **Cyan spectral (froid lumineux) = LE MONDE.** La magie froide, le mystère,
  la menace, ce qui est à libérer.
- Tout le reste est une **base d'ombre profonde** (sombres désaturés
  bleu-vert) que ces deux lueurs viennent trouer.

Le héros (braise) s'enfonce dans un monde (cyan) plus froid que lui. Ce
contraste chaud/froid chargé de sens est LE marqueur du jeu.

### Pilier 2 — Le gothique-lumineux
Base d'ombre + couleurs qui **rayonnent** par-dessus (émission + glow, pas des
aplats). Le monde est parsemé de **lueurs magiques** — champignons, fleurs,
cristaux, particules, yeux luisants dans le noir — **généreusement, dosées par
biome** (beaucoup en grotte/marais, plus discret en prairie).

### Pilier 3 — Tout monte avec le danger (progression)
Les premières zones sont **claires, mignonnes, accueillantes** ; les dernières
sont **sombres, tordues, hostiles**. Trois choses évoluent ENSEMBLE avec
l'avancée dans la run :
- **Formes** : arbres ronds et amicaux → noueux, tordus, menaçants.
- **Lumière / value** : clair et lisible → sombre et oppressant.
- **Sol** : herbeux et accueillant → aride, craquelé, mort.

C'est un marqueur original **et** un outil de game design (le décor raconte la
montée en tension).

### Pilier 4 — Trait dessiné + tension 50/50
- **Contours subtils** : un fin liseré sombre détache les objets (patte
  "dessinée"), sans faire BD franche.
- **50/50 cute ↔ gothique** : chaque asset garde une part de charme ET une
  part d'inquiétude. Ni purement mignon, ni purement macabre — la tension est
  l'identité.

---

## 3. Palette (la signature — le plus important)

### Les 3 rôles de couleur
| Rôle | Sens | Teintes | Usage |
|------|------|---------|-------|
| **Braise** | Nous / héros / feu / vie | `#E8622A` → `#F4A03C` | Joueur, feu, combat, baies, UI d'action, foyers, effets amis |
| **Cyan spectral** | Le monde / magie / menace | `#2FC9D6` → `#7FF0F5` (lueur), `#1E7E9E` (profond) | Lueurs magiques, cristaux, eau enchantée, sorts, dangers, faune sauvage lumineuse |
| **Ombre** | La base du monde | `#14181C`, `#1B2228`, `#2A3138` (bleu-vert très sombres) | Troncs, roche, terre, fonds — tout ce qui n'est pas accent |

### Règles
- **La braise est RARE et réservée.** Si tout devient orange, elle ne veut
  plus rien dire. Un accent chaud = un signal (le héros, un feu, une baie).
- Le **cyan** peut être plus présent (c'est le monde), mais toujours en
  **lueur** sur fond sombre, jamais en aplat plat.
- Chaque biome a **6–8 couleurs identifiables**, mais partage TOUJOURS : base
  d'ombre + au moins une des deux lueurs signature.
- Couleurs **de base des meshes = neutres/moyennes** ; la valeur sombre et la
  saturation finale se jouent au **moteur** (lumière, `adjustment_saturation`,
  glow, émission) — cf. `BiomeAmbiance.gd`.

### Direction couleur & progression par biome
Ordonnés du plus clair/mignon (début) au plus sombre/tordu (fin) — *ordre
indicatif, à caler sur la structure de run*.
| Biome | Value | Formes | Lueur dominante | Sol |
|-------|-------|--------|-----------------|-----|
| Prairie | clair | rondes | braise douce (soleil) | herbeux vif |
| Forêt | moyen-clair | rondes+ | cyan léger (clairières) | herbe/terre |
| Lac | moyen | douces | **cyan** (eau enchantée) | rives claires |
| Bois d'automne | moyen-sombre | un peu tordues | braise (feuilles rousses) | tapis mort chaud |
| Marécage | sombre | tordues | cyan glauque + spores | boue, eau noire |
| Éboulis | sombre | anguleuses | cyan minéral / cristaux | roche aride craquelée |
| Grotte | très sombre | très tordues | **cyan** intense (bioluminescence) | pierre morte |

---

## 4. Lumière & lueurs (le mood se joue ici, pas en post-process)

- **Ciel/heure propre à chaque biome** (crépuscule en forêt, nuit en grotte,
  etc.) — piloté par biome dans `BiomeAmbiance.gd`.
- **1 source directionnelle** nette + ombres franches → volumes solides,
  facettes lisibles.
- **Ambiant bas** : c'est ce qui fait ressortir les lueurs (émission + glow).
  Plus une zone est tardive, plus l'ambiant descend.
- **Émission + glow** : les éléments lumineux (flore magique, cristaux,
  particules, braise) ont un matériau émissif ; le glow du `WorldEnvironment`
  les fait "rayonner". C'est le cœur du gothique-lumineux.
- **Brouillard coloré** teinté vers la lueur du biome (cyan en marais/grotte)
  pour la profondeur et le mystère.

---

## 5. Style des assets 3D

- **Ombrage** : facetté pour feuillage/roche/ce qui doit croustiller ; lissé
  pour troncs/formes organiques allongées. Le contraste facetté/lissé fait
  partie du look.
- **Contours subtils** : liseré sombre par coque inversée (backface étendue,
  sombre) — marche sur le renderer actuel (GL Compatibility), sans
  post-process ni depth.
- **Peinture par couleur de sommet** (glTF `COLOR_0`, pas d'UV/texture) :
  dégradés sombre→clair, stries d'écorce, mouchetures, **et** les zones
  émissives (lueurs). Signature technique, cohérente, légère, native Godot.
- **Silhouettes franches et un peu trapues** — lisibles en ombre chinoise,
  amies des sprites 2D. Stylisation = mix cartoon franc / semi-réaliste (formes
  crédibles mais idéalisées).
- **Progression des formes** : prévoir des variantes/params "mignon → tordu"
  pour chaque famille d'asset (cf. le générateur d'arbres : `oak` rond → `dead_oak`
  et troncs très cambrés pour les zones tardives).
- **2–3 touches de vécu** (nœud, usure, mousse) sans surcharger.
- Éviter le sur-détail invisible à distance de jeu (subdivisions inutiles,
  micro-feuilles) — poids fichier pour rien.

---

## 6. Sprites Pokémon (pixel 2D) : on ASSUME le contraste

Le monde peint-gothique est un **écrin** ; les sprites pixel **popent** dessus
comme des figurines de conte. On n'essaie pas de les fondre — l'écart de style
garantit qu'on distingue toujours perso/décor (lisibilité) et donne un charme
"figurine sur diorama peint". Corollaire : la **base d'ombre** du monde aide
les sprites colorés à ressortir → garder les fonds assez sombres/contrastés
derrière l'action.

---

## 7. Méthode : juger en scène, pas isolé

Itérer sur une **scène-pilier** : plusieurs assets d'un même biome + sol +
lumière/glow du biome + un sprite Pokémon. C'est l'ensemble (et surtout la
**lumière**) qui dit si la DA tient. Les assets Blender se valident hors-jeu
(rendus) ; l'intégration + la lumière se jugent **en lançant le jeu**.

**Première scène-pilier conseillée** : un biome tardif (marécage ou grotte),
là où la DA gothique-lumineux est la plus démonstrative — base d'ombre, lueurs
cyan, formes tordues, et la braise du joueur qui tranche.

---

## 8. Outils & assets existants

- `tools/blender/generate_tree_cartoon.py` — base de style (presets = espèces :
  oak, oak_clumped, dead_oak, pine, sakura, willow, bonsai, palm). À faire
  évoluer vers le gothique-lumineux (palette d'ombre + émission + variantes
  "tordues" pour zones tardives).
- `tools/blender/generate_tree.py` — variante low-poly simple.
- `tools/blender/generate_grass_tuft.py`, `generate_flower.py` — herbe, fleurs
  (candidates aux versions LUMINEUSES).
- Rendu/lumière moteur : `scripts/world/BiomeAmbiance.gd`, `KitProps.gd`.

Technique commune : géométrie facettée/lissée + couleur de sommet + émission,
export glTF, lu nativement par Godot.

---

## 9. Checklist de cohérence (tout nouvel asset / réglage)

- [ ] Respecte la palette : base d'ombre + lueur(s) signature, pas d'aplat mort ?
- [ ] La braise reste RARE et signifiante (pas d'orange gratuit) ?
- [ ] Le cyan est en lueur (émissif) et non en aplat plat ?
- [ ] Silhouette lisible en ombre chinoise ?
- [ ] Ombrage : feuillage/roche facetté, tronc/organique lissé ?
- [ ] Contour subtil présent ?
- [ ] La forme correspond au niveau de danger de la zone (mignon tôt / tordu tard) ?
- [ ] Couleurs de mesh neutres (la valeur/sat/glow se règlent au moteur) ?
- [ ] Garde la tension 50/50 (une part de charme ET une part d'inquiétude) ?
- [ ] Ça se justifie par la phrase de vision (§1) ?
