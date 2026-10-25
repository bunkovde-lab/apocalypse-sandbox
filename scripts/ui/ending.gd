class_name Ending
extends CanvasLayer
## Финал: после победы над «Ядром» игрок выбирает судьбу убежища. Игра на паузе до выбора.

signal chosen(kind: String)
signal closed

const CHOICES := {
	"shutdown": "Выключить «Ядро»: машины замолчат, а люди начнут заново.",
	"control": "Подчинить «Ядро»: корпорация станет вашим убежищем и вашим щитом.",
}

var open := false
var kind := ""
var stats := {}
var label := Label.new()
var bg := ColorRect.new()


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	visible = false


static func epilogue(k: String, st: Dictionary) -> String:
	var tail := "\n\nДней в убежище: %d. Убито врагов: %d. Спасено выживших: %d." % [int(st.get("days", 0)), int(st.get("kills", 0)), int(st.get("residents", 0))]
	match k:
		"shutdown":
			return "Реактор гаснет. Дроны падают, двери открываются, над пустошью впервые за годы тихо.\nВыжившие выходят из убежища и строят новый мир на обломках старого." + tail
		"control":
			return "«Ядро» принимает вас как оператора. Лаборатории оживают, турели прикрывают ваши стены.\nЦена этой безопасности — власть, которой не было ни у кого." + tail
	return tail


func show_choice(st: Dictionary) -> void:
	stats = st
	open = true
	kind = ""
	visible = true
	get_tree().paused = true
	label.text = "«Ядро» побеждено.\n\nЧто дальше?\n\n1 — " + CHOICES["shutdown"] + "\n2 — " + CHOICES["control"]


func choose(k: String) -> bool:
	if not open or kind != "" or not CHOICES.has(k):
		return false
	kind = k
	Progress.ending = k
	label.text = epilogue(k, stats) + "\n\nEnter — продолжить игру."
	chosen.emit(k)
	return true


func close() -> bool:
	if not open or kind == "":
		return false
	open = false
	visible = false
	get_tree().paused = false
	closed.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			choose("shutdown")
		KEY_2:
			choose("control")
		KEY_ENTER, KEY_KP_ENTER:
			close()
