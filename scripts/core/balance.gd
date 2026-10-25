class_name Balance
extends RefCounted
## Числа баланса убежища из data/balance.json: правятся без изменения кода.

static var _loaded := false
static var values := {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open("res://data/balance.json", FileAccess.READ)
	assert(file != null, "Не найден data/balance.json")
	values = JSON.parse_string(file.get_as_text())
	_loaded = true


static func g(key: String) -> float:
	ensure_loaded()
	return float(values[key])
