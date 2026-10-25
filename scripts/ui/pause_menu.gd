class_name PauseMenu
extends CanvasLayer
## Пауза по Esc: продолжить, сохранить, звук, выход в меню.

signal save_pressed
signal quit_pressed
signal resumed

var open := false
var bg := ColorRect.new()
var box := VBoxContainer.new()
var sound_button := Button.new()
var status := Label.new()


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(300, 0)
	box.position = Vector2(490, 220)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Пауза"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_button("Продолжить", close)
	_button("Сохранить игру (F5)", func() -> void: save_pressed.emit())
	sound_button = _button("", _toggle_sound)
	_button("Выйти в главное меню", func() -> void: quit_pressed.emit())
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	_refresh_sound()
	visible = false


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 40)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _toggle_sound() -> void:
	Settings.sound_on = not Settings.sound_on
	_refresh_sound()


func _refresh_sound() -> void:
	sound_button.text = "Звук: " + ("вкл" if Settings.sound_on else "выкл")


func show_status(text: String) -> void:
	status.text = text


func toggle() -> void:
	if open:
		close()
	else:
		open_menu()


func open_menu() -> void:
	open = true
	visible = true
	status.text = ""
	_refresh_sound()
	get_tree().paused = true


func close() -> void:
	if not open:
		return
	open = false
	visible = false
	get_tree().paused = false
	resumed.emit()
