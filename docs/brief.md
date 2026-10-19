# STRATE — Brief de projet

## Où on en est (19/10/2026)

**État** : jalons 0, 1, 2, 2b, 2c bouclés, jalon 4 entamé (élites avec affixes, loot généré avec slots / rareté / paliers). Arène de vagues jouable au preset par défaut (`tools/presets/default.json`), rendu `mix` avec langage visuel orange = joueur / rouge = menace / couleur par rareté pour le loot. 214 tests headless.

**Prochaine session : jouer.** Valider en jeu les deux briques du jalon 4 (listes « à valider » ci-dessous) avant d'empiler la suite.

**Ensuite** : reste du jalon 4 (paliers de difficulté, boss, éditeur de zone).

**Comment on travaille** : une conversation par session. Ce brief est la source des décisions ; `CLAUDE.md` et `docs/` sont la source pour l'agent. Fin de session = brief à jour.

---

Septembre 2026. Synthèse des pratiques observées chez Thomas Ricouard (Void Explorer, Evergrow), Adam Whitcroft (Tithe), Tom Johnson (Pilgrimage) et Sprite Fusion, et plan de démarrage adapté à un projet perso sans deadline.

---

## 1. Le modèle mental

Le moteur n'est plus le centre, l'agent l'est. Le pipeline type :

```
Brief expérience + références visuelles
        ↓
Agent propose architecture + implémente
        ↓
Harnais : scènes de test, état inspectable, screenshots
        ↓
Humain joue, juge le feel, corrige en langage naturel
        ↓
Outillage maison (éditeurs, viewers) → sorties structurées (JSON) → l'agent ré-ingère
```

Le rôle humain : direction artistique, game design, product owner du pipeline. Les trois créateurs disent la même chose : ils n'auraient pas su résoudre les problèmes techniques, mais ils ont fourni le look et itéré sur le flow jusqu'à ce que ce soit juste.

---

## 2. Mapping des couches

### 2.1 Harnais agentique

| Option | Note |
|---|---|
| **Claude Code** | Déjà dans ta stack. Terminal, navigateur via Chrome, MCP. Fait la même boucle que Codex. |
| **Codex + GPT-6 Astra** | Ce que les showcases utilisent cette semaine. Sessions longues (12h+), Blender intégré, audio via API. |
| Cursor | Bien pour l'édition ponctuelle, moins pour les sessions longues autonomes. |

Ce qui compte : sessions longues, accès terminal + navigateur, capacité à tester seul. Le modèle est secondaire par rapport au harnais et aux outils branchés. Commence avec ce que tu maîtrises.

### 2.2 Moteur

| Moteur | Pour | Contre | Verdict |
|---|---|---|---|
| **Web natif** (TS + Three.js / canvas) | Agent 100 % à l'aise, tests Playwright, déploiement en un lien, ta stack | Pas de moteur : physique, UI, save à construire | Voie de moindre friction. Ricouard, Johnson. |
| **Godot 4** | Moteur complet, gratuit, open source. Scènes `.tscn` et scripts GDScript en texte, `--headless` en CLI, export web. MCP Godot communautaires. | Courbe d'apprentissage de l'éditeur, agent moins chez lui qu'en web | Meilleur compromis « vrai moteur ». Whitcroft. |
| Unity 6 | Unity CLI (juillet 2026) laisse les agents piloter l'éditeur, Play Mode, builds. Unity AI en beta. | Lourd, C#, écosystème pro | Seulement si cible mobile/console. |
| Unreal | AAA | Visuel, pas textuel, lourd | Non. |
| Rétro (GBA, Pico-8) | Contraintes créatives fortes, charme immédiat | Cul-de-sac technique | Projet-jouet d'un week-end. |

**Recommandation** : web natif si tu veux tout contrôler et rester sur ta stack ; Godot si tu veux un moteur qui gère physique/UI/scènes pour toi. Les deux exportent navigateur.

### 2.3 Assets visuels — cinq voies

| Voie | Principe | Force | Faiblesse | Qui |
|---|---|---|---|---|
| **A. Génération d'images** | Prompt → PNG (GPT Image, Midjourney, Flux) | Rapide, concept art, moodboard | Incohérence entre assets, animation impossible | Tous, pour le concept art uniquement |
| **B. Générateur de sprites par API** | Sprite Fusion et équivalents, appelés par l'agent dans le pipeline | Pixel art cohérent, poses et animations | Style contraint par l'outil | Sprite Fusion (GBA Bowman) |
| **C. Procédural pur en code** | L'agent écrit un moteur de dessin | Cohérence totale, paramétrable | Gros investissement initial, style « dessiné en code » | Ricouard (Evergrow, Hollowflux) |
| **D. 3D low-poly → rendu pixel** | Primitives 3D, rig, 8 directions, pixellisation | Cohérence + identité forte, l'agent est bon en géométrie | Pipeline à construire (mais réutilisable) | Johnson (offline, spritesheets), Whitcroft (temps réel, shader) |
| **E. 3D via Blender** | Concept image → géométrie dans Blender → rig → export | Assets 3D réutilisables | Premier jet à retoucher | Ricouard (vaisseau, bateau) |

**Le pattern gagnant** : hybride. Environnement procédural + quelques assets auteur. Voie D pour les personnages si tu vises du pixel art avec une vraie DA.

Détail de la chaîne Johnson (voie D offline) :
`rig de primitives Three.js → rotation 8 directions → capture → colorisation → pixellisation → passe de profondeur → ombres → spritesheet`
Résultat : 311k sprites, l'agent one-shot un nouveau modèle une fois les règles posées.

### 2.4 Audio

- Musique : décrire ambiance, instruments, contraintes (durée, boucle sans couture). Whitcroft : 9 itérations pour la bonne. Passe par un service audio branché à l'agent (ElevenLabs, Suno ou équivalent).
- SFX : même logique, plus dur à rendre cohérent. Alternatives : jsfxr / sfxr pour du rétro procédural, Freesound + traitement.
- Bruitages procéduraux en code (Web Audio API) : cohérent avec la voie C.

### 2.5 Outillage jetable

C'est le vrai différenciateur et ton terrain naturel. Trois familles :

| Famille | Exemples | Rôle |
|---|---|---|
| **Éditeurs visuels** | Rigging editor (Johnson), motion & equipment editor (Ricouard), sprite editor | Régler à l'œil ce qu'on ne règle pas en prompt |
| **Harnais de test** | Scènes nommées, `window.__GAME__` pour inspecter l'état, screenshots Playwright, compteurs de perf | Permettre à l'agent d'observer et vérifier seul |
| **Audits de données** | Cohérence des items, équilibrage, listing d'assets | Garder le contrôle à l'échelle |

**Architecture clé** : l'éditeur produit du JSON, l'agent ré-ingère le JSON. L'humain ne touche jamais au code de rendu.

### 2.6 Direction artistique pour agent

Deux approches observées :

- **Règles dans le prompt** (Whitcroft) : bibliothèque de références « look and feel » (vieilles illustrations, parchemins, UI de jeux) + un prompt massif qui évolue à chaque correction. Marche, mais « still loads of misses ».
- **Règles dans le code** (Johnson) : palette, proportions, passes de rendu encodées dans le pipeline. L'agent ne peut plus dévier. Passe mieux à l'échelle.

Le concept art (voie A) sert dans les deux cas à fixer la cible visuelle avant de construire. Ricouard : les premières images étaient trop réalistes, puis trop simples ; il a corrigé jusqu'à avoir des références par situation (orbite, vitesse, entrée atmosphérique, atterrissage).

### 2.7 Distribution

- Web : Vercel, Netlify, GitHub Pages, ou Sites (Codex). Un lien, zéro install.
- itch.io pour le côté « jeu » et le retour de la communauté.
- Godot export web → même chose.

---

## 3. Les pièges

- **Trop grand** : ton passé MMO pousse vers le multi et le vaste. Le netcode reste le mur. Solo, une zone, une boucle.
- **Trop d'assets trop tôt** : construire des outils avant d'avoir un jeu jouable. Le jouable moche d'abord.
- **Soupe visuelle** : générer des images une par une. Choisir sa voie d'assets avant de produire.
- **Agent aveugle** : demander des corrections sans harnais. L'agent doit pouvoir voir et mesurer.
- **Le projet meurt sans cadence** : une session par semaine, même d'une heure, vaut plus qu'un sprint de trois week-ends.

---

## 4. Plan de démarrage

Découpé en jalons, pas en semaines. Chaque jalon tient en quelques sessions.

### Jalon 0 — Décisions (mis à jour 18/10/2026)

**Concept**
> Tu incarnes un aventurier dans un monde ouvert découpé en zones, avec un village-hub où tu reviens entre deux sorties. Tu explores, tu farmes des packs, tu descends dans des donjons où le loot et les boss te font grimper en puissance, et tu choisis toi-même jusqu'où pousser la difficulté. Rien ne se perd : ton perso, ton stuff, ta stash et ta collection restent, et chaque nouveau perso hérite du monde que tu as construit.

Accroche : *un MMO sans les autres.* Dark sci-fi grimdark isométrique, univers original. Hack & slash inspiré Diablo 3/4, Grim Dawn, PoE, avec les mécaniques MMO (Dofus, Flyff) qui comptent : farming, loot, scaling, boutique cosmétique, paliers de difficulté, mécaniques de boss, alts.

**Décisions prises**
- [x] Contrôle : ZQSD + souris (attaques orientées souris, dash obligatoire).
- [x] Monde : zones persistantes faites main + hub + donjons (générés, seedés).
- [x] Mort : softcore, tout reste. Respawn au hub avec une taxe.
- [x] Moteur : Godot 4 (navmesh, physique, scènes, export web, API multijoueur haut niveau).
- [x] Assets : voie D temps réel — 3D low-poly + shader de rendu en post-process. Le filtre final (dither, pixel, ASCII) est interchangeable et se décide en dernier.
- [x] Multijoueur : solo d'abord, **coop 1–4 anticipée dans l'architecture** (voir jalon 1 et jalon 5). Jamais MMO.
- [x] « Cash shop » solo = monnaie premium farmable, cosmétiques, pets, progression de compte.
- [x] Une seule mécanique à rendre bonne : tirer + esquiver dans un couloir avec 3 ennemis.
- [x] Harnais : Claude Code.
- [x] Moodboard — grille en six cases :

| Case | Question | Refs posées |
|---|---|---|
| Univers et ton | **Tranché : dark sci-fi grimdark, gothique industriel, fatalisme. Univers original, pas 40K.** | Ton : Warhammer 40K, StarCraft (inspiration de ton, jamais de marques). Darktide (ruches, échelle). Signalis (horreur froide). Tithe (identité forte), Senje (ruines) |
| Caméra et lisibilité | Angle iso, échelle du perso, densité | **The Ascent** (twin-stick iso), Tithe, Senje |
| Ambiance et lumière | Lumière industrielle, écrans, fumée, signal dégradé | Darktide, Signalis, Senje |
| Boss et combat | Télégraphie, phases, feel. **Tir orienté souris par défaut, mêlée comme classe.** | The Ascent, Senje (dragon), D4, Grim Dawn |
| UI et loot | Inventaire, tooltips, affixes, hub | **Moonlighter** (flat, panneaux arrondis, accent unique), **Hades** (matière minimale, losanges, or), D4 (paper doll centrale, bordures de rareté), Dofus (tooltip structuré +/-), Grim Dawn / D2 (grille Tetris, ornementé — à éviter en chrome) |
| Rendu | Pixel dense / dither / mélange | Ouvert. Candidats : pixel dense sans dither (Dead Cells, Moonlighter en densité) ; dither sur 3D (Tithe). Se tranche sur une scène de test, pas sur des refs. |

**Règles UI (posées le 18/10/2026)**
1. Paper doll centrale, slots d'équipement autour, perso qui reflète le stuff en temps réel — c'est ce qui fait tenir skins et boutique cosmétique.
2. Rareté en couleur + lumière, jamais en texte seul. Cinq paliers max. Avec le rendu 3D, le glow d'un légendaire au sol est une vraie lumière dynamique.
3. Tooltip d'item structuré : nom, rareté, stats principales en gros, affixes en vert/rouge, une ligne de flavor. C'est l'écran le plus lu du jeu.
4. Une seule famille typographique, une couleur d'accent, le reste neutre. L'ornement vient des items et du perso, pas du chrome.
5. Panneaux ouverts sur le monde : le jeu reste visible derrière l'inventaire.
6. HUD in-game minimal : vie, ressource, barre de skills, mini-map.
7. Grille d'inventaire : slots uniformes (D4, Dofus, Moonlighter) par défaut ; la grille Tetris (D2, Grim Dawn) est plus riche mais coûte un asset dimensionné par item — à ne reconsidérer qu'après le jalon 4.

**Univers — STRATE (piste posée le 18/10/2026, ajustable)**

- **Le monde.** Une cité verticale bâtie dans la carcasse d'une arche échouée il y a si longtemps que personne ne sait plus que c'était un vaisseau. Les ponts sont devenus des strates, chacune avec sa faction, son culte, ses lois. Les strates hautes vivent de ce qu'on remonte d'en bas.
- **Pourquoi on descend.** Tout ce qui a de la valeur vient des profondeurs : métal, machines, savoir, reliques. Descendre est un métier. Tu es un descendeur, mandaté par une faction ou par personne.
- **La menace.** La ville s'enfonce, lentement, mesurablement, sans que personne ne sache pourquoi ni comment l'arrêter. Les strates basses sont perdues une à une.
- **Pas de méchant.** Ennemis : descendeurs d'autres factions, habitants des strates abandonnées qui refusent de partir, machines du vaisseau qui font encore leur travail, ce qui vit là où personne n'est allé. Chacun a ses raisons. Conflits d'intérêts, jamais bien contre mal.

Ce que ça donne au jeu : hub = ta strate ; zones persistantes = strates connues et cartographiées ; donjons = strates basses perdues, générées ; difficulté = profondeur ; factions = levier pour cosmétiques (couleurs, insignes) et classes (le culte de la machine est une faction) ; fatalisme = tu ne sauves pas la ville, tu tiens une saison de plus.

**Direction artistique (posée le 18/10/2026)**

Ton : grimdark, gothique industriel, fatalisme. Univers **original** avec son propre nom et sa propre cosmogonie dès le départ — inspiration de ton et de structure visuelle (40K, StarCraft), jamais de marques, d'iconographie ni de vocabulaire propriétaire.

Conséquences :
- **Rendu** : le dither / scanline devient diégétique (écrans cathodiques, grain, signal dégradé). Le filtre est une partie du monde, pas un style posé dessus. Candidat favori : dither bichrome gris + accent.
- **Palette** : noirs, gris acier, rouille ; un accent chaud (orange/rouge) ou froid (cyan). À trancher sur la scène de test.
- **Combat** : tir orienté souris par défaut (twin-stick iso à la The Ascent), le mêlée est une classe. Lisibilité iso plus simple, mécaniques de boss (zones, télégraphie, adds) naturelles.
- **Loot** : armes, armures, implants, modules, munitions. Vocabulaire technique (cadence, pénétration, surchauffe) qui se lit bien en UI terminal.
- **Cosmétiques** : peintures d'armure, drones-pets, effets d'arme.
- **Monde** : intérieurs modulaires (ruches, vaisseaux abandonnés, stations, raffineries) — kit de pièces en 3D low-poly, bien plus simple à produire qu'un extérieur organique. Hub : un vaisseau ou un avant-poste.
- **UI** : terminal / militaire net (StarCraft 2) + HUD diégétique possible (Dead Space). Reste dans les règles UI ci-dessus.
- **Inquisitor – Martyr** (ARPG iso 40K) est le jeu le plus proche en structure : à étudier pour ses erreurs autant que pour ses réussites.

**Game design — backlog trié (18/10/2026)**

*Archétypes (3, un seul construit au départ : le tireur)*

| Archétype | Version grimdark sci-fi | Rôle mécanique |
|---|---|---|
| Mêlée | Brute augmentée, exosquelette, armes lourdes à percussion | Encaisse, contrôle l'espace, risque/récompense au contact |
| Distance | Chasseur : fusils longs, drones, mines, pièges | Kite, précision, gestion de la distance |
| Casteur | Technomancien d'un culte de la machine original (ton Adeptus Mechanicus, pas lui) : sceptres, tourelles, champs, surchauffe comme ressource ; peut soigner / réparer | Zones, contrôle, soutien |

*Compétences* : pas d'arbre géant. ~8 compétences par classe, chacune avec ~3 modificateurs. Les builds naissent des modificateurs + du stuff + du style de jeu, pas du nombre de sorts.

*Rythme (tranché)* : **densité pour le trash, mécanique pour ce qui compte.** Les packs explosent (D4), les élites et les boss forcent à lire, bouger, esquiver (Hades / The Ascent). Difficulté mécanique, jamais du stat-check pur.

*Tiroir 1 — Cœur (jalons 1–2)*
- ZQSD + visée souris, dash avec i-frames
- Le tireur, une arme, 2–3 compétences actives
- Un couloir, 3–5 ennemis faibles
- Le loot tombe, se ramasse, change une stat visible

*Tiroir 2 — Profondeur (jalons 3–4)*
- Élites avec affixes (bouclier, vitesse, explosion à la mort…) et table de loot dédiée
- Modificateurs de compétences
- Paliers de difficulté
- Boss à mécaniques lisibles

*Tiroir 3 — Rêves (jalon 6+)*
- Mobilité avancée (monture, jetpack, mini-vaisseau) — se décide avant le level design des zones, s'implémente après
- Classes 2 et 3
- Saisons perso, ladder, coop (jalon 5)

**Référence structurelle** : Moonlighter prouve que hub + donjons générés + loot ramené + progression de compte tient en solo avec un contenu tenable pour une petite équipe.

**Piliers**
1. Chaque run te rend plus fort, visiblement.
2. Le loot raconte une histoire (affixes lisibles, drops qui changent un build).
3. Le monde persiste même quand le perso meurt ou change.
4. La difficulté est un choix (paliers), pas un mur.

**Couches, dans l'ordre**

| Couche | Contenu | Jalon |
|---|---|---|
| Boucle | 1 classe, 1 donjon généré, packs, loot, retour au hub | 1–2 |
| Scaling | Stats, affixes, niveaux, paliers | 2 |
| Boss | 1 boss, 2–3 mécaniques lisibles | 3 |
| Compte | Stash, monnaie premium, cosmétiques, pets, alts | 4 |
| Coop | Lobby, 1–4 joueurs, persistance par perso | 5 |
| Expansion | Classes 2–3, biomes, saisons perso, ladder | 6+ |

### Jalon 1 — Squelette + harnais

- [x] Repo, stack, un écran qui affiche un rectangle qui bouge.
- [x] État du jeu exposé (autoload `GameState`) pour inspection.
- [x] Une scène de test nommée (`scenes/test/harness.tscn`), un script qui charge + screenshot (`tools/snap.sh`).
- [ ] Déploiement web automatique à chaque push.

**Contraintes d'architecture coop-ready (à poser dès maintenant, pas à implémenter)**
- Simulation séparée du rendu : positions, dégâts, loot, état des monstres vivent dans une couche sans dépendance à l'affichage. Le rendu observe.
- Tout passe par des commandes (`move`, `attack`, `dash`) que la simulation consomme ; jamais d'action directe depuis l'input.
- Génération seedée : un donjon = une seed, reproductible.
- ID stable sur chaque entité, item, monstre ; pas de référence directe entre objets.
- Persistance par perso, pas par partie : le perso, son stuff et son compte sont transportables dans la partie d'un autre.

Critère de sortie : l'agent peut lancer le jeu, prendre une capture, lire l'état, sans toi.

### Jalon 2 — La mécanique (bouclé le 18/10/2026)

- [x] Couloir 6×24 + salle 16×20 avec piliers, grunts (chase / windup / recover), tir, dash avec i-frames traversant, knockback, stagger.
- [x] Events de sim consommés par le view (hit, kill, dodge, impact, swing, explosion, stagger, wave_cleared).
- [x] Dial de tuning (Tab) : 24 sliders, presets dans `tools/presets/`, Save as, pause pendant le réglage.
- [x] Arène de vagues : R relance la vague, N suivante, 0 retour, tuning conservé.
- [x] Trois profils d'arme (1/2/3) : hunter (tir), brute (cône + fente + i-frames + armure), technomancer (projectile lent explosif). Profils = multiplicateurs sur le tuning, sauf cadence et vitesse de projectile qui sont absolues par profil.
- [x] Murs fantômes (segments entre caméra et joueur à 25 %).
- [x] Mort du joueur, R pour recommencer.

**Ce que le jeu a appris (session de tuning du 18/10)**
- Base retenue : preset **A densité** (`tools/presets/baseline.json`), `proj_speed` 16. Les packs tombent vite, la menace vient du nombre.
- `grunt_aggro` 10–14 : le joueur choisit quand le combat commence. Pilier confirmé. À étendre en aggro de groupe + perte d'aggro (jalon 4).
- **Hunter = archétype de départ**, confirmé en jeu. Technomancien fun. Brute injouable sans stagger / armure ; à réévaluer après ces ajouts, sinon elle attend le jalon 4.
- Les projectiles partaient trop vite : voir la balle voyager donne du poids.
- **Starter ARPG, pas roguelike (tranché le 18/10 au soir).** Le preset A avec cadence 0,12 et déplacement libre réglait un twin-stick (Isaac, Gungeon) : la puissance dans le joueur. Strate est un ARPG : la puissance est dans le build. Le starter est **faible mais satisfaisant** — cadence lente, coup lourd, projectile visible, déplacement ralenti pendant l'attaque (`attack_move_mult`), mono-cible. Tout ce qui rend nerveux (cadence, perforation, AoE large, vitesse) s'acquiert par items et compétences. Preset `E_starter_arpg` à valider ; dès validé, le **premier item de croissance** (+30 % cadence ou +1 perforation) passe en tête du jalon 4, avant les élites : c'est le vrai test du feel.
- Règle de design : les multiplicateurs de profil s'appliquent aux stats de corps et de dégâts, jamais aux identités d'arme (cadence, vitesse de projectile).

### Jalon 2b — Premier item (bouclé le 19/10/2026)

- [x] `SimStats` : modificateurs `{source, stat, mult, pct, flat}`, formule `tuning × Π mult × (1 + Σ pct) + Σ flat`. Profils d'arme en `mult`, items en `pct`. Le monde ne lit plus le tuning du joueur que via `player_stats.value()`.
- [x] `SimItem` « servo-gâchette » +30 % cadence, 20 % de drop (tuning `item_drop_chance`), ramassage au contact, HUD empilé, octaèdre orange avec halo et lumière au sol. R garde les items, 0 les retire.
- [x] **Verdict en jeu : le pickup se sent.** Fondation ARPG validée.

Retenir pour le système de loot (jalon 4) : l'empilement linéaire (+30 % × n) ramène au twin-stick en quelques vagues → slots + rendements décroissants + affixes à +5/+8/+12 %. Additif entre affixes de même type, multiplicatif entre catégories.

### Jalon 2c — Rendu (bouclé le 19/10/2026)

**DA tranchée : low-poly flat-shaded comme source** (refs dans `docs/da/`), post-process par-dessus.

- [x] `scenes/test/render_test.tscn` : deux SubViewports à 1/2 résolution (monde / entités, mondes 3D séparés — Compatibility ne gère pas les masques de couche par caméra), shader `src/view/post_filter.gdshader` avec modes `pixel` / `dither` / `mix` (touche F, sélecteur et slider dither dans le panneau). Omni chaude qui suit le joueur, deux omnis froides fixes, ombres.
- [x] **Mode par défaut : `mix`**. Les entités de gameplay sont toujours en `pixel`. `dither` pur gardé comme variante pour les strates profondes.
- [x] **Langage visuel posé** : orange = joueur et ce qui est à lui ; **rouge franc = menace** (`DANGER`, hors rampe accent) ; gris acier = monde. La rareté du loot aura ses propres couleurs.

Fait le 19/10 : `.gdignore` sur `tools/out/`, la référence est `tools/presets/default.json` (preset F). Les entités ne projettent pas d'ombre sur le sol du monde (mondes séparés) — acceptable.

### Jalon 3 — Le viewer d'assets

- [ ] Un personnage, une pose, huit directions, sliders de proportions, export PNG.
- [ ] Palette et proportions verrouillées dans le code.
- [ ] Sorties en JSON ré-ingérables par l'agent.

Critère de sortie : l'agent produit un nouveau personnage cohérent en un prompt.

### Jalon 4 — Élites (première brique, bouclée le 19/10/2026)

Une élite est un grunt qui change la règle d'engagement. Règle posée : **chaque affixe a un contre que le hunter de départ possède déjà** (placement, dash, distance), jamais un stat-check.

- [x] Sim : `SimEntity.elite / affixes / fuse_t`, une élite par vague dès `elite_from_wave` (2), à la tête d'un pack seedé, tirée après le placement (activer ou couper les élites ne déplace aucun grunt de la vague). Corps × 1,2, PV × 3, dégâts × 1,5. Un affixe, deux distincts à partir de la vague 5. Les élites lâchent toujours un item.
- [x] **blindé** : les coups frontaux (cône de 120°) perdent 70 % de dégâts et de recul, événement `blocked`. Contre : flanquer.
- [x] **instable** : le cadavre explose après 0,6 s (rayon 2, dégâts grunt × 2, recul), joueur et grunts compris, i-frames respectées. Contre : reculer ou dasher à travers. Tuée dans son pack, l'élite devient un outil.
- [x] **célère** : poursuite à 1,6× la vitesse, retour au spawn inchangé. Contre : la distance, le dash.
- [x] View : corps plus grand et plus sombre, anneau rouge DANGER au sol, plaque acier devant le blindé, pulsation rouge de l'instable, corps fin et haut du célère ; disque rouge qui grandit pendant la mèche, flash du blast, flash bleu acier sur un coup bloqué. HUD : ligne « ÉLITE · blindé · 59/72 PV ». Harnais : `--elite=x,z[,affixe,...]`.
- [x] 29 checks headless de plus (171 au total).

À valider en jeu : la mèche de 0,6 s laisse-t-elle le temps de reculer sans dash ; le cône de 120° force-t-il vraiment le flanc avec une cadence de 0,45 s ; l'élite célère est-elle lisible quand elle sort d'un pack ; le blast dans le pack est-il un plaisir ou un piège (il tue les packmates mais aussi le joueur collé). Décider si l'élite doit passer devant son pack (aujourd'hui c'est le premier grunt placé, sans comportement de leader).

### Jalon 4 — Loot (deuxième brique, bouclée le 19/10/2026)

Un item doit changer un **breakpoint**, pas une moyenne : 22 dégâts contre 80 PV = 4 tirs, et seul un affixe dégâts T3 (+25 %) passe à 3 ; un T2 (+15 %) reste à 4. Tout le système est dimensionné sur cette règle.

- [x] `SimItem` généré (`roll`, seedé) : slot **arme / armure / module**, rareté **série / modifié / relique** = 1 / 2 / 3 affixes distincts tirés dans le pool du slot, chaque affixe à un palier T1 / T2 / T3 (tiré 50 / 35 / 15 %) valant `affix_t1..t3` = +8 / +15 / +25 %. Les stats « moins c'est mieux » (recharge du dash, dégâts subis) sont tirées en négatif.
- [x] Pools : arme = cadence, dégâts, recul, vitesse de tir ; armure = PV, dégâts subis, vitesse ; module = cadence, dégâts, recharge du dash, vitesse. Même stat sur deux slots = additif (arme T1 + module T1 cadence = +16 %) ; cadence × dégâts se multiplient dans le temps de kill.
- [x] **Équipement par swap**, pas d'inventaire : marcher sur un item l'équipe, l'ancien du slot tombe aux pieds du joueur (même id, mêmes affixes) et reste inerte tant qu'on n'en est pas sorti. La décision se prend avant de poser le pied, grâce à la ligne « Au sol : … » du HUD (3 u). R garde l'équipement, 0 le lâche.
- [x] Tables de drop dans le tuning : trash `item_drop_chance` 20 %, modifié à `drop_rare_chance` 20 % sinon série ; élite toujours, relique à `elite_drop_epic_chance` 30 % sinon modifié ; slot uniforme. Tous les tirages passent par le rng du monde et sont toujours tirés (l'item lui-même sur un sous-rng seedé par le monde) : activer ou couper le loot ne déplace aucun grunt.
- [x] View : couleur par rareté — série blanc acier, modifié cyan froid (0.4, 0.8, 0.9), relique orange avec lampe plus forte et halo plus large. Jamais de rouge (réservé à la menace). HUD : une ligne par slot dans la couleur de la rareté (« Arme · modifié · cadence +15 % · dégâts +8 % »), « Arme · — » grisé quand vide. Harnais : `--drop=x,z[,rareté[,slot]]`, `--drop2=…`.
- [x] 22 checks de plus (214 au total) : roll seedé, breakpoint 3 / 4 tirs, swap et empilement, tables de drop sur 200 trash et 50 élites, persistance R / N / 0.

À valider en jeu : le swap sans confirmation — perd-on un bon item en marchant dessus par accident (si oui : ramassage sur touche, ou l'item ne s'équipe que s'il est meilleur) ; les +8 % se sentent-ils ou faut-il attendre un T2 ; la ligne « Au sol » suffit-elle pour lire un item à distance, ou faut-il un tooltip au-dessus de l'item ; la part de reliques (30 % par élite, une élite toutes les 2 vagues) est-elle assez rare pour compter ; recul et vitesse de tir sont-ils des affixes morts à côté de cadence et dégâts (si oui, leur donner un effet : perforation, portée) ; faut-il une rareté au-dessus de relique avant les boss ou plutôt un affixe à effet (jalon 4, suite).

### Jalon 4 — Contenu

Seulement maintenant : items, ennemis, zone, musique. C'est là que « prendre le temps de concevoir items, gameplay, assets » commence vraiment.

Deuxième outil maison à construire ici : un **éditeur de zone** (tilemap 3D + props + spawns, sortie JSON), parce que les zones faites main sont ce que l'agent fait le moins bien seul.

### Jalon 5 — Coop 1–4

Jalon à part entière, le plus technique du projet : les bugs réseau ne se voient pas en screenshot.

- [ ] Transport : API multijoueur haut niveau de Godot (réplication de scènes), relais ou Steam pour traverser les NAT.
- [ ] Lobby : créer / rejoindre une partie, chaque joueur amène son perso.
- [ ] Synchronisation des commandes et des animations.
- [ ] Scaling de la difficulté selon le nombre de joueurs.
- [ ] Règle de loot : partagé ou instancié.

Critère de sortie : deux instances du jeu, deux persos, un donjon seedé, un boss tué ensemble.

---

## 5. Références

- Ricouard, *Building games with Astra* — developers.openai.com/blog/how-to-build-games-with-astra
- Sprite Fusion, *Making a GBA game with GPT-6 Astra* — spritefusion.com/blog
- Unity, *Meet the Unity CLI* — unity.com/blog/meet-the-unity-cli
- Johnson, Pilgrimage assets — pilgrimagegame.com/assets
- @AdamWhitcroft, @tomjohndesign, @Dimillian, @Ansenjeo (Senje, MMORPG ASCII — 3D + convertisseur shader → ASCII) sur X
