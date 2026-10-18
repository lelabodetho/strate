class_name WorldView
extends Node3D
## Owns one EntityView per sim entity, one small mesh per projectile, and short-lived
## feedback spawned from sim events. Reads only.

const PROJ_COLOR := Color(1.0, 0.8, 0.45)
const IMPACT_COLOR := Color(1.0, 0.85, 0.6, 0.9)
const IMPACT_RADIUS := 0.3
const IMPACT_TIME := 0.3
const DEBUG_PROJ_COLOR := Color(1.0, 0.8, 0.45, 0.9)

var debug: bool = false:
	set(v):
		debug = v
		_debug_dirty = true

var _views: Dictionary = {}       # id -> EntityView
var _proj_views: Dictionary = {}  # id -> MeshInstance3D
var _proj_mesh: SphereMesh
var _proj_mat: StandardMaterial3D
var _impact_mesh: CylinderMesh
var _transients: Array = []       # [{node, t, ttl}]
var _debug_dirty := false

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
	_transients.append({"node": m, "t": 0.0, "ttl": IMPACT_TIME})

func _process(dt: float) -> void:
	var keep := []
	for tr in _transients:
		tr.t += dt
		var k: float = tr.t / tr.ttl
		if k >= 1.0:
			tr.node.queue_free()
			continue
		var m: MeshInstance3D = tr.node
		var s := 1.0 + k * 0.8
		m.scale = Vector3(s, 1.0, s)
		var mat := m.material_override as StandardMaterial3D
		mat.albedo_color.a = IMPACT_COLOR.a * (1.0 - k)
		keep.append(tr)
	_transients = keep
