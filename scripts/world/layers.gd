class_name Layers
extends RefCounted
## Подземные слои из data/layers.json. Каждый слой отделён от верхнего печатью (две строки блока seal),
## которая исчезает, когда побеждены нужные боссы.

static var _loaded := false
static var list: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open("res://data/layers.json", FileAccess.READ)
	assert(file != null, "Не найден data/layers.json")
	list = JSON.parse_string(file.get_as_text())
	for l in list:
		l["y0"] = int(l["y0"])
		l["y1"] = int(l["y1"])
	_loaded = true


static func at_y(y: int) -> Dictionary:
	ensure_loaded()
	for l in list:
		if y >= int(l["y0"]) and y <= int(l["y1"]):
			return l
	return {}


static func by_id(id: String) -> Dictionary:
	ensure_loaded()
	for l in list:
		if l["id"] == id:
			return l
	return {}


static func is_unlocked(layer: Dictionary) -> bool:
	return Progress.has(str(layer["requires"]))


## Строки печати перед слоем.
static func seal_rows(layer: Dictionary) -> Vector2i:
	return Vector2i(int(layer["y0"]) - 2, int(layer["y0"]) - 1)
