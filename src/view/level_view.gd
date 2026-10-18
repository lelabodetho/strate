class_name LevelView
extends Node3D
## Builds floor and wall meshes from a SimLevel. Reads only.
## Ghost walls: wall segments on the camera side of the player and within GHOST_RADIUS of it
## fade to GHOST_ALPHA so the player is never hidden behind foreground walls or pillars.

const FLOOR_COLOR := Color(0.16, 0.17, 0.19)
const WALL_COLOR := Color(0.3, 0.29, 0.3)
const SEGMENT_LEN := 2.0      # walls are split into segments so only the nearby part fades
const GHOST_ALPHA := 0.25
const GHOST_RADIUS := 3.0
const GHOST_FADE := 0.1       # seconds for a full 0 -> 1 alpha transition

var _segments: Array = []     # [{mat: StandardMaterial3D, rect: Rect2, alpha: float}]

func build(level: SimLevel) -> void:
	for c in get_children():
		c.queue_free()
	_segments.clear()

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = FLOOR_COLOR
	for f in level.floors:
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = f.size
		floor_mesh.mesh = plane
		floor_mesh.material_override = floor_mat
		var c := f.get_center()
		floor_mesh.position = Vector3(c.x, 0.0, c.y)
		add_child(floor_mesh)

	for w in level.walls:
		for seg in _split(w):
			_add_segment(seg)

## Cut a rect into pieces of at most SEGMENT_LEN along its long axis.
func _split(w: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var along_x := w.size.x >= w.size.y
	var length := w.size.x if along_x else w.size.y
	var n := maxi(1, ceili(length / SEGMENT_LEN))
	var piece := length / float(n)
	for i in n:
		if along_x:
			out.append(Rect2(w.position.x + i * piece, w.position.y, piece, w.size.y))
		else:
			out.append(Rect2(w.position.x, w.position.y + i * piece, w.size.x, piece))
	return out

func _add_segment(r: Rect2) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(r.size.x, SimLevel.WALL_HEIGHT, r.size.y)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	m.material_override = mat
	var wc := r.get_center()
	m.position = Vector3(wc.x, SimLevel.WALL_HEIGHT * 0.5, wc.y)
	add_child(m)
	_segments.append({"mat": mat, "rect": r, "alpha": 1.0})

func _process(dt: float) -> void:
	if _segments.is_empty() or GameState.world == null:
		return
	var p: SimEntity = GameState.world.player()
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null:
		return
	# Camera looks along its local -Z, so basis.z points from the scene toward the camera.
	var bz := cam.global_transform.basis.z
	var to_cam := Vector2(bz.x, bz.z).normalized()
	for s in _segments:
		var r: Rect2 = s.rect
		var closest := Vector2(clampf(p.pos.x, r.position.x, r.end.x), clampf(p.pos.y, r.position.y, r.end.y))
		# Between the camera and the player: the segment sits on the camera side of the player.
		var in_front: bool = (r.get_center() - p.pos).dot(to_cam) > 0.0
		var near: bool = closest.distance_to(p.pos) <= GHOST_RADIUS
		var target := GHOST_ALPHA if in_front and near else 1.0
		if is_equal_approx(s.alpha, target):
			continue
		s.alpha = move_toward(s.alpha, target, dt / GHOST_FADE)
		var mat: StandardMaterial3D = s.mat
		mat.albedo_color.a = s.alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if s.alpha >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
