class_name LevelView
extends Node3D
## Builds floor and wall meshes from a SimLevel. Reads only.

func build(level: SimLevel) -> void:
	for c in get_children():
		c.queue_free()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = level.bounds.size
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.19)
	floor_mesh.material_override = floor_mat
	var c := level.bounds.get_center()
	floor_mesh.position = Vector3(c.x, 0.0, c.y)
	add_child(floor_mesh)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.3, 0.29, 0.3)
	for w in level.walls:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w.size.x, SimLevel.WALL_HEIGHT, w.size.y)
		m.mesh = box
		m.material_override = wall_mat
		var wc := w.get_center()
		m.position = Vector3(wc.x, SimLevel.WALL_HEIGHT * 0.5, wc.y)
		add_child(m)
