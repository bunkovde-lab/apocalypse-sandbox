class_name EnemyDB
extends RefCounted
## Описания врагов из data/enemies.json.

static var _loaded := false
static var defs := {}   # имя -> Dictionary


static func ensure_loaded() -> void:
	if _loaded:
		return
	ItemDB.ensure_loaded()
	var file := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	assert(file != null, "Не найден data/enemies.json")
	var data: Array = JSON.parse_string(file.get_as_text())
	for e in data:
		var d: Dictionary = e
		defs[str(d["name"])] = d
	_loaded = true


## Случайный враг, доступный в эту ночь, с учётом весов.
static func pick(night: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	var total := 0.0
	for d in defs.values():
		if int(d["min_night"]) <= night:
			pool.append(d)
			total += float(d["weight"])
	var roll := rng.randf() * total
	for d in pool:
		roll -= float(d["weight"])
		if roll <= 0.0:
			return d
	return pool[0]
