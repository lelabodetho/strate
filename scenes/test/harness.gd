extends Node3D
## Test harness scene: iso camera, 6x24 corridor, one player cube, three grunts. The agent runs this via tools/snap.sh.

@onready var cam: Camera3D = $Camera3D
@onready var world_view: WorldView = $WorldView
@onready var level_view: LevelView = $LevelView
@onready var input: PlayerInput = $PlayerInput
@onready var tuning_panel: TuningPanel = $TuningPanel

func _ready() -> void:
	input.camera = cam
	var w: SimWorld = GameState.world
	if w.player() == null:
		w.spawn(&"player", Vector2(0, 9))
		w.spawn(&"grunt", Vector2(-1.5, -3))
		w.spawn(&"grunt", Vector2(1.5, -6))
		w.spawn(&"grunt", Vector2(0, -9))
	level_view.build(w.level)
	world_view.debug = GameState.debug
	world_view.sync(w)

func _physics_process(dt: float) -> void:
	input.combat_locked = tuning_panel.is_open()
	GameState.step(dt, input.read())
	world_view.sync(GameState.world)
