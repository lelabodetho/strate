# STRATE

Hack & slash isométrique, dark sci-fi. Side project. Godot 4.7, Compatibility renderer, export web.

- `CLAUDE.md` — contexte agent (lire en premier)
- `docs/brief.md` — brief complet, décisions, jalons
- `scenes/test/harness.tscn` — arène de tuning : couloir + salle à piliers, vagues de grunts (3, 5, 7… plafond 12), caméra qui suit
- `tools/snap.sh [nom] [frames] [seed] [--flags]` — screenshot + dump d'état pour l'agent. En capture, l'input live est ignoré : `--hold=attack`, `--aim=x,z`, `--move=x,z`, `--dash=t1,t2` scriptent la commande.
- `tools/sim_test.gd` — tests headless de la sim : `godot --headless --path . -s tools/sim_test.gd`
- `tools/out/tuning.json` — valeurs de référence du gameplay, éditées par le panneau in-game (Tab), chargées au démarrage. Flags utiles : `--debug` (rayons au sol), `--panel` (panneau ouvert), `--weapon=brute`, `--preset=nom`.
- `tools/presets/*.json` — presets de tuning nommés, listés dans le panneau. En choisir un l'applique au tuning courant sans toucher `tuning.json` ; « Save as… » en crée un.
- Profils d'arme (touches 1/2/3, `src/sim/weapon_profile.gd`) : hunter (tir), brute (cône 90° à 1,6, fente), technomancer (projectile lent qui explose sur 2 unités). Multiplicateurs sur le tuning courant, pas des classes.
- `tools/export_web.sh` — export web headless

Lancer : ouvrir dans Godot, F5. ZQSD bouge, souris oriente, clic gauche tire, espace dash (i-frames, traverse les ennemis), Tab ouvre le dial de tuning (sim en pause), R rejoue la vague après la mort, N vague suivante, 0 retour vague 1, 1/2/3 profil d'arme.
