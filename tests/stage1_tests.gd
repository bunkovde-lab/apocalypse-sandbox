extends RefCounted
## Этап 1: ядро мира. Критерий из ТЗ: мир 4200x1200 создаётся за 10 секунд или быстрее,
## блок ставится и убирается, игрок ходит, прыгает и не проходит сквозь стены.

const TILE := 16


func run(t) -> void:
	_test_block_db(t)
	_test_world_data(t)
	_test_collider(t)
	_test_mining_and_placing(t)
	_test_world_gen_small(t)
	_test_world_gen_full(t)
	_test_renderer(t)
	await _test_main_scene(t)


func _flat_world(w: int = 64, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	return world


func _player_on(world: WorldData, tile_x: int) -> Player:
	var p := Player.new()
	p.world = world
	p.position = Vector2(tile_x * TILE, 0)
	for _i in 120:
		p.physics_step(1.0 / 60.0, 0.0, false)
	return p


func _test_block_db(t) -> void:
	BlockDB.ensure_loaded()
	t.check(BlockDB.count >= 13, "в базе минимум 13 блоков, нашлось %d" % BlockDB.count)
	t.check(BlockDB.is_solid(BlockDB.STONE) and not BlockDB.is_solid(BlockDB.AIR), "камень твёрдый, воздух нет")
	t.check(BlockDB.hardness[BlockDB.BEDROCK] < 0.0, "основание неразрушимо")
	t.check(BlockDB.name_to_id["iron_ore"] == BlockDB.IRON_ORE, "имена блоков совпадают с константами")
	t.check(BlockDB.placeable[BlockDB.DIRT] == 1 and BlockDB.placeable[BlockDB.IRON_ORE] == 0, "ставить можно землю, но не руду")


func _test_world_data(t) -> void:
	var world := _flat_world(32, 32, 20)
	t.check(world.get_block(-1, 5) == BlockDB.BEDROCK, "за левым краем твёрдая стена")
	t.check(world.get_block(5, -3) == BlockDB.AIR, "над миром воздух")
	t.check(world.get_block(5, 99) == BlockDB.BEDROCK, "под миром твёрдая стена")
	var changes := [0]
	world.block_changed.connect(func(_x, _y): changes[0] += 1)
	world.set_block(3, 25, BlockDB.AIR)
	world.set_block(3, 25, BlockDB.AIR)
	t.check(world.get_block(3, 25) == BlockDB.AIR and changes[0] == 1, "set_block меняет блок и шлёт сигнал один раз")
	t.check(world.dirty_chunks.has(Vector2i(0, 0)), "изменённый чанк помечается для сохранения")
	t.check(not world.damage_block(4, 25, 0.5), "половина урона блок не ломает")
	t.check(world.damage_fraction(4, 25) > 0.4, "урон накапливается")
	t.check(world.damage_block(4, 25, 0.5) and world.get_block(4, 25) == BlockDB.AIR, "накопленный урон ломает камень")
	world.set_block(5, 25, BlockDB.BEDROCK)
	t.check(not world.damage_block(5, 25, 100.0), "основание не ломается")
	t.check(world.get_bg(5, 21) == BlockDB.DIRT and world.get_bg(5, 40) == 0, "стена: земля под поверхностью, вне мира нет")
	world.set_bg(5, 21, 0)
	t.check(world.get_bg(5, 21) == 0, "стену можно убрать")


func _test_collider(t) -> void:
	var world := _flat_world()
	var p := _player_on(world, 10)
	t.check(p.on_floor, "игрок падает и встаёт на пол")
	t.check(absf(p.position.y + Player.SIZE.y - 40 * TILE) < 0.01, "ноги точно на поверхности пола")

	# Стена высотой 3 блока: пройти нельзя.
	for y in [37, 38, 39]:
		world.fg[y * world.width + 30] = BlockDB.STONE
	var q := _player_on(world, 15)
	for _i in 300:
		q.physics_step(1.0 / 60.0, 1.0, false)
	t.check(q.position.x + Player.SIZE.x <= 30 * TILE + 0.01, "высокая стена останавливает игрока")
	t.check(q.position.x + Player.SIZE.x > 30 * TILE - 2.0, "игрок упирается вплотную в стену")

	# Ступенька в один блок: проходится без прыжка.
	var world2 := _flat_world()
	world2.fg[39 * world2.width + 30] = BlockDB.STONE
	var r := _player_on(world2, 15)
	for _i in 300:
		r.physics_step(1.0 / 60.0, 1.0, false)
	t.check(r.position.x > 31 * TILE, "ступеньку в блок игрок преодолевает")

	# Прыжок: высота около 5-6 блоков.
	var world3 := _flat_world()
	var j := _player_on(world3, 10)
	var floor_y := j.position.y
	var top := floor_y
	j.physics_step(1.0 / 60.0, 0.0, true)
	for _i in 90:
		j.physics_step(1.0 / 60.0, 0.0, false)
		top = minf(top, j.position.y)
	var rise := floor_y - top
	t.check(rise > 80.0 and rise < 100.0, "высота прыжка %.0f пикселей (5-6 блоков)" % rise)
	t.check(j.on_floor, "после прыжка игрок снова на полу")

	# Потолок: прыжок под низким блоком упирается в него.
	var world4 := _flat_world()
	var c := _player_on(world4, 10)
	world4.fg[37 * world4.width + 10] = BlockDB.STONE   # потолок ставим, когда игрок уже стоит под ним
	var min_y := c.position.y
	c.physics_step(1.0 / 60.0, 0.0, true)
	for _i in 60:
		c.physics_step(1.0 / 60.0, 0.0, false)
		min_y = minf(min_y, c.position.y)
	t.check(min_y >= 38 * TILE - 0.01, "блок над головой не даёт прыгнуть выше")

	# Быстрое падение не пробивает пол.
	var world5 := _flat_world()
	var f := Player.new()
	f.world = world5
	f.position = Vector2(200, 100)
	f.vel = Vector2(0, 700)
	for _i in 200:
		f.physics_step(0.05, 0.0, false)
	t.check(f.position.y + Player.SIZE.y <= 40 * TILE + 0.01, "падение на скорости не проходит сквозь пол")
	for node in [p, q, r, j, c, f]:
		node.free()


func _test_mining_and_placing(t) -> void:
	var world := _flat_world()
	var p := _player_on(world, 10)
	var below := Vector2i(p.tile_pos().x, 40)
	var ticks := 0
	var broken := false
	while not broken and ticks < 60:
		broken = p.mine_tick(below, 0.05)
		ticks += 1
	t.check(broken and world.get_block(below.x, below.y) == BlockDB.AIR, "камень разрушается за %d тиков" % ticks)
	t.check(ticks >= 15 and ticks <= 25, "камень ломается примерно за секунду")
	t.check(p.item_count("stone") == 1, "добытый камень попадает в инвентарь")

	var far := Vector2i(below.x + 20, 40)
	t.check(not p.mine_tick(far, 5.0) and world.get_block(far.x, far.y) == BlockDB.STONE, "далёкий блок копать нельзя")

	t.check(p.place_block(below, "stone") and world.get_block(below.x, below.y) == BlockDB.STONE, "блок ставится обратно")
	t.check(p.item_count("stone") == 0, "поставленный блок расходуется")
	t.check(not p.place_block(below, "stone"), "на занятое место ставить нельзя")

	var beside := Vector2i(below.x + 3, 39)
	t.check(not p.place_block(beside, "dirt"), "без предмета в инвентаре блок не ставится")
	p.add_item("dirt", 5)
	t.check(p.place_block(beside, "dirt") and p.item_count("dirt") == 4, "земля ставится рядом с твёрдым блоком")
	t.check(not p.place_block(Vector2i(below.x, 35), "dirt"), "блок не висит в воздухе без опоры")
	t.check(not p.place_block(p.tile_pos(), "dirt"), "нельзя поставить блок внутрь игрока")
	t.check(not p.place_block(Vector2i(below.x + 1, 39), "iron_ore"), "руду поставить нельзя")
	p.free()


func _test_world_gen_small(t) -> void:
	var a := WorldGen.generate(42, 512, 300)
	var b := WorldGen.generate(42, 512, 300)
	var c := WorldGen.generate(43, 512, 300)
	t.check(a.checksum() == b.checksum(), "один seed даёт один и тот же мир")
	t.check(a.checksum() != c.checksum(), "другой seed даёт другой мир")


func _test_world_gen_full(t) -> void:
	var t0 := Time.get_ticks_msec()
	var world := WorldGen.generate(20261025)
	var elapsed := Time.get_ticks_msec() - t0
	print("  время генерации 4200x1200: %d мс" % elapsed)
	t.check(world.width == 4200 and world.height == 1200, "размер мира 4200x1200")
	t.check(elapsed <= 10000, "генерация не дольше 10 секунд (%d мс)" % elapsed)

	var biomes := {}
	var min_s := 9999
	var max_s := 0
	for x in world.width:
		biomes[world.biome[x]] = true
		min_s = mini(min_s, world.surface[x])
		max_s = maxi(max_s, world.surface[x])
	t.check(biomes.size() == WorldGen.BIOME_COUNT, "на поверхности есть все 5 биомов")
	t.check(min_s >= 60 and max_s <= 200, "поверхность между %d и %d" % [min_s, max_s])

	var counts := []
	counts.resize(BlockDB.count)
	counts.fill(0)
	var fg := world.fg
	for i in fg.size():
		counts[fg[i]] += 1
	for id in [BlockDB.IRON_ORE, BlockDB.COPPER_ORE, BlockDB.COAL, BlockDB.CRYSTAL, BlockDB.SAND, BlockDB.MUD, BlockDB.CONCRETE]:
		t.check(counts[id] > 100, "в мире есть %s (%d блоков)" % [BlockDB.names[id], counts[id]])
	var cave_share := float(counts[BlockDB.AIR]) / fg.size()
	t.check(cave_share > 0.05 and cave_share < 0.45, "воздух и пещеры занимают %.0f%% мира" % (cave_share * 100.0))

	var bedrock_ok := true
	for x in range(0, world.width, 7):
		for y in range(world.height - 3, world.height):
			if world.get_block(x, y) != BlockDB.BEDROCK:
				bedrock_ok = false
	t.check(bedrock_ok, "дно мира из основания")

	var cx := world.width / 2
	var solid_spawn := true
	for x in range(cx - 69, cx + 70):
		for y in range(world.surface[x] + 12, world.surface[x] + 45):
			if world.get_block(x, y) == BlockDB.AIR:
				solid_spawn = false
	t.check(solid_spawn, "под местом старта нет пещер")
	var sp := world.spawn_tile
	t.check(world.get_block(sp.x, sp.y) == BlockDB.AIR and world.surface[sp.x] > sp.y, "точка старта над землёй")
	var bad := 0
	var total := 0
	for x in range(0, world.width, 11):
		total += 1
		var above := world.get_block(x, world.surface[x] - 1)
		if [BlockDB.STONE, BlockDB.DIRT, BlockDB.SAND].has(above):
			bad += 1
	var air_above := bad * 50 <= total
	t.check(air_above, "над поверхностью почти везде нет природной породы (исключения — арены, %d из %d)" % [bad, total])


func _test_renderer(t) -> void:
	var world := _flat_world(512, 128, 40)
	var renderer := ChunkRenderer.new()
	t.root.add_child(renderer)
	renderer.setup(world, TileSetBuilder.build())
	renderer.update_view(Vector2i(64, 45))
	renderer.flush()
	t.check(renderer.loaded_count() > 0 and renderer.loaded_count() <= 35, "загружено %d чанков (не больше 35)" % renderer.loaded_count())
	var view := renderer.get_view(Vector2i(2, 1))
	t.check(view != null, "чанк под игроком загружен")
	var local := Vector2i(0, 18)   # тайл (64, 50): камень
	t.check(view.fg.get_cell_source_id(local) == 0, "камень нарисован")
	world.set_block(64, 50, BlockDB.AIR)
	t.check(view.fg.get_cell_source_id(local) == -1, "после копания блок исчез с экрана")
	t.check(view.bg.get_cell_source_id(local) == 0, "на его месте видна стена")
	world.set_block(64, 50, BlockDB.DIRT)
	t.check(view.fg.get_cell_source_id(local) == 0 and view.bg.get_cell_source_id(local) == -1, "поставленный блок снова рисуется")
	renderer.update_view(Vector2i(480, 45))
	t.check(renderer.get_view(Vector2i(2, 1)) == null, "далёкие чанки выгружаются")
	renderer.flush()
	t.check(renderer.loaded_count() <= 35, "после перехода чанков не больше 35 (%d)" % renderer.loaded_count())
	renderer.queue_free()


func _test_main_scene(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 256
	main.world_height = 160
	t.root.add_child(main)
	for _i in 60:
		await t.process_frame
		if main.ready_done:
			break
	t.check(main.ready_done, "главная сцена запускается и создаёт мир")
	if main.ready_done:
		for _i in 200:
			main.player.physics_step(1.0 / 60.0, 0.0, false)
		t.check(main.player.on_floor, "игрок из точки старта приземляется")
		await t.process_frame
		t.check(main.renderer.loaded_count() > 0, "вокруг игрока показаны чанки")
		t.check(main.hud.label.text != "", "интерфейс показывает состояние")
		t.check(main.camera != null and main.camera.is_current(), "камера следует за игроком")
	main.queue_free()
	await t.process_frame
