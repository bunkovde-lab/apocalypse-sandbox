class_name RecipeDB
extends RefCounted
## Рецепты из data/recipes.json. Пустая станция означает крафт руками.

static var _loaded := false
static var recipes: Array = []   # элементы: Dictionary {result, count, station, ingredients}


static func ensure_loaded() -> void:
	if _loaded:
		return
	ItemDB.ensure_loaded()
	var file := FileAccess.open("res://data/recipes.json", FileAccess.READ)
	assert(file != null, "Не найден data/recipes.json")
	var data: Array = JSON.parse_string(file.get_as_text())
	for e in data:
		var r: Dictionary = e
		r["count"] = int(r.get("count", 1))
		r["station"] = str(r.get("station", ""))
		r["requires"] = str(r.get("requires", ""))
		recipes.append(r)
	_loaded = true


## Станции крафта в радиусе от клетки. Возвращает {имя станции: true}.
static func nearby_stations(world: WorldData, tile: Vector2i, rx: int = 6, ry: int = 4) -> Dictionary:
	var found := {}
	for y in range(tile.y - ry, tile.y + ry + 1):
		for x in range(tile.x - rx, tile.x + rx + 1):
			var id := world.get_block(x, y)
			if BlockDB.station[id] == 1:
				found[BlockDB.names[id]] = true
	return found


static func is_craftable(inv: Inventory, stations: Dictionary, r: Dictionary) -> bool:
	if not Progress.has(str(r.get("requires", ""))):
		return false
	var st: String = r["station"]
	if st != "" and not stations.has(st):
		return false
	var ing: Dictionary = r["ingredients"]
	for k in ing:
		if inv.count(k) < int(ing[k]):
			return false
	return true


## Крафтит предмет. Если результат не помещается, ингредиенты возвращаются.
static func craft(inv: Inventory, stations: Dictionary, r: Dictionary) -> bool:
	if not is_craftable(inv, stations, r):
		return false
	var snap := inv.snapshot()
	var ing: Dictionary = r["ingredients"]
	for k in ing:
		inv.remove(k, int(ing[k]))
	if inv.add(r["result"], r["count"]) > 0:
		inv.restore(snap)
		return false
	return true


static func ingredients_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	var ing: Dictionary = r["ingredients"]
	for k in ing:
		parts.append("%s x%d" % [ItemDB.title(k), int(ing[k])])
	return ", ".join(parts)
