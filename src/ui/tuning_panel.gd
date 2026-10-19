class_name TuningPanel
extends CanvasLayer
## Dev dial: one slider per SimTuning value, live. Tab toggles. Save/Load go through GameState
## to tools/out/tuning.json; the panel never touches the sim directly.

const PANEL_W := 420
const ROW_LABEL_W := 150
const VALUE_W := 60

var _root: PanelContainer
var _sliders: Dictionary = {}  # key -> HSlider
var _values: Dictionary = {}   # key -> Label
var _status: Label
var _presets: OptionButton
var _preset_label: Label
var _save_as_name: LineEdit
var _weapons: OptionButton
var _modes: OptionButton
var _dither: HSlider
var _dither_value: Label

func _ready() -> void:
	layer = 10
	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_top = 0.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -PANEL_W - 12
	_root.offset_right = -12
	_root.offset_top = 12
	_root.offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.55)
	style.border_color = Color(0.85, 0.45, 0.2)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	var title := Label.new()
	title.text = "TUNING  [Tab]"
	vbox.add_child(title)

	# Presets: pick one to apply it live; "Save as…" writes the current values to tools/presets/.
	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	var preset_title := Label.new()
	preset_title.text = "preset"
	preset_title.custom_minimum_size.x = 60
	preset_row.add_child(preset_title)
	_presets = OptionButton.new()
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_presets.focus_mode = Control.FOCUS_NONE
	_presets.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_presets)
	_preset_label = Label.new()
	_preset_label.custom_minimum_size.x = 90
	_preset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preset_row.add_child(_preset_label)

	var save_row := HBoxContainer.new()
	vbox.add_child(save_row)
	_save_as_name = LineEdit.new()
	_save_as_name.placeholder_text = "nom du preset"
	_save_as_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_as_name.text_submitted.connect(func(_t): _on_save_as())
	save_row.add_child(_save_as_name)
	var save_as := Button.new()
	save_as.text = "Save as…"
	save_as.focus_mode = Control.FOCUS_NONE
	save_as.pressed.connect(_on_save_as)
	save_row.add_child(save_as)

	# Weapon profile (keys 1/2/3 do the same).
	var weapon_row := HBoxContainer.new()
	vbox.add_child(weapon_row)
	var weapon_title := Label.new()
	weapon_title.text = "arme"
	weapon_title.custom_minimum_size.x = 60
	weapon_row.add_child(weapon_title)
	_weapons = OptionButton.new()
	_weapons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapons.focus_mode = Control.FOCUS_NONE
	for i in WeaponProfile.NAMES.size():
		_weapons.add_item("%d · %s" % [i + 1, WeaponProfile.NAMES[i]], i)
	_weapons.item_selected.connect(func(i: int): GameState.set_weapon(WeaponProfile.NAMES[i]))
	weapon_row.add_child(_weapons)

	# Render filter (render_test scene only; F cycles the mode). Not part of the sim tuning.
	var render_row := HBoxContainer.new()
	vbox.add_child(render_row)
	var render_title := Label.new()
	render_title.text = "rendu"
	render_title.custom_minimum_size.x = 60
	render_row.add_child(render_title)
	_modes = OptionButton.new()
	_modes.custom_minimum_size.x = 100
	_modes.focus_mode = Control.FOCUS_NONE
	for i in GameState.RENDER_MODES.size():
		_modes.add_item(GameState.RENDER_MODES[i], i)
	_modes.item_selected.connect(func(i: int): GameState.set_render_mode(GameState.RENDER_MODES[i]))
	render_row.add_child(_modes)
	var dither_title := Label.new()
	dither_title.text = " dither"
	render_row.add_child(dither_title)
	_dither = HSlider.new()
	_dither.min_value = 0.0
	_dither.max_value = 1.0
	_dither.step = 0.05
	_dither.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dither.focus_mode = Control.FOCUS_NONE
	_dither.value_changed.connect(func(v: float):
		GameState.set_render_dither(v)
		_dither_value.text = _fmt(v))
	render_row.add_child(_dither)
	_dither_value = Label.new()
	_dither_value.custom_minimum_size.x = 40
	_dither_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	render_row.add_child(_dither_value)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for spec in SimTuning.SPECS:
		rows.add_child(_make_row(spec))

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	for b in [["Save", _on_save], ["Load", _on_load], ["Defaults", _on_defaults]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	_status = Label.new()
	_status.text = GameState.TUNING_PATH
	_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status)

	_root.visible = GameState.has_arg("panel")
	refresh()

func _make_row(spec: Array) -> HBoxContainer:
	var key: String = spec[0]
	var row := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = key
	name_l.custom_minimum_size.x = ROW_LABEL_W
	row.add_child(name_l)
	var s := HSlider.new()
	s.min_value = spec[1]
	s.max_value = spec[2]
	s.step = spec[3]
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(_on_slider.bind(key))
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = VALUE_W
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	_sliders[key] = s
	_values[key] = v
	return row

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_root.visible = not _root.visible
		if _root.visible:
			refresh()
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return _root.visible

## Pull the current sim values into the sliders, the preset list and the weapon selector.
func refresh() -> void:
	var t: Dictionary = GameState.world.tuning.to_dict()
	for key in _sliders:
		_sliders[key].set_value_no_signal(t[key])
		_values[key].text = _fmt(t[key])
	_presets.clear()
	_presets.add_item("—", 0)
	var names := GameState.list_presets()
	for i in names.size():
		_presets.add_item(names[i], i + 1)
		if names[i] == GameState.preset_name:
			_presets.select(i + 1)
	_weapons.select(WeaponProfile.NAMES.find(GameState.world.weapon.name))
	_modes.select(GameState.RENDER_MODES.find(GameState.render_mode))
	_dither.set_value_no_signal(GameState.render_dither)
	_dither_value.text = _fmt(GameState.render_dither)
	_refresh_preset_label()

func _refresh_preset_label() -> void:
	var l := GameState.preset_label()
	_preset_label.text = l if not l.is_empty() else "(aucun)"

func _fmt(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func _on_slider(value: float, key: String) -> void:
	GameState.set_tuning(key, value)
	_values[key].text = _fmt(value)
	_refresh_preset_label()

func _on_preset_selected(index: int) -> void:
	if index <= 0:
		return
	var name := _presets.get_item_text(index)
	if GameState.apply_preset(name):
		refresh()
		_status.text = "preset " + name + " appliqué (tuning.json intact)"
	else:
		_status.text = "preset introuvable: " + name

func _on_save_as() -> void:
	var name := _save_as_name.text.strip_edges()
	if name.is_empty():
		_status.text = "donne un nom au preset"
		return
	if GameState.save_preset(name):
		_save_as_name.text = ""
		refresh()
		_status.text = "preset -> " + GameState.preset_path(GameState.preset_name)
	else:
		_status.text = "save as FAILED: " + name

func _on_save() -> void:
	_status.text = ("saved -> " if GameState.save_tuning() else "save FAILED: ") + GameState.TUNING_PATH

func _on_load() -> void:
	GameState.load_tuning()
	refresh()
	_status.text = "loaded <- " + GameState.TUNING_PATH

func _on_defaults() -> void:
	GameState.reset_tuning()
	refresh()
	_status.text = "defaults (not saved)"
