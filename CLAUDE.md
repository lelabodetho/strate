# STRATE — contexte pour l'agent

Hack & slash isométrique, dark sci-fi grimdark, univers original. Side project solo, sans deadline.
Moteur : Godot 4.7, renderer **Compatibility** (export web obligatoire). GDScript. Langue du code : anglais. Commentaires et commits : anglais. Conversation avec Tho : français.

Brief complet : `docs/brief.md`. Le lire au démarrage d'une session longue.

## Concept
Un aventurier dans une cité verticale (STRATE) bâtie dans une arche échouée. Hub = ta strate, zones persistantes = strates connues, donjons = strates basses perdues (générées). Difficulté = profondeur. Softcore, tout reste. Pas de méchant : conflits d'intérêts.

## Piliers
1. Chaque run rend plus fort, visiblement.
2. Le loot raconte une histoire (affixes lisibles).
3. Le monde persiste.
4. La difficulté est un choix, jamais un mur. Densité pour le trash, mécanique pour élites et boss.

## Feel — règle de base
Starter ARPG, pas roguelike : à nu le joueur est faible mais chaque coup est satisfaisant. Cadence lente, coup lourd, projectile visible, déplacement ralenti pendant l'attaque, mono-cible. Tout ce qui rend nerveux s'acquiert par le build. Ne jamais régler le starter comme un twin-stick.

## Contrôles
ZQSD (physical WASD) + visée souris. Dash avec i-frames. Tir par défaut ; mêlée = une classe.

## Architecture — règles non négociables
- `src/sim/` : simulation pure. Aucune dépendance à Node, Scene, Input, Rendering. Données + `step(dt, commands)`. Testable sans fenêtre.
- `src/view/` : lit l'état de la sim et l'affiche. Jamais l'inverse.
- `src/input/` : transforme Input en `Command` (move, aim, attack, dash). Jamais d'action directe sur le monde.
- Génération seedée : tout aléa passe par `RandomNumberGenerator` avec seed explicite.
- ID stable (`int`) sur chaque entité, item, monstre. Pas de référence directe entre objets de sim.
- Persistance par perso, pas par partie.
Ces règles préparent la coop 1–4 (jalon 5) sans la coder maintenant.

## Greybox kit
Ce repo est un kit de greybox (sim pure + harnais + tuning + arène) dont Strate est le premier contenu. Description complète, boucle de session et procédure de réutilisation : `docs/greybox-kit.md`. Toute nouvelle feature passe par le kit : dans la sim, paramétrée dans le tuning, capturée par `tools/snap.sh`, vérifiée dans `tools/sim_test.gd`.

## Harnais de test
- `scenes/test/harness.tscn` : scène de test nommée.
- `GameState` (autoload) expose `to_dict()` et répond aux flags CLI `--screenshot=<path>` et `--state=<path>` puis quitte.
- `tools/snap.sh` : lance la scène, capture, dump l'état. À utiliser après chaque changement visuel ou de gameplay.
- `scenes/test/render_test.tscn` : même arène et même sim, rendue en 1/2 de résolution à travers `src/view/post_filter.gdshader` (F : pixel / dither / mix, défaut mix, entités toujours en pixel, windup sur un ton danger rouge). `tools/snap.sh --mode=pixel|dither|mix` capture cette scène et dépose aussi `<nom>_world.png` et `<nom>_entities.png` (viewports bruts). Le look (mode, dither, scanlines, échelle du viewport, lampes) est un `Look` côté view, édité dans le bloc « rendu » du panneau, sauvé dans `tools/presets/look_<nom>.json` ; `look_default.json` est chargé au démarrage s'il existe (`--look=<nom>` pour un autre).
- Ne jamais déclarer une feature terminée sans avoir lancé `tools/snap.sh` et regardé l'image.
- Événements de sim (`SimWorld.events`, vidé à chaque tick, consommés une fois par tick par le view) : hit, kill, dodge, shot, impact, wave_cleared, swing, explosion, stagger, aggro, deaggro, drop, pickup, blocked (coup frontal sur un blindé), fuse (élite instable mort, explosion dans `time`), blast.
- `tools/sim_test.gd` : tests headless de la sim (`godot --headless --path . -s tools/sim_test.gd`). À lancer après tout changement dans `src/sim/`.
- Les valeurs de référence du gameplay sont dans `tools/out/tuning.json`, pas dans le code. `SimTuning` porte les défauts, le panneau in-game (Tab) les édite et les sauve, `GameState` charge le fichier au démarrage.

## Assets
**DA tranchée : low-poly flat-shaded.** Volumes nets, couleurs plates, pas de textures, ~2000 tris par perso. Post-process par-dessus pour lumière, ombres, grain. Palette : gris acier froid (8 tons), rouille, noir, un accent orange (4 tons) — valeurs dans `tools/filters_preview.py`. Références visuelles : `docs/da/`. Rendu : `scenes/test/render_test.tscn`, shader `src/view/post_filter.gdshader`, mode `mix` par défaut, entités en `pixel`. **Langage visuel** : orange = joueur et ce qui est à lui ; rouge DANGER = menace (windups, zones de boss) ; gris acier = monde. Ne jamais utiliser l'orange pour un ennemi.

## Jalons
- J1 : squelette + harnais — bouclé
- J2 : la mécanique — bouclé. Base = preset A densité (tools/presets/baseline.json), hunter = archétype de départ.
- J2b : premier item — bouclé. SimStats + SimItem, le pickup se sent.
- J2c : rendu — bouclé. `render_test.tscn`, mode `mix` par défaut, entités toujours en `pixel`. Langage visuel : orange = joueur, rouge DANGER = menace, gris acier = monde.
- J3 : viewer de personnage (8 directions, sliders, export PNG, JSON)
- J4 : contenu — en cours. Première brique bouclée : élites avec affixes (blindé / instable / célère, `SimWorld.AFFIXES`), une par vague dès `elite_from_wave`, chaque affixe a un contre que le hunter de départ possède déjà. Reste : loot (rareté, slots, affixes), paliers, boss, éditeur de zone.
- J5 : coop 1–4
- J6+ : classes 2–3, biomes, saisons

## Interdits
- Rien de 40K : pas d'aquila, space marines, Emperor, Mechanicus, warp. Ton oui, marques non.
- Pas d'arbre de talents géant : ~8 compétences × 3 modificateurs par classe.
- Pas de code de rendu dans la sim.
