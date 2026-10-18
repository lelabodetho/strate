class_name SimWorld
extends RefCounted
## The whole game state and its update rule. Deterministic given (seed, commands).
## Rendering never touches this; input never bypasses step().

const PLAYER_SPEED := 6.0
const DASH_SPEED := 22.0
const DASH_TIME := 0.14
const DASH_COOLDOWN := 0.6
const ARENA_HALF := 9.0

var seed: int
var rng := RandomNumberGenerator.new()
var tick: int = 0
var time: float = 0.0
var entities: Dictionary = {}   # id -> SimEntity
var player_id: int = -1
var _next_id: int = 1

# Dash state (player only for now)
var dash_t: float = 0.0
var dash_cd: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO

func _init(p_seed: int = 0) -> void:
	seed = p_seed
	rng.seed = p_seed

func spawn(kind: StringName, pos: Vector2) -> SimEntity:
	var e := SimEntity.new(_next_id, kind, pos)
	_next_id += 1
	entities[e.id] = e
	if kind == &"player":
		player_id = e.id
	return e

func player() -> SimEntity:
	return entities.get(player_id)

func step(dt: float, cmd: Command) -> void:
	tick += 1
	time += dt
	var p := player()
	if p == null or not p.alive:
		return

	dash_cd = maxf(0.0, dash_cd - dt)
	if cmd.dash and dash_cd <= 0.0 and dash_t <= 0.0:
		dash_dir = cmd.move if cmd.move.length() > 0.1 else p.facing
		dash_t = DASH_TIME
		dash_cd = DASH_COOLDOWN

	if dash_t > 0.0:
		dash_t -= dt
		p.vel = dash_dir * DASH_SPEED
	else:
		p.vel = cmd.move * PLAYER_SPEED

	p.pos += p.vel * dt
	p.pos = p.pos.clamp(Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF))

	var to_aim := cmd.aim - p.pos
	if to_aim.length() > 0.05:
		p.facing = to_aim.normalized()

func is_dashing() -> bool:
	return dash_t > 0.0

func to_dict() -> Dictionary:
	var ents := []
	for e in entities.values():
		ents.append(e.to_dict())
	return {
		"seed": seed, "tick": tick, "time": snappedf(time, 0.001),
		"player_id": player_id, "dashing": is_dashing(),
		"entities": ents,
	}
