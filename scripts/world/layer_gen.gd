class_name LayerGen
extends RefCounted
## Подземные слои: печати, метро, шахты, бункеры, гнёзда и их арены боссов.
## Всё пишется прямо в массив fg до создания рендера. Алтари регистрируются в world.altars.

const AIR := BlockDB.AIR
const MIN_WIDTH := 2000
const MIN_HEIGHT := 1200

static var rng := RandomNumberGenerator.new()


static func generate(world: WorldData) -> void:
	if world.width < MIN_WIDTH or world.height < MIN_HEIGHT:
		return
	Layers.ensure_loaded()
	rng.seed = world.seed_value + 40
	_seals(world)
	_metro(world)
	_mines(world)
	_bunkers(world)
	_nests(world)
	LabGen.generate(world, rng)


# ---------- Помощники ----------

static func put(world: WorldData, x: int, y: int, id: int) -> void:
	StructureGen._put(world, x, y, id)


static func rect(world: WorldData, x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	StructureGen._rect(world, x0, y0, x1, y1, id)


## Горизонтальный туннель: пол на yf, высота h, обшивка из lining.
static func tunnel(world: WorldData, x0: int, x1: int, yf: int, h: int, lining: int) -> void:
	rect(world, x0, yf - h - 1, x1, yf + 1, lining)
	rect(world, x0, yf - h, x1, yf - 1, AIR)


## Эллиптическая полость с обшивкой стен.
static func blob(world: WorldData, cx: int, cy: int, rx: int, ry: int, lining: int = -1, lining_chance: float = 1.0) -> void:
	for dy in range(-ry - 2, ry + 3):
		for dx in range(-rx - 2, rx + 3):
			var e := float(dx * dx) / float(rx * rx) + float(dy * dy) / float(ry * ry)
			var x := cx + dx
			var y := cy + dy
			if e <= 1.0:
				put(world, x, y, AIR)
			elif e <= 1.5 and lining >= 0 and rng.randf() < lining_chance and world.is_solid(x, y):
				put(world, x, y, lining)


## Шахта шириной 3 с лестницей по центру от y_top до y_bot (пол на y_bot).
static func ladder_shaft(world: WorldData, x: int, y_top: int, y_bot: int) -> void:
	rect(world, x - 1, y_top, x + 1, y_bot - 1, AIR)
	for y in range(y_top, y_bot):
		put(world, x, y, BlockDB.LADDER)
	rect(world, x - 1, y_bot, x + 1, y_bot, BlockDB.STONE)


## Лестница вниз вправо: ступень на 1 ниже каждые 2 блока.
static func stairs_down(world: WorldData, x_start: int, y_start: int, y_end: int) -> void:
	for i in range(y_end - y_start + 1):
		var yf := y_start + i
		for dx in 2:
			var x := x_start + 2 * i + dx
			for k in range(1, 4):
				put(world, x, yf - k, AIR)
			if world.get_block(x, yf) == AIR:
				put(world, x, yf, BlockDB.STONE)


static func loot(world: WorldData, x: int, y: int, strong: bool = false) -> void:
	StructureGen._loot(world, x, y, strong)


static func altar(world: WorldData, x: int, y: int, boss_id: String) -> void:
	put(world, x, y, BlockDB.ALTAR)
	world.altars[Vector2i(x, y)] = boss_id


static func _seals(world: WorldData) -> void:
	for l in Layers.list:
		var r := Layers.seal_rows(l)
		rect(world, 0, r.x, world.width - 1, r.y, BlockDB.SEAL)


# ---------- Метро и канализация ----------

static func _metro(world: WorldData) -> void:
	var w := world.width
	var floors: Array[int] = [232, 272]
	for yf in floors:
		tunnel(world, 40, w - 41, yf, 6, BlockDB.CONCRETE)
		var x := 120 + rng.randi_range(0, 40)
		while x < w - 140:
			rect(world, x - 10, yf - 9, x + 10, yf - 1, AIR)
			rect(world, x - 10, yf, x + 10, yf, BlockDB.CONCRETE)
			loot(world, x - 6, yf - 1)
			loot(world, x + 6, yf - 1, rng.randf() < 0.2)
			x += rng.randi_range(130, 170)
	for sx in [int(w * 0.25), int(w * 0.72)]:
		stairs_down(world, sx, floors[0], floors[1])
	world.structures.append({"type": "layer", "layer": "metro"})


# ---------- Шахты ----------

static func _mines(world: WorldData) -> void:
	var w := world.width
	for yf in [330, 368, 404]:
		tunnel(world, 60, w - 61, yf, 4, BlockDB.STONE)
		for x in range(70, w - 70, 8):
			put(world, x, yf - 4, BlockDB.WOOD)
		# обвалившиеся участки, которые придётся пробить
		for _i in 20:
			var rx := rng.randi_range(80, w - 90)
			rect(world, rx, yf - 4, rx + rng.randi_range(2, 6), yf - 1, BlockDB.STONE)
	# шахты с лестницей между горизонтами
	var xs := []
	for sx in range(260, w - 200, 520):
		xs.append(sx + rng.randi_range(-30, 30))
	for sx in xs:
		ladder_shaft(world, sx, 292, 405)
	# кристальные пещеры
	for _i in 16:
		var cx := rng.randi_range(120, w - 120)
		var cy := rng.randi_range(310, 395)
		blob(world, cx, cy, rng.randi_range(7, 11), rng.randi_range(5, 8), BlockDB.CRYSTAL, 0.35)
		if rng.randf() < 0.6:
			loot(world, cx, cy + 3)
	# арена Короля шахты: шахта с лестницей и кристальный зал
	var xa := int(w * 0.45)
	ladder_shaft(world, xa, 292, 410)
	rect(world, xa - 1, 394, xa + 46, 409, AIR)
	rect(world, xa - 1, 410, xa + 46, 411, BlockDB.STONE)
	for k in 14:
		put(world, xa + rng.randi_range(2, 45), 394, BlockDB.CRYSTAL)
	for ly in range(394, 410):
		put(world, xa, ly, BlockDB.LADDER)
	altar(world, xa + 22, 409, "mine_king")
	loot(world, xa + 8, 409, true)
	loot(world, xa + 38, 409, true)
	world.structures.append({"type": "arena_mine", "altar": Vector2i(xa + 22, 409), "shaft": Vector2i(xa, 292),
		"rect": Rect2i(xa - 1, 394, 48, 16), "layer": "mines"})


# ---------- Военные бункеры ----------

static func _bunkers(world: WorldData) -> void:
	var w := world.width
	var floors: Array[int] = [502, 542]
	for yf in floors:
		tunnel(world, 80, w - 81, yf, 5, BlockDB.REINFORCED)
		var x := 100 + rng.randi_range(0, 30)
		var n := 0
		while x < w - 160:
			var rw := rng.randi_range(14, 22)
			var up := n % 2 == 0
			var y_a: int = yf - 7 - 9 if up else yf + 3
			var y_b: int = yf - 8 if up else yf + 11
			rect(world, x - 1, y_a - 1, x + rw, y_b + 1, BlockDB.REINFORCED)
			rect(world, x, y_a, x + rw - 1, y_b, AIR)
			# проход в коридор с закрытой дверью
			var dx := x + rw / 2
			if up:
				rect(world, dx, yf - 8, dx + 1, yf - 6, AIR)
				put(world, dx, yf - 7, BlockDB.DOOR)
				put(world, dx, yf - 6, BlockDB.DOOR)
			else:
				rect(world, dx, yf + 1, dx + 1, yf + 3, AIR)
				put(world, dx, yf + 2, BlockDB.DOOR)
				put(world, dx, yf + 3, BlockDB.DOOR)
			loot(world, x + 3, y_b, n % 5 == 0)
			if rng.randf() < 0.5:
				loot(world, x + rw - 4, y_b)
			n += 1
			x += rw + rng.randi_range(8, 30)
	for sx in [int(w * 0.3), int(w * 0.8)]:
		stairs_down(world, sx, floors[0], floors[1])
	world.structures.append({"type": "layer", "layer": "bunkers"})


# ---------- Гнёзда мутантов ----------

static func _nests(world: WorldData) -> void:
	var w := world.width
	for _i in 10:
		var x := rng.randi_range(100, w - 100)
		var y := rng.randi_range(600, 700)
		var dir := 1 if rng.randf() < 0.5 else -1
		for _s in 380:
			rect(world, x, y, x + 3, y + 3, AIR)
			if rng.randf() < 0.55:
				x += dir
			elif rng.randf() < 0.5:
				y += rng.randi_range(-1, 1)
			else:
				dir = 1 if rng.randf() < 0.5 else -1
			x = clampi(x, 20, w - 24)
			y = clampi(y, 580, 705)
			if rng.randf() < 0.025:
				blob(world, x, y, rng.randi_range(7, 13), rng.randi_range(5, 9), BlockDB.MUD, 0.8)
				if rng.randf() < 0.5:
					for _k in 6:
						put(world, x + rng.randi_range(-8, 8), y + rng.randi_range(5, 8), BlockDB.BIOMASS_BLOCK)
				if rng.randf() < 0.5:
					loot(world, x, y + 4)
	# арена Мозга гнезда
	var xb := int(w * 0.55)
	ladder_shaft(world, xb - 26, 562, 700)
	rect(world, xb - 27, 682, xb + 20, 699, AIR)
	rect(world, xb - 27, 700, xb + 20, 701, BlockDB.MUD)
	rect(world, xb - 27, 681, xb + 20, 681, BlockDB.BIOMASS_BLOCK)
	altar(world, xb, 699, "nest_brain")
	loot(world, xb - 14, 699, true)
	loot(world, xb + 14, 699, true)
	world.structures.append({"type": "arena_nest", "altar": Vector2i(xb, 699), "shaft": Vector2i(xb - 26, 562),
		"rect": Rect2i(xb - 27, 682, 48, 18), "layer": "nests"})
