class_name TouchControls
extends CanvasLayer
## Экранные кнопки для планшета: ходьба, прыжок, действие, режим «ставить», инвентарь, карта, пауза.
## Мультитач: каждая кнопка отслеживает свой палец. Копание и бой — касание мира (эмуляция мыши).
## Чтобы использовать предмет рядом с объектом (кровать, алтарь, выживший), коснитесь его и нажмите «E».

signal pause_pressed
signal map_pressed

const HOLD := {"left": "move_left", "right": "move_right", "jump": "jump", "down": "move_down"}
const SPECS := [
	{"id": "left", "pos": Vector2(30, 540), "size": Vector2(120, 120), "text": "◀"},
	{"id": "right", "pos": Vector2(170, 540), "size": Vector2(120, 120), "text": "▶"},
	{"id": "jump", "pos": Vector2(1130, 520), "size": Vector2(130, 130), "text": "▲"},
	{"id": "down", "pos": Vector2(990, 580), "size": Vector2(100, 90), "text": "▼"},
	{"id": "use", "pos": Vector2(1130, 380), "size": Vector2(110, 110), "text": "E"},
	{"id": "mode", "pos": Vector2(1130, 260), "size": Vector2(110, 100), "text": "Копать"},
	{"id": "inv", "pos": Vector2(1130, 150), "size": Vector2(110, 90), "text": "Рюкзак"},
	{"id": "prev", "pos": Vector2(300, 640), "size": Vector2(70, 60), "text": "‹"},
	{"id": "next", "pos": Vector2(1000, 640), "size": Vector2(70, 60), "text": "›"},
	{"id": "map", "pos": Vector2(1130, 50), "size": Vector2(70, 60), "text": "Карта"},
	{"id": "pause", "pos": Vector2(1210, 50), "size": Vector2(60, 60), "text": "II"},
]

var buttons := {}          # id -> Label
var fingers := {}          # индекс пальца -> id кнопки
var forced := false


func _init() -> void:
	layer = 20


func setup(force: bool = false) -> void:
	forced = force
	for spec in SPECS:
		var b := Label.new()
		b.position = spec["pos"]
		b.size = spec["size"]
		b.text = spec["text"]
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 26 if str(spec["text"]).length() < 3 else 17)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_style(b, false)
		add_child(b)
		buttons[spec["id"]] = b
	visible = force or DisplayServer.is_touchscreen_available()


func _style(b: Label, pressed: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.34 if pressed else 0.16)
	s.set_corner_radius_all(18)
	s.border_color = Color(1, 1, 1, 0.5)
	s.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", s)


func button_at(p: Vector2) -> String:
	for id in buttons:
		if Rect2(buttons[id].position, buttons[id].size).has_point(p):
			return id
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var id := button_at(event.position)
			if id != "":
				fingers[event.index] = id
				_press(id)
				get_viewport().set_input_as_handled()
		elif fingers.has(event.index):
			_release(fingers[event.index])
			fingers.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		var id: String = fingers[event.index]
		if button_at(event.position) != id:
			_release(id)
			fingers.erase(event.index)
			var nid := button_at(event.position)
			if nid != "":
				fingers[event.index] = nid
				_press(nid)


func _press(id: String) -> void:
	_style(buttons[id], true)
	if HOLD.has(id):
		Input.action_press(HOLD[id])
		return
	match id:
		"use":
			_tap("interact")
		"inv":
			_tap("toggle_inventory")
		"prev":
			_tap("hotbar_prev")
		"next":
			_tap("hotbar_next")
		"mode":
			Settings.touch_place = not Settings.touch_place
			buttons["mode"].text = "Ставить" if Settings.touch_place else "Копать"
		"map":
			map_pressed.emit()
		"pause":
			pause_pressed.emit()


func _release(id: String) -> void:
	_style(buttons[id], false)
	if HOLD.has(id):
		Input.action_release(HOLD[id])


func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
