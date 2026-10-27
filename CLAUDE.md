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
**Fenêtre d'attaque** : chaque attaque est windup (engagé, rien n'est encore parti) → hit (la balle naît, le cône ou le blast résout) → recovery (pas de nouvelle attaque). Windup / recovery sont l'identité du profil (`WeaponProfile` : hunter 0,12 / 0,30, brute 0,22 / 0,45, technomancer 0,30 / 0,55), jamais dans le tuning ; la stat `fire_rate` (items) divise toute la fenêtre. Tenir le tir réenchaîne à la fin de la recovery, jamais avant. Le dash annule windup (tir perdu) et recovery. `attack_move_mult` (0,25) ralentit le joueur pendant toute la fenêtre, pour tous les profils.

## Contrôles
ZQSD (physical WASD) + visée souris. Dash avec i-frames. Tir par défaut ; mêlée = une classe. **Visée aimantée (style D4)** : chaque tick, le grunt vivant dont le centre est à moins de `target_snap_radius` (1,5) du point curseur devient la cible (`SimWorld.target_at`, le cercle de hit le plus proche du curseur gagne) ; la balle, le projectile du technomancer et le cône de la brute partent vers la position de la cible à l'instant du hit (pas de guidage après), le curseur brut sinon. La cible porte un anneau DANGER fin aux pieds. Survoler un item au sol affiche sa ligne au-dessus de lui (couleur de rareté, curseur main) ; **cliquer dessus le ramasse** dans le sac (à portée `pickup_reach`, sinon rien ; le clic sur un item ne tire pas). E en secours ramasse le plus proche. I ouvre le sac (le monde ne s'arrête pas ; Entrée équipe, Suppr lâche aux pieds). `Command` porte move, aim, attack, dash, interact, pickup_id, target_id (-1 = aucune).

## Architecture — règles non négociables
- `src/sim/` : simulation pure. Aucune dépendance à Node, Scene, Input, Rendering. Données + `step(dt, commands)`. Testable sans fenêtre.
- **Personnage ≠ monde.** `SimCharacter` (`src/sim/character.gd`) porte ce qui survit aux niveaux : profil d'arme, équipement par slot, sac, compteur d'ids d'items (dès `ITEM_ID_BASE` = 1 000 000, jamais en collision avec les ids d'entités qui repartent à 1 par niveau). `to_dict()` / `from_dict()` = futur format de sauvegarde. `SimWorld` = un niveau : il reçoit un `character` et lit / écrit l'équipement à travers lui (`world.equipped` / `world.inventory` sont des vues, pas du stockage). Changer de niveau = nouveau `SimWorld` sur le même personnage.
- **Niveaux en JSON** : `data/levels/<nom>.json` → `SimLevel.from_dict()` (floors, walls optionnels sinon `auto_walls`, player_spawn, packs posés à la main `{pos, size, elite, affixes}`, exit, descend, name, kind `arena | hub | strate`). Le chargeur valide (spawn, centres de pack et exit sur un floor) et renvoie `null` avec une erreur sinon. `arena.json` est `SimLevel.arena()` exporté. `kind == "arena"` → vagues ; sinon les packs du fichier, pas de vague après le nettoyage. Sortie : joueur dans `exit` sans grunt vivant à moins de `exit_lock_radius` (12) → événement `exit` (`descend` sur le pad du hub), une fois par séjour ; la sim ne change jamais de niveau, c'est `GameState.load_level()` (seed = hash(run_seed, nom), hub ↔ strate, mort en strate → hub avec le personnage intact : softcore).
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
- `tools/snap.sh` : lance la scène, capture, dump l'état. À utiliser après chaque changement visuel ou de gameplay. Flags utiles : `--level=<nom>` (défaut arena ; hub, strate_01), `--hold=attack`, `--aim=x,z`, `--target=<id>`, `--grunt=x,z` / `--grunt2`, `--elite=x,z[,affixe]`, `--drop=x,z`, `--weapon=<nom>`, `--dash=t1,t2` (liste complète en tête de `src/game_state.gd`). L'état dumpé porte `attack` (phase, t, windup, recovery), `target_id`, `level`, `level_kind`, `exit_open`, `character` et `level_loads`. Les scènes rebâtissent leurs vues sur `GameState.level_changed`.
- `scenes/test/render_test.tscn` : même arène et même sim, rendue en 1/2 de résolution à travers `src/view/post_filter.gdshader` (F : pixel / dither / mix, défaut mix, entités toujours en pixel, windup sur un ton danger rouge). `tools/snap.sh --mode=pixel|dither|mix` capture cette scène et dépose aussi `<nom>_world.png` et `<nom>_entities.png` (viewports bruts). Le look (mode, dither, scanlines, échelle du viewport, lampes, caméra `camera_pitch` 50° / `camera_size` 24 appliqués chaque frame à la caméra monde et copiés sur la caméra entités, `ambient_energy` 0,9 sur les deux environnements, `shadow_blur` 1,5 sur toutes les omnis, `dither_low` 0,06 = seuil bas du tramage en mode mix pour tramer ou non les ombres) est un `Look` côté view, édité dans le bloc « rendu » du panneau, sauvé dans `tools/presets/look_<nom>.json` ; `look_default.json` est chargé au démarrage s'il existe (`--look=<nom>` pour un autre).
- Ne jamais déclarer une feature terminée sans avoir lancé `tools/snap.sh` et regardé l'image.
- Événements de sim (`SimWorld.events`, vidé à chaque tick, consommés une fois par tick par le view) : windup (`id`, `profile` : l'attaque du joueur s'engage), hit, kill, dodge, shot, impact, wave_cleared, swing, explosion, stagger, aggro, deaggro, drop (item au sol : `slot`, `rarity`), pickup (clic ou E : l'item entre dans le sac), inventory_full (sac plein, l'item reste), equip (`SimWorld.equip()` depuis le sac ; `replaced_id` = l'ancien item du slot, retourné au sac ou posé aux pieds si plein), blocked (coup frontal sur un blindé), fuse (élite instable mort, explosion dans `time`), blast, exit / descend (`level` : joueur sur la sortie ou le pad de descente, aucun grunt dans `exit_lock_radius`).
- `tools/sim_test.gd` : tests headless de la sim (`godot --headless --path . -s tools/sim_test.gd`). À lancer après tout changement dans `src/sim/`.
- Les valeurs de référence du gameplay sont dans `tools/presets/default.json`, pas dans le code : `GameState` le charge au démarrage, le panneau in-game (Tab) l'édite et « Save » l'écrit. Les défauts de `SimTuning` sont la fixture de `tools/sim_test.gd` et ne bougent pas. `tools/out/` (captures, non suivi) reçoit un `.gdignore` de `tools/snap.sh` et `docs/` en porte un, pour que l'éditeur n'importe ni les captures ni les images de référence.

## Assets
**DA tranchée : low-poly flat-shaded.** Volumes nets, couleurs plates, pas de textures, ~2000 tris par perso. Post-process par-dessus pour lumière, ombres, grain. Palette : gris acier froid (8 tons), rouille, noir, un accent orange (4 tons) — valeurs dans `tools/filters_preview.py`. Références visuelles : `docs/da/`. Rendu : `scenes/test/render_test.tscn`, shader `src/view/post_filter.gdshader`, mode `mix` par défaut, entités en `pixel`. **Langage visuel** : orange = joueur et ce qui est à lui ; rouge DANGER = menace (windups, zones de boss) ; gris acier = monde. Ne jamais utiliser l'orange pour un ennemi.

## Jalons
- J1 : squelette + harnais — bouclé
- J2 : la mécanique — bouclé. Base = preset A densité (tools/presets/baseline.json), hunter = archétype de départ.
- J2b : premier item — bouclé. SimStats + SimItem, le pickup se sent.
- J2c : rendu — bouclé. `render_test.tscn`, mode `mix` par défaut, entités toujours en `pixel`. Langage visuel : orange = joueur, rouge DANGER = menace, gris acier = monde.
- J3 : viewer de personnage (8 directions, sliders, export PNG, JSON)
- J4 : contenu — en cours. Brique 1 bouclée : élites avec affixes (blindé / instable / célère, `SimWorld.AFFIXES`), une par vague dès `elite_from_wave`, chaque affixe a un contre que le hunter de départ possède déjà. Brique 2 bouclée et validée en jeu : loot généré (`SimItem.roll` : slot arme / armure / module, rareté série / modifié / relique = 1 / 2 / 3 affixes, paliers T1–T3 à `affix_t1..t3`), sac minimal (`SimWorld.inventory`, cap `inventory_size`, clic ou E ramasse, `equip()` / `drop()` appelés par `src/ui/inventory_panel.gd` via GameState), tables de drop dans le tuning. Les événements émis hors `step()` (UI, harnais) survivent au tick suivant pour que le view les voie. Brique 3 bouclée, à valider en jeu : contrôles ARPG (fenêtres d'attaque windup / hit / recovery par profil, visée aimantée `target_snap_radius`, caméra pitch / taille dans le look). Brique 4a bouclée : `SimCharacter` qui survit aux niveaux, niveaux en JSON (`data/levels/`), hub ↔ strate_01 par `exit` / `descend`, mort en strate → hub. Reste : contenu de zone (4b), paliers, boss, éditeur de zone.
- J5 : coop 1–4
- J6+ : classes 2–3, biomes, saisons

## Rythme de session
- Une session Claude Code = une session de travail. Au démarrage : lire CLAUDE.md et docs/brief.md, `git status` propre, `git pull`.
- Une brique = un commit. Jamais de feature non commitée en fin de session.
- Fin de session : suite headless verte, docs/brief.md et CLAUDE.md à jour, `git push`.
- Si le contexte semble saturé (répétitions, règles oubliées) : commit ce qui est bon et proposer d'arrêter la session.

## Interdits
- Rien de 40K : pas d'aquila, space marines, Emperor, Mechanicus, warp. Ton oui, marques non.
- Pas d'arbre de talents géant : ~8 compétences × 3 modificateurs par classe.
- Pas de code de rendu dans la sim.
