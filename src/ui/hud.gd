class_name Hud
extends CanvasLayer
## Minimal HUD for the tuning arena: wave line top-left, "R pour recommencer" on death.
## Meta keys (physical, layout-independent): R restart the wave (when dead), N next wave, 0 back to wave 1.
## Everything goes through GameState; the HUD never touches the sim.

const TEXT_COLOR := Color(0.85, 0.82, 0.78)
const FLASH_COLOR := Color(1.0, 0.85, 0.5)
const FLASH_TIME := 0.6

var _wave_label: Label
var _death_label: Label
var _flash_t := 0.0

func _ready() -> void:
	layer = 20
	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 20)
	_wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_wave_label.add_theme_constant_override("shadow_offset_x", 1)
	_wave_label.add_theme_constant_override("shadow_offset_y", 1)
	_wave_label.position = Vector2(16, 12)
	add_child(_wave_label)

	_death_label = Label.new()
	_death_label.text = "R pour recommencer"
	_death_label.add_theme_font_size_override("font_size", 36)
	_death_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	_death_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_death_label.add_theme_constant_override("shadow_offset_x", 2)
	_death_label.add_theme_constant_override("shadow_offset_y", 2)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_label.visible = false
	add_child(_death_label)

	GameState.wave_cleared.connect(_on_wave_cleared)

func _on_wave_cleared(_wave: int) -> void:
	_flash_t = FLASH_TIME

func _process(dt: float) -> void:
	var w: SimWorld = GameState.world
	var p: SimEntity = w.player()
	var hp := int(round(p.hp)) if p != null else 0
	_wave_label.text = "Vague %d · %d grunts · %d PV" % [w.wave, w.grunts_alive(), hp]
	_flash_t = maxf(0.0, _flash_t - dt)
	var k := _flash_t / FLASH_TIME
	_wave_label.add_theme_color_override("font_color", TEXT_COLOR.lerp(FLASH_COLOR, k))
	_wave_label.scale = Vector2.ONE * (1.0 + 0.25 * k)
	_death_label.visible = p != null and not p.alive

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_R:
			if _death_label.visible:
				GameState.restart()
				get_viewport().set_input_as_handled()
		KEY_N:
			GameState.next_wave()
			get_viewport().set_input_as_handled()
		KEY_0, KEY_KP_0:
			GameState.reset_waves()
			get_viewport().set_input_as_handled()
