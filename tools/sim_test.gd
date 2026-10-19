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
	test_stats_mods()
	test_item_drop()
	test_item_roll()
	test_loot_pools()
	test_breakpoint()
	test_item_pickup()
	test_equip_from_bag()
	test_drop_from_bag()
	test_drop_tables()
	test_items_persist()
	test_elite_spawn()
	test_shielded()
	test_volatile()
	test_fast()
	test_elite_drop()
	test_wave_pacing()
	test_turn_rate()
	test_attack_commitment()
	test_shield_window()
	print("[sim_test] ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("[sim_test] FAIL: " + msg)
	else:
		print("[sim_test] ok: " + msg)

func cmd(move := Vector2.ZERO, aim := Vector2(0, -20), attack := false, dash := false, interact := false) -> Command:
	var c := Command.new()
	c.move = move
	c.aim = aim
	c.attack = attack
	c.dash = dash
	c.interact = interact
	return c

## Put an item under the player, pick it up with E and wear it.
func _give(w: SimWorld, it: SimItem) -> void:
	w.place_item(it, w.player().pos)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	w.equip(it.id)

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
	check(is_equal_approx(w.fire_interval(), 0.8), "technomancer cadence is 0.8 s with the default tuning")
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

func test_stats_mods() -> void:
	var w := SimWorld.new(1)
	w.tuning.fire_interval = 0.15
	var st := w.player_stats
	check(is_equal_approx(st.value("fire_rate"), 1.0 / 0.15) and is_equal_approx(w.fire_interval(), 0.15),
		"0 mods: fire_rate is 1 / fire_interval (%.2f/s)" % st.value("fire_rate"))
	check(is_equal_approx(st.value("player_speed"), w.tuning.player_speed) and is_equal_approx(st.value("proj_damage"), w.tuning.proj_damage),
		"0 mods: every stat reads the tuning")
	st.add(7, "fire_rate", 0.30)
	check(is_equal_approx(st.value("fire_rate"), 1.0 / 0.15 * 1.3), "1 mod: +30 %% fire_rate (%.2f/s)" % st.value("fire_rate"))
	check(is_equal_approx(w.fire_interval(), 0.15 / 1.3) and w.fire_interval() < 0.15, "+30 %% fire_rate shortens the interval to %.4f s" % w.fire_interval())
	st.add(8, "fire_rate", 0.30)
	check(is_equal_approx(st.value("fire_rate"), 1.0 / 0.15 * 1.6), "2 mods: pct adds up to +60 %% (%.2f/s)" % st.value("fire_rate"))
	st.add(9, "proj_damage", 0.0, 5.0)
	check(is_equal_approx(st.value("proj_damage"), w.tuning.proj_damage + 5.0), "flat mod adds after the pct")
	st.add(10, "proj_damage", 0.5, 0.0)
	check(is_equal_approx(st.value("proj_damage"), w.tuning.proj_damage * 1.5 + 5.0), "tuning × (1 + Σ pct) + Σ flat")
	st.remove_source(7)
	check(is_equal_approx(st.value("fire_rate"), 1.0 / 0.15 * 1.3), "removing a source drops its mod")
	w.tuning.fire_interval = 0.3
	check(is_equal_approx(st.value("fire_rate"), 1.0 / 0.3 * 1.3), "stats follow the live tuning")
	# The weapon profile is a modifier too: brute is 0.5 s at the default 0.15, and an item's
	# +30 % reads +30 % on top of it (0.5 / 1.3), not +30 % of the hunter's rate.
	var w2 := SimWorld.new(1)
	w2.set_weapon("brute")
	check(is_equal_approx(w2.fire_interval(), 0.5) and w2.player_stats.has_source("weapon"), "brute: weapon mods give 0.5 s (%.3f)" % w2.fire_interval())
	w2.player_stats.add(1, "fire_rate", 0.30)
	check(is_equal_approx(w2.fire_interval(), 0.5 / 1.3), "brute + item: 0.5 / 1.3 s (%.3f)" % w2.fire_interval())
	w2.set_weapon("hunter")
	check(is_equal_approx(w2.fire_interval(), 0.15 / 1.3), "switching weapons keeps the item mods (%.3f)" % w2.fire_interval())
	# In play: shots per second go up by 30 %.
	var w3 := SimWorld.new(1)
	w3.spawn(&"player", Vector2(0, 9))
	run(w3, 3.0, cmd(Vector2.ZERO, Vector2(0, -20), true))
	var base_shots: int = w3.stats.shots
	var w4 := SimWorld.new(1)
	w4.spawn(&"player", Vector2(0, 9))
	w4.player_stats.add(1, "fire_rate", 0.30)
	run(w4, 3.0, cmd(Vector2.ZERO, Vector2(0, -20), true))
	# Ticks quantize the interval (9 ticks → 7 ticks at 60 Hz), so the ratio is 1.29–1.44.
	var ratio := float(w4.stats.shots) / float(base_shots)
	check(w4.stats.shots > base_shots and ratio > 1.25 and ratio < 1.5,
		"in play: %d shots in 3 s instead of %d" % [w4.stats.shots, base_shots])

func _kill_grunts(w: SimWorld, n: int) -> void:
	for i in n:
		var g := w.spawn(&"grunt", Vector2(-6 + i * 0.5, -20))
		g.state = &"chase"
		w.damage(g.id, g.hp_max, Vector2.ZERO, 0.0)

func test_item_drop() -> void:
	var w := SimWorld.new(3)
	w.spawn(&"player", Vector2(0, 9))
	w.tuning.item_drop_chance = 1.0
	var g := w.spawn(&"grunt", Vector2(2, -20))
	w.damage(g.id, g.hp_max, Vector2.ZERO, 0.0)
	var drops := w.events.filter(func(ev): return ev.type == "drop")
	var it: SimItem = w.items.values()[0] if w.items.size() == 1 else null
	check(it != null and drops.size() == 1 and it.pos == g.pos and drops[0].slot == it.slot and drops[0].rarity == it.rarity
		and SimItem.SLOTS.has(it.slot) and (it.rarity == &"common" or it.rarity == &"rare"),
		"chance 1: the dead grunt leaves an item where it fell (%s %s), with a drop event" % [it.rarity if it else "", it.slot if it else ""])
	w.tuning.item_drop_chance = 0.0
	_kill_grunts(w, 20)
	check(w.items.size() == 1, "chance 0: nothing drops")
	# Seeded: same seed, same drops; the default 20 % lands near 20 over 100 kills.
	var a := SimWorld.new(11)
	a.spawn(&"player", Vector2(0, 9))
	_kill_grunts(a, 100)
	var b := SimWorld.new(11)
	b.spawn(&"player", Vector2(0, 9))
	_kill_grunts(b, 100)
	var c := SimWorld.new(12)
	c.spawn(&"player", Vector2(0, 9))
	_kill_grunts(c, 100)
	check(a.items.size() > 0 and JSON.stringify(a.to_dict()["items"]) == JSON.stringify(b.to_dict()["items"]),
		"same seed = same drops, same affixes (%d of 100)" % a.items.size())
	check(JSON.stringify(a.to_dict()["items"]) != JSON.stringify(c.to_dict()["items"]), "different seed = different drops (%d of 100)" % c.items.size())
	check(a.items.size() >= 10 and a.items.size() <= 32, "drop rate near 20 %% (%d of 100)" % a.items.size())
	# The drop chance only decides whether the item appears, never what the rng hands out next:
	# two worlds that differ only by the chance place the next wave identically.
	var d := SimWorld.new(11)
	d.spawn(&"player", Vector2(0, 9))
	d.tuning.item_drop_chance = 0.0
	_kill_grunts(d, 100)
	a.start_wave(3)
	d.start_wave(3)
	check(d.items.is_empty() and _grunt_positions(a) == _grunt_positions(d), "the drop chance does not move the next wave's grunts")

func test_item_roll() -> void:
	var t := SimTuning.new()
	var pcts := [t.affix_t1, t.affix_t2, t.affix_t3]
	for rarity in SimItem.RARITIES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var it := SimItem.roll(rng, rarity, &"weapon", t)
		var stats := []
		var ok: bool = it.affixes.size() == SimItem.AFFIX_COUNT[rarity] and it.mods.size() == it.affixes.size()
		for i in it.affixes.size():
			var a: Dictionary = it.affixes[i]
			ok = ok and SimItem.POOLS[&"weapon"].has(a.stat) and not stats.has(a.stat)
			ok = ok and a.tier >= 1 and a.tier <= 3 and is_equal_approx(a.pct, pcts[a.tier - 1])
			ok = ok and it.mods[i].stat == a.stat and is_equal_approx(it.mods[i].pct, a.pct)
			stats.append(a.stat)
		check(ok and it.slot == &"weapon" and it.rarity == rarity, "%s weapon: %d distinct affixes from the pool, tier pcts from the tuning (%s)" % [rarity, it.affixes.size(), JSON.stringify(it.affixes)])
	# Negative-is-good stats carry -pct; everything else +pct.
	var neg := SimItem.make(&"armor", &"rare", [{"stat": "damage_taken", "tier": 2}, {"stat": "player_hp", "tier": 3}], t)
	check(is_equal_approx(neg.affixes[0].pct, -t.affix_t2) and is_equal_approx(neg.affixes[1].pct, t.affix_t3) and neg.name_key == "armor_player_hp",
		"damage_taken T2 reads -15 %%, player_hp T3 +25 %%, name_key from the best affix (%s)" % neg.name_key)
	var mod_rng := RandomNumberGenerator.new()
	mod_rng.seed = 9
	var neg_seen := 0
	var tiers := [0, 0, 0]
	for i in 300:
		var m := SimItem.roll(mod_rng, &"rare", &"module", t)
		for a in m.affixes:
			tiers[a.tier - 1] += 1
			if a.stat == "dash_cooldown":
				neg_seen += 1
				if a.pct >= 0.0:
					neg_seen = -1000
	check(neg_seen > 0, "rolled dash_cooldown affixes are all negative (%d seen)" % neg_seen)
	var total := float(tiers[0] + tiers[1] + tiers[2])
	check(tiers[0] / total > 0.42 and tiers[0] / total < 0.58 and tiers[2] / total > 0.09 and tiers[2] / total < 0.21,
		"rare: tiers over 600 affixes near 50/35/15 (%d/%d/%d)" % tiers)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 77
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	var i1 := SimItem.roll(r1, &"epic", &"weapon", t)
	var i2 := SimItem.roll(r2, &"epic", &"weapon", t)
	check(JSON.stringify(i1.to_dict()) == JSON.stringify(i2.to_dict()), "same seed, same item")

func test_loot_pools() -> void:
	var t := SimTuning.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# No dead affix: knockback and proj_speed never roll, whatever the slot or rarity.
	var dead := 0
	var tiers := {&"common": [0, 0, 0], &"rare": [0, 0, 0], &"epic": [0, 0, 0]}
	var n := 0
	for i in 500:
		var slot: StringName = SimItem.SLOTS[i % 3]
		var rarity: StringName = SimItem.RARITIES[(i / 3) % 3]
		var it := SimItem.roll(rng, rarity, slot, t)
		n += 1
		for a in it.affixes:
			if a.stat == "knockback" or a.stat == "proj_speed":
				dead += 1
			tiers[rarity][a.tier - 1] += 1
	check(n == 500 and dead == 0, "500 items: knockback / proj_speed never rolled")
	check(tiers[&"common"][2] == 0 and tiers[&"common"][0] > 0 and tiers[&"common"][1] > 0,
		"common: T1–T2 only (%s)" % str(tiers[&"common"]))
	check(tiers[&"epic"][0] == 0 and tiers[&"epic"][1] > 0 and tiers[&"epic"][2] > 0,
		"epic: never T1 (%s)" % str(tiers[&"epic"]))
	check(tiers[&"rare"][0] > 0 and tiers[&"rare"][1] > 0 and tiers[&"rare"][2] > 0, "rare: T1–T3 (%s)" % str(tiers[&"rare"]))
	var e: Array = tiers[&"epic"]
	var e_t2 := float(e[1]) / float(e[1] + e[2])
	check(e_t2 > 0.5 and e_t2 < 0.7, "epic tiers near 60/40 (%.2f T2)" % e_t2)
	# Role guarantee: 200 rare/epic weapons carry damage or fire rate, armors hp or damage taken.
	var weapons_ok := 0
	var armors_ok := 0
	var distinct_ok := 0
	for i in 200:
		var rarity: StringName = &"rare" if i % 2 == 0 else &"epic"
		var w := SimItem.roll(rng, rarity, &"weapon", t)
		var a := SimItem.roll(rng, rarity, &"armor", t)
		var w_role: String = w.affixes[0].stat
		var a_role: String = a.affixes[0].stat
		if w_role == "proj_damage" or w_role == "fire_rate":
			weapons_ok += 1
		if a_role == "player_hp" or a_role == "damage_taken":
			armors_ok += 1
		var ws := w.affixes.map(func(x): return x.stat)
		var as_ := a.affixes.map(func(x): return x.stat)
		if ws.size() == SimItem.AFFIX_COUNT[rarity] and as_.size() == SimItem.AFFIX_COUNT[rarity]:
			var wd := {}
			for x in ws:
				wd[x] = true
			var ad := {}
			for x in as_:
				ad[x] = true
			if wd.size() == ws.size() and ad.size() == as_.size():
				distinct_ok += 1
	check(weapons_ok == 200, "200 rare/epic weapons: first affix is damage or fire rate (%d)" % weapons_ok)
	check(armors_ok == 200, "200 rare/epic armors: first affix is hp or damage taken (%d)" % armors_ok)
	check(distinct_ok == 200, "role + remaining affixes stay distinct and complete (%d)" % distinct_ok)
	# A common weapon has no role guarantee: player_speed shows up alone over many rolls.
	var speed_alone := 0
	for i in 200:
		if SimItem.roll(rng, &"common", &"weapon", t).affixes[0].stat == "player_speed":
			speed_alone += 1
	check(speed_alone > 30, "common weapons are unconstrained (%d of 200 roll speed)" % speed_alone)

## Shots landed on a grunt before it dies, with a proj_damage weapon of that tier on the
## default preset's numbers (22 damage, 80 hp).
func _shots_to_kill(tier: int) -> int:
	var t := SimTuning.new()
	t.proj_damage = 22.0
	t.grunt_hp = 80.0
	t.grunt_speed = 0.5
	var w := SimWorld.new(1, null, t)
	w.spawn(&"player", Vector2(0, 9))
	if tier > 0:
		_give(w, SimItem.make(&"weapon", &"common", [{"stat": "proj_damage", "tier": tier}], t))
	var g := w.spawn(&"grunt", Vector2(0, 3))
	var hits := 0
	for i in 240:
		w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), true))
		for ev in w.events:
			if ev.type == "hit" and ev.target == g.id:
				hits += 1
		if not g.alive:
			return hits
	return -1

func test_breakpoint() -> void:
	check(_shots_to_kill(0) == 4, "22 vs 80: 4 shots bare (%d)" % _shots_to_kill(0))
	check(_shots_to_kill(2) == 4, "T2 +15 %% (25.3): still 4 shots (%d)" % _shots_to_kill(2))
	check(_shots_to_kill(3) == 3, "T3 +25 %% (27.5): 3 shots, the breakpoint moves (%d)" % _shots_to_kill(3))

func test_item_pickup() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var it := w.place_item(SimItem.make(&"weapon", &"common", [{"stat": "fire_rate", "tier": 1}], w.tuning), Vector2(0, 6))
	var reach := p.radius + SimWorld.PICKUP_REACH
	var before := w.fire_interval()
	# Walking over it without E: nothing.
	run(w, 1.0, cmd(Vector2(0, -1)))
	check(w.items.has(it.id) and w.inventory.is_empty() and w.equipped.is_empty() and p.pos.y < 6.0, "walking over an item does nothing")
	# E out of reach: nothing.
	p.pos = Vector2(0, 6 + reach + 0.05)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.items.has(it.id) and w.inventory.is_empty(), "E at %.2f: out of reach" % (reach + 0.05))
	# E within reach: into the bag, not worn, no mods, pickup event.
	p.pos = Vector2(0, 6 + reach - 0.05)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	var picks := w.events.filter(func(ev): return ev.type == "pickup")
	check(picks.size() == 1 and picks[0].id == it.id and picks[0].slot == &"weapon" and not w.items.has(it.id)
		and w.inventory.size() == 1 and w.inventory[0] == it and w.equipped.is_empty() and is_equal_approx(w.fire_interval(), before),
		"E within reach: pickup event, the item is in the bag, nothing worn")
	# Nearest first.
	var near := w.place_item(SimItem.make(&"armor", &"common", [{"stat": "player_hp", "tier": 1}], w.tuning), p.pos + Vector2(0.2, 0))
	var far := w.place_item(SimItem.make(&"module", &"common", [{"stat": "player_hp", "tier": 1}], w.tuning), p.pos + Vector2(0.5, 0))
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.inventory.size() == 2 and w.inventory[1] == near and w.items.has(far.id), "two items in reach: the nearest goes first")
	# Cap: a full bag refuses with inventory_full, the item stays on the floor.
	w.tuning.inventory_size = 2.0
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	var full := w.events.filter(func(ev): return ev.type == "inventory_full")
	check(full.size() == 1 and w.inventory.size() == 2 and w.items.has(far.id), "full bag: inventory_full, the item stays")
	w.tuning.inventory_size = 12.0
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.inventory.size() == 3 and not w.items.has(far.id), "room again: taken")
	# Held E only takes one item per press tick, never without the key.
	w.place_item(SimItem.make(&"module", &"common", [{"stat": "player_hp", "tier": 1}], w.tuning), p.pos)
	run(w, 0.5, cmd())
	check(w.inventory.size() == 3, "no E, no pickup")

func test_equip_from_bag() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var base_rate := w.player_stats.value("fire_rate")
	var base_dmg := w.player_stats.value("proj_damage")
	var a := w.place_item(SimItem.make(&"weapon", &"common", [{"stat": "fire_rate", "tier": 1}], w.tuning), p.pos)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	var b := w.place_item(SimItem.make(&"weapon", &"rare", [{"stat": "proj_damage", "tier": 2}, {"stat": "player_speed", "tier": 1}], w.tuning), p.pos)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.inventory.size() == 2 and w.equipped.is_empty(), "two weapons in the bag")
	check(w.equip(a.id) and w.equipped.get(&"weapon") == a and w.inventory.size() == 1 and w.inventory[0] == b
		and w.player_stats.has_source(a.id) and is_equal_approx(w.player_stats.value("fire_rate"), base_rate * 1.08),
		"equip(a): worn, out of the bag, its mods on the player")
	var ev := w.events.filter(func(e): return e.type == "equip")
	check(ev.size() == 1 and ev[0].id == a.id and ev[0].replaced_id == -1, "equip event, empty slot: replaced_id -1")
	w.events.clear()
	check(w.equip(b.id) and w.equipped.get(&"weapon") == b and w.inventory.size() == 1 and w.inventory[0] == a
		and not w.player_stats.has_source(a.id) and w.player_stats.has_source(b.id)
		and is_equal_approx(w.player_stats.value("fire_rate"), base_rate) and is_equal_approx(w.player_stats.value("proj_damage"), base_dmg * 1.15),
		"equip(b): a goes back to the bag, the player's mods reflect only b")
	ev = w.events.filter(func(e): return e.type == "equip")
	check(ev.size() == 1 and ev[0].replaced_id == a.id, "equip event names the replaced item")
	check(not w.equip(999) and not w.equip(b.id), "unknown or worn id: equip refuses")
	# Bag full when the replaced item comes back: it goes to the floor at the player's feet.
	w.tuning.inventory_size = 1.0
	var c := w.place_item(SimItem.make(&"weapon", &"common", [{"stat": "player_speed", "tier": 1}], w.tuning), Vector2(0, 5))
	w.inventory.append(c)
	w.items.erase(c.id)
	check(w.equip(a.id) and w.equipped.get(&"weapon") == a and w.inventory.size() == 1 and w.inventory[0] == c
		and w.items.has(b.id) and b.pos == p.pos and not b.armed,
		"equip with a full bag: the replaced weapon lies at the player's feet, unarmed")
	# Stacking: the same stat on two slots adds (weapon T1 + module T1 fire_rate = +16 %), and
	# fire_rate × proj_damage multiply in the kill time.
	var w2 := SimWorld.new(1)
	w2.spawn(&"player", Vector2(0, 9))
	_give(w2, SimItem.make(&"weapon", &"common", [{"stat": "fire_rate", "tier": 1}], w2.tuning))
	_give(w2, SimItem.make(&"module", &"common", [{"stat": "fire_rate", "tier": 1}], w2.tuning))
	check(w2.equipped.size() == 2 and is_equal_approx(w2.player_stats.value("fire_rate"), base_rate * 1.16),
		"weapon T1 + module T1 fire_rate = +16 %% additive (%.3f/s)" % w2.player_stats.value("fire_rate"))
	_give(w2, SimItem.make(&"module", &"common", [{"stat": "proj_damage", "tier": 2}], w2.tuning))
	var dps := w2.player_stats.value("fire_rate") * w2.player_stats.value("proj_damage")
	check(w2.inventory.size() == 1 and is_equal_approx(dps, base_rate * base_dmg * 1.08 * 1.15),
		"fire_rate +8 %% × proj_damage +15 %%: damage per second × 1.242 (%.2f)" % dps)

func test_drop_from_bag() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var a := w.place_item(SimItem.make(&"armor", &"rare", [{"stat": "player_hp", "tier": 2}, {"stat": "damage_taken", "tier": 1}], w.tuning), p.pos)
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	w.events.clear()
	check(w.inventory.size() == 1 and w.drop(a.id) and w.inventory.is_empty() and w.items.has(a.id) and a.pos == p.pos and not a.armed,
		"drop: the item lies at the player's feet with its id")
	var drops := w.events.filter(func(e): return e.type == "drop" and e.id == a.id)
	check(drops.size() == 1 and drops[0].rarity == &"rare", "drop event with slot and rarity")
	check(not w.drop(a.id), "dropping it twice refuses")
	run(w, 0.3, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.items.has(a.id) and w.inventory.is_empty(), "E on the spot does not take it back")
	run(w, 0.5, cmd(Vector2(0, -1)))
	check(a.armed, "stepping away re-arms it")
	run(w, 0.5, cmd(Vector2(0, 1)))
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	check(w.inventory.size() == 1 and w.inventory[0] == a, "back on it, E takes it again")
	# No rng in the bag: pickup, equip and drop leave the seed's path untouched.
	var state_before := w.rng.state
	_give(w, SimItem.make(&"weapon", &"common", [{"stat": "fire_rate", "tier": 1}], w.tuning))
	w.drop(a.id)
	check(w.items.has(a.id) and w.equipped.size() == 1 and w.rng.state == state_before, "pickup / equip / drop never touch the world rng")

func test_drop_tables() -> void:
	var w := SimWorld.new(21)
	w.spawn(&"player", Vector2(0, 9))
	w.tuning.item_drop_chance = 1.0
	_kill_grunts(w, 200)
	var rare := 0
	var other := 0
	for it in w.items.values():
		if it.rarity == &"rare":
			rare += 1
		elif it.rarity != &"common":
			other += 1
	check(w.items.size() == 200 and other == 0 and rare >= 20 and rare <= 60, "200 trash kills: %d rare, rest common" % rare)
	var w2 := SimWorld.new(22)
	w2.spawn(&"player", Vector2(0, 9))
	w2.tuning.item_drop_chance = 0.0
	var epic := 0
	var low := 0
	for i in 50:
		var e := w2.spawn_elite(Vector2(-6 + i * 0.5, -20), [&"fast"])
		w2.damage(e.id, e.hp_max, Vector2.ZERO, 0.0)
	for it in w2.items.values():
		if it.rarity == &"epic":
			epic += 1
		elif it.rarity != &"rare":
			low += 1
	check(w2.items.size() == 50 and low == 0 and epic >= 8 and epic <= 22, "50 elite kills: every drop rare or epic, %d epic" % epic)
	var slots := {}
	for it in w.items.values():
		slots[it.slot] = slots.get(it.slot, 0) + 1
	check(slots.size() == 3 and slots.values().min() >= 40, "slots uniform over 200 drops (%s)" % JSON.stringify(slots))

func test_items_persist() -> void:
	var w := SimWorld.new(1)
	w.begin()
	var p := w.player()
	var it := w.drop_item(p.pos, &"rare", &"weapon")
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	w.equip(it.id)
	var bagged := w.drop_item(p.pos, &"common", &"module")
	w.step(DT, cmd(Vector2.ZERO, Vector2(0, -20), false, false, true))
	var it_floor := w.drop_item(Vector2(0, -20))
	check(w.equipped.get(&"weapon") == it and w.inventory.size() == 1 and w.inventory[0] == bagged and w.player_stats.has_source(it.id),
		"wearing a rare weapon, a module in the bag")
	w.damage(p.id, p.hp_max + 1.0)
	w.restart_wave()
	check(w.equipped.get(&"weapon") == it and w.player_stats.has_source(it.id) and w.inventory.size() == 1 and p.alive,
		"R: equipment and bag stay")
	check(not w.items.has(it_floor.id), "R: the floor is cleared")
	w.start_wave(3)
	check(w.equipped.get(&"weapon") == it and w.inventory.size() == 1, "N: both stay too")
	var base := SimStats.new(w.tuning).fire_interval()
	w.reset_run()
	check(w.equipped.is_empty() and w.inventory.is_empty() and not w.player_stats.has_source(it.id) and is_equal_approx(w.fire_interval(), base) and w.wave == 1,
		"0: back to wave 1, equipment and bag cleared (%.4f s)" % w.fire_interval())
	check(w.player_stats.has_source("weapon") or w.weapon.name == "hunter", "0: the weapon profile is untouched")
	w.set_weapon("brute")
	w.reset_run()
	check(w.weapon.name == "brute" and is_equal_approx(w.fire_interval(), base * 0.5 / 0.15), "0 keeps the weapon profile and its mods")
	var d: Dictionary = w.to_dict()
	check(d.has("equipped") and d.equipped is Dictionary and d.has("inventory") and d.inventory is Array, "to_dict: equipment by slot, inventory list")

func _elites(w: SimWorld) -> Array:
	return w.entities.values().filter(func(e): return e.kind == &"grunt" and e.elite)

func test_elite_spawn() -> void:
	var w := SimWorld.new(7)
	w.begin()
	check(_elites(w).is_empty(), "wave 1 has no elite")
	w.start_wave(2)
	var el := _elites(w)
	check(el.size() == 1, "wave 2 has exactly one elite (%d)" % el.size())
	if el.size() != 1:
		return
	var e: SimEntity = el[0]
	var mates := w.entities.values().filter(func(g): return g.kind == &"grunt" and g.pack == e.pack)
	check(mates.size() >= 2 and e.pack >= 0, "the elite leads a pack of %d" % mates.size())
	check(is_equal_approx(e.hp_max, w.tuning.grunt_hp * 3.0) and e.hp == e.hp_max, "elite hp_max = grunt_hp × 3 (%.0f)" % e.hp_max)
	check(is_equal_approx(e.radius, w.tuning.grunt_radius * 1.2) and is_equal_approx(e.hit_radius, w.tuning.grunt_hit_radius * 1.2), "elite body × 1.2")
	check(e.affixes.size() == 1 and SimWorld.AFFIXES.has(e.affixes[0]), "wave 2 elite has one affix (%s)" % [e.affixes])
	w.start_wave(5)
	var e5: SimEntity = _elites(w)[0]
	check(_elites(w).size() == 1 and e5.affixes.size() == 2 and e5.affixes[0] != e5.affixes[1], "wave 5 elite has two distinct affixes (%s)" % [e5.affixes])
	# Seeded: same path of waves, same elite.
	var a := SimWorld.new(7)
	a.begin()
	a.start_wave(2)
	a.start_wave(5)
	var ea: SimEntity = _elites(a)[0]
	check(ea.pos == e5.pos and ea.affixes == e5.affixes, "same seed = same elite and affixes")
	# Off: never, and the wave's grunt positions are identical with elites on and off (the elite
	# draw happens after placement; later waves diverge since the rng moved on).
	var on := SimWorld.new(7)
	on.begin()
	on.start_wave(2)
	var off := SimWorld.new(7)
	off.tuning.elite_from_wave = 0.0
	off.begin()
	off.start_wave(2)
	check(_elites(off).is_empty(), "elite_from_wave = 0: never")
	check(_grunt_positions(off) == _grunt_positions(on) and _elites(on).size() == 1, "grunt positions identical with elites on and off")

func _bullet_from(w: SimWorld, target: SimEntity, from: Vector2) -> float:
	# Direct damage() call standing in for a bullet flying from `from` into the target.
	var before := target.hp
	w.events.clear()
	w.damage(target.id, 10.0, (target.pos - from).normalized(), 0.0)
	return before - target.hp

func test_shielded() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	var e := w.spawn_elite(Vector2(0, 0), [&"shielded"])
	e.state = &"recover"
	e.state_t = 100.0
	e.facing = Vector2(0, 1)   # facing the player (z+)
	var taken := _bullet_from(w, e, Vector2(0, 9))
	var blocked := w.events.filter(func(ev): return ev.type == "blocked" and ev.target == e.id)
	check(is_equal_approx(taken, 3.0) and blocked.size() == 1, "frontal bullet: 10 × 0.3 = %.1f and a blocked event" % taken)
	taken = _bullet_from(w, e, Vector2(0, -9))
	blocked = w.events.filter(func(ev): return ev.type == "blocked")
	check(is_equal_approx(taken, 10.0) and blocked.is_empty(), "bullet from behind: full damage, no event")
	taken = _bullet_from(w, e, Vector2(9, 0.5))   # ~87 degrees off the facing: outside the 120 cone
	check(is_equal_approx(taken, 10.0), "bullet from the flank: full damage")
	var before := e.hp
	w.damage(e.id, 10.0)
	check(is_equal_approx(before - e.hp, 10.0), "dir ZERO: full damage")
	# Knockback is reduced too.
	var z0 := e.pos.y
	w.damage(e.id, 1.0, Vector2(0, -1))
	check(absf((z0 - e.pos.y) - w.tuning.knockback * 0.3) < 0.001, "frontal knockback × 0.3 (%.2f)" % (z0 - e.pos.y))

func test_volatile() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var e := w.spawn_elite(Vector2(0, 8), [&"volatile"])   # 1.0 from the player
	w.damage(e.id, e.hp_max)
	var fuse := w.events.filter(func(ev): return ev.type == "fuse" and ev.id == e.id)
	check(not e.alive and fuse.size() == 1 and p.hp == p.hp_max and is_equal_approx(e.fuse_t, w.tuning.elite_fuse),
		"kill: fuse event, no damage yet, corpse counts down from %.1f s" % e.fuse_t)
	var blasts := _events_of(w, "blast", w.tuning.elite_fuse - 0.05, cmd())
	check(blasts.is_empty() and p.hp == p.hp_max, "nothing before the fuse runs out")
	blasts = _events_of(w, "blast", 0.1, cmd())
	check(blasts.size() == 1 and is_equal_approx(blasts[0].radius, w.tuning.elite_blast_radius), "blast event at the end of the fuse")
	check(is_equal_approx(p.hp_max - p.hp, w.tuning.grunt_damage * 2.0), "player at 1.0 loses grunt_damage × 2 (%.0f)" % (p.hp_max - p.hp))
	check(p.pos.y > 9.0, "pushed away from the blast (z=%.2f)" % p.pos.y)
	# Out of range: nothing.
	var w2 := SimWorld.new(1)
	var p2 := w2.spawn(&"player", Vector2(0, 9))
	var e2 := w2.spawn_elite(Vector2(0, 6), [&"volatile"])   # 3.0 away
	w2.damage(e2.id, e2.hp_max)
	var b2 := _events_of(w2, "blast", w2.tuning.elite_fuse + 0.1, cmd())
	check(b2.size() == 1 and p2.hp == p2.hp_max, "at 3.0: the blast misses")
	# Dash through at blast time: dodged.
	var w3 := SimWorld.new(1)
	var p3 := w3.spawn(&"player", Vector2(0, 9))
	var e3 := w3.spawn_elite(Vector2(0, 8), [&"volatile"])
	w3.damage(e3.id, e3.hp_max)
	run(w3, w3.tuning.elite_fuse - 0.1, cmd())
	w3.step(DT, cmd(Vector2(0, -1), Vector2(0, -20), false, true))
	var b3 := _events_of(w3, "blast", 0.2, cmd(Vector2(0, -1)))
	check(b3.size() == 1 and w3.stats.dodged == 1 and p3.hp == p3.hp_max, "dashing through the blast dodges it")
	# Grunts take the blast too: a volatile elite killed inside its pack clears it.
	var w4 := SimWorld.new(1)
	w4.spawn(&"player", Vector2(0, 20))
	var e4 := w4.spawn_elite(Vector2(0, 0), [&"volatile"])
	var m1 := _still_grunt(w4, Vector2(1.5, 0))
	var m2 := _still_grunt(w4, Vector2(0, -1.5))
	var far := _still_grunt(w4, Vector2(0, 3.0))
	w4.damage(e4.id, e4.hp_max)
	run(w4, w4.tuning.elite_fuse + 0.1, cmd())
	var expected := w4.tuning.grunt_damage * 2.0
	check(is_equal_approx(m1.hp_max - m1.hp, expected) and is_equal_approx(m2.hp_max - m2.hp, expected), "packmates at 1.5 take grunt_damage × 2 (%.0f)" % (m1.hp_max - m1.hp))
	check(far.hp == far.hp_max, "packmate at 3.0 is spared")
	check(m1.pos.x > 1.5 and m2.pos.y < -1.5, "packmates are pushed away")

func test_fast() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	var e := w.spawn_elite(Vector2(0, -20), [&"fast"])
	e.state = &"chase"
	e.provoked_t = 100.0
	var z0 := e.pos.y
	run(w, 0.5, cmd())
	var v := (e.pos.y - z0) / 0.5
	check(absf(v - w.tuning.grunt_speed * 1.6) < 0.05, "fast elite chases at grunt_speed × 1.6 (%.2f)" % v)
	e.state = &"return"
	e.provoked_t = 0.0
	e.spawn_pos = Vector2(0, -40)
	w.tuning.grunt_aggro = 1.0
	z0 = e.pos.y
	run(w, 0.5, cmd())
	v = (z0 - e.pos.y) / 0.5
	check(absf(v - w.tuning.grunt_speed * SimWorld.RETURN_SPEED_MULT) < 0.05, "return walk unchanged (%.2f)" % v)

func test_elite_drop() -> void:
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(0, 9))
	w.tuning.item_drop_chance = 0.0
	var e := w.spawn_elite(Vector2(0, -20), [&"fast"])
	w.damage(e.id, e.hp_max)
	check(w.items.size() == 1 and w.items.values()[0].rarity != &"common", "an elite always drops, never a common")
	_kill_grunts(w, 20)
	check(w.items.size() == 1, "chance 0: 20 grunts drop nothing more")

func test_wave_pacing() -> void:
	# wave_delay: the next wave waits that long after the last kill.
	var w := SimWorld.new(1)
	w.tuning.wave_delay = 5.0
	w.begin()
	for g in w.entities.values().filter(func(e): return e.kind == &"grunt"):
		w.damage(g.id, g.hp_max)
	check(is_equal_approx(w.next_wave_t, 5.0), "wave_delay arms the timer at 5 s")
	run(w, 4.5, cmd())
	check(w.wave == 1, "still wave 1 after 4.5 s")
	run(w, 0.6, cmd())
	check(w.wave == 2, "wave 2 after 5 s")
	# wave_cap.
	var w2 := SimWorld.new(1)
	w2.tuning.wave_cap = 5.0
	w2.begin()
	w2.start_wave(10)
	check(_grunt_positions(w2).size() == 5, "wave_cap 5: wave 10 has 5 grunts")
	# pack_spacing: every pair of centers at least 10 apart, or the fallback picked the farthest.
	var w3 := SimWorld.new(1)
	w3.tuning.pack_spacing = 10.0
	w3.begin()
	var ok := true
	var clean_waves := 0
	var min_pair := INF
	for n in range(2, 8):
		w3.start_wave(n)
		if w3.wave_fallbacks == 0:
			clean_waves += 1
		for i in w3.wave_packs.size():
			for j in range(i + 1, w3.wave_packs.size()):
				var d: float = w3.wave_packs[i].distance_to(w3.wave_packs[j])
				min_pair = minf(min_pair, d)
				ok = ok and (d >= 10.0 or w3.wave_fallbacks > 0)
	check(ok and clean_waves >= 3, "pack_spacing 10: centers >= 10 apart unless the fallback had to pick the farthest (%d/6 waves clean, min %.1f)" % [clean_waves, min_pair])
	var w3b := SimWorld.new(1)
	w3b.begin()
	w3b.start_wave(2)
	check(w3b.wave_fallbacks == 0, "spacing off: no fallback on the arena")
	# elite_every 2 with elite_from_wave 2: elites on waves 2 and 4, none on 3.
	var w4 := SimWorld.new(1)
	w4.tuning.elite_every = 2.0
	w4.begin()
	var pattern := []
	for n in [2, 3, 4, 5]:
		w4.start_wave(n)
		pattern.append(_elites(w4).size())
	check(pattern == [1, 0, 1, 0], "elite_every 2: elites on waves 2 and 4 only (%s)" % [pattern])
	# Defaults: the old constants, wave 6 capped at 12, 2 s delay.
	var w5 := SimWorld.new(1)
	check(w5.tuning.wave_delay == 2.0 and w5.tuning.wave_cap == 12.0 and w5.tuning.pack_spacing == 0.0 and w5.tuning.elite_every == 1.0, "defaults unchanged")

func _angle_to_player(w: SimWorld, g: SimEntity) -> float:
	return rad_to_deg(absf(g.facing.angle_to((w.player().pos - g.pos).normalized())))

func test_turn_rate() -> void:
	# 720 deg/s: a 20-degree offset is closed within 2 ticks (12 degrees per tick).
	var w := SimWorld.new(1)
	w.spawn(&"player", Vector2(sin(deg_to_rad(20.0)) * 10.0, cos(deg_to_rad(20.0)) * 10.0))
	var g := w.spawn(&"grunt", Vector2(0, 0))   # facing DOWN (0, 1)
	run(w, 2.0 * DT, cmd())
	check(_angle_to_player(w, g) < 1.0, "720 deg/s: faces the player within 2 ticks (%.1f deg off)" % _angle_to_player(w, g))
	# 90 deg/s: a 180-degree turn takes about 2 s.
	var w2 := SimWorld.new(1)
	w2.tuning.grunt_turn_rate = 90.0
	w2.spawn(&"player", Vector2(0, -10))
	var g2 := w2.spawn(&"grunt", Vector2(0, 0))   # facing DOWN, player straight behind
	run(w2, 1.0, cmd())
	var mid := _angle_to_player(w2, g2)
	check(absf(mid - 90.0) < 3.0, "90 deg/s: 90 degrees left after 1 s (%.1f)" % mid)
	run(w2, 0.9, cmd())
	check(_angle_to_player(w2, g2) > 5.0, "not yet aligned at 1.9 s (%.1f deg)" % _angle_to_player(w2, g2))
	run(w2, 0.2, cmd())
	check(_angle_to_player(w2, g2) < 1.0, "aligned after ~2 s (%.1f deg)" % _angle_to_player(w2, g2))

func _reach_windup(w: SimWorld, g: SimEntity) -> bool:
	var guard := 0
	while g.state != &"windup" and guard < 600:
		w.step(DT, cmd())
		guard += 1
	return g.state == &"windup"

func test_attack_commitment() -> void:
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var g := w.spawn(&"grunt", Vector2(0, 7.8))
	check(_reach_windup(w, g), "grunt winds up at contact")
	var frozen := g.facing
	# Strafe 90 degrees around the grunt while it winds up and recovers.
	p.pos = g.pos + Vector2(1.2, 0)
	run(w, w.tuning.grunt_windup * 0.5, cmd())
	check(g.state == &"windup" and g.facing == frozen, "windup: facing frozen while the player strafes (%.2f deg)" % _angle_to_player(w, g))
	run(w, w.tuning.grunt_windup * 0.5 + 0.1, cmd())
	check(g.state == &"recover" and g.facing == frozen, "recover: still frozen")
	run(w, w.tuning.grunt_recover + 0.2, cmd())
	check(g.state != &"recover" and _angle_to_player(w, g) < 1.0, "after recover it turns to the player again (%.1f deg)" % _angle_to_player(w, g))

func test_shield_window() -> void:
	# Shielded elite at contact, facing the player. Dash through to its back while it winds up,
	# shoot it in the back during recover: full damage, no "blocked".
	var w := SimWorld.new(1)
	var p := w.spawn(&"player", Vector2(0, 9))
	var e := w.spawn_elite(Vector2(0, 7.8), [&"shielded"])   # facing DOWN = toward the player
	check(_reach_windup(w, e), "shielded elite winds up at contact")
	var facing_at_windup := e.facing
	w.step(DT, cmd(Vector2(0, -1), Vector2(0, -20), false, true))   # dash north, through it
	run(w, w.tuning.dash_time, cmd(Vector2(0, -1)))
	check(p.pos.y < e.pos.y - 1.0 and e.facing == facing_at_windup, "dashed through: player behind (z=%.1f vs %.1f), elite still facing south" % [p.pos.y, e.pos.y])
	# Shoot back at it (aim south) while it recovers.
	var hp0 := e.hp
	var blocked := []
	var hits := []
	var guard := 0
	while hits.is_empty() and guard < 60:
		w.step(DT, cmd(Vector2.ZERO, Vector2(0, 20), true))
		for ev in w.events:
			if ev.type == "blocked" and ev.target == e.id:
				blocked.append(ev)
			if ev.type == "hit" and ev.target == e.id:
				hits.append(ev)
		guard += 1
	check(hits.size() == 1 and e.state == &"recover", "the shot lands during recover (state=%s)" % e.state)
	check(blocked.is_empty() and is_equal_approx(hp0 - e.hp, w.player_stats.value("proj_damage")), "shot in the back: full damage (%.1f), no blocked event" % (hp0 - e.hp))
	# Control: the same shot from the front is blocked.
	var w2 := SimWorld.new(1)
	w2.spawn(&"player", Vector2(0, 9))
	var e2 := w2.spawn_elite(Vector2(0, 4), [&"shielded"])
	e2.state = &"recover"
	e2.state_t = 100.0
	var hp2 := e2.hp
	var blocked2 := _events_of(w2, "blocked", 0.6, cmd(Vector2.ZERO, Vector2(0, -20), true))
	check(blocked2.size() >= 1 and hp2 - e2.hp < w2.player_stats.value("proj_damage"), "control: frontal shots are blocked")
