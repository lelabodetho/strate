class_name LevelView
extends Node3D
## Builds floor and wall meshes from a SimLevel. Reads only.
## Ghost walls: wall segments on the camera side of the player and within GHOST_RADIUS of it
## fade to GHOST_ALPHA so the player is never hidden behind foreground walls or pillars.
## Occluder mode (render test): the same geometry drawn unshaded in KEY_COLOR inside the entity
## viewport's own world, so entities get correct depth occlusion and wall shadows while the post
## filter turns the key colour transparent. Ghosted segments are hidden instead of faded.

const FLOOR_COLOR := Color(0.16, 0.17, 0.19)
const WALL_COLOR := Color(0.3, 0.29, 0.3)
const SEGMENT_LEN := 2.0      # walls are split into segments so only the nearby part fades
const GHOST_ALPHA := 0.25
const GHOST_RADIUS := 3.0
const GHOST_FADE := 0.1       # seconds for a full 0 -> 1 alpha transition
const KEY_COLOR := Color(1.0, 0.0, 1.0)

var occluder := false
var _segments: Array = []     # [{mesh, mat: StandardMaterial3D, rect: Rect2, alpha: float}]

func build(level: SimLevel, as_occluder: bool = false) -> void:
	occluder = as_occluder
	for c in get_children():
		c.queue_free()
	_segments.clear()

	var floor_mat := _material(FLOOR_COLOR)
	for f in level.floors:
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = f.size
		floor_mesh.mesh = plane
		floor_mesh.material_override = floor_mat
		# A plane has nothing to cast; keeping it out of the shadow pass avoids the omni-light
		# self-shadow acne that darkened the floor under the player.
		floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var mat := _material(WALL_COLOR)
	m.material_override = mat
	var wc := r.get_center()
	m.position = Vector3(wc.x, SimLevel.WALL_HEIGHT * 0.5, wc.y)
	add_child(m)
	_segments.append({"mesh": m, "mat": mat, "rect": r, "alpha": 1.0})

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if occluder:
		mat.albedo_color = KEY_COLOR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.albedo_color = color
	return mat

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
		if occluder:
			# No fade: a ghosted wall stops hiding the entities behind it.
			s.mesh.visible = target >= 1.0
			continue
		if is_equal_approx(s.alpha, target):
			continue
		s.alpha = move_toward(s.alpha, target, dt / GHOST_FADE)
		var mat: StandardMaterial3D = s.mat
		mat.albedo_color.a = s.alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if s.alpha >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
