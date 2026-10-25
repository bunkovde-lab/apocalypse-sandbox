class_name Hud
extends CanvasLayer
## Интерфейс: строка состояния, полоска здоровья, сообщения и подсказка по управлению.

var label := Label.new()
var help := Label.new()
var panel := Label.new()
var banner := Label.new()
var equip_label := Label.new()
var rad_bar := ProgressBar.new()
var boss_label := Label.new()
var boss_bar := ProgressBar.new()
var hp_bar := ProgressBar.new()
var hp_text := Label.new()
var message := Label.new()
var _message_time := 0.0


func _init() -> void:
	_style(label)
	label.position = Vector2(8, 6)
	add_child(label)

	hp_bar.position = Vector2(8, 52)
	hp_bar.custom_minimum_size = Vector2(180, 16)
	hp_bar.size = Vector2(180, 16)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("fill", _flat(Color(0.8, 0.15, 0.15)))
	hp_bar.add_theme_stylebox_override("background", _flat(Color(0.15, 0.05, 0.05, 0.8)))
	add_child(hp_bar)
	_style(hp_text)
	hp_text.position = Vector2(12, 50)
	hp_text.add_theme_font_size_override("font_size", 12)
	add_child(hp_text)

	_style(message)
	message.add_theme_font_size_override("font_size", 28)
	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 0.3
	message.anchor_bottom = 0.3
	message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message.visible = false
	add_child(message)

	_style(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-8, 6)
	panel.add_theme_font_size_override("font_size", 14)
	panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(panel)

	_style(banner)
	banner.add_theme_font_size_override("font_size", 15)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position = Vector2(0, 62)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner)
	_style(equip_label)
	equip_label.add_theme_font_size_override("font_size", 12)
	equip_label.position = Vector2(8, 92)
	add_child(equip_label)
	rad_bar.position = Vector2(8, 72)
	rad_bar.size = Vector2(180, 10)
	rad_bar.custom_minimum_size = Vector2(180, 10)
	rad_bar.show_percentage = false
	rad_bar.max_value = 100.0
	rad_bar.add_theme_stylebox_override("fill", _flat(Color(0.55, 0.85, 0.2)))
	rad_bar.add_theme_stylebox_override("background", _flat(Color(0.08, 0.12, 0.05, 0.8)))
	rad_bar.visible = false
	add_child(rad_bar)

	_style(boss_label)
	boss_label.add_theme_font_size_override("font_size", 16)
	boss_label.anchor_left = 0.5
	boss_label.anchor_right = 0.5
	boss_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_label.position = Vector2(0, 8)
	boss_label.visible = false
	add_child(boss_label)
	boss_bar.anchor_left = 0.5
	boss_bar.anchor_right = 0.5
	boss_bar.position = Vector2(-220, 34)
	boss_bar.size = Vector2(440, 14)
	boss_bar.custom_minimum_size = Vector2(440, 14)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("fill", _flat(Color(0.7, 0.2, 0.55)))
	boss_bar.add_theme_stylebox_override("background", _flat(Color(0.1, 0.05, 0.1, 0.8)))
	boss_bar.visible = false
	add_child(boss_bar)

	_style(help)
	help.text = "A/D ходьба, Пробел прыжок, ЛКМ копать или бить, ПКМ ставить, 1-0 или колесо выбор ячейки, E использовать (дверь, генератор, кровать), Tab инвентарь и крафт"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(8, -28)
	add_child(help)


## Показывает полоску босса; name = "" прячет её.
func set_boss(boss_name: String, hp: float, max_hp: float) -> void:
	var on := boss_name != ""
	boss_label.visible = on
	boss_bar.visible = on
	if on:
		boss_label.text = boss_name
		boss_bar.max_value = max_hp
		boss_bar.value = maxf(hp, 0.0)


func set_rad(rad: float) -> void:
	rad_bar.visible = rad > 0.5
	rad_bar.value = rad


func set_banner(text: String) -> void:
	banner.text = text


func set_equip(text: String) -> void:
	equip_label.text = text


func set_text(t: String) -> void:
	label.text = t


func set_hp(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = maxf(hp, 0.0)
	hp_text.text = "HP %d / %d" % [ceili(maxf(hp, 0.0)), int(max_hp)]


func flash_message(text: String, seconds: float = 3.0) -> void:
	message.text = text
	message.visible = true
	_message_time = seconds


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.visible = false


func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	return s


func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
