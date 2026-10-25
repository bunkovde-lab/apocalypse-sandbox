class_name Hud
extends CanvasLayer
## Простейший интерфейс: строка состояния сверху и подсказка по управлению снизу.

var label := Label.new()
var help := Label.new()


func _init() -> void:
	_style(label)
	label.position = Vector2(8, 6)
	add_child(label)
	_style(help)
	help.text = "A/D ходьба, Пробел прыжок, ЛКМ копать, ПКМ ставить, 1-0 или колесо выбор ячейки, Tab инвентарь и крафт"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(8, -28)
	add_child(help)


func set_text(t: String) -> void:
	label.text = t


func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
