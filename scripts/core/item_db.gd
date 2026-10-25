class_name ItemDB
extends RefCounted
## База предметов из data/items.json. Блоки, материалы, инструменты и оружие.
## Предмет-блок называется так же, как блок в BlockDB.

static var _loaded := false
static var items := {}   # имя -> Dictionary из json


static func ensure_loaded() -> void:
	if _loaded:
		return
	BlockDB.ensure_loaded()
	var file := FileAccess.open("res://data/items.json", FileAccess.READ)
	assert(file != null, "Не найден data/items.json")
	var data: Array = JSON.parse_string(file.get_as_text())
	for e in data:
		var d: Dictionary = e
		d["stack"] = int(d.get("stack", 999))
		items[str(d["name"])] = d
	_loaded = true


static func has_item(item: String) -> bool:
	return items.has(item)


static func title(item: String) -> String:
	return str(items[item]["title"]) if items.has(item) else item


static func kind(item: String) -> String:
	return str(items[item]["kind"]) if items.has(item) else ""


static func stack_max(item: String) -> int:
	return int(items[item]["stack"]) if items.has(item) else 999


## id блока, если предмет можно поставить в мир, иначе -1.
static func block_id(item: String) -> int:
	if kind(item) != "block":
		return -1
	var id: int = BlockDB.name_to_id.get(item, -1)
	if id <= 0 or BlockDB.placeable[id] == 0:
		return -1
	return id


static func tool_power(item: String) -> float:
	return float(items[item].get("power", 0.0)) if items.has(item) else 0.0


static func damage(item: String) -> float:
	return float(items[item].get("damage", 0.0)) if items.has(item) else 0.0


static func stat(item: String, key: String, default_value: float = 0.0) -> float:
	return float(items[item].get(key, default_value)) if items.has(item) else default_value
