class_name LabGen
extends RefCounted
## Корпоративный район на поверхности, лаборатории и реактор с ядром ИИ.
## Всё пишется прямо в fg; алтари регистрируются в world.altars.

const AIR := BlockDB.AIR


static func generate(world: WorldData, rng: RandomNumberGenerator) -> void:
	_corp_district(world, int(world.width * 0.9), rng)
	_labs(world, rng)
	_reactor(world, rng)


static func _put(world: WorldData, x: int, y: int, id: int) -> void:
	StructureGen._put(world, x, y, id)


static func _rect(world: WorldData, x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	StructureGen._rect(world, x0, y0, x1, y1, id)


static func lab_loot(world: WorldData, rng: RandomNumberGenerator, x: int, y: int, tier: int) -> void:
	var items := {"medkit": rng.randi_range(1, 2), "cell": rng.randi_range(4, 10)}
	if rng.randf() < 0.6 or tier >= 1:
		items["data_crystal"] = rng.randi_range(1, 3)
	if rng.randf() < 0.5 or tier >= 1:
		items["alloy"] = rng.randi_range(1, 3)
	if rng.randf() < 0.4:
		items["antirad"] = rng.randi_range(1, 2)
	if tier >= 1 and rng.randf() < 0.7:
		items["mutagen"] = rng.randi_range(1, 2)
	if tier >= 2:
		items["fuel_rod"] = rng.randi_range(1, 2)
		items["alloy"] = rng.randi_range(3, 5)
	_put(world, x, y, BlockDB.LOOT)
	world.tombstones[Vector2i(x, y)] = items


## Горизонтальный коридор с обшивкой и светильниками на потолке.
static func _corridor(world: WorldData, x0: int, x1: int, yf: int, h: int, lining: int) -> void:
	LayerGen.tunnel(world, x0, x1, yf, h, lining)
	for x in range(x0 + 6, x1 - 6, 14):
		_put(world, x, yf - h, BlockDB.LAB_LIGHT)


## Комнаты по обе стороны коридора, закрытые дверями.
static func _rooms(world: WorldData, rng: RandomNumberGenerator, yf: int, lining: int, tier: int, x_from: int, x_to: int) -> void:
	var x := x_from + rng.randi_range(0, 20)
	var n := 0
	while x < x_to - 40:
		var rw := rng.randi_range(12, 20)
		var up := n % 2 == 0
		var y_a: int = yf - 7 - 8 if up else yf + 3
		var y_b: int = yf - 8 if up else yf + 10
		_rect(world, x - 1, y_a - 1, x + rw, y_b + 1, lining)
		_rect(world, x, y_a, x + rw - 1, y_b, AIR)
		var dx := x + rw / 2
		if up:
			_rect(world, dx, yf - 8, dx + 1, yf - 6, AIR)
			_put(world, dx, yf - 7, BlockDB.DOOR)
			_put(world, dx, yf - 6, BlockDB.DOOR)
		else:
			_rect(world, dx, yf + 1, dx + 1, yf + 3, AIR)
			_put(world, dx, yf + 2, BlockDB.DOOR)
			_put(world, dx, yf + 3, BlockDB.DOOR)
		_put(world, x + 2, y_a, BlockDB.LAB_LIGHT)
		_put(world, x + rw - 3, y_a, BlockDB.LAB_LIGHT)
		lab_loot(world, rng, x + 3, y_b, tier + (1 if n % 4 == 0 else 0))
		if rng.randf() < 0.5:
			lab_loot(world, rng, x + rw - 4, y_b, tier)
		n += 1
		x += rw + rng.randi_range(6, 24)


# ---------- Корпоративный район ----------

static func _tower(world: WorldData, rng: RandomNumberGenerator, x0: int, base: int, door_right: bool) -> void:
	_rect(world, x0, base - 20, x0 + 13, base - 1, BlockDB.CORP_WALL)
	_rect(world, x0 + 1, base - 19, x0 + 12, base - 2, AIR)
	_rect(world, x0 + 1, base - 11, x0 + 12, base - 11, BlockDB.LAB_FLOOR)
	var lx := x0 + 3
	_rect(world, lx, base - 11, lx + 1, base - 11, AIR)
	for y in range(base - 12, base - 1):
		_put(world, lx, y, BlockDB.LADDER)
	# ладдер до верхнего этажа заканчивается в проёме
	var door_x := x0 + 13 if door_right else x0
	_rect(world, door_x, base - 4, door_x, base - 2, AIR)
	_put(world, x0 + 8, base - 19, BlockDB.LAB_LIGHT)
	_put(world, x0 + 8, base - 10, BlockDB.LAB_LIGHT)
	lab_loot(world, rng, x0 + 9, base - 2, 0)
	lab_loot(world, rng, x0 + 9, base - 12, 1)


static func _corp_district(world: WorldData, xc: int, rng: RandomNumberGenerator) -> void:
	if world.width < 2000:
		return
	var base := world.surface[xc]
	StructureGen._flatten(world, xc - 74, xc + 74, base)
	# плита и алтарь
	_rect(world, xc - 34, base - 1, xc + 34, base - 1, BlockDB.LAB_FLOOR)
	_put(world, xc, base - 2, BlockDB.ALTAR)
	world.altars[Vector2i(xc, base - 2)] = "corp_guard"
	for side in [-1, 1]:
		for off in [26, 33]:
			var px: int = xc + side * off
			_rect(world, px, base - 10, px, base - 2, BlockDB.CORP_WALL)
			_put(world, px, base - 11, BlockDB.LAB_LIGHT)
	_tower(world, rng, xc - 66, base, true)
	_tower(world, rng, xc + 53, base, false)
	lab_loot(world, rng, xc - 22, base - 2, 1)
	lab_loot(world, rng, xc + 22, base - 2, 1)
	world.structures.append({"type": "arena_corp", "altar": Vector2i(xc, base - 2),
		"rect": Rect2i(xc - 40, base - 30, 81, 40), "layer": "surface"})


# ---------- Лаборатории ----------

static func _labs(world: WorldData, rng: RandomNumberGenerator) -> void:
	var w := world.width
	var floors: Array[int] = [760, 810, 860, 910]
	for yf in floors:
		_corridor(world, 60, w - 61, yf, 5, BlockDB.LAB_WALL)
		_rooms(world, rng, yf, BlockDB.LAB_WALL, 0, 70, w - 70)
	# лестницы между этажами (и сверху от гнёзд)
	for i in range(floors.size() - 1):
		for sx in range(220, w - 200, 640):
			LayerGen.ladder_shaft(world, sx + rng.randi_range(-40, 40) + i * 17, floors[i], floors[i + 1])
	for sx in range(300, w - 200, 820):
		LayerGen.ladder_shaft(world, sx + rng.randi_range(-20, 20), 722, floors[0])
	# зал Директора
	var xd := int(w * 0.4)
	LayerGen.ladder_shaft(world, xd, floors[3], 966)
	_rect(world, xd - 1, 940, xd + 46, 965, AIR)
	_rect(world, xd - 2, 938, xd + 47, 939, BlockDB.LAB_WALL)
	_rect(world, xd - 1, 966, xd + 46, 967, BlockDB.LAB_FLOOR)
	for y in range(floors[3], 966):
		_put(world, xd, y, BlockDB.LADDER)
	for y in range(938, 940):
		_put(world, xd - 1, y, AIR)
		_put(world, xd + 1, y, AIR)
	for k in range(4, 46, 8):
		_put(world, xd + k, 940, BlockDB.LAB_LIGHT)
	LayerGen.altar(world, xd + 22, 965, "director")
	lab_loot(world, rng, xd + 8, 965, 1)
	lab_loot(world, rng, xd + 38, 965, 1)
	world.structures.append({"type": "arena_lab", "altar": Vector2i(xd + 22, 965), "shaft": Vector2i(xd, floors[3]),
		"rect": Rect2i(xd - 1, 940, 48, 26), "layer": "labs"})
	world.structures.append({"type": "layer", "layer": "labs"})


# ---------- Реактор ----------

static func _reactor(world: WorldData, rng: RandomNumberGenerator) -> void:
	var w := world.width
	var floors: Array[int] = [1030, 1075, 1120]
	for yf in floors:
		_corridor(world, 60, w - 61, yf, 5, BlockDB.REACTOR_WALL)
		_rooms(world, rng, yf, BlockDB.REACTOR_WALL, 1, 70, w - 70)
	for i in range(floors.size() - 1):
		for sx in range(260, w - 200, 700):
			LayerGen.ladder_shaft(world, sx + rng.randi_range(-30, 30) + i * 23, floors[i], floors[i + 1])
	for sx in range(340, w - 200, 800):
		LayerGen.ladder_shaft(world, sx + rng.randi_range(-20, 20), 992, floors[0])
	# зал ядра: широкий, потолок с трубами, пол над магмой
	var xc := int(w * 0.62)
	LayerGen.ladder_shaft(world, xc, floors[2], 1188)
	_rect(world, xc - 1, 1148, xc + 58, 1187, AIR)
	_rect(world, xc - 2, 1146, xc + 59, 1147, BlockDB.REACTOR_WALL)
	_rect(world, xc - 1, 1188, xc + 58, 1195, BlockDB.REACTOR_WALL)
	for y in range(floors[2], 1188):
		_put(world, xc, y, BlockDB.LADDER)
	for y in range(1146, 1148):
		_put(world, xc - 1, y, AIR)
		_put(world, xc + 1, y, AIR)
	for k in range(6, 58, 10):
		_put(world, xc + k, 1148, BlockDB.LAB_LIGHT)
	LayerGen.altar(world, xc + 29, 1187, "core")
	lab_loot(world, rng, xc + 8, 1187, 2)
	lab_loot(world, rng, xc + 50, 1187, 2)
	world.structures.append({"type": "arena_core", "altar": Vector2i(xc + 29, 1187), "shaft": Vector2i(xc, floors[2]),
		"rect": Rect2i(xc - 1, 1148, 60, 40), "layer": "reactor"})
	world.structures.append({"type": "layer", "layer": "reactor"})
