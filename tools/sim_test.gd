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
	test_arena_level()
	test_waves()
	test_wave_clear_and_next()
	test_restart_keeps_tuning()
	test_brute_cone()
	test_technomancer_blast()
	test_weapon_switch_keeps_tuning()
	test_stagger()
	test_body_stats()
	test_attack_move()
	test_pack_aggro()
	test_hit_wakes_pack()
	test_leash()
	test_wave_packs()
	test_provoke()
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
	# Fire into the east wall: impact.
	var w2 := SimWorld.new(1)
	w2.spawn(&"player", Vector2(0, 9))
	var impacts := 0
	for i in int(round(2.0 / DT)):
		w2.step(DT, cmd(Vector2.ZERO, Vector2(20, 9), true))
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

func test_arena_level() -> void:
	var l := SimLevel.arena()
	check(l.floors.size() == 2 and l.walls.size() == 10, "arena has 2 floors and 10 wall rects")
	check(not l.is_blocked(Vector2(0, 0)) and not l.is_blocked(Vector2(0, -20)), "corridor and room are walkable")
	check(l.is_blocked(Vector2(-6, 0)), "void beside the corridor is blocked")
	check(l.is_blocked(Vector2(-3, -22)) and l.is_blocked(Vector2(3, -22)), "pillars are blocked")
	check(not l.is_blocked(Vector2(0, -22)) and not l.is_blocked(Vector2(-6, -22)), "gap between pillars and sides are open")
	check(not l.is_blocked(Vector2(0, -12.5)), "corridor mouth is open")
	check(l.is_blocked(Vector2(-5, -12.5)), "room south wall is closed beside the mouth")
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	run(w, 6.0, cmd(Vector2(0, -1)))
	check(p.pos.y < -13.0, "player can walk from the corridor into the room (z=%.1f)" % p.pos.y)
	run(w, 3.0, cmd(Vector2(-1, 0)))
	check(p.pos.x <= -8.0 + p.radius + 0.001, "room west wall stops the player (x=%.2f)" % p.pos.x)

func _grunt_positions(w: SimWorld) -> Array:
	var out := []
	for e in w.entities.values():
		if e.kind == &"grunt":
			out.append(e.pos)
	return out

func test_waves() -> void:
	var w := SimWorld.new(3)
	w.begin()
	var p := w.player()
	check(p != null and p.pos == w.level.player_spawn, "begin() spawns the player at the level spawn")
	check(w.wave == 1 and w.stats.wave == 1 and _grunt_positions(w).size() == 3, "wave 1 has 3 grunts")
	var all_far := true
	var all_fit := true
	for g in w.entities.values():
		if g.kind != &"grunt":
			continue
		all_far = all_far and g.pos.distance_to(p.pos) > SimWorld.SPAWN_MIN_DIST
		all_fit = all_fit and w.level.circle_fits(g.pos, g.radius)
	check(all_far, "every grunt spawns farther than %.0f from the player" % SimWorld.SPAWN_MIN_DIST)
	check(all_fit, "every grunt spawns on a floor, clear of walls")
	w.start_wave(5)
	check(_grunt_positions(w).size() == 11 and w.wave == 5, "wave 5 has 11 grunts")
	w.start_wave(6)
	check(_grunt_positions(w).size() == 12, "wave 6 is capped at 12")
	w.start_wave(30)
	check(_grunt_positions(w).size() == 12 and w.grunts_alive() == 12, "cap holds for any wave")
	var a := SimWorld.new(42)
	a.begin()
	var b := SimWorld.new(42)
	b.begin()
	var c := SimWorld.new(43)
	c.begin()
	check(_grunt_positions(a) == _grunt_positions(b), "same seed = same spawn positions")
	check(_grunt_positions(a) != _grunt_positions(c), "different seed = different spawn positions")

func test_wave_clear_and_next() -> void:
	var w := SimWorld.new(1)
	w.begin()
	for g in w.entities.values():
		if g.kind == &"grunt":
			w.damage(g.id, 1000.0)
	var cleared := false
	for ev in w.events:
		if ev.type == "wave_cleared" and ev.wave == 1:
			cleared = true
	check(cleared and w.grunts_alive() == 0 and w.next_wave_t > 0.0, "last kill emits wave_cleared and arms the timer")
	run(w, 1.0, cmd())
	check(w.wave == 1, "next wave waits (still wave 1 after 1s)")
	run(w, 1.2, cmd())
	check(w.wave == 2 and w.grunts_alive() == 5, "wave 2 starts after the delay with 5 grunts")

func test_restart_keeps_tuning() -> void:
	var t := SimTuning.new()
	t.grunt_speed = 5.5
	var w := SimWorld.new(1, null, t)
	w.begin()
	w.start_wave(3)
	var p := w.player()
	w.damage(p.id, 1000.0)
	check(not p.alive, "player can die")
	w.tuning.proj_damage = 42.0   # a live slider change, not saved
	w.restart_wave()
	check(w.tuning == t and w.tuning.grunt_speed == 5.5 and w.tuning.proj_damage == 42.0,
		"restart keeps the same tuning object and values")
	check(p.alive and p.hp == p.hp_max and p.pos == w.level.player_spawn, "restart revives the player at the spawn")
	check(w.wave == 3 and w.grunts_alive() == 7 and w.projectiles.is_empty(), "restart replays the same wave")

func _still_grunt(w: SimWorld, pos: Vector2) -> SimEntity:
	var g := w.spawn(&"grunt", pos)
	g.state = &"recover"
	g.state_t = 100.0
	return g

func test_brute_cone() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 0))
	w.set_weapon("brute")
	var near := _still_grunt(w, Vector2(0, -1.5))
	var far := _still_grunt(w, Vector2(0, -1.8))
	var side := _still_grunt(w, Vector2(1.3, -0.75))   # 1.5 away, 60 degrees off the aim
	var near_z := near.pos.y
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	var expected := w.tuning.proj_damage * 2.5
	check(near.hp == near.hp_max - expected, "cone hits at 1.5 for 2.5x damage (hp=%.0f)" % near.hp)
	check(far.hp == far.hp_max, "cone misses at 1.8")
	check(side.hp == side.hp_max, "cone misses at 1.5 but 60 degrees off")
	check(is_equal_approx(near_z - near.pos.y, w.tuning.knockback * 2.0), "cone knockback is doubled (%.2f)" % (near_z - near.pos.y))
	var swings := 0
	for ev in w.events:
		if ev.type == "swing":
			swings += 1
	check(swings == 1 and w.projectiles.is_empty(), "swing event, no projectile")
	var z0 := p.pos.y
	run(w, 0.2, cmd())
	check(absf((z0 - p.pos.y) - 0.8) < 0.001, "lunge covers exactly 0.8 along the aim (%.3f)" % (z0 - p.pos.y))
	check(_count_swings(w, 0.25) == 0, "cadence: no second swing before 0.5 s")
	check(_count_swings(w, 0.1) == 1, "second swing after 0.5 s")

func _count_swings(w: SimWorld, seconds: float) -> int:
	var n := 0
	for i in int(round(seconds / DT)):
		w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
		for ev in w.events:
			if ev.type == "swing":
				n += 1
	return n

func test_technomancer_blast() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	w.set_weapon("technomancer")
	# Shot flies 8 u/s for 1.5 s from z=8.4 and bursts at z=-3.6.
	var inside := _still_grunt(w, Vector2(1.3, -3.6))
	var outside := _still_grunt(w, Vector2(-1.5, -3.6))
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(w.projectiles.size() == 1 and is_equal_approx(w.projectiles.values()[0].blast_radius, 1.4), "technomancer fires a blast projectile (radius 1.4)")
	var explosions := []
	for i in 100:
		w.step(DT, cmd())
		for ev in w.events:
			if ev.type == "explosion":
				explosions.append(ev)
	check(explosions.size() == 1 and is_equal_approx(explosions[0].radius, 1.4), "one explosion at end of life (%d)" % explosions.size())
	check(inside.hp < inside.hp_max, "explosion hits at 1.3 (hp=%.1f)" % inside.hp)
	check(outside.hp == outside.hp_max, "explosion misses at 1.5")
	check(is_equal_approx(w.tuning.fire_interval * w.weapon.fire_interval_mult, 0.8), "technomancer cadence is 0.8 s with the default tuning")
	# Center damage: a grunt right under the burst takes 2x.
	var w2 := SimWorld.new(1)
	w2.spawn(&"player", Vector2(0, 9))
	w2.set_weapon("technomancer")
	var g := _still_grunt(w2, Vector2(0, 5))
	w2.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	run(w2, 0.5, cmd())
	var taken := g.hp_max - g.hp
	check(is_equal_approx(taken, w2.tuning.proj_damage * 2.0), "direct contact burst deals the full 2x (%.1f)" % taken)

func test_weapon_switch_keeps_tuning() -> void:
	var w := SimWorld.new(1)
	w.tuning.proj_damage = 13.0
	var before := JSON.stringify(w.tuning.to_dict())
	var obj := w.tuning
	for n in WeaponProfile.NAMES:
		w.set_weapon(n)
	check(w.weapon.name == "technomancer" and w.tuning == obj and JSON.stringify(w.tuning.to_dict()) == before,
		"switching profiles leaves the tuning object and values untouched")

func test_stagger() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 7.8))   # at contact
	var guard := 0
	while g.state != &"windup" and guard < 600:
		w.step(DT, cmd())
		guard += 1
	check(g.state == &"windup", "grunt winds up at contact")
	w.damage(g.id, 1.0, Vector2.ZERO)
	var staggered := false
	for ev in w.events:
		if ev.type == "stagger" and ev.target == g.id:
			staggered = true
	check(staggered and g.state == &"recover" and is_equal_approx(g.state_t, w.tuning.grunt_recover),
		"hit during windup: stagger event, straight to recover")
	run(w, w.tuning.grunt_recover + 0.05, cmd())
	check(w.stats.hits_taken == 0 and p.hp == p.hp_max, "the interrupted attack never lands")
	run(w, 1.5, cmd())
	check(w.stats.hits_taken >= 1, "the grunt attacks again after recovering (hits=%d)" % w.stats.hits_taken)

func test_body_stats() -> void:
	var w := SimWorld.new(1)
	w.set_weapon("brute")
	var p := w.spawn(&"player", Vector2(0, 9))
	check(is_equal_approx(p.hp_max, w.tuning.player_hp * 1.6) and p.hp == p.hp_max, "brute spawns with 1.6x hp (%.0f)" % p.hp_max)
	w.damage(p.id, 10.0)
	check(is_equal_approx(p.hp_max - p.hp, 6.5), "brute takes 0.65x damage (%.2f)" % (p.hp_max - p.hp))
	w.set_weapon("technomancer")
	check(is_equal_approx(p.hp_max, w.tuning.player_hp * 0.85), "technomancer max hp is 0.85x (%.1f)" % p.hp_max)
	var frac := p.hp / p.hp_max
	check(absf(frac - (1.0 - 6.5 / (w.tuning.player_hp * 1.6))) < 0.001, "switching keeps the health fraction (%.3f)" % frac)
	var before := p.hp
	w.damage(p.id, 10.0)
	check(is_equal_approx(before - p.hp, 11.0), "technomancer takes 1.1x damage (%.1f)" % (before - p.hp))
	w.set_weapon("hunter")
	before = p.hp
	w.damage(p.id, 10.0)
	check(is_equal_approx(before - p.hp, 10.0) and is_equal_approx(p.hp_max, w.tuning.player_hp), "hunter is 1.0x on both")
	var t_before := JSON.stringify(w.tuning.to_dict())
	w.set_weapon("brute")
	check(JSON.stringify(w.tuning.to_dict()) == t_before, "body stats never touch the tuning")
	# Brute swing grants 0.12 s of i-frames; the other profiles none.
	w.restart_wave()
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(w.is_invulnerable() and absf(w.iframes_t - 0.12) < 0.001, "brute swing grants 0.12 s i-frames (%.3f)" % w.iframes_t)
	var dodged: bool = (not w.damage(p.id, 10.0)) and w.stats.dodged == 1
	check(dodged, "a hit during the swing is dodged")
	w.set_weapon("hunter")
	w.restart_wave()
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(not w.is_invulnerable(), "hunter shot grants no i-frames")
	var w2 := SimWorld.new(1)
	w2.set_weapon("technomancer")
	w2.spawn(&"player", Vector2(0, 9))
	w2.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(not w2.is_invulnerable() and is_equal_approx(w2.projectiles.values()[0].vel.length(), w2.tuning.proj_speed * 0.4),
		"technomancer: no i-frames, projectile at 0.4x speed (%.1f)" % w2.projectiles.values()[0].vel.length())

func test_attack_move() -> void:
	var w := SimWorld.new(1)
	w.tuning.attack_move_mult = 0.55
	var p := w.spawn(&"player", Vector2(0, 9))
	# Hunter: shooting while walking up the corridor is 0.55x speed as long as fire_cd > 0
	# (the trigger tick itself still moves at full speed: fire happens after movement).
	var z0 := p.pos.y
	run(w, 0.5, cmd(Vector2(0, -1), Vector2(0, -20), true))
	var walked := z0 - p.pos.y
	var expected := DT * w.tuning.player_speed + (0.5 - DT) * w.tuning.player_speed * 0.55
	check(absf(walked - expected) < 0.01, "hunter walks at 0.55x while firing (%.2f)" % walked)
	w.fire_cd = 0.0
	z0 = p.pos.y
	run(w, 0.2, cmd(Vector2(0, -1)))
	check(absf((z0 - p.pos.y) - 0.2 * w.tuning.player_speed) < 0.01, "full speed again once fire_cd is spent")
	# Brute: during the 9 swing ticks, lunge plus steering at 0.55x; after it, full speed even with fire_cd > 0.
	w.set_weapon("brute")
	p.pos = Vector2(0, 0)
	w.step(DT, cmd(Vector2(-1, 0), Vector2(0, -20), true))   # trigger tick: full-speed step, then the swing starts
	var x0 := p.pos.x
	run(w, 0.15, cmd(Vector2(-1, 0)))
	check(absf((x0 - p.pos.x) - 0.15 * w.tuning.player_speed * 0.55) < 0.01 and absf(p.pos.y + 0.8) < 0.01,
		"brute swing: lunge 0.8 plus 0.55x steering (dx=%.3f z=%.2f)" % [x0 - p.pos.x, p.pos.y])
	check(w.swing_t <= 0.0, "swing is over after 0.15 s")
	x0 = p.pos.x
	run(w, 0.2, cmd(Vector2(-1, 0)))
	check(w.fire_cd > 0.0 and absf((x0 - p.pos.x) - 0.2 * w.tuning.player_speed) < 0.01, "brute moves at full speed between swings")
	# Technomancer: unaffected.
	w.set_weapon("technomancer")
	p.pos = Vector2(0, 0)
	run(w, 0.3, cmd(Vector2(0, -1), Vector2(0, -20), true))
	check(absf(-p.pos.y - 0.3 * w.tuning.player_speed) < 0.01, "technomancer keeps full speed while firing")
	check(SimTuning.keys().has("attack_move_mult") and SimTuning.new().attack_move_mult == 1.0, "attack_move_mult is a tuning key, default 1.0")

func _idle_grunt(w: SimWorld, pos: Vector2) -> SimEntity:
	return w.spawn(&"grunt", pos)

func _events_of(w: SimWorld, type: String, seconds: float, c: Command) -> Array:
	var out := []
	for i in int(round(seconds / DT)):
		w.step(DT, c)
		for ev in w.events:
			if ev.type == type:
				out.append(ev)
	return out

func test_pack_aggro() -> void:
	var w := SimWorld.new(5)
	w.tuning.grunt_aggro = 6.0
	w.spawn(&"player", Vector2(0, 9))
	var a := _idle_grunt(w, Vector2(0, 4))         # 5 from the player: wakes on its own
	var b := _idle_grunt(w, Vector2(0, 1))         # 3 from a, 8 from the player
	var c := _idle_grunt(w, Vector2(-4.9, 3))      # 5 from a, 5.3 from b, 7.7 from the player
	w.step(DT, cmd())
	var b_delay := b.aggro_delay
	check(a.state == &"chase" and b.state == &"idle" and b_delay > 0.0, "a wakes and arms its neighbour at 3 with a delay (%.2f s)" % b_delay)
	check(c.aggro_delay == 0.0 and c.state == &"idle", "the grunt at 5 is not armed")
	check(b.provoked_t == 0.0, "a natural wake passes no provocation")
	var aggro := _events_of(w, "aggro", 0.35, cmd())
	check(b.state == &"chase" and aggro.size() == 1 and aggro[0].id == b.id, "the neighbour at 3 follows within 0.3 s")
	check(c.state == &"idle", "the grunt at 5 stays idle")
	# Delay is seeded: same seed, same delay.
	var w2 := SimWorld.new(5)
	w2.tuning.grunt_aggro = 6.0
	w2.spawn(&"player", Vector2(0, 9))
	_idle_grunt(w2, Vector2(0, 4))
	var b2 := _idle_grunt(w2, Vector2(0, 1))
	_idle_grunt(w2, Vector2(-4.9, 3))
	w2.step(DT, cmd())
	check(is_equal_approx(b2.aggro_delay, b_delay), "wake delay is seeded (%.3f)" % b2.aggro_delay)

func test_hit_wakes_pack() -> void:
	var w := SimWorld.new(1)
	w.tuning.grunt_aggro = 10.0   # leash at 18: the pack at 15 chases once woken
	w.spawn(&"player", Vector2(0, 9))
	var a := _idle_grunt(w, Vector2(0, -6))        # 15 from the player
	var b := _idle_grunt(w, Vector2(2, -7))
	var c := _idle_grunt(w, Vector2(-2, -8))
	var far := _idle_grunt(w, Vector2(0, -20))     # 14 from a
	run(w, 0.5, cmd())
	check(a.state == &"idle" and b.state == &"idle", "a sleeping pack out of range stays idle")
	w.damage(a.id, 1.0)
	var woke_a := false
	for ev in w.events:
		if ev.type == "aggro" and ev.id == a.id:
			woke_a = true
	check(woke_a and a.state == &"chase", "the hit grunt wakes at once")
	run(w, 0.35, cmd())
	check(b.state == &"chase" and c.state == &"chase", "its packmates follow")
	check(far.state == &"idle" and far.aggro_delay == 0.0, "a grunt outside the share radius sleeps on")

func test_leash() -> void:
	var w := SimWorld.new(1)
	w.tuning.grunt_aggro = 6.0
	var p := w.spawn(&"player", Vector2(0, 9))
	var g := _idle_grunt(w, Vector2(0, 4))
	run(w, 0.3, cmd())
	check(g.state == &"chase" and g.pos.y > 4.0, "grunt chases")
	p.pos = Vector2(0, -20)   # 24+ away: beyond 6 * 1.8
	var de := _events_of(w, "deaggro", DT, cmd())
	check(g.state == &"return" and de.size() == 1 and de[0].id == g.id, "too far: deaggro, walks home")
	var z_before := g.pos.y
	run(w, 0.2, cmd())
	check(absf((z_before - g.pos.y) - 0.2 * w.tuning.grunt_speed * 0.6) < 0.02, "walks home at 0.6x speed (%.2f)" % (z_before - g.pos.y))
	run(w, 3.0, cmd())
	check(g.state == &"idle" and g.pos.distance_to(g.spawn_pos) <= 0.2, "back at its spawn, idle (d=%.2f)" % g.pos.distance_to(g.spawn_pos))
	p.pos = Vector2(0, 8)
	w.step(DT, cmd())
	check(g.state == &"chase", "re-aggro when the player comes back in range")

func test_wave_packs() -> void:
	var w := SimWorld.new(9)
	w.begin()
	check(w.wave_packs.size() == 1 and _grunt_positions(w).size() == 3, "3 grunts = one pack of 3")
	for n in [2, 3, 4, 5, 6, 30]:
		w.start_wave(n)
		var grunts := []
		for e in w.entities.values():
			if e.kind == &"grunt":
				grunts.append(e)
		var expected := mini(12, 3 + 2 * (n - 1))
		var sizes := {}
		var in_radius := true
		var far := true
		for g in grunts:
			sizes[g.pack] = sizes.get(g.pack, 0) + 1
			in_radius = in_radius and g.pos.distance_to(w.wave_packs[g.pack]) <= SimWorld.PACK_RADIUS + 0.01
			far = far and g.pos.distance_to(w.player().pos) > SimWorld.SPAWN_MIN_DIST
		var packs := w.wave_packs.size()
		var sizes_ok := true
		for k in sizes:
			sizes_ok = sizes_ok and sizes[k] >= 2 and sizes[k] <= 4
		check(grunts.size() == expected and packs >= 2 and packs <= 4 and sizes_ok and in_radius and far,
			"wave %d: %d grunts in %d packs of %s, all within %.0f of their center and > %.0f from the player" % [n, grunts.size(), packs, sizes.values(), SimWorld.PACK_RADIUS, SimWorld.SPAWN_MIN_DIST])

func test_provoke() -> void:
	# aggro 14: leash at 25.2. A grunt hit from 26 chases anyway; an unprovoked one lets go.
	var w := SimWorld.new(1)
	w.tuning.grunt_aggro = 14.0
	w.spawn(&"player", Vector2(0, 9))
	var hit := _idle_grunt(w, Vector2(0, -17))      # 26 from the player
	var mate := _idle_grunt(w, Vector2(-3, -17))    # 3 from it: woken by the hit, never hit itself, 26.2 from the player
	w.damage(hit.id, 1.0)
	check(hit.state == &"chase" and is_equal_approx(hit.provoked_t, w.tuning.provoke_time), "the hit wakes and provokes the grunt")
	check(mate.aggro_delay > 0.0 and is_equal_approx(mate.provoked_t, w.tuning.provoke_time), "the woken packmate inherits the provocation")
	var de := _events_of(w, "deaggro", 1.0, cmd())
	check(hit.state == &"chase" and hit.pos.y > -16.0, "provoked at 26: keeps chasing (z=%.1f)" % hit.pos.y)
	check(de.is_empty() and mate.state == &"chase" and mate.provoked_t > 2.5, "the packmate chases past the leash too (%.1f s left)" % mate.provoked_t)
	# Re-armed on every hit: a second hit at 3.5 s pushes the window past 4 s.
	run(w, 2.5, cmd())
	w.damage(hit.id, 1.0)
	run(w, 1.0, cmd())
	check(hit.state == &"chase" and hit.provoked_t > 2.5, "a new hit re-arms the window (%.1f s left)" % hit.provoked_t)
	# Without further hits the leash applies again once provoke_time runs out, if still too far.
	var w2 := SimWorld.new(1)
	w2.tuning.grunt_aggro = 14.0
	w2.tuning.grunt_speed = 0.1   # so it is still far away when the window closes
	var p2 := w2.spawn(&"player", Vector2(0, 9))
	var g2 := _idle_grunt(w2, Vector2(0, -17))
	w2.damage(g2.id, 1.0)
	var de2 := _events_of(w2, "deaggro", w2.tuning.provoke_time + 0.1, cmd())
	check(de2.size() == 1 and g2.state == &"return" and g2.pos.distance_to(p2.pos) > 25.2, "leash resumes after provoke_time without a new hit")
