class_name BlockDB
extends RefCounted
## База блоков. Данные лежат в res://data/blocks.json, id блока = его индекс.

const AIR := 0
const DIRT := 1
const STONE := 2
const SAND := 3
const MUD := 4
const CONCRETE := 5
const IRON_ORE := 6
const COPPER_ORE := 7
const COAL := 8
const CRYSTAL := 9
const SCRAP := 10
const WOOD := 11
const BEDROCK := 12
const WORKBENCH := 13
const FORGE := 14
const TOMBSTONE := 15

static var _loaded := false
static var count := 0
static var names := PackedStringArray()
static var titles := PackedStringArray()
static var drops := PackedStringArray()
static var colors := PackedColorArray()
static var specks := PackedColorArray()
static var hardness := PackedFloat32Array()
static var solid := PackedByteArray()
static var placeable := PackedByteArray()
static var station := PackedByteArray()      # 1 = станция крафта
static var name_to_id := {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open("res://data/blocks.json", FileAccess.READ)
	assert(file != null, "Не найден data/blocks.json")
	var data: Array = JSON.parse_string(file.get_as_text())
	count = data.size()
	names.resize(count)
	titles.resize(count)
	drops.resize(count)
	colors.resize(count)
	specks.resize(count)
	hardness.resize(count)
	solid.resize(count)
	placeable.resize(count)
	station.resize(count)
	for entry in data:
		var id: int = int(entry["id"])
		assert(id >= 0 and id < count, "id блока должны идти подряд с 0")
		names[id] = str(entry["name"])
		titles[id] = str(entry["title"])
		drops[id] = str(entry.get("drop", ""))
		colors[id] = Color.html(str(entry["color"]))
		var speck_text: String = str(entry.get("speck", ""))
		specks[id] = Color.html(speck_text) if speck_text != "" else Color(0, 0, 0, 0)
		hardness[id] = float(entry["hardness"])
		solid[id] = 1 if bool(entry["solid"]) else 0
		placeable[id] = 1 if bool(entry["placeable"]) else 0
		station[id] = 1 if bool(entry.get("station", false)) else 0
		name_to_id[names[id]] = id
	_loaded = true


static func is_solid(id: int) -> bool:
	return solid[id] == 1
