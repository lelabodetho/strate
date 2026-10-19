class_name SimWorld
extends RefCounted
## The whole game state and its update rule. Deterministic given (seed, commands, tuning).
## Rendering never touches this; input never bypasses step().

# Waves
const WAVE_BASE := 3
const WAVE_STEP := 2
const WAVE_CAP := 12
const WAVE_DELAY := 2.0        # seconds between the last kill and the next wave
const SPAWN_MIN_DIST := 8.0    # grunts never appear closer than this to the player
const PACK_RADIUS := 2.0       # wave grunts spawn within this distance of their pack center
const PACK_MIN := 2
const PACK_MAX := 4
const PACKS_MIN := 2
const PACKS_MAX := 4
const AGGRO_DELAY_MAX := 0.3   # seeded delay before a woken packmate starts chasing
const RETURN_SPEED_MULT := 0.6 # walking-home speed, as a fraction of grunt_speed
const HOME_EPSILON := 0.2
const PICKUP_REACH := 0.4      # an item is taken when within player_radius + this
# Elite affixes, each with a counter the starter hunter already has:
#   shielded  frontal hits (within elite_shield_angle) are cut by elite_shield_reduction: flank it
#   volatile  its corpse blasts after elite_fuse: step back or dash through; kills its own pack
#   fast      chases at grunt_speed × elite_fast_mult: keep distance, dash past
const AFFIXES: Array[StringName] = [&"shielded", &"volatile", &"fast"]
const ELITE_SECOND_AFFIX_WAVE := 5

var seed: int
var level: SimLevel
var tuning: SimTuning:
	set(v):
		tuning = v
		if player_stats != null:
			player_stats.tuning = v
var weapon: WeaponProfile = WeaponProfile.hunter()
# The player's effective numbers: tuning × weapon mods × item mods. Every player value the
# world needs goes through player_stats.value(); the tuning is never read directly for it.
var player_stats: SimStats
var rng := RandomNumberGenerator.new()
var tick: int = 0
var time: float = 0.0
var entities: Dictionary = {}   # id -> SimEntity
var projectiles: Dictionary = {}  # id -> SimProjectile (removed when they die)
var player_id: int = -1
var _next_id: int = 1
var fire_cd: float = 0.0
var swing_t: float = 0.0        # > 0 while the brute's swing (and lunge) plays
var swing_dir: Vector2 = Vector2.DOWN
var wave: int = 0
var next_wave_t: float = 0.0   # > 0 while counting down to the next wave
var wave_packs: Array[Vector2] = []   # pack centers of the current wave
var items: Dictionary = {}            # id -> SimItem, lying on the floor
var picked_items: Array[SimItem] = [] # what the player carries, in pickup order

# What happened during the last step(), for the view and the harness. Cleared every step.
# {type:"hit", target, pos, dir, damage} {type:"kill", target, pos} {type:"dodge", pos}
# {type:"shot", pos, dir} {type:"impact", pos} {type:"wave_cleared", wave}
# {type:"swing", pos, dir} {type:"explosion", pos, radius} {type:"stagger", target}
# {type:"aggro", id} {type:"deaggro", id} {type:"drop", id, kind, pos}
# {type:"pickup", id, kind, pos, mods}
# {type:"blocked", target, pos, dir}   shielded elite took a frontal hit
# {type:"fuse", id, pos, radius, time} volatile elite died, blast in `time`
# {type:"blast", pos, radius}          the corpse blew up
var events: Array[Dictionary] = []

# Dash state (player only for now)
var dash_t: float = 0.0
var dash_cd: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO
var iframes_t: float = 0.0

# Counters for the harness and tuning
var stats := {"wave": 0, "hits_taken": 0, "dodged": 0, "kills": 0, "shots": 0, "shots_hit": 0}

func _init(p_seed: int = 0, p_level: SimLevel = null, p_tuning: SimTuning = null) -> void:
	seed = p_seed
	rng.seed = p_seed
	level = p_level if p_level != null else SimLevel.arena()
	tuning = p_tuning if p_tuning != null else SimTuning.new()
	player_stats = SimStats.new(tuning)
	player_stats.add_all("weapon", weapon.mods)

## Spawn the player at the level's spawn point and start wave 1.
func begin() -> void:
	spawn(&"player", level.player_spawn)
	start_wave(1)

## Wave n: clear remaining grunts, spawn min(cap, 3 + 2*(n-1)) of them as 2–4 packs of 2–4,
## each pack within PACK_RADIUS of a seeded center on one of the level's floors, never within
## SPAWN_MIN_DIST of the player. Small waves get fewer or smaller packs so the total holds.
func start_wave(n: int) -> void:
	wave = n
	stats.wave = n
	next_wave_t = 0.0
	wave_packs.clear()
	for id in entities.keys():
		if entities[id].kind == &"grunt":
			entities.erase(id)
	var p := player()
	var count := mini(WAVE_CAP, WAVE_BASE + WAVE_STEP * (n - 1))
	var sizes := _pack_sizes(count)
	var placed: Array[Vector2] = []
	for pack_i in sizes.size():
		var area: Rect2 = level.floors[pack_i % level.floors.size()]
		var center := _find_spawn(area, p, placed, SPAWN_MIN_DIST + PACK_RADIUS)
		wave_packs.append(center)
		for j in sizes[pack_i]:
			var pos := _find_pack_slot(center, p, placed)
			var g := spawn(&"grunt", pos)
			g.pack = pack_i
			placed.append(pos)
	# One elite per wave, leading a seeded pack. Drawn after every placement so toggling
	# elites never moves a grunt.
	if tuning.elite_from_wave > 0.0 and n >= int(tuning.elite_from_wave) and not sizes.is_empty():
		var lead_pack := rng.randi_range(0, sizes.size() - 1)
		var affixes: Array[StringName] = []
		var pool := AFFIXES.duplicate()
		var count_affixes := 2 if n >= ELITE_SECOND_AFFIX_WAVE else 1
		for i in mini(count_affixes, pool.size()):
			affixes.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		for e in entities.values():
			if e.kind == &"grunt" and e.pack == lead_pack:
				make_elite(e, affixes)
				break

## Turn a grunt into an elite: tougher, bigger, refilled, with its affixes.
func make_elite(g: SimEntity, affixes: Array[StringName]) -> void:
	g.elite = true
	g.affixes = affixes.duplicate()
	g.hp_max = tuning.grunt_hp * tuning.elite_hp_mult
	g.hp = g.hp_max
	g.radius = tuning.grunt_radius * tuning.elite_body_mult
	g.hit_radius = tuning.grunt_hit_radius * tuning.elite_body_mult

## Hand-placed elite, for the harness and the tests.
func spawn_elite(pos: Vector2, affixes: Array[StringName]) -> SimEntity:
	var g := spawn(&"grunt", pos)
	make_elite(g, affixes)
	return g

func elites() -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for e in entities.values():
		if e.kind == &"grunt" and e.elite:
			out.append(e)
	return out

## Split `count` into packs of PACK_MIN..PACK_MAX, PACKS_MIN..PACKS_MAX of them when the
## count allows it; otherwise as close as possible (3 grunts = one pack of 3).
func _pack_sizes(count: int) -> Array[int]:
	var lo := maxi(1, ceili(float(count) / PACK_MAX))
	var hi := maxi(lo, mini(PACKS_MAX, int(count / PACK_MIN)))
	var packs := rng.randi_range(maxi(lo, mini(PACKS_MIN, hi)), hi)
	var sizes: Array[int] = []
	for i in packs:
		sizes.append(int(count / packs) + (1 if i < count % packs else 0))
	return sizes

func _find_spawn(area: Rect2, p: SimEntity, placed: Array[Vector2], min_dist: float) -> Vector2:
	var r := tuning.grunt_radius + 0.1
	var best := Vector2.INF
	var best_d := -1.0
	for attempt in 64:
		var pos := Vector2(rng.randf_range(area.position.x + r, area.end.x - r),
			rng.randf_range(area.position.y + r, area.end.y - r))
		if not level.circle_fits(pos, r):
			continue
		var d_player := pos.distance_to(p.pos) if p != null else INF
		var crowded := false
		for q in placed:
			if q.distance_to(pos) < r * 2.5:
				crowded = true
				break
		if crowded:
			continue
		if d_player > min_dist:
			return pos
		if d_player > best_d:
			best_d = d_player
			best = pos
	return best if best != Vector2.INF else area.get_center()

## A free spot within PACK_RADIUS of the pack center, still clear of the player.
func _find_pack_slot(center: Vector2, p: SimEntity, placed: Array[Vector2]) -> Vector2:
	var r := tuning.grunt_radius + 0.1
	var fallback := center
	for attempt in 48:
		var a := rng.randf_range(0.0, TAU)
		var d := sqrt(rng.randf()) * PACK_RADIUS
		var pos := center + Vector2(cos(a), sin(a)) * d
		if not level.circle_fits(pos, r):
			continue
		if p != null and pos.distance_to(p.pos) <= SPAWN_MIN_DIST:
			continue
		var crowded := false
		for q in placed:
			if q.distance_to(pos) < r * 2.2:
				crowded = true
				break
		if not crowded:
			return pos
		fallback = pos
	return fallback

## Same wave again: player back to full health at the spawn point, fresh grunts and bullets.
## Tuning is untouched.
func restart_wave() -> void:
	var p := player()
	if p != null:
		p.alive = true
		p.hp_max = player_stats.value("player_hp")
		p.hp = p.hp_max
		p.pos = level.player_spawn
		p.vel = Vector2.ZERO
		p.facing = Vector2.DOWN
		p.state = &"idle"
	projectiles.clear()
	items.clear()
	dash_t = 0.0
	dash_cd = 0.0
	iframes_t = 0.0
	fire_cd = 0.0
	start_wave(maxi(1, wave))

## Back to wave 1 with a fresh player: the items are dropped too. Only R keeps them.
func reset_run() -> void:
	for it in picked_items:
		player_stats.remove_source(it.id)
	picked_items.clear()
	wave = 1
	restart_wave()

func grunts_alive() -> int:
	var n := 0
	for e in entities.values():
		if e.kind == &"grunt" and e.alive:
			n += 1
	return n

func spawn(kind: StringName, pos: Vector2) -> SimEntity:
	var e := SimEntity.new(_next_id, kind, pos)
	_next_id += 1
	match kind:
		&"player":
			player_id = e.id
			e.hp_max = player_stats.value("player_hp")
			e.radius = player_stats.value("player_radius")
			e.hit_radius = e.radius
		&"grunt":
			e.hp_max = tuning.grunt_hp
			e.radius = tuning.grunt_radius
			e.hit_radius = tuning.grunt_hit_radius
	e.hp = e.hp_max
	e.spawn_pos = pos
	entities[e.id] = e
	return e

func player() -> SimEntity:
	return entities.get(player_id)

## Switch the attack profile. Tuning is untouched; only the "weapon" modifiers change.
## The player keeps the same health fraction under the new max.
func set_weapon(n: String) -> void:
	weapon = WeaponProfile.by_name(n)
	player_stats.remove_source("weapon")
	player_stats.add_all("weapon", weapon.mods)
	fire_cd = 0.0
	swing_t = 0.0
	_refresh_body()

## Body values derived from stats (max hp, radius) after the modifiers changed.
func _refresh_body() -> void:
	var p := player()
	if p == null:
		return
	var frac := p.hp / p.hp_max if p.hp_max > 0.0 else 1.0
	p.hp_max = player_stats.value("player_hp")
	p.hp = p.hp_max * frac
	p.radius = player_stats.value("player_radius")
	p.hit_radius = p.radius

## Seconds between two player attacks, from the fire_rate stat.
func fire_interval() -> float:
	return player_stats.fire_interval()

func step(dt: float, cmd: Command) -> void:
	tick += 1
	time += dt
	events.clear()
	var p := player()
	if p == null:
		return
	if p.alive:
		_step_player(dt, p, cmd)
		_pick_up(p)
	for e in entities.values():
		if e.kind == &"grunt" and e.alive:
			_step_grunt(dt, e, p)
	_step_fuses(dt)
	_separate()
	_step_projectiles(dt)
	if next_wave_t > 0.0 and p.alive:
		next_wave_t -= dt
		if next_wave_t <= 0.0:
			start_wave(wave + 1)

func _step_player(dt: float, p: SimEntity, cmd: Command) -> void:
	dash_cd = maxf(0.0, dash_cd - dt)
	iframes_t = maxf(0.0, iframes_t - dt)
	if cmd.dash and dash_cd <= 0.0 and dash_t <= 0.0:
		dash_dir = cmd.move.normalized() if cmd.move.length() > 0.1 else p.facing
		dash_t = player_stats.value("dash_time")
		dash_cd = player_stats.value("dash_cooldown")
		iframes_t = player_stats.value("dash_iframes")

	if dash_t > 0.0:
		dash_t -= dt
		p.vel = dash_dir * player_stats.value("dash_speed")
	elif swing_t > 1e-6:
		# Bounded so the lunge covers exactly `lunge` whatever the tick rounding; the epsilon
		# keeps float residue from adding a tenth tick.
		# Steering during the swing is allowed at attack_move_mult speed, on top of the lunge.
		var t := minf(dt, swing_t)
		swing_t -= dt
		if swing_t < 1e-6:
			swing_t = 0.0
		p.vel = swing_dir * (weapon.lunge / weapon.swing_time) * (t / dt)
		if weapon.attack_move:
			p.vel += cmd.move * player_stats.value("player_speed") * player_stats.value("attack_move_mult")
	else:
		var speed := player_stats.value("player_speed")
		if weapon.attack_move and weapon.kind != &"cone" and fire_cd > 0.0:
			speed *= player_stats.value("attack_move_mult")
		p.vel = cmd.move * speed

	p.pos = level.resolve_circle(p.pos + p.vel * dt, p.radius)

	var to_aim := cmd.aim - p.pos
	if to_aim.length() > 0.05:
		p.facing = to_aim.normalized()

	fire_cd = maxf(0.0, fire_cd - dt)
	if cmd.attack and fire_cd <= 0.0 and not is_dashing():
		fire_cd = fire_interval()
		match weapon.kind:
			&"cone":
				_swing(p, p.facing)
			_:
				_fire(p, p.facing)

func _fire(owner: SimEntity, dir: Vector2) -> void:
	var start := owner.pos + dir * player_stats.value("muzzle_offset")
	if level.is_blocked(start):
		return
	var b := SimProjectile.new(_next_id, owner, start, dir * player_stats.value("proj_speed"))
	_next_id += 1
	b.radius = player_stats.value("proj_radius")
	b.damage = player_stats.value("proj_damage")
	b.knockback = player_stats.value("knockback")
	b.ttl = player_stats.value("proj_ttl")
	if weapon.kind == &"blast":
		b.blast_radius = weapon.blast_radius
	projectiles[b.id] = b
	stats.shots += 1
	_emit({"type": "shot", "pos": start, "dir": dir})

## Brute: hit every grunt whose center is within cone_range and within half the cone angle
## of the aim, then lunge forward for swing_time.
func _swing(owner: SimEntity, dir: Vector2) -> void:
	swing_t = weapon.swing_time
	swing_dir = dir
	iframes_t = maxf(iframes_t, player_stats.value("attack_iframes"))
	stats.shots += 1
	_emit({"type": "swing", "pos": owner.pos, "dir": dir})
	var cos_half := cos(deg_to_rad(weapon.cone_angle_deg * 0.5))
	var hit_any := false
	for e in entities.values():
		if not e.alive or e.id == owner.id or e.kind == owner.kind:
			continue
		var to_e: Vector2 = e.pos - owner.pos
		var d := to_e.length()
		if d > weapon.cone_range or d < 0.0001:
			continue
		if to_e.dot(dir) / d < cos_half:
			continue
		damage(e.id, player_stats.value("proj_damage"), dir, player_stats.value("knockback"))
		hit_any = true
	if hit_any:
		stats.shots_hit += 1

## Technomancer: damage everything within radius, full at the center, blast_edge_factor at the
## edge. A target hit directly by the projectile (direct_id) always takes the center damage.
func _explode(center: Vector2, radius: float, center_damage: float, kb: float, owner_id: int, owner_kind: StringName, direct_id: int = -1) -> void:
	_emit({"type": "explosion", "pos": center, "radius": radius})
	var hit_any := false
	for e in entities.values():
		if not e.alive or e.id == owner_id or e.kind == owner_kind:
			continue
		var d: float = e.pos.distance_to(center)
		if d > radius and e.id != direct_id:
			continue
		var k := 1.0 if e.id == direct_id else lerpf(1.0, weapon.blast_edge_factor, d / radius)
		var dir: Vector2 = (e.pos - center).normalized() if d > 0.0001 else Vector2.ZERO
		damage(e.id, center_damage * k, dir, kb)
		hit_any = true
	if hit_any and owner_id == player_id:
		stats.shots_hit += 1

func _step_projectiles(dt: float) -> void:
	var dead: Array[int] = []
	for b in projectiles.values():
		b.ttl -= dt
		var prev: Vector2 = b.pos
		b.pos += b.vel * dt
		if level.is_blocked(b.pos):
			if b.blast_radius > 0.0:
				_explode(prev, b.blast_radius, b.damage, b.knockback, b.owner_id, b.owner_kind)
			else:
				_emit({"type": "impact", "pos": b.pos})
			dead.append(b.id)
			continue
		if b.ttl <= 0.0:
			if b.blast_radius > 0.0:
				_explode(b.pos, b.blast_radius, b.damage, b.knockback, b.owner_id, b.owner_kind)
			dead.append(b.id)
			continue
		for e in entities.values():
			if not e.alive or e.id == b.owner_id or e.kind == b.owner_kind:
				continue
			var r: float = e.hit_radius + b.radius
			if e.pos.distance_squared_to(b.pos) <= r * r:
				if b.blast_radius > 0.0:
					_explode(b.pos, b.blast_radius, b.damage, b.knockback, b.owner_id, b.owner_kind, e.id)
				else:
					damage(e.id, b.damage, b.vel.normalized(), b.knockback)
					if b.owner_id == player_id:
						stats.shots_hit += 1
				dead.append(b.id)
				break
	for id in dead:
		projectiles.erase(id)

## Idle or returning grunt starts chasing, and wakes idle packmates within aggro_share_radius
## after a seeded delay so the pack does not move as one block. A provoked grunt passes its
## provocation on, so a pack woken by a sniped member chases past the leash together.
func _wake(g: SimEntity) -> void:
	if not g.alive or (g.state != &"idle" and g.state != &"return"):
		return
	g.aggro_delay = 0.0
	g.state = &"chase"
	_emit({"type": "aggro", "id": g.id})
	if tuning.aggro_share_radius <= 0.0:
		return
	for o in entities.values():
		if o == g or not o.alive or o.kind != &"grunt" or o.aggro_delay > 0.0:
			continue
		if o.state != &"idle" and o.state != &"return":
			continue
		if o.pos.distance_to(g.pos) <= tuning.aggro_share_radius:
			o.aggro_delay = maxf(0.001, rng.randf_range(0.0, AGGRO_DELAY_MAX))
			o.provoked_t = maxf(o.provoked_t, g.provoked_t)

func _step_grunt(dt: float, g: SimEntity, p: SimEntity) -> void:
	g.attack_cd = maxf(0.0, g.attack_cd - dt)
	g.provoked_t = maxf(0.0, g.provoked_t - dt)
	g.vel = Vector2.ZERO
	var to_p := p.pos - g.pos
	var dist := to_p.length()
	var contact := g.radius + p.radius + tuning.grunt_reach

	if g.aggro_delay > 0.0:
		g.aggro_delay -= dt
		if g.aggro_delay <= 0.0:
			g.aggro_delay = 0.0
			_wake(g)

	match g.state:
		&"idle":
			if p.alive and dist <= tuning.grunt_aggro:
				_wake(g)
		&"return":
			if p.alive and dist <= tuning.grunt_aggro:
				_wake(g)
			else:
				var home := g.spawn_pos - g.pos
				if home.length() <= HOME_EPSILON:
					g.state = &"idle"
				else:
					g.vel = home.normalized() * tuning.grunt_speed * RETURN_SPEED_MULT
		&"chase":
			if not p.alive:
				g.state = &"idle"
			elif dist > tuning.grunt_aggro * tuning.aggro_drop_mult and g.provoked_t <= 0.0:
				# Leash: too far and not provoked, give up and walk home.
				g.state = &"return"
				_emit({"type": "deaggro", "id": g.id})
			elif dist <= contact and g.attack_cd <= 0.0:
				g.state = &"windup"
				g.state_t = tuning.grunt_windup
			elif dist > contact:
				var speed := tuning.grunt_speed
				if g.has_affix(&"fast"):
					speed *= tuning.elite_fast_mult
				g.vel = to_p / dist * speed
		&"windup":
			g.state_t -= dt
			if g.state_t <= 0.0:
				if p.alive and dist <= contact + tuning.grunt_hit_slack:
					var dmg := tuning.grunt_damage
					if g.elite:
						dmg *= tuning.elite_damage_mult
					damage(p.id, dmg, g.facing)
				g.attack_cd = tuning.grunt_recover
				g.state = &"recover"
				g.state_t = tuning.grunt_recover
		&"recover":
			g.state_t -= dt
			if g.state_t <= 0.0:
				g.state = &"chase"

	if g.state == &"return" and g.vel != Vector2.ZERO:
		g.facing = g.vel.normalized()
	elif dist > 0.05:
		g.facing = to_p / dist
	if g.vel != Vector2.ZERO:
		g.pos = level.resolve_circle(g.pos + g.vel * dt, g.radius)

## Keep living bodies from overlapping. A dashing player passes through everything.
## Cheap O(n^2); n is tiny.
func _separate() -> void:
	var list := entities.values().filter(func(e): return e.alive)
	var ghost := player_id if is_dashing() else -1
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: SimEntity = list[i]
			var b: SimEntity = list[j]
			if a.id == ghost or b.id == ghost:
				continue
			var d: Vector2 = b.pos - a.pos
			var min_d: float = a.radius + b.radius
			var dist := d.length()
			if dist < min_d and dist > 0.0001:
				var push := d / dist * (min_d - dist) * 0.5
				a.pos = level.resolve_circle(a.pos - push, a.radius)
				b.pos = level.resolve_circle(b.pos + push, b.radius)

## Apply damage to an entity, pushing it along `dir` by `kb` (tuning.knockback when negative).
## Returns true if it landed (false if dead, missing, or invulnerable).
func damage(id: int, amount: float, dir: Vector2 = Vector2.ZERO, kb: float = -1.0) -> bool:
	var e: SimEntity = entities.get(id)
	if e == null or not e.alive:
		return false
	if e.id == player_id and is_invulnerable():
		stats.dodged += 1
		_emit({"type": "dodge", "pos": e.pos})
		return false
	if e.id == player_id:
		amount *= player_stats.value("damage_taken")
	var knock := kb if kb >= 0.0 else tuning.knockback
	if e.has_affix(&"shielded") and dir != Vector2.ZERO and dir.dot(e.facing) < -cos(deg_to_rad(tuning.elite_shield_angle * 0.5)):
		# Frontal hit on a shielded elite: mostly absorbed. Flank it.
		amount *= 1.0 - tuning.elite_shield_reduction
		knock *= 1.0 - tuning.elite_shield_reduction
		_emit({"type": "blocked", "target": e.id, "pos": e.pos, "dir": dir})
	e.hp = maxf(0.0, e.hp - amount)
	if e.kind == &"grunt":
		e.provoked_t = tuning.provoke_time
	if e.state == &"windup":
		# Stagger: a grunt hit while winding up loses its attack and goes straight to recover.
		e.state = &"recover"
		e.state_t = tuning.grunt_recover
		e.attack_cd = tuning.grunt_recover
		_emit({"type": "stagger", "target": e.id})
	elif e.kind == &"grunt" and (e.state == &"idle" or e.state == &"return"):
		# Shooting a sleeping pack wakes the whole pack.
		_wake(e)
	if dir != Vector2.ZERO:
		e.pos = level.resolve_circle(e.pos + dir * knock, e.radius)
	_emit({"type": "hit", "target": e.id, "pos": e.pos, "dir": dir, "damage": amount})
	if e.id == player_id:
		stats.hits_taken += 1
	if e.hp <= 0.0:
		e.alive = false
		e.state = &"dead"
		e.vel = Vector2.ZERO
		if e.id != player_id:
			stats.kills += 1
		_emit({"type": "kill", "target": e.id, "pos": e.pos})
		if e.kind == &"grunt":
			if e.has_affix(&"volatile"):
				e.fuse_t = tuning.elite_fuse
				_emit({"type": "fuse", "id": e.id, "pos": e.pos, "radius": tuning.elite_blast_radius, "time": e.fuse_t})
			# Always draw, so the drop chance never changes what the rng hands out next.
			var roll := rng.randf()
			if e.elite or roll < tuning.item_drop_chance:
				drop_item("servo_trigger", e.pos)
			if wave > 0 and grunts_alive() == 0:
				_emit({"type": "wave_cleared", "wave": wave})
				next_wave_t = WAVE_DELAY
	return true

## Volatile corpses count down, then blast: the player (i-frames apply, so a dash through
## dodges it) and every living grunt within elite_blast_radius + their radius take
## grunt_damage × elite_blast_damage_mult, pushed away from the center. A volatile elite killed
## inside its own pack is a tool.
func _step_fuses(dt: float) -> void:
	for e in entities.values():
		if e.alive or e.fuse_t < 0.0:
			continue
		e.fuse_t -= dt
		if e.fuse_t > 0.0:
			continue
		e.fuse_t = -1.0
		_blast(e.pos, tuning.elite_blast_radius, tuning.grunt_damage * tuning.elite_blast_damage_mult)

func _blast(center: Vector2, radius: float, dmg: float) -> void:
	_emit({"type": "blast", "pos": center, "radius": radius})
	for t in entities.values().duplicate():
		if not t.alive:
			continue
		var d: float = t.pos.distance_to(center)
		if d > radius + t.radius:
			continue
		var dir: Vector2 = (t.pos - center) / d if d > 0.0001 else Vector2.ZERO
		damage(t.id, dmg, dir, tuning.knockback)

## Put an item on the floor.
func drop_item(kind: String, pos: Vector2) -> SimItem:
	var it := SimItem.new(_next_id, kind, pos)
	_next_id += 1
	items[it.id] = it
	_emit({"type": "drop", "id": it.id, "kind": it.kind, "pos": it.pos})
	return it

## Items within reach join the player's modifiers under their own id as source. No stacking
## limit: two servo triggers are +60 %.
func _pick_up(p: SimEntity) -> void:
	var reach := p.radius + PICKUP_REACH
	for id in items.keys():
		var it: SimItem = items[id]
		if it.pos.distance_squared_to(p.pos) > reach * reach:
			continue
		items.erase(id)
		picked_items.append(it)
		player_stats.add_all(it.id, it.mods)
		_refresh_body()
		_emit({"type": "pickup", "id": it.id, "kind": it.kind, "pos": it.pos, "mods": it.mods.duplicate(true)})

func _emit(ev: Dictionary) -> void:
	events.append(ev)

func is_dashing() -> bool:
	return dash_t > 0.0

func is_invulnerable() -> bool:
	return iframes_t > 0.0

func to_dict() -> Dictionary:
	var ents := []
	for e in entities.values():
		ents.append(e.to_dict())
	var projs := []
	for b in projectiles.values():
		projs.append(b.to_dict())
	var floor_items := []
	for it in items.values():
		floor_items.append(it.to_dict())
	var carried := []
	for it in picked_items:
		carried.append(it.to_dict())
	var evs := []
	for ev in events:
		var d := {}
		for k in ev:
			var v = ev[k]
			d[k] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01)] if v is Vector2 else v
		evs.append(d)
	return {
		"seed": seed, "tick": tick, "time": snappedf(time, 0.001),
		"player_id": player_id, "dashing": is_dashing(), "invulnerable": is_invulnerable(),
		"wave": wave, "grunts_alive": grunts_alive(), "next_wave_in": snappedf(next_wave_t, 0.01),
		"wave_packs": wave_packs.map(func(c: Vector2): return [snappedf(c.x, 0.01), snappedf(c.y, 0.01)]),
		"weapon": weapon.name,
		"player_stats": player_stats.to_dict(),
		"items": floor_items,
		"picked_items": carried,
		"stats": stats,
		"tuning": tuning.to_dict(),
		"level": level.to_dict(),
		"entities": ents,
		"projectiles": projs,
		"events": evs,
	}
