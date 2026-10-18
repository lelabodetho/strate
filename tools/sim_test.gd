extends SceneTree
## Headless checks on the pure simulation. No window, no view.
## Run: godot --headless --path . -s tools/sim_test.gd

const DT := 1.0 / 60.0
var failures := 0

func _init() -> void:
	test_corridor_walls_block_player()
	test_grunt_chases_and_hits()
	test_dash_through_grunt()
	test_events_and_knockback()
	test_hit_radius()
	test_projectile_kills_grunt()
	test_determinism()
	test_tuning_roundtrip()
	print("[sim_test] ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("[sim_test] FAIL: " + msg)
	else:
		print("[sim_test] ok: " + msg)

func cmd(move := Vector2.ZERO, aim := Vector2(0, -20), attack := false, dash := false) -> Command:
	var c := Command.new()
	c.move = move
	c.aim = aim
	c.attack = attack
	c.dash = dash
	return c

func run(w: SimWorld, seconds: float, c: Command) -> void:
	for i in int(round(seconds / DT)):
		w.step(DT, c)

func test_corridor_walls_block_player() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	run(w, 3.0, cmd(Vector2(1, 0)))
	check(p.pos.x <= 3.0 - p.radius + 0.001, "player stopped by east wall at x=%.2f" % p.pos.x)
	run(w, 6.0, cmd(Vector2(0, 1)))
	check(p.pos.y <= 12.0 - p.radius + 0.001, "player stopped by near wall at z=%.2f" % p.pos.y)

func test_grunt_chases_and_hits() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 0))
	run(w, 1.0, cmd())
	check(g.state == &"chase" and g.pos.y > 0.5, "grunt chases (state=%s z=%.2f)" % [g.state, g.pos.y])
	run(w, 4.0, cmd())
	check(w.stats.hits_taken >= 1 and p.hp < p.hp_max, "grunt hits at contact (hp=%.0f hits=%d)" % [p.hp, w.stats.hits_taken])

func test_dash_through_grunt() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 7.8))   # already at contact, down the corridor
	# Step until the grunt is about to land its hit.
	var guard := 0
	while not (g.state == &"windup" and g.state_t <= 0.05) and guard < 600:
		w.step(DT, cmd())
		guard += 1
	check(g.state == &"windup", "grunt reached windup before the dash")
	# Dash straight through the grunt: still in reach when the hit resolves, so only i-frames save us.
	w.step(DT, cmd(Vector2(0, -1), Vector2(0, -20), false, true))
	check(w.is_dashing() and w.is_invulnerable(), "dash grants i-frames")
	var dodge_seen := false
	for i in int(round(0.3 / DT)):
		w.step(DT, cmd(Vector2(0, -1)))
		for ev in w.events:
			if ev.type == "dodge":
				dodge_seen = true
	check(w.stats.dodged == 1 and dodge_seen and w.stats.hits_taken == 0 and p.hp == p.hp_max,
		"hit during dash is dodged (dodged=%d hits=%d hp=%.0f)" % [w.stats.dodged, w.stats.hits_taken, p.hp])
	check(p.pos.y < g.pos.y - 0.5, "player went through the grunt (player z=%.2f grunt z=%.2f)" % [p.pos.y, g.pos.y])
	check(w.tuning.dash_iframes > w.tuning.dash_time, "i-frames outlast the dash")
	run(w, 2.0, cmd())
	check(w.stats.hits_taken >= 1, "after i-frames end the next hit lands (hits=%d)" % w.stats.hits_taken)

func test_events_and_knockback() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 2))
	g.state = &"recover"   # hold still so the only displacement is the knockback
	g.state_t = 100.0
	var types := {}
	var first_hit_dz := 0.0
	for i in int(round(1.5 / DT)):
		var before := g.pos.y
		w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
		for ev in w.events:
			types[ev.type] = types.get(ev.type, 0) + 1
			if ev.type == "hit" and first_hit_dz == 0.0:
				first_hit_dz = before - g.pos.y
	check(types.has("shot") and types.has("hit") and types.has("kill"), "events emitted: %s" % [types])
	check(absf(first_hit_dz - w.tuning.knockback) < 0.001, "hit knocks the grunt back %.2f" % first_hit_dz)
	check(w.events.is_empty() or w.events[0].type != "kill", "events are cleared each step")
	# Fire into the far wall: impact.
	var w2 := SimWorld.new(1)
	w2.spawn(&"player", Vector2(0, 9))
	var impacts := 0
	for i in int(round(2.0 / DT)):
		w2.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
		for ev in w2.events:
			if ev.type == "impact":
				impacts += 1
	check(impacts > 0, "bullets hitting a wall emit impact (%d)" % impacts)

func test_hit_radius() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	# Grunt offset so the bullet line (x=0) misses the body (0.45) but touches the hit radius (0.55+0.25).
	var g := w.spawn(&"grunt", Vector2(0.72, 2))
	g.state = &"recover"   # keep it still long enough
	g.state_t = 100.0
	check(g.radius < g.hit_radius, "grunt body radius < hit radius")
	run(w, 0.6, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(w.stats.shots_hit > 0, "bullet grazing the hit radius counts (hits=%d)" % w.stats.shots_hit)

func test_projectile_kills_grunt() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 2))
	run(w, 1.0, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(not g.alive and w.stats.kills == 1 and w.stats.shots_hit == 3,
		"three hits kill a grunt (alive=%s hits=%d)" % [g.alive, w.stats.shots_hit])
	check(w.projectiles.size() <= int(w.tuning.proj_ttl / w.tuning.fire_interval) + 1, "bullets expire")

func test_tuning_roundtrip() -> void:
	var path := OS.get_user_data_dir().path_join("sim_test_tuning.json")
	var t := SimTuning.new()
	t.grunt_speed = 5.5
	t.dash_iframes = 0.33
	check(t.save_file(path), "tuning saves to " + path)
	var t2 := SimTuning.load_file(path)
	check(t2.grunt_speed == 5.5 and t2.dash_iframes == 0.33 and t2.player_speed == t.player_speed,
		"tuning loads back (grunt_speed=%.1f dash_iframes=%.2f)" % [t2.grunt_speed, t2.dash_iframes])
	t2.apply({"grunt_speed": 999.0, "bogus": 1.0})
	check(t2.grunt_speed == 12.0, "loaded values are clamped to spec range")
	var w := SimWorld.new(1, null, t2)
	var g := w.spawn(&"grunt", Vector2.ZERO)
	check(g.hit_radius == t2.grunt_hit_radius, "world spawns from its tuning")
	DirAccess.remove_absolute(path)

func test_determinism() -> void:
	var a := _scripted_run()
	var b := _scripted_run()
	check(JSON.stringify(a) == JSON.stringify(b), "same seed + same commands = same state")

func _scripted_run() -> Dictionary:
	var w := SimWorld.new(7)
	w.spawn(&"player", Vector2(0, 9))
	w.spawn(&"grunt", Vector2(-1.5, -3))
	w.spawn(&"grunt", Vector2(1.5, -6))
	w.spawn(&"grunt", Vector2(0, -9))
	for i in 300:
		var c := cmd(Vector2(sin(i * 0.05), -0.3), Vector2(1, -20), i % 3 == 0, i == 120 or i == 200)
		w.step(DT, c)
	return w.to_dict()
