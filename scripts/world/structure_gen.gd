class_name StructureGen
extends RefCounted
## Постройки мира для первого среза: арена Главаря в руинах, руины с ящиками,
## гнездо Королевы в болотах и лагерь рейдеров с подземным бункером.
## Всё пишется прямо в массив fg до создания рендера. Описания лежат в world.structures.

const AIR := BlockDB.AIR
const MIN_WIDTH := 2000
const MIN_HEIGHT := 400

static var _rng := RandomNumberGenerator.new()


static func generate(world: WorldData) -> void:
	if world.width < MIN_WIDTH or world.height < MIN_HEIGHT:
		return
	_rng.seed = world.seed_value + 30
	var cx := world.width / 2
	var arena_x := cx + 260
	_boss_arena(world, arena_x)
	_ruins(world, cx, arena_x)
	_swamp_nest(world, int(world.width * 0.1))
	_raider_camp(world, int(world.width * 0.7))
	_wasteland_arena(world, int(world.width * 0.3))


# ---------- Помощники ----------

static func _put(world: WorldData, x: int, y: int, id: int) -> void:
	if world.in_bounds(x, y):
		world.fg[y * world.width + x] = id


static func _rect(world: WorldData, x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(world, x, y, id)


## Выравнивает поверхность в колонках x0..x1 до высоты base и убирает всё над ней (деревья, хлам).
static func _flatten(world: WorldData, x0: int, x1: int, base: int) -> void:
	for x in range(x0, x1 + 1):
		if x < 0 or x >= world.width:
			continue
		var s := world.surface[x]
		var top: int = WorldGen.TOP_BLOCK[world.biome[x]]
		if s < base:
			for y in range(s, base):
				_put(world, x, y, top)
		for y in range(base - 40, base):
			_put(world, x, y, AIR)
		world.surface[x] = base


static func _loot(world: WorldData, x: int, y: int, strong: bool = false) -> void:
	var r := _rng
	var items := {"scrap": r.randi_range(2, 5), "wood": r.randi_range(2, 6), "coal": r.randi_range(1, 3)}
	if r.randf() < 0.5 or strong:
		items["bullet"] = r.randi_range(5, 12)
	if r.randf() < 0.3 or strong:
		items["medkit"] = r.randi_range(1, 2)
	if r.randf() < 0.2 or strong:
		items["iron_bar"] = r.randi_range(2, 4)
	if r.randf() < 0.12:
		items["copper_bar"] = r.randi_range(1, 3)
	_put(world, x, y, BlockDB.LOOT)
	world.tombstones[Vector2i(x, y)] = items


## Лестница вниз слева направо: каждая ступень 2 блока в ширину и на 1 ниже. Возвращает x начала.
## Приходит на уровень y_floor в колонке x_end (первая колонка камеры).
static func _stairs_left(world: WorldData, x_end: int, y_floor: int) -> int:
	var s0 := y_floor - 30
	var x_s := x_end - 60
	for _it in 5:
		var n := maxi(1, y_floor - s0)
		x_s = clampi(x_end - 2 * n, 2, world.width - 3)
		s0 = world.surface[x_s]
	var steps := maxi(1, y_floor - s0)
	x_s = clampi(x_end - 2 * steps, 2, world.width - 3)
	for i in range(steps + 1):
		var yf := s0 + i
		for dx in 2:
			var x := x_s + 2 * i + dx
			for k in range(1, 4):
				_put(world, x, yf - k, AIR)
			if world.get_block(x, yf) == AIR:
				_put(world, x, yf, BlockDB.STONE)
	# коридор до самой камеры на уровне пола
	for x in range(x_s + 2 * steps, x_end + 3):
		for k in range(1, 4):
			_put(world, x, y_floor - k, AIR)
		if world.get_block(x, y_floor) == AIR:
			_put(world, x, y_floor, BlockDB.STONE)
	return x_s


# ---------- Арена Главаря мародёров ----------

static func _boss_arena(world: WorldData, xc: int) -> void:
	var half := 28
	var base := world.surface[xc]
	_flatten(world, xc - half - 2, xc + half + 2, base)
	# укрытия: две стенки по бокам и плинт с алтарём
	_rect(world, xc - 17, base - 2, xc - 15, base - 1, BlockDB.CONCRETE)
	_rect(world, xc + 15, base - 2, xc + 17, base - 1, BlockDB.CONCRETE)
	_rect(world, xc - 1, base - 1, xc + 1, base - 1, BlockDB.CONCRETE)
	_put(world, xc, base - 2, BlockDB.ALTAR_RAIDER)
	world.altars[Vector2i(xc, base - 2)] = "chief"
	# разрушенные колонны по краям арены
	for side in [-1, 1]:
		var px: int = xc + side * half
		for k in range(1, _rng.randi_range(5, 9)):
			if _rng.randf() < 0.85:
				_put(world, px, base - k, BlockDB.CONCRETE)
	_loot(world, xc - 24, base - 1, true)
	_loot(world, xc + 24, base - 1)
	world.structures.append({"type": "arena_raider", "altar": Vector2i(xc, base - 2),
		"rect": Rect2i(xc - half, base - 30, half * 2 + 1, 40)})


# ---------- Руины ----------

static func _ruins(world: WorldData, cx: int, arena_x: int) -> void:
	var x := cx - 300
	var count := 0
	while x < cx + 320:
		var bw := _rng.randi_range(8, 14)
		var blocked: bool = absi(x + bw / 2 - cx) < 30 or absi(x + bw / 2 - arena_x) < 45
		if not blocked and x > 8 and x + bw < world.width - 8 and world.biome[x] == WorldGen.BIOME_RUINS:
			_building(world, x, bw)
			count += 1
		x += bw + _rng.randi_range(6, 22)


static func _building(world: WorldData, x0: int, bw: int) -> void:
	var base := world.surface[x0 + bw / 2]
	var fh := _rng.randi_range(5, 7)
	_flatten(world, x0 - 1, x0 + bw, base)
	for side in [x0, x0 + bw - 1]:
		for k in range(1, fh + 1):
			if k <= 2 or _rng.randf() < 0.75:
				_put(world, side, base - k, BlockDB.CONCRETE)
	for x in range(x0, x0 + bw):
		if _rng.randf() < 0.6:
			_put(world, x, base - fh, BlockDB.CONCRETE)
	var slab_end := x0 + bw / 2
	for x in range(x0 + 1, slab_end):
		_put(world, x, base - 4, BlockDB.SCRAP)
	if _rng.randf() < 0.75:
		_loot(world, x0 + bw / 2 + 1, base - 1)
	world.structures.append({"type": "ruin", "rect": Rect2i(x0, base - fh, bw, fh)})


# ---------- Гнездо Королевы-матки ----------

static func _swamp_nest(world: WorldData, xc: int) -> void:
	var max_s := 0
	for x in range(xc - 24, xc + 25):
		max_s = maxi(max_s, world.surface[x])
	var y_floor := max_s + 36
	_rect(world, xc - 22, y_floor - 16, xc + 22, y_floor + 2, BlockDB.MUD)
	_rect(world, xc - 20, y_floor - 14, xc + 20, y_floor - 1, AIR)
	var entry_x := _stairs_left(world, xc - 22, y_floor)
	# яйцевые холмики и добыча
	for dx in [-17, -9, 9, 17]:
		_rect(world, xc + dx - 1, y_floor - 1, xc + dx + 1, y_floor - 1, BlockDB.MUD)
	_put(world, xc, y_floor - 1, BlockDB.ALTAR_HIVE)
	world.altars[Vector2i(xc, y_floor - 1)] = "queen"
	_loot(world, xc - 14, y_floor - 1, true)
	_loot(world, xc + 14, y_floor - 1)
	world.structures.append({"type": "arena_hive", "altar": Vector2i(xc, y_floor - 1),
		"rect": Rect2i(xc - 20, y_floor - 14, 41, 14), "floor": y_floor,
		"entry": Vector2i(entry_x, world.surface[entry_x])})


# ---------- Лагерь рейдеров и бункер ----------

static func _raider_camp(world: WorldData, xc: int) -> void:
	var half := 24
	var base := world.surface[xc]
	_flatten(world, xc - half - 1, xc + half + 1, base)
	# частокол: слева ворота на 3 блока
	for k in range(1, 8):
		_put(world, xc - half, base - k, BlockDB.WOOD if k % 2 == 0 else BlockDB.SCRAP)
		if k > 3:
			pass
	for k in range(1, 4):
		_put(world, xc - half, base - k, AIR)
	for k in range(1, 8):
		_put(world, xc + half, base - k, BlockDB.WOOD if k % 2 == 0 else BlockDB.SCRAP)
	# вышки
	_rect(world, xc - half + 1, base - 9, xc - half + 3, base - 1, BlockDB.SCRAP)
	_rect(world, xc + half - 3, base - 9, xc + half - 1, base - 1, BlockDB.SCRAP)
	# палатки
	for tx in [xc - 12, xc + 6]:
		_rect(world, tx, base - 4, tx + 6, base - 1, BlockDB.WOOD)
		_rect(world, tx + 1, base - 3, tx + 5, base - 1, AIR)
		_loot(world, tx + 3, base - 1)
	var guards: Array = []
	for gx in [-15, -5, 4, 14, 19]:
		guards.append(Vector2i(xc + gx, base))
	world.structures.append({"type": "camp", "rect": Rect2i(xc - half, base - 9, half * 2 + 1, 10),
		"spawns": guards, "center": Vector2i(xc, base)})
	# подземный бункер под лагерем
	var y_floor := base + 30
	_rect(world, xc - 20, y_floor - 12, xc + 20, y_floor + 2, BlockDB.CONCRETE)
	_rect(world, xc - 18, y_floor - 10, xc + 18, y_floor - 1, AIR)
	var bunker_entry := _stairs_left(world, xc - 20, y_floor)
	# внутренняя перегородка с проходом и ящики
	_rect(world, xc, y_floor - 10, xc, y_floor - 4, BlockDB.CONCRETE)
	for dx in [-14, -6, 8, 15]:
		_loot(world, xc + dx, y_floor - 1, dx == 15)
	_put(world, xc + 17, y_floor - 1, BlockDB.ALTAR)
	world.altars[Vector2i(xc + 17, y_floor - 1)] = "commander"
	var bunker_guards: Array = []
	for gx in [-10, -2, 6, 12]:
		bunker_guards.append(Vector2i(xc + gx, y_floor))
	world.structures.append({"type": "bunker", "rect": Rect2i(xc - 18, y_floor - 10, 37, 10),
		"spawns": bunker_guards, "floor": y_floor,
		"entry": Vector2i(bunker_entry, world.surface[bunker_entry])})


# ---------- Арена Хозяина пустоши ----------

static func _wasteland_arena(world: WorldData, xc: int) -> void:
	var half := 30
	var base := world.surface[xc]
	_flatten(world, xc - half - 2, xc + half + 2, base)
	# каменные гребни по краям и плита с алтарём
	for side in [-1, 1]:
		for dx in range(0, 4):
			var h := 3 - dx
			for k in range(1, h + 1):
				_put(world, xc + side * (half - dx), base - k, BlockDB.SAND)
	_rect(world, xc - 2, base - 1, xc + 2, base - 1, BlockDB.CONCRETE)
	_put(world, xc, base - 2, BlockDB.ALTAR)
	world.altars[Vector2i(xc, base - 2)] = "wasteland_lord"
	_loot(world, xc - 22, base - 1, true)
	_loot(world, xc + 22, base - 1)
	world.structures.append({"type": "arena_wasteland", "altar": Vector2i(xc, base - 2),
		"rect": Rect2i(xc - half, base - 30, half * 2 + 1, 40)})
