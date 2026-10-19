class_name InventoryPanel
extends CanvasLayer
## Minimal bag: I toggles it, the world keeps running behind it (ARPG rule: no pause for the
## bag). Right third of the screen, dark translucent. Top: the three slots in their rarity
## colour. Below: the bag, one line per item with ▲ / ▼ / = next to each affix against the
## worn item of the same slot (▲ better, ▼ worse, = equal or absent on the other; an empty
## slot reads ▲ everywhere). Up / Down or mouse select, Enter or click equips, Suppr drops.
## Everything goes through GameState; the panel never touches the sim.

const TEXT_COLOR := Color(0.85, 0.82, 0.78)
const EMPTY_COLOR := Color(0.85, 0.82, 0.78, 0.4)
const SELECT_BG := Color(0.85, 0.45, 0.2, 0.25)
const ROW_BG := Color(0, 0, 0, 0)

var _root: PanelContainer
var _slot_labels: Dictionary = {}   # slot -> Label
var _list: VBoxContainer
var _rows: Array[Button] = []
var _count_label: Label
var _hint: Label
var _sel := 0
var _last_ids: Array = []           # bag ids at the last rebuild, to rebuild only on change

func _ready() -> void:
	layer = 10
	_root = PanelContainer.new()
	_root.anchor_left = 0.67
	_root.anchor_right = 1.0
	_root.anchor_top = 0.0
	_root.anchor_bottom = 1.0
	_root.offset_left = 0
	_root.offset_right = -12
	_root.offset_top = 12
	_root.offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.6)
	style.border_color = Color(0.85, 0.45, 0.2)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	var title := Label.new()
	title.text = "INVENTAIRE  [I]"
	vbox.add_child(title)
	for slot in SimItem.SLOTS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(l)
		_slot_labels[slot] = l
	vbox.add_child(HSeparator.new())
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", EMPTY_COLOR)
	vbox.add_child(_count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_hint = Label.new()
	_hint.text = "↑↓ choisir · Entrée équiper · Suppr lâcher"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", EMPTY_COLOR)
	vbox.add_child(_hint)

	_root.visible = GameState.has_arg("panel-inv")
	refresh()

func is_open() -> bool:
	return _root.visible

func _process(_dt: float) -> void:
	if _root.visible:
		refresh()

func refresh() -> void:
	var w: SimWorld = GameState.world
	for slot in SimItem.SLOTS:
		var l: Label = _slot_labels[slot]
		var it: SimItem = w.equipped.get(slot)
		if it == null:
			l.text = "%s · —" % Hud.SLOT_NAMES.get(String(slot), String(slot))
			l.add_theme_color_override("font_color", EMPTY_COLOR)
		else:
			l.text = Hud.item_line(it)
			l.add_theme_color_override("font_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
	_count_label.text = "sac %d / %d" % [w.inventory.size(), int(w.tuning.inventory_size)]
	var ids := w.inventory.map(func(it): return it.id)
	if ids != _last_ids:
		_last_ids = ids
		_rebuild(w)
	_sel = clampi(_sel, 0, maxi(0, _rows.size() - 1))
	for i in _rows.size():
		var it: SimItem = w.inventory[i]
		_rows[i].text = compare_line(it, w.equipped.get(it.slot))
		_style_row(_rows[i], i == _sel)

func _rebuild(w: SimWorld) -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in w.inventory.size():
		var it: SimItem = w.inventory[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
		b.add_theme_color_override("font_hover_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
		b.add_theme_color_override("font_pressed_color", ItemView.RARITY_COLORS.get(it.rarity, TEXT_COLOR))
		b.pressed.connect(_on_row_pressed.bind(i))
		b.mouse_entered.connect(func(): _sel = i)
		_list.add_child(b)
		_rows.append(b)

func _style_row(b: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SELECT_BG if selected else ROW_BG
	sb.set_content_margin_all(4)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)

func _on_row_pressed(i: int) -> void:
	_sel = i
	_equip_selected()

func _equip_selected() -> void:
	var w: SimWorld = GameState.world
	if _sel >= 0 and _sel < w.inventory.size():
		GameState.equip_item(w.inventory[_sel].id)

func _drop_selected() -> void:
	var w: SimWorld = GameState.world
	if _sel >= 0 and _sel < w.inventory.size():
		GameState.drop_item(w.inventory[_sel].id)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_I:
		_root.visible = not _root.visible
		if _root.visible:
			refresh()
		get_viewport().set_input_as_handled()
		return
	if not _root.visible:
		return
	match event.keycode:
		KEY_UP:
			_sel = maxi(0, _sel - 1)
		KEY_DOWN:
			_sel = mini(maxi(0, _rows.size() - 1), _sel + 1)
		KEY_ENTER, KEY_KP_ENTER:
			_equip_selected()
		KEY_DELETE, KEY_BACKSPACE:
			_drop_selected()
		_:
			return
	refresh()
	get_viewport().set_input_as_handled()

## "Arme · modifié · dégâts +15 % ▲ · cadence +8 % =" against the worn item of the slot.
static func compare_line(it: SimItem, worn: SimItem) -> String:
	var parts := PackedStringArray()
	parts.append(Hud.SLOT_NAMES.get(String(it.slot), String(it.slot)))
	parts.append(Hud.RARITY_NAMES.get(String(it.rarity), String(it.rarity)))
	for a in it.affixes:
		var stat: String = Hud.STAT_NAMES.get(a.stat, a.stat)
		parts.append("%s %+d %% %s" % [stat, int(round(float(a.pct) * 100.0)), arrow(a, worn)])
	return " · ".join(parts)

## ▲ when this affix beats the worn item's same stat (sign-aware: a lower dash_cooldown or
## damage_taken is better), ▼ when it loses, = when equal or when the worn item lacks the stat.
## No worn item: ▲.
static func arrow(a: Dictionary, worn: SimItem) -> String:
	if worn == null:
		return "▲"
	var other := 0.0
	var found := false
	for b in worn.affixes:
		if b.stat == a.stat:
			other = float(b.pct)
			found = true
	if not found:
		return "="
	var good := -1.0 if SimItem.NEGATIVE_IS_GOOD.has(String(a.stat)) else 1.0
	var diff := (float(a.pct) - other) * good
	if diff > 0.001:
		return "▲"
	if diff < -0.001:
		return "▼"
	return "="
