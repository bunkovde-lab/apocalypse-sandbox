class_name WorldGen
extends RefCounted
## Генерация мира. Этап 1: поверхность с пятью биомами, подземный камень, пещеры и руды.
## Бункеры, лагеря и корпоративные зоны добавляются на следующих этапах.

const SURFACE_BASE := 120

const BIOME_SWAMP := 0
const BIOME_WASTELAND := 1
const BIOME_RUINS := 2
const BIOME_RAIDERS := 3
const BIOME_CORPORATE := 4
const BIOME_COUNT := 5

# Верхний слой почвы и его толщина по биомам (порядок как у констант биомов).
const TOP_BLOCK := [4, 3, 1, 1, 5]    # грязь, песок, земля, земля, бетон
const TOP_DEPTH := [12, 14, 8, 6, 4]
const AMPLITUDE := [0.4, 0.7, 0.5, 1.0, 0.2]
# Шанс дерева и кучи металлолома на колонку по биомам.
const TREE_CHANCE := [0.05, 0.01, 0.03, 0.025, 0.0]
const SCRAP_CHANCE := [0.01, 0.015, 0.03, 0.03, 0.04]


@warning_ignore("integer_division")
static func generate(seed_value: int, w: int = 4200, h: int = 1200) -> WorldData:
	var world := WorldData.new(w, h)
	world.seed_value = seed_value
	_make_surface(world)
	_fill_terrain(world)
	_decorate_surface(world)
	var cx := w / 2
	world.spawn_tile = Vector2i(cx, world.surface[cx] - 4)
	return world


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = freq
	return n


static func _noise_bytes(seed_value: int, freq: float, w: int, h: int) -> PackedByteArray:
	var img := _noise(seed_value, freq).get_image(w, h, false, false, true)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _make_surface(world: WorldData) -> void:
	var w := world.width
	var hill := _noise(world.seed_value, 0.004)
	var detail := _noise(world.seed_value + 1, 0.03)
	var edge := _noise(world.seed_value + 2, 0.005)
	var band := float(w) / BIOME_COUNT
	var cx := w * 0.5
	var raw := PackedFloat32Array()
	raw.resize(w)
	for x in w:
		var jitter := edge.get_noise_1d(x) * 40.0
		var b := clampi(int((x + jitter) / band), 0, BIOME_COUNT - 1)
		world.biome[x] = b
		var flat := clampf(absf(x - cx) / 250.0, 0.2, 1.0)
		var a: float = AMPLITUDE[b] * flat
		raw[x] = SURFACE_BASE + hill.get_noise_1d(x) * 30.0 * a + detail.get_noise_1d(x) * 6.0 * a
	for _pass in 2:
		var tmp := raw.duplicate()
		for x in w:
			var total := 0.0
			var n := 0
			for k in range(-5, 6):
				var xx := x + k
				if xx >= 0 and xx < w:
					total += raw[xx]
					n += 1
			tmp[x] = total / n
		raw = tmp
	for x in w:
		world.surface[x] = roundi(raw[x])


@warning_ignore("integer_division")
static func _fill_terrain(world: WorldData) -> void:
	var w := world.width
	var h := world.height
	var sd := world.seed_value
	var cave_a := _noise_bytes(sd + 10, 0.018, w, h)   # узкие туннели
	var cave_b := _noise_bytes(sd + 11, 0.011, w, h)   # крупные полости
	var ore_a := _noise_bytes(sd + 12, 0.12, w, h)     # железо и кристаллы
	var ore_b := _noise_bytes(sd + 13, 0.12, w, h)     # медь и уголь
	var fg := world.fg
	var cx := w / 2
	for x in w:
		var s := world.surface[x]
		var b := world.biome[x]
		var top_block: int = TOP_BLOCK[b]
		var top_depth: int = TOP_DEPTH[b]
		var spawn_zone := absi(x - cx) < 70
		for y in range(s, h):
			var idx := y * w + x
			var depth := y - s
			var id := BlockDB.STONE
			if y >= h - 3:
				id = BlockDB.BEDROCK
			elif depth < top_depth:
				id = top_block
			else:
				var cave := false
				if depth > 12 and not (spawn_zone and depth < 45):
					cave = absi(cave_a[idx] - 128) < 7 or cave_b[idx] > 222
				if cave:
					id = BlockDB.AIR
				elif ore_a[idx] > 236 and depth > 25:
					id = BlockDB.IRON_ORE
				elif ore_b[idx] > 236 and depth > 15:
					id = BlockDB.COPPER_ORE
				elif ore_b[idx] < 20 and depth > 40:
					id = BlockDB.COAL
				elif ore_a[idx] < 14 and depth > 150:
					id = BlockDB.CRYSTAL
			fg[idx] = id
	world.fg = fg


## Мёртвые деревья (дают дерево) и кучи металлолома на поверхности. Возле старта (3 блока) пусто.
@warning_ignore("integer_division")
static func _decorate_surface(world: WorldData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.seed_value + 20
	var w := world.width
	var cx := w / 2
	var last_tree := -100
	var last_pile := -100
	for x in range(8, w - 8):
		if absi(x - cx) <= 3:
			continue
		var b := world.biome[x]
		var s := world.surface[x]
		if x - last_tree >= 6 and rng.randf() < TREE_CHANCE[b]:
			var h := rng.randi_range(4, 9)
			for k in range(1, h + 1):
				world.fg[(s - k) * w + x] = BlockDB.WOOD
			last_tree = x
		elif x - last_pile >= 10 and rng.randf() < SCRAP_CHANCE[b]:
			var width := rng.randi_range(1, 3)
			for dx in width:
				var xx := x + dx
				if absi(xx - cx) <= 3:
					continue
				for k in range(1, rng.randi_range(1, 2) + 1):
					world.fg[(world.surface[xx] - k) * w + xx] = BlockDB.SCRAP
			last_pile = x + width
