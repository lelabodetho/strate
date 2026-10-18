# STRATE

Hack & slash isométrique, dark sci-fi. Side project. Godot 4.7, Compatibility renderer, export web.

- `CLAUDE.md` — contexte agent (lire en premier)
- `docs/brief.md` — brief complet, décisions, jalons
- `scenes/test/harness.tscn` — scène de test (scène principale pour l'instant)
- `tools/snap.sh [nom] [frames] [seed] [--flags]` — screenshot + dump d'état pour l'agent. En capture, l'input live est ignoré : `--hold=attack`, `--aim=x,z`, `--move=x,z`, `--dash=t1,t2` scriptent la commande.
- `tools/sim_test.gd` — tests headless de la sim : `godot --headless --path . -s tools/sim_test.gd`
- `tools/out/tuning.json` — valeurs de référence du gameplay, éditées par le panneau in-game (Tab), chargées au démarrage. Flags utiles : `--debug` (rayons au sol), `--panel` (panneau ouvert).
- `tools/export_web.sh` — export web headless

Lancer : ouvrir dans Godot, F5. ZQSD bouge, souris oriente, clic gauche tire, espace dash (i-frames, traverse les ennemis), Tab ouvre le dial de tuning.
