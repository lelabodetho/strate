class_name EntityView
extends Node3D
## Mirrors one SimEntity. Reads only; never writes to the sim.

var entity_id: int = -1
var _mesh: MeshInstance3D

func setup(e: SimEntity) -> void:
	entity_id = e.id
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.6, 0.8)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.45, 0.2) if e.kind == &"player" else Color(0.5, 0.5, 0.55)
	_mesh.material_override = mat
	_mesh.position.y = 0.8
	add_child(_mesh)

func sync(e: SimEntity, dashing: bool) -> void:
	position = Vector3(e.pos.x, 0.0, e.pos.y)
	rotation.y = atan2(-e.facing.x, -e.facing.y)
	visible = e.alive
	if _mesh and _mesh.material_override:
		var mat := _mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.85, 0.5) if dashing and e.kind == &"player" else (Color(0.85, 0.45, 0.2) if e.kind == &"player" else Color(0.5, 0.5, 0.55))
