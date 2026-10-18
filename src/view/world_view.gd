class_name WorldView
extends Node3D
## Owns one EntityView per sim entity, one small mesh per projectile, and short-lived
## feedback spawned from sim events. Reads only.

const PROJ_COLOR := Color(1.0, 0.8, 0.45)
const IMPACT_COLOR := Color(1.0, 0.85, 0.6, 0.9)
const IMPACT_RADIUS := 0.3
const IMPACT_TIME := 0.3
const DEBUG_PROJ_COLOR := Color(1.0, 0.8, 0.45, 0.9)
const SWING_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const SWING_TIME := 0.1
const EXPLOSION_COLOR := Color(1.0, 0.6, 0.3, 0.8)
const EXPLOSION_TIME := 0.35

var debug: bool = false:
	set(v):
		debug = v
		_debug_dirty = true

var _views: Dictionary = {}       # id -> EntityView
var _proj_views: Dictionary = {}  # id -> MeshInstance3D
var _proj_mesh: SphereMesh
var _proj_mat: StandardMaterial3D
var _impact_mesh: CylinderMesh
var _transients: Array = []       # [{node, t, ttl, kind}]
var _debug_dirty := false
var _last_event_tick := -1        # events are consumed once per sim tick

func _ready() -> void:
	_proj_mesh = SphereMesh.new()
	_proj_mesh.radius = 0.15
	_proj_mesh.height = 0.3
	_proj_mat = StandardMaterial3D.new()
	_proj_mat.albedo_color = PROJ_COLOR
	_proj_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_mesh = CylinderMesh.new()
	_impact_mesh.top_radius = IMPACT_RADIUS
	_impact_mesh.bottom_radius = IMPACT_RADIUS
	_impact_mesh.height = 0.02

func sync(world: SimWorld) -> void:
	for e in world.entities.values():
		var v: EntityView = _views.get(e.id)
		if v == null:
			v = EntityView.new()
			v.setup(e)
			add_child(v)
			_views[e.id] = v
			v.set_debug(debug, e)
		elif _debug_dirty:
			v.set_debug(debug, e)
		v.sync(e, world.is_dashing() and e.id == world.player_id)
	_debug_dirty = false
	for id in _views.keys():
		if not world.entities.has(id):
			_views[id].queue_free()
			_views.erase(id)

	for b in world.projectiles.values():
		var m: MeshInstance3D = _proj_views.get(b.id)
		if m == null:
			m = MeshInstance3D.new()
			m.mesh = _proj_mesh
			m.material_override = _proj_mat
			if debug:
				m.add_child(EntityView.make_ring(b.radius, DEBUG_PROJ_COLOR))
			add_child(m)
			_proj_views[b.id] = m
		m.position = Vector3(b.pos.x, 0.9, b.pos.y)
	for id in _proj_views.keys():
		if not world.projectiles.has(id):
			_proj_views[id].queue_free()
			_proj_views.erase(id)

	if world.tick != _last_event_tick:
		_last_event_tick = world.tick
		for ev in world.events:
			_on_event(ev, world)

func _on_event(ev: Dictionary, world: SimWorld) -> void:
	match ev.type:
		"hit":
			var v: EntityView = _views.get(ev.target)
			if v != null:
				v.flash(EntityView.HIT_FLASH, EntityView.HIT_FLASH_TIME)
		"kill":
			var v: EntityView = _views.get(ev.target)
			if v != null:
				v.die()
		"dodge":
			var v: EntityView = _views.get(world.player_id)
			if v != null:
				v.flash(EntityView.DODGE_FLASH, EntityView.DODGE_FLASH_TIME)
		"impact":
			_spawn_impact(ev.pos)
		"swing":
			_spawn_swing(ev.pos, ev.dir, world.weapon)
		"explosion":
			_spawn_explosion(ev.pos, ev.radius)

func _spawn_impact(pos: Vector2) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _impact_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = IMPACT_COLOR
	m.material_override = mat
	m.position = Vector3(pos.x, 0.02, pos.y)
	add_child(m)
	_transients.append({"node": m, "t": 0.0, "ttl": IMPACT_TIME, "kind": "impact"})

## Brute: a flat white sector in front of the player, gone in 100 ms.
func _spawn_swing(pos: Vector2, dir: Vector2, weapon: WeaponProfile) -> void:
	var im := ImmediateMesh.new()
	var half := deg_to_rad(weapon.cone_angle_deg * 0.5)
	var base := atan2(dir.y, dir.x)
	var segments := 12
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := base - half + (2.0 * half) * float(i) / float(segments)
		var a1 := base - half + (2.0 * half) * float(i + 1) / float(segments)
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(Vector3(cos(a1), 0.0, sin(a1)) * weapon.cone_range)
		im.surface_add_vertex(Vector3(cos(a0), 0.0, sin(a0)) * weapon.cone_range)
	im.surface_end()
	var m := MeshInstance3D.new()
	m.mesh = im
	m.material_override = _flat_material(SWING_COLOR)
	m.position = Vector3(pos.x, 0.05, pos.y)
	add_child(m)
	_transients.append({"node": m, "t": 0.0, "ttl": SWING_TIME, "kind": "swing"})

## Technomancer: a ground disc growing to the blast radius, then fading.
func _spawn_explosion(pos: Vector2, radius: float) -> void:
	var m := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	m.mesh = disc
	m.material_override = _flat_material(EXPLOSION_COLOR)
	m.position = Vector3(pos.x, 0.04, pos.y)
	m.scale = Vector3(0.1, 1.0, 0.1)
	add_child(m)
	_transients.append({"node": m, "t": 0.0, "ttl": EXPLOSION_TIME, "kind": "explosion"})

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat

func _process(dt: float) -> void:
	var keep := []
	for tr in _transients:
		tr.t += dt
		var k: float = tr.t / tr.ttl
		if k >= 1.0:
			tr.node.queue_free()
			continue
		var m: MeshInstance3D = tr.node
		var mat := m.material_override as StandardMaterial3D
		match tr.kind:
			"impact":
				var s := 1.0 + k * 0.8
				m.scale = Vector3(s, 1.0, s)
				mat.albedo_color.a = IMPACT_COLOR.a * (1.0 - k)
			"swing":
				mat.albedo_color.a = SWING_COLOR.a * (1.0 - k)
			"explosion":
				# Grow fast over the first third, then fade.
				var g := clampf(k * 3.0, 0.0, 1.0)
				var s := lerpf(0.1, 1.0, 1.0 - (1.0 - g) * (1.0 - g))
				m.scale = Vector3(s, 1.0, s)
				mat.albedo_color.a = EXPLOSION_COLOR.a * (1.0 - maxf(0.0, (k - 0.33) / 0.67))
		keep.append(tr)
	_transients = keep
