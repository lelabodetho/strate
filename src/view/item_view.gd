class_name ItemView
extends Node3D
## Mirrors one SimItem on the floor: a small octahedron that floats and spins, over a ground
## halo and a real light (UI rule 2: rarity is light). Colour by rarity: common steel white,
## rare cold cyan, epic the accent orange with a stronger light and a bigger halo. Never red:
## red is the threat tone. On pickup it flashes and shoots up toward the HUD, then frees itself.
## Reads only.

const ITEM_COLOR := Color(1.0, 0.55, 0.2)   # epic; the HUD and the pickup flash use the same
const RARITY_COLORS := {
	&"common": Color(0.82, 0.85, 0.9),
	&"rare": Color(0.4, 0.8, 0.9),
	&"epic": ITEM_COLOR,
}
const RARITY_HALO := {&"common": 0.85, &"rare": 1.0, &"epic": 1.45}     # × HALO_RADIUS
const RARITY_LIGHT := {&"common": 0.8, &"rare": 1.3, &"epic": 2.2}      # × LIGHT_ENERGY
const HALO_ALPHA := 0.3
const FLASH_COLOR := Color(1.0, 1.0, 1.0)
const SIZE := 0.3            # half-width of the octahedron
const HEIGHT := 0.45         # half-height
const HOVER_Y := 0.75
const HOVER_AMP := 0.12
const HOVER_SPEED := 2.2
const SPIN_SPEED := 1.3      # rad/s
const HALO_RADIUS := 0.7
const LIGHT_RANGE := 3.5
const LIGHT_ENERGY := 1.4
const PICKUP_TIME := 0.45
const PICKUP_RISE := 6.0     # units climbed by the end of the pickup animation
const FLASH_TIME := 0.1

var item_id: int = -1
var color: Color = ITEM_COLOR
var leaving: bool = false    # pickup animation in progress; the view frees itself at the end
var _light_energy := LIGHT_ENERGY
var _halo_color: Color

var _gem: MeshInstance3D
var _gem_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0
var _leave_t := 0.0
var _phase := 0.0

func setup(it: SimItem) -> void:
	item_id = it.id
	_phase = float(it.id) * 1.7   # items do not bob in sync
	position = Vector3(it.pos.x, 0.0, it.pos.y)
	color = RARITY_COLORS.get(it.rarity, ITEM_COLOR)
	_halo_color = Color(color, HALO_ALPHA)
	_light_energy = LIGHT_ENERGY * float(RARITY_LIGHT.get(it.rarity, 1.0))
	var halo_r: float = HALO_RADIUS * float(RARITY_HALO.get(it.rarity, 1.0))

	_gem = MeshInstance3D.new()
	_gem.mesh = make_octahedron(SIZE, HEIGHT)
	_gem_mat = StandardMaterial3D.new()
	_gem_mat.albedo_color = color
	_gem_mat.emission_enabled = true
	_gem_mat.emission = color
	_gem_mat.emission_energy_multiplier = 0.6
	_gem.material_override = _gem_mat
	_gem.position.y = HOVER_Y
	add_child(_gem)

	_halo = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = halo_r
	disc.bottom_radius = halo_r
	disc.height = 0.02
	_halo.mesh = disc
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.albedo_color = _halo_color
	_halo.material_override = _halo_mat
	_halo.position.y = 0.03
	add_child(_halo)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = LIGHT_RANGE
	_light.light_energy = _light_energy
	_light.position.y = HOVER_Y
	add_child(_light)

func sync(it: SimItem) -> void:
	position = Vector3(it.pos.x, 0.0, it.pos.y)

## Called on the sim's pickup event: flash, rise toward the HUD, free.
func pickup() -> void:
	leaving = true
	_leave_t = 0.0

func _process(dt: float) -> void:
	_t += dt
	_gem.rotation.y += SPIN_SPEED * dt
	if not leaving:
		var bob := sin(_t * HOVER_SPEED + _phase)
		_gem.position.y = HOVER_Y + HOVER_AMP * bob
		_light.position.y = _gem.position.y
		var pulse := 1.0 + 0.08 * bob
		_halo.scale = Vector3(pulse, 1.0, pulse)
		return
	_leave_t += dt
	var k := _leave_t / PICKUP_TIME
	if k >= 1.0:
		queue_free()
		return
	_gem_mat.albedo_color = FLASH_COLOR if _leave_t < FLASH_TIME else color
	_gem_mat.emission = _gem_mat.albedo_color
	_gem_mat.emission_energy_multiplier = 1.5 if _leave_t < FLASH_TIME else 0.6
	# Ease-in climb, shrinking on the way; halo and light fade out fast.
	_gem.position.y = HOVER_Y + PICKUP_RISE * k * k
	var s := lerpf(1.3, 0.2, k)
	_gem.scale = Vector3(s, s, s)
	_gem.rotation.y += SPIN_SPEED * 4.0 * dt
	_halo_mat.albedo_color.a = HALO_ALPHA * maxf(0.0, 1.0 - k * 2.0)
	_light.light_energy = _light_energy * (1.0 + 2.0 * (1.0 - k)) * maxf(0.0, 1.0 - k * 1.5)
	_light.position.y = _gem.position.y

## Two square pyramids base to base, flat shaded.
static func make_octahedron(r: float, h: float) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	var top := Vector3(0, h, 0)
	var bottom := Vector3(0, -h, 0)
	var ring := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_tri(im, top, b, a)
		_tri(im, bottom, a, b)
	im.surface_end()
	return im

static func _tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	im.surface_set_normal(n)
	im.surface_add_vertex(a)
	im.surface_set_normal(n)
	im.surface_add_vertex(b)
	im.surface_set_normal(n)
	im.surface_add_vertex(c)
