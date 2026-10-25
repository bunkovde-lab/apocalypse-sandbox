extends Control
## Главное меню: новая игра, продолжить, сложность, звук, выход.

var diff_button := Button.new()
var sound_button := Button.new()
var continue_button := Button.new()
var info := Label.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("14161c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(470, 120)
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "АПОКАЛИПСИС\nпесочница выживания"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_add(box, "Новая игра", _new_game)
	continue_button = _add(box, "Продолжить", _continue)
	continue_button.disabled = not SaveSystem.exists()
	diff_button = _add(box, "", _cycle_difficulty)
	sound_button = _add(box, "", _toggle_sound)
	_add(box, "Выход", func() -> void: get_tree().quit())
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "Постройте убежище, спасайте выживших, спуститесь к ядру корпорации."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	_refresh()


func _add(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 44)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _refresh() -> void:
	diff_button.text = "Сложность: " + Settings.difficulty_name()
	sound_button.text = "Звук: " + ("вкл" if Settings.sound_on else "выкл")


func _cycle_difficulty() -> void:
	Settings.difficulty = (Settings.difficulty + 1) % 3
	_refresh()


func _toggle_sound() -> void:
	Settings.sound_on = not Settings.sound_on
	_refresh()


func _new_game() -> void:
	Settings.load_requested = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _continue() -> void:
	Settings.load_requested = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")
