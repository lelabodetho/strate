extends Node
## Render test scene: the tuning arena, same sim and input, rendered through two low-resolution
## SubViewports (1/2, nearest upscale: at 1/3 the cubes lose their edges) with the post filter
## of src/view/post_filter.gdshader.
##   WorldVP   level geometry and lights, filter mode from GameState (F cycles)
##   EntityVP  its own World3D: entities, bullets, items, always mode pixel, over a copy of the
##             level drawn unshaded in the key colour (correct occlusion, keyed out by the
##             filter) and copies of the lights so both layers are lit the same.
## Lights: a warm omni that follows the player, two cold omnis fixed in the room, shadows on.
## Camera: orthographic iso (45-degree yaw), pitch and size from the look, applied every frame
## to the world camera and copied to the entity camera.

const CAM_DIST := 30.0        # orthographic: only the near/far window depends on it
const CAM_YAW := PI / 4
const CAM_SMOOTH := 8.0
const PLAYER_LIGHT_HEIGHT := 3.0

@onready var world_container: SubViewportContainer = $WorldContainer
@onready var entity_container: SubViewportContainer = $EntityContainer
@onready var world_vp: SubViewport = $WorldContainer/WorldVP
@onready var entity_vp: SubViewport = $EntityContainer/EntityVP
@onready var cam: Camera3D = $WorldContainer/WorldVP/Camera3D
@onready var entity_cam: Camera3D = $EntityContainer/EntityVP/EntityCam
@onready var level_view: LevelView = $WorldContainer/WorldVP/LevelView
@onready var occluder: LevelView = $EntityContainer/EntityVP/Occluder
@onready var world_view: WorldView = $EntityContainer/EntityVP/WorldView
@onready var player_lights: Array[OmniLight3D] = [$WorldContainer/WorldVP/PlayerLight, $EntityContainer/EntityVP/PlayerLight]
@onready var cold_lights: Array[OmniLight3D] = [$WorldContainer/WorldVP/RoomLightA, $WorldContainer/WorldVP/RoomLightB,
	$EntityContainer/EntityVP/RoomLightA, $EntityContainer/EntityVP/RoomLightB]
@onready var input: PlayerInput = $PlayerInput
@onready var tuning_panel: TuningPanel = $TuningPanel
@onready var hud: Hud = $Hud
var inventory_panel: InventoryPanel

func _ready() -> void:
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	GameState.render_scene = true
	input.camera = cam
	hud.camera = cam
	var w: SimWorld = GameState.world
	level_view.build(w.level)
	occluder.build(w.level, true)
	world_view.debug = GameState.debug
	world_view.sync(w)
	cam.position = _cam_target()
	_apply_camera()
	_sync_cameras()
	_apply_look()
	GameState.capturing.connect(_dump_viewports)

## Capture mode: the raw low-res world and entity viewports, before the filter.
func _dump_viewports(base: String) -> void:
	world_vp.get_texture().get_image().save_png(base + "_world.png")
	entity_vp.get_texture().get_image().save_png(base + "_entities.png")

## Direction from the looked-at ground point to the camera, for the look's pitch.
func _cam_offset() -> Vector3:
	var pitch := deg_to_rad(GameState.look.camera_pitch)
	return Vector3(sin(CAM_YAW) * cos(pitch), sin(pitch), cos(CAM_YAW) * cos(pitch)) * CAM_DIST

func _cam_target() -> Vector3:
	var p: SimEntity = GameState.world.player()
	var ground := Vector3.ZERO if p == null else Vector3(p.pos.x, 0.0, p.pos.y)
	return ground + _cam_offset()

## Pitch and size from the look; the orientation never lerps, only the position does.
func _apply_camera() -> void:
	cam.basis = Basis.looking_at(-_cam_offset().normalized(), Vector3.UP)
	cam.size = GameState.look.camera_size

func _sync_cameras() -> void:
	entity_cam.global_transform = cam.global_transform
	entity_cam.projection = cam.projection
	entity_cam.size = cam.size
	entity_cam.near = cam.near
	entity_cam.far = cam.far

## Push GameState.look onto the shaders, the viewports and the lights.
func _apply_look() -> void:
	var look: Look = GameState.look
	var m := world_container.material as ShaderMaterial
	m.set_shader_parameter("mode", look.mode_index())
	m.set_shader_parameter("dither_strength", look.dither)
	m.set_shader_parameter("scanlines", look.scanlines)
	var e := entity_container.material as ShaderMaterial
	e.set_shader_parameter("mode", 0)
	e.set_shader_parameter("scanlines", look.scanlines)
	e.set_shader_parameter("key_transparent", true)
	e.set_shader_parameter("key_color", LevelView.KEY_COLOR)
	for c in [world_container, entity_container]:
		if c.stretch_shrink != look.viewport_scale:
			c.stretch_shrink = look.viewport_scale
	for l in player_lights:
		l.light_color = look.player_light_color
		l.light_energy = look.player_light_energy
	for l in cold_lights:
		l.light_energy = look.cold_light_energy

func _process(dt: float) -> void:
	cam.position = cam.position.lerp(_cam_target(), 1.0 - exp(-CAM_SMOOTH * dt))
	_apply_camera()
	_sync_cameras()
	var p: SimEntity = GameState.world.player()
	if p != null:
		for l in player_lights:
			l.position = Vector3(p.pos.x, PLAYER_LIGHT_HEIGHT, p.pos.y)
	_apply_look()

func _physics_process(dt: float) -> void:
	GameState.paused = tuning_panel.is_open()
	# The bag does not pause the world, but attack / dash / E are off while it is open.
	input.combat_locked = GameState.paused or inventory_panel.is_open()
	GameState.step(dt, input.read())
	GameState.set_hovered(input.hovered_item_id)
	world_view.hovered_item = GameState.hovered_item
	world_view.sync(GameState.world)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		GameState.cycle_render_mode()
		tuning_panel.refresh()
		get_viewport().set_input_as_handled()
