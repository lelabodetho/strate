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

## Harnais de test
- `scenes/test/harness.tscn` : scène de test nommée.
- `GameState` (autoload) expose `to_dict()` et répond aux flags CLI `--screenshot=<path>` et `--state=<path>` puis quitte.
- `tools/snap.sh` : lance la scène, capture, dump l'état. À utiliser après chaque changement visuel ou de gameplay.
- Ne jamais déclarer une feature terminée sans avoir lancé `tools/snap.sh` et regardé l'image.
- `tools/sim_test.gd` : tests headless de la sim (`godot --headless --path . -s tools/sim_test.gd`). À lancer après tout changement dans `src/sim/`.
- Les valeurs de référence du gameplay sont dans `tools/out/tuning.json`, pas dans le code. `SimTuning` porte les défauts, le panneau in-game (Tab) les édite et les sauve, `GameState` charge le fichier au démarrage.

## Assets
3D low-poly + shader de post-process (dither / pixel). Le filtre final se décide sur `scenes/test/render_test.tscn`. Palette : gris acier, rouille, noir, un accent. Pas de textures au départ : couleurs plates.

## Jalons
- J1 : squelette + harnais — bouclé
- J2 : la mécanique — bouclé. Base = preset A densité (tools/presets/baseline.json), hunter = archétype de départ.
- J2b : scène de test de rendu (3 filtres commutables), murs translucides propres, déploiement web
- J3 : viewer de personnage (8 directions, sliders, export PNG, JSON)
- J4 : contenu (élites, affixes, paliers, boss, éditeur de zone)
- J5 : coop 1–4
- J6+ : classes 2–3, biomes, saisons

## Interdits
- Rien de 40K : pas d'aquila, space marines, Emperor, Mechanicus, warp. Ton oui, marques non.
- Pas d'arbre de talents géant : ~8 compétences × 3 modificateurs par classe.
- Pas de code de rendu dans la sim.
