class_name EntityView
extends Node3D
## Mirrors one SimEntity. Reads only; never writes to the sim.
## Feedback (flash, death pop, windup telegraph) is driven by sim state and sim events.
## Player: the attack windup lifts and brightens the body (orange, never red: it is not a
## threat), the recovery settles it back a little under its size. The enemy the cursor snaps
## to (SimWorld.target_id) wears a thin DANGER ring at its feet.
## Elites: bigger darker body with a DANGER ring on the ground; shielded = a steel plate in
## front, volatile = body pulsing toward DANGER, fast = thinner and taller. Never orange.

const PLAYER_COLOR := Color(0.85, 0.45, 0.2)
const PLAYER_DASH_COLOR := Color(1.0, 0.85, 0.5)
const PLAYER_WINDUP_COLOR := Color(1.0, 0.62, 0.3)
const PLAYER_WINDUP_SCALE := 1.15
const PLAYER_RECOVERY_SCALE := 0.94
const GRUNT_COLOR := Color(0.5, 0.5, 0.55)
const ELITE_COLOR := Color(0.3, 0.31, 0.36)
const DANGER_COLOR := Color(0.9, 0.15, 0.1)
const TARGET_RING_GAP := 0.35
const TARGET_RING_WIDTH := 0.04
const SHIELD_COLOR := Color(0.72, 0.7, 0.68)
const BLOCKED_FLASH := Color(0.55, 0.65, 0.9)
const BLOCKED_FLASH_TIME := 0.1
const VOLATILE_PULSE := 6.0   # rad/s
const WINDUP_COLOR := Color(0.6, 0.08, 0.06)
const WINDUP_SCALE := 1.15
const HIT_FLASH := Color(1.0, 1.0, 1.0)
const HIT_FLASH_TIME := 0.08
const DODGE_FLASH := Color(0.55, 0.9, 1.0)
const DODGE_FLASH_TIME := 0.15
const AGGRO_FLASH := Color(1.0, 0.75, 0.4)
const AGGRO_FLASH_TIME := 0.12
const DEATH_TIME := 0.18
const DEATH_SCALE := 1.3
const FALLEN_COLOR := Color(0.4, 0.22, 0.12)
const DEBUG_BODY_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const DEBUG_HIT_COLOR := Color(1.0, 0.25, 0.2, 0.9)

var entity_id: int = -1
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _kind: StringName
var _state: StringName = &"idle"
var _dashing := false
var _attack_phase: StringName = &"idle"   # player only
var _alive := true
var _flash_t := 0.0
var _flash_color := Color.WHITE
var _death_t := -1.0   # >= 0 while playing the death pop
var _fallen := false   # player only: stays on the ground after death
var _debug: Node3D
var _elite := false
var _affixes: Array[StringName] = []
var _t := 0.0
var _target_ring: MeshInstance3D   # built on first use

func setup(e: SimEntity) -> void:
	entity_id = e.id
	_kind = e.kind
	_elite = e.elite
	_affixes = e.affixes.duplicate()
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.6, 0.8)
	if _elite:
		var k: float = GameState.world.tuning.elite_body_mult if GameState.world != null else 1.2
		box.size = (Vector3(0.6, 2.0, 0.6) if e.has_affix(&"fast") else Vector3(0.8, 1.6, 0.8)) * k
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = PLAYER_COLOR if e.kind == &"player" else (ELITE_COLOR if _elite else GRUNT_COLOR)
	_mesh.material_override = _mat
	_mesh.position.y = box.size.y * 0.5
	add_child(_mesh)
	if _elite:
		add_child(make_ring(e.radius + 0.15, DANGER_COLOR, 0.08))
		if e.has_affix(&"shielded"):
			# A thin plate in front of the body; the whole view turns with the facing.
			var plate := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(box.size.x + 0.3, box.size.y * 0.75, 0.08)
			plate.mesh = pb
			var pm := StandardMaterial3D.new()
			pm.albedo_color = SHIELD_COLOR
			plate.material_override = pm
			plate.position = Vector3(0.0, pb.size.y * 0.5 + 0.1, -(e.radius + 0.2))
			_mesh.add_child(plate)
			plate.position.y -= _mesh.position.y

func sync(e: SimEntity, dashing: bool, attack_phase: StringName = &"idle") -> void:
	position = Vector3(e.pos.x, 0.0, e.pos.y)
	rotation.y = atan2(-e.facing.x, -e.facing.y)
	_state = e.state
	_dashing = dashing
	_attack_phase = attack_phase
	if e.alive and not _alive:
		# Revived (wave restart): stand back up.
		_fallen = false
		_death_t = -1.0
		_flash_t = 0.0
		_mesh.rotation = Vector3.ZERO
		_mesh.position = Vector3(0.0, _body_height() * 0.5, 0.0)
	_alive = e.alive
	visible = _alive or _death_t >= 0.0 or _fallen

## Show or hide the targeting ring (grunts only; the sim never targets the player).
func set_targeted(on: bool, e: SimEntity) -> void:
	if on and _target_ring == null:
		_target_ring = make_ring(e.radius + TARGET_RING_GAP, DANGER_COLOR, TARGET_RING_WIDTH)
		add_child(_target_ring)
	if _target_ring != null:
		_target_ring.visible = on and e.alive

func flash(color: Color, time: float) -> void:
	_flash_color = color
	_flash_t = time

func die() -> void:
	visible = true
	if _kind == &"player":
		_fallen = true
	else:
		_death_t = DEATH_TIME

func set_debug(enabled: bool, e: SimEntity) -> void:
	if _debug != null:
		_debug.queue_free()
		_debug = null
	if not enabled:
		return
	_debug = Node3D.new()
	_debug.add_child(make_ring(e.radius, DEBUG_BODY_COLOR))
	_debug.add_child(make_ring(e.hit_radius, DEBUG_HIT_COLOR))
	add_child(_debug)

func _body_height() -> float:
	return (_mesh.mesh as BoxMesh).size.y

func _process(dt: float) -> void:
	_t += dt
	_flash_t = maxf(0.0, _flash_t - dt)
	var s := 1.0
	if _death_t >= 0.0:
		_death_t -= dt
		if _death_t < 0.0:
			visible = false
		else:
			s = lerpf(1.0, DEATH_SCALE, _death_t / DEATH_TIME)
	elif _state == &"windup":
		s = WINDUP_SCALE
	elif _kind == &"player" and not _dashing:
		if _attack_phase == &"windup":
			s = PLAYER_WINDUP_SCALE
		elif _attack_phase == &"recovery":
			s = PLAYER_RECOVERY_SCALE
	_mesh.scale = Vector3(s, s, s)
	if _fallen:
		# Lying on its back, head toward where it was facing.
		_mesh.rotation.x = -PI / 2
		_mesh.position = Vector3(0.0, 0.4, -0.4)
	else:
		_mesh.position.y = _body_height() * 0.5 * s

	var c: Color
	if _fallen:
		c = FALLEN_COLOR
	elif _kind == &"player":
		c = PLAYER_DASH_COLOR if _dashing else (PLAYER_WINDUP_COLOR if _attack_phase == &"windup" else PLAYER_COLOR)
	elif _state == &"windup":
		c = WINDUP_COLOR
	elif _elite:
		c = ELITE_COLOR
		if _affixes.has(&"volatile"):
			c = ELITE_COLOR.lerp(DANGER_COLOR, 0.5 + 0.5 * sin(_t * VOLATILE_PULSE))
	else:
		c = GRUNT_COLOR
	if _flash_t > 0.0:
		c = _flash_color
	_mat.albedo_color = c

## A flat ring on the ground, drawn through geometry, for debug overlays.
static func make_ring(radius: float, color: Color, width: float = 0.05, segments: int = 40) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var d := Vector3(cos(a), 0.0, sin(a))
		im.surface_add_vertex(d * (radius - width * 0.5) + Vector3(0, 0.03, 0))
		im.surface_add_vertex(d * (radius + width * 0.5) + Vector3(0, 0.03, 0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	m.albedo_color = color
	mi.material_override = m
	return mi
