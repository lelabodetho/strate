class_name Hud
extends CanvasLayer
## Minimal HUD for the tuning arena: wave line top-left (with the effective cadence), an elite
## line while one is alive, one line per carried item under it, "R pour recommencer" on death.
## Meta keys (physical, layout-independent): R restart the wave (when dead), N next wave,
## 0 back to wave 1, 1/2/3 weapon profile.
## Everything goes through GameState; the HUD never touches the sim.

const TEXT_COLOR := Color(0.85, 0.82, 0.78)
const FLASH_COLOR := Color(1.0, 0.85, 0.5)
const FLASH_TIME := 0.6
const ITEM_COLOR := Color(1.0, 0.6, 0.25)
const DANGER_COLOR := Color(0.9, 0.15, 0.1)
const AFFIX_NAMES := {"shielded": "blindé", "volatile": "instable", "fast": "célère"}
const LINE_H := 22

# Player-facing names for item kinds and stats (view-side only; the sim knows keys).
const ITEM_NAMES := {"servo_trigger": "Servo-gâchette"}
const STAT_NAMES := {"fire_rate": "cadence", "proj_damage": "dégâts", "proj_speed": "vitesse de tir",
	"player_speed": "vitesse", "player_hp": "PV", "knockback": "recul", "dash_cooldown": "recharge du dash"}

var _wave_label: Label
var _elite_label: Label
var _items_label: Label
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

	_elite_label = Label.new()
	_elite_label.add_theme_font_size_override("font_size", 16)
	_elite_label.add_theme_color_override("font_color", DANGER_COLOR)
	_elite_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_elite_label.add_theme_constant_override("shadow_offset_x", 1)
	_elite_label.add_theme_constant_override("shadow_offset_y", 1)
	_elite_label.position = Vector2(16, 42)
	_elite_label.visible = false
	add_child(_elite_label)

	_items_label = Label.new()
	_items_label.add_theme_font_size_override("font_size", 16)
	_items_label.add_theme_color_override("font_color", ITEM_COLOR)
	_items_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_items_label.add_theme_constant_override("shadow_offset_x", 1)
	_items_label.add_theme_constant_override("shadow_offset_y", 1)
	_items_label.position = Vector2(16, 42)
	add_child(_items_label)

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
	var line := "Vague %d · %d grunts · %d PV · %s · cadence %.1f/s" % [w.wave, w.grunts_alive(), hp, w.weapon.name, w.player_stats.value("fire_rate")]
	var preset := GameState.preset_label()
	if not preset.is_empty():
		line += " · " + preset
	if GameState.render_scene:
		line += " · rendu %s [F]" % GameState.look.mode
	_wave_label.text = line
	var elite: SimEntity = null
	for e in w.elites():
		if e.alive:
			elite = e
			break
	_elite_label.visible = elite != null
	if elite != null:
		var names := PackedStringArray()
		for a in elite.affixes:
			names.append(AFFIX_NAMES.get(String(a), String(a)))
		_elite_label.text = "ÉLITE · %s · %d/%d PV" % [" · ".join(names), int(round(elite.hp)), int(round(elite.hp_max))]
	_items_label.position.y = 42 + (LINE_H if elite != null else 0)
	var lines := PackedStringArray()
	for it in w.picked_items:
		lines.append(item_line(it))
	_items_label.text = "\n".join(lines)
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
		KEY_1, KEY_KP_1:
			GameState.set_weapon("hunter")
			get_viewport().set_input_as_handled()
		KEY_2, KEY_KP_2:
			GameState.set_weapon("brute")
			get_viewport().set_input_as_handled()
		KEY_3, KEY_KP_3:
			GameState.set_weapon("technomancer")
			get_viewport().set_input_as_handled()

## "Servo-gâchette +30 % cadence"
static func item_line(it: SimItem) -> String:
	var parts := PackedStringArray()
	for m in it.mods:
		var stat: String = STAT_NAMES.get(m.stat, m.stat)
		var pct := float(m.get("pct", 0.0))
		var flat := float(m.get("flat", 0.0))
		if pct != 0.0:
			parts.append("%+d %% %s" % [int(round(pct * 100.0)), stat])
		if flat != 0.0:
			parts.append("%+.0f %s" % [flat, stat])
	return "%s %s" % [ITEM_NAMES.get(it.kind, it.kind), " ".join(parts)]
