class_name Hud
extends CanvasLayer
## Minimal HUD for the tuning arena: wave line top-left (with the effective cadence), an elite
## line while one is alive, one line per equipment slot under it ("Arme · modifié · cadence
## +15 % · dégâts +8 %" in the rarity colour, "Arme · —" dim when empty). The floor item under
## the cursor (GameState.hovered_item) gets its line floating over it in the world, in the
## rarity colour, and the cursor becomes a hand: click it to pick it up (E takes the nearest).
## The scene sets `camera` so the label can be projected to the screen.
## "R pour recommencer" on death.
## Meta keys (physical, layout-independent): R restart the wave (when dead), N next wave,
## 0 back to wave 1, 1/2/3 weapon profile.
## Everything goes through GameState; the HUD never touches the sim.

const TEXT_COLOR := Color(0.85, 0.82, 0.78)
const FLASH_COLOR := Color(1.0, 0.85, 0.5)
const FLASH_TIME := 0.6
const EMPTY_COLOR := Color(0.85, 0.82, 0.78, 0.4)
const DANGER_COLOR := Color(0.9, 0.15, 0.1)
const AFFIX_NAMES := {"shielded": "blindé", "volatile": "instable", "fast": "célère"}
const LINE_H := 22
const ITEM_LABEL_HEIGHT := 1.4   # world units over the item's ground point

# Player-facing names (view-side only; the sim knows keys).
const SLOT_NAMES := {"weapon": "Arme", "armor": "Armure", "module": "Module"}
const RARITY_NAMES := {"common": "série", "rare": "modifié", "epic": "relique"}
const STAT_NAMES := {"fire_rate": "cadence", "proj_damage": "dégâts", "proj_speed": "vitesse de tir",
	"player_speed": "vitesse", "player_hp": "PV", "knockback": "recul", "dash_cooldown": "recharge du dash",
	"damage_taken": "dégâts subis"}

var _wave_label: Label
var _elite_label: Label
var _slot_labels: Dictionary = {}   # slot -> Label
var _item_label: Label
var camera: Camera3D   # set by the scene; projects the hovered item's label
var _death_label: Label
var _flash_t := 0.0

func _ready() -> void:
	layer = 20
	_wave_label = _make_label(20, TEXT_COLOR)
	_wave_label.position = Vector2(16, 12)
	_elite_label = _make_label(16, DANGER_COLOR)
	_elite_label.visible = false
	for slot in SimItem.SLOTS:
		_slot_labels[slot] = _make_label(16, EMPTY_COLOR)
	_item_label = _make_label(16, TEXT_COLOR)
	_item_label.visible = false

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

func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l

func _on_wave_cleared(_wave: int) -> void:
	_flash_t = FLASH_TIME

func _process(dt: float) -> void:
	var w: SimWorld = GameState.world
	var p: SimEntity = w.player()
	var hp := int(round(p.hp)) if p != null else 0
	var line := "Vague %d · %d grunts · %d PV · %s · cadence %.2f s" % [w.wave, w.grunts_alive(), hp, w.weapon.name, w.fire_interval()]
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
	_elite_label.position = Vector2(16, 42)
	if elite != null:
		var names := PackedStringArray()
		for a in elite.affixes:
			names.append(AFFIX_NAMES.get(String(a), String(a)))
		_elite_label.text = "ÉLITE · %s · %d/%d PV" % [" · ".join(names), int(round(elite.hp)), int(round(elite.hp_max))]
	var y := 42 + (LINE_H if elite != null else 0)
	for slot in SimItem.SLOTS:
		var l: Label = _slot_labels[slot]
		l.position = Vector2(16, y)
		y += LINE_H
		var it: SimItem = w.equipped.get(slot)
		if it == null:
			l.text = "%s · —" % SLOT_NAMES.get(String(slot), String(slot))
			l.add_theme_color_override("font_color", EMPTY_COLOR)
		else:
			l.text = item_line(it)
			l.add_theme_color_override("font_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
	_update_item_label(w.items.get(GameState.hovered_item))
	_flash_t = maxf(0.0, _flash_t - dt)
	var k := _flash_t / FLASH_TIME
	_wave_label.add_theme_color_override("font_color", TEXT_COLOR.lerp(FLASH_COLOR, k))
	_wave_label.scale = Vector2.ONE * (1.0 + 0.25 * k)
	_death_label.visible = p != null and not p.alive

## The hovered item's line, centred over it in the world. The camera may live in a SubViewport
## drawn at a lower resolution: its projection is scaled to this layer's viewport.
func _update_item_label(it: SimItem) -> void:
	_item_label.visible = it != null and camera != null
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if _item_label.visible else Input.CURSOR_ARROW)
	if not _item_label.visible:
		return
	_item_label.text = item_line(it)
	_item_label.add_theme_color_override("font_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
	var anchor := camera.unproject_position(Vector3(it.pos.x, ITEM_LABEL_HEIGHT, it.pos.y))
	var scale_v := get_viewport().get_visible_rect().size / camera.get_viewport().get_visible_rect().size
	var size := _item_label.get_combined_minimum_size()
	_item_label.position = (anchor * scale_v - Vector2(size.x * 0.5, size.y)).round()

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

## "Arme · modifié · cadence +15 % · dégâts +8 %"
static func item_line(it: SimItem) -> String:
	var parts := PackedStringArray()
	parts.append(SLOT_NAMES.get(String(it.slot), String(it.slot)))
	parts.append(RARITY_NAMES.get(String(it.rarity), String(it.rarity)))
	for a in it.affixes:
		var stat: String = STAT_NAMES.get(a.stat, a.stat)
		parts.append("%s %+d %%" % [stat, int(round(float(a.pct) * 100.0))])
	return " · ".join(parts)
