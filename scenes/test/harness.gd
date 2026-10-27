extends Node3D
## Test harness scene: the tuning arena. Iso camera following the player, waves of grunts,
## tuning panel (Tab), HUD. The agent runs this via tools/snap.sh.

const CAM_OFFSET := Vector3(12, 12, 12)
const CAM_SMOOTH := 8.0

@onready var cam: Camera3D = $Camera3D
@onready var world_view: WorldView = $WorldView
@onready var level_view: LevelView = $LevelView
@onready var input: PlayerInput = $PlayerInput
@onready var tuning_panel: TuningPanel = $TuningPanel
@onready var hud: Hud = $Hud
var inventory_panel: InventoryPanel

func _ready() -> void:
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	input.camera = cam
	hud.camera = cam
	var w: SimWorld = GameState.world
	level_view.build(w.level)
	world_view.debug = GameState.debug
	world_view.sync(w)
	cam.position = _cam_target()
	GameState.level_changed.connect(_on_level_changed)

## A new world (hub <-> strate, death): rebuild the geometry, drop every entity view.
func _on_level_changed() -> void:
	var w: SimWorld = GameState.world
	level_view.build(w.level)
	world_view.reset()
	world_view.sync(w)
	cam.position = _cam_target()

func _cam_target() -> Vector3:
	var p: SimEntity = GameState.world.player()
	if p == null:
		return CAM_OFFSET
	return Vector3(p.pos.x, 0.0, p.pos.y) + CAM_OFFSET

func _process(dt: float) -> void:
	cam.position = cam.position.lerp(_cam_target(), 1.0 - exp(-CAM_SMOOTH * dt))

func _physics_process(dt: float) -> void:
	GameState.paused = tuning_panel.is_open()
	# The bag does not pause the world, but attack / dash / E are off while it is open.
	input.combat_locked = GameState.paused or inventory_panel.is_open()
	GameState.step(dt, input.read())
	GameState.set_hovered(input.hovered_item_id)
	world_view.hovered_item = GameState.hovered_item
	world_view.sync(GameState.world)
