# Greybox Kit — tester un concept de jeu en une session

Ce repo contient deux choses : **Strate** (le contenu) et **un kit de greybox** (l'outillage) dans lequel Strate est le premier jeu. Le kit est pensé pour être extrait et réutilisé sur n'importe quel autre concept : on vide la sim, on garde le reste.

Principe : le feel d'un jeu vit dans les nombres (vitesses, timings, distances, hitbox), pas dans les pixels. On règle les nombres avec des boîtes, parce qu'une boîte se change en dix secondes. On n'investit dans l'art, le son ou le contenu que sur un gameplay validé en greybox.

## Ce qui compose le kit

| Couche | Fichiers | Rôle | Réutilisable tel quel ? |
|---|---|---|---|
| **Simulation pure** | `src/sim/world.gd`, `entity.gd`, `command.gd`, `level.gd`, `projectile.gd`, `weapon_profile.gd`, `stats.gd`, `item.gd` | L'état du jeu et sa règle d'évolution `step(dt, cmd)`. Aucune dépendance à Node, Input ou Rendering. Déterministe à seed et commandes égales. Émet des `events` par tick. | Le **pattern** oui (RefCounted, step, events, IDs, seed). Le contenu (grunts, projectiles) est spécifique à Strate. |
| **Tuning** | `src/sim/tuning.gd`, `tools/presets/*.json`, `tools/presets/default.json` | Toutes les constantes de gameplay dans un objet avec une table de specs (min, max, pas). Presets nommés, fichier de référence chargé au démarrage. | Oui. On change la liste des specs. |
| **Input → Command** | `src/input/player_input.gd` | Transforme Input en un `Command` par tick. Jamais d'action directe sur le monde. C'est ce qui rend la sim testable sans fenêtre et prête pour le réseau. | Oui. |
| **View** | `src/view/world_view.gd`, `entity_view.gd`, `level_view.gd` | Lit l'état et les events, affiche. N'écrit jamais dans la sim. Cubes, couleurs plates, flashs sur events. | Le pattern oui ; les primitives sont génériques. |
| **GameState (autoload)** | `src/game_state.gd` | Tient la sim, la fait avancer, pause, restart, vagues. Sert le harnais via flags CLI. | Oui, quasi tel quel. |
| **Harnais de capture** | `tools/snap.sh`, flags `--screenshot --state --frames --seed --move --level --aim --target --hold --dash --pickup --click --drop --grunt --elite --weapon --preset --debug --panel` | Lance la scène, joue des commandes scriptées, capture PNG + JSON du même tick, quitte. Permet à l'agent de voir et mesurer seul. | Oui. |
| **Tests headless** | `tools/sim_test.gd` (`godot --headless -s`) | Vérifications sur la sim sans fenêtre : collisions, i-frames, déterminisme, round-trip du tuning. | Le runner oui ; les tests sont à réécrire par jeu. |
| **Dial de tuning** | `src/ui/tuning_panel.gd` (Tab) | Un slider par spec, presets, Save / Save as / Load / Defaults, pause de la sim pendant le réglage. | Oui. |
| **Arène** | `scenes/test/harness.tscn`, `harness.gd`, `src/ui/hud.gd` | Scène de test : niveau en boîtes, caméra iso, vagues (R même vague, N suivante, 0 reset), HUD minimal, `--debug` dessine les hitbox. | La scène oui ; la géométrie et les vagues sont du contenu. |
| **Scène de rendu** | `scenes/test/render_test.tscn`, `render_test.gd`, `src/view/post_filter.gdshader` | Même sim, même input, rendu en basse résolution (SubViewports 1/2, nearest) avec un filtre canvas à trois modes (F). Les entités ont leur propre viewport et restent en pixel ; une copie du niveau en couleur-clé leur donne l'occlusion. Lampes avec ombres. Le look (filtre, échelle, lampes) est un objet `Look` sauvé en `tools/presets/look_<nom>.json`, édité depuis le panneau. | Le montage oui ; la palette du shader est du contenu. |
| **Export web** | `tools/export_web.sh`, `.github/workflows/deploy-web.yml` | Build headless et déploiement Pages. | Oui. |

## La boucle d'une session de test

1. **Décrire** le concept à l'agent en langage joueur (« des ennemis qui sautent sur toi », « un dash qui laisse une traînée qui brûle »).
2. L'agent l'ajoute **dans la sim**, avec ses paramètres dans le tuning et ses events. Le view reçoit le strict minimum pour voir (une couleur, un flash).
3. `tools/snap.sh` après chaque étape : l'agent regarde la capture et lit l'état avant de dire « c'est fait ».
4. **Jouer**. Tab, régler, rejouer. Pousser chaque valeur trop loin dans les deux sens avant de la poser.
5. **Trancher** en langage joueur : ce qui a plu, ce qui a frustré, une phrase. Sauver le preset si c'est mieux qu'avant.
6. Commit. Un concept, un commit.

Verdict en 30 secondes de jeu ou on jette : si ce n'est pas fun avec des cubes, l'art ne le sauvera pas.

## Règles qui font tenir le kit

- Sim sans Node. Si un fichier de `src/sim/` importe Input, Mesh ou get_tree, c'est une faute.
- Tout passe par `Command`. Pas d'input qui touche le monde.
- Les multiplicateurs (profils, items, buffs) s'appliquent sur les valeurs du tuning, via `SimStats` : `tuning × Π mult × (1 + Σ pct) + Σ flat`. Les profils d'arme sont des `mult` (source `weapon`), les items des `pct` additifs (source = id de l'item, un item équipé par slot dans `SimWorld.equipped`). Le monde ne lit jamais le tuning directement pour le joueur.
- Les valeurs de référence vivent dans `tools/presets/default.json`, jamais en dur dans le code ; les défauts de `SimTuning` sont la fixture des tests.
- Une feature n'est terminée qu'avec sa capture et ses tests headless.
- Le view consomme les events une fois par tick de sim, jamais par frame.

## Réutiliser le kit sur un autre jeu

1. Copier le repo, supprimer `docs/brief.md` et le contenu de `src/sim/` sauf `command.gd`, `tuning.gd` et le squelette de `world.gd` (`step`, `events`, `spawn`, `to_dict`, rng seedée).
2. Garder tels quels : `game_state.gd`, `player_input.gd`, `tools/`, `tuning_panel.gd`, `hud.gd`, `harness.tscn`, le workflow.
3. Réécrire les specs de `tuning.gd` et les tests de `sim_test.gd` pour le nouveau concept.
4. Nouveau `CLAUDE.md` : concept, piliers, feel, et pointer vers ce fichier.
5. Premier prompt : « Lis CLAUDE.md et docs/greybox-kit.md. Mets un rectangle qui bouge dans l'arène et lance tools/snap.sh. »

Pour la 2D, le kit tient aussi : la sim ne sait pas en combien de dimensions elle est rendue. Seuls `*_view.gd` et la caméra changent.

## Pistes d'outils supplémentaires (à construire quand le besoin arrive)

- Éditeur de niveau greybox : boîtes, spawns, export JSON, chargé par `SimLevel`.
- Replay : enregistrer les `Command` par tick dans un fichier, rejouer à l'identique. Gratuit avec cette architecture, précieux pour reproduire un bug ou comparer deux tunings sur la même partie.
- Metrics : temps par kill, coups pris par vague, distance parcourue, exportés dans le JSON de capture.
