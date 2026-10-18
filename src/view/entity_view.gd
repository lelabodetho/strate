class_name EntityView
extends Node3D
## Mirrors one SimEntity. Reads only; never writes to the sim.
## Feedback (flash, death pop, windup telegraph) is driven by sim state and sim events.

const PLAYER_COLOR := Color(0.85, 0.45, 0.2)
const PLAYER_DASH_COLOR := Color(1.0, 0.85, 0.5)
const GRUNT_COLOR := Color(0.5, 0.5, 0.55)
const WINDUP_COLOR := Color(0.6, 0.08, 0.06)
const WINDUP_SCALE := 1.15
const HIT_FLASH := Color(1.0, 1.0, 1.0)
const HIT_FLASH_TIME := 0.08
const DODGE_FLASH := Color(0.55, 0.9, 1.0)
const DODGE_FLASH_TIME := 0.15
const DEATH_TIME := 0.18
const DEATH_SCALE := 1.3
const DEBUG_BODY_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const DEBUG_HIT_COLOR := Color(1.0, 0.25, 0.2, 0.9)

var entity_id: int = -1
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _kind: StringName
var _state: StringName = &"idle"
var _dashing := false
var _alive := true
var _flash_t := 0.0
var _flash_color := Color.WHITE
var _death_t := -1.0   # >= 0 while playing the death pop
var _debug: Node3D

func setup(e: SimEntity) -> void:
	entity_id = e.id
	_kind = e.kind
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.6, 0.8)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = PLAYER_COLOR if e.kind == &"player" else GRUNT_COLOR
	_mesh.material_override = _mat
	_mesh.position.y = 0.8
	add_child(_mesh)

func sync(e: SimEntity, dashing: bool) -> void:
	position = Vector3(e.pos.x, 0.0, e.pos.y)
	rotation.y = atan2(-e.facing.x, -e.facing.y)
	_state = e.state
	_dashing = dashing
	_alive = e.alive
	visible = _alive or _death_t >= 0.0

func flash(color: Color, time: float) -> void:
	_flash_color = color
	_flash_t = time

func die() -> void:
	_death_t = DEATH_TIME
	visible = true

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

func _process(dt: float) -> void:
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
	_mesh.scale = Vector3(s, s, s)
	_mesh.position.y = 0.8 * s

	var c: Color
	if _kind == &"player":
		c = PLAYER_DASH_COLOR if _dashing else PLAYER_COLOR
	else:
		c = WINDUP_COLOR if _state == &"windup" else GRUNT_COLOR
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
