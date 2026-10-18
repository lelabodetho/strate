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

var seed: int
var level: SimLevel
var tuning: SimTuning
var rng := RandomNumberGenerator.new()
var tick: int = 0
var time: float = 0.0
var entities: Dictionary = {}   # id -> SimEntity
var projectiles: Dictionary = {}  # id -> SimProjectile (removed when they die)
var player_id: int = -1
var _next_id: int = 1
var fire_cd: float = 0.0
var wave: int = 0
var next_wave_t: float = 0.0   # > 0 while counting down to the next wave

# What happened during the last step(), for the view and the harness. Cleared every step.
# {type:"hit", target, pos, dir, damage} {type:"kill", target, pos} {type:"dodge", pos}
# {type:"shot", pos, dir} {type:"impact", pos} {type:"wave_cleared", wave}
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

## Spawn the player at the level's spawn point and start wave 1.
func begin() -> void:
	spawn(&"player", level.player_spawn)
	start_wave(1)

## Wave n: clear remaining grunts, spawn min(cap, 3 + 2*(n-1)) of them at seeded positions,
## spread over the level's floors, never within SPAWN_MIN_DIST of the player.
func start_wave(n: int) -> void:
	wave = n
	stats.wave = n
	next_wave_t = 0.0
	for id in entities.keys():
		if entities[id].kind == &"grunt":
			entities.erase(id)
	var p := player()
	var count := mini(WAVE_CAP, WAVE_BASE + WAVE_STEP * (n - 1))
	var placed: Array[Vector2] = []
	for i in count:
		var area: Rect2 = level.floors[i % level.floors.size()]
		var pos := _find_spawn(area, p, placed)
		spawn(&"grunt", pos)
		placed.append(pos)

func _find_spawn(area: Rect2, p: SimEntity, placed: Array[Vector2]) -> Vector2:
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
		if d_player > SPAWN_MIN_DIST:
			return pos
		if d_player > best_d:
			best_d = d_player
			best = pos
	return best if best != Vector2.INF else area.get_center()

## Same wave again: player back to full health at the spawn point, fresh grunts and bullets.
## Tuning is untouched.
func restart_wave() -> void:
	var p := player()
	if p != null:
		p.alive = true
		p.hp = p.hp_max
		p.pos = level.player_spawn
		p.vel = Vector2.ZERO
		p.facing = Vector2.DOWN
		p.state = &"idle"
	projectiles.clear()
	dash_t = 0.0
	dash_cd = 0.0
	iframes_t = 0.0
	fire_cd = 0.0
	start_wave(maxi(1, wave))

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
			e.hp_max = tuning.player_hp
			e.radius = tuning.player_radius
			e.hit_radius = tuning.player_radius
			player_id = e.id
		&"grunt":
			e.hp_max = tuning.grunt_hp
			e.radius = tuning.grunt_radius
			e.hit_radius = tuning.grunt_hit_radius
	e.hp = e.hp_max
	entities[e.id] = e
	return e

func player() -> SimEntity:
	return entities.get(player_id)

func step(dt: float, cmd: Command) -> void:
	tick += 1
	time += dt
	events.clear()
	var p := player()
	if p == null:
		return
	if p.alive:
		_step_player(dt, p, cmd)
	for e in entities.values():
		if e.kind == &"grunt" and e.alive:
			_step_grunt(dt, e, p)
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
		dash_t = tuning.dash_time
		dash_cd = tuning.dash_cooldown
		iframes_t = tuning.dash_iframes

	if dash_t > 0.0:
		dash_t -= dt
		p.vel = dash_dir * tuning.dash_speed
	else:
		p.vel = cmd.move * tuning.player_speed

	p.pos = level.resolve_circle(p.pos + p.vel * dt, p.radius)

	var to_aim := cmd.aim - p.pos
	if to_aim.length() > 0.05:
		p.facing = to_aim.normalized()

	fire_cd = maxf(0.0, fire_cd - dt)
	if cmd.attack and fire_cd <= 0.0 and not is_dashing():
		fire_cd = tuning.fire_interval
		_fire(p, p.facing)

func _fire(owner: SimEntity, dir: Vector2) -> void:
	var start := owner.pos + dir * tuning.muzzle_offset
	if level.is_blocked(start):
		return
	var b := SimProjectile.new(_next_id, owner, start, dir * tuning.proj_speed)
	_next_id += 1
	b.radius = tuning.proj_radius
	b.damage = tuning.proj_damage
	b.ttl = tuning.proj_ttl
	projectiles[b.id] = b
	stats.shots += 1
	_emit({"type": "shot", "pos": start, "dir": dir})

func _step_projectiles(dt: float) -> void:
	var dead: Array[int] = []
	for b in projectiles.values():
		b.ttl -= dt
		b.pos += b.vel * dt
		if level.is_blocked(b.pos):
			_emit({"type": "impact", "pos": b.pos})
			dead.append(b.id)
			continue
		if b.ttl <= 0.0:
			dead.append(b.id)
			continue
		for e in entities.values():
			if not e.alive or e.id == b.owner_id or e.kind == b.owner_kind:
				continue
			var r: float = e.hit_radius + b.radius
			if e.pos.distance_squared_to(b.pos) <= r * r:
				damage(e.id, b.damage, b.vel.normalized())
				if b.owner_id == player_id:
					stats.shots_hit += 1
				dead.append(b.id)
				break
	for id in dead:
		projectiles.erase(id)

func _step_grunt(dt: float, g: SimEntity, p: SimEntity) -> void:
	g.attack_cd = maxf(0.0, g.attack_cd - dt)
	g.vel = Vector2.ZERO
	var to_p := p.pos - g.pos
	var dist := to_p.length()
	var contact := g.radius + p.radius + tuning.grunt_reach

	match g.state:
		&"idle":
			if p.alive and dist <= tuning.grunt_aggro:
				g.state = &"chase"
		&"chase":
			if not p.alive:
				g.state = &"idle"
			elif dist <= contact and g.attack_cd <= 0.0:
				g.state = &"windup"
				g.state_t = tuning.grunt_windup
			elif dist > contact:
				g.vel = to_p / dist * tuning.grunt_speed
		&"windup":
			g.state_t -= dt
			if g.state_t <= 0.0:
				if p.alive and dist <= contact + tuning.grunt_hit_slack:
					damage(p.id, tuning.grunt_damage, g.facing)
				g.attack_cd = tuning.grunt_recover
				g.state = &"recover"
				g.state_t = tuning.grunt_recover
		&"recover":
			g.state_t -= dt
			if g.state_t <= 0.0:
				g.state = &"chase"

	if dist > 0.05:
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

## Apply damage to an entity, pushing it along `dir`. Returns true if it landed
## (false if dead, missing, or invulnerable).
func damage(id: int, amount: float, dir: Vector2 = Vector2.ZERO) -> bool:
	var e: SimEntity = entities.get(id)
	if e == null or not e.alive:
		return false
	if e.id == player_id and is_invulnerable():
		stats.dodged += 1
		_emit({"type": "dodge", "pos": e.pos})
		return false
	e.hp = maxf(0.0, e.hp - amount)
	if dir != Vector2.ZERO:
		e.pos = level.resolve_circle(e.pos + dir * tuning.knockback, e.radius)
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
		if e.kind == &"grunt" and wave > 0 and grunts_alive() == 0:
			_emit({"type": "wave_cleared", "wave": wave})
			next_wave_t = WAVE_DELAY
	return true

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
		"stats": stats,
		"tuning": tuning.to_dict(),
		"level": level.to_dict(),
		"entities": ents,
		"projectiles": projs,
		"events": evs,
	}
