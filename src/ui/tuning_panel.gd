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
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return _root.visible

## Pull the current sim values into the sliders.
func refresh() -> void:
	var t: Dictionary = GameState.world.tuning.to_dict()
	for key in _sliders:
		_sliders[key].set_value_no_signal(t[key])
		_values[key].text = _fmt(t[key])

func _fmt(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func _on_slider(value: float, key: String) -> void:
	GameState.set_tuning(key, value)
	_values[key].text = _fmt(value)

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
