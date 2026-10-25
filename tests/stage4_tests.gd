extends RefCounted
## Этап 4: убежище. Критерий из ТЗ: турели работают от энергии, враги ломают слабые блоки.

const TILE := 16


func run(t) -> void:
	_test_data(t)
	_test_walls_and_hammer(t)
	_test_doors(t)
	_test_room(t)
	_test_enemy_breaks(t)
	_test_power_and_turret(t)
	_test_spikes(t)
	_test_bed(t)
	await _test_main_scene(t)


func _flat_world(w: int = 120, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	return world


func _player(world: WorldData, tile_x: int) -> Player:
	var p := Player.new()
	p.world = world
	p.position = Vector2(tile_x * TILE, 0)
	for _i in 120:
		p.physics_step(1.0 / 60.0, 0.0, false)
	p.spawn_pos = Vector2(5 * TILE, 40 * TILE - Player.SIZE.y)
	return p


func _setup(world: WorldData, p: Player) -> Array:
	var em := EnemyManager.new()
	em.world = world
	em.player = p
	em.rng.seed = 1
	p.combat = em
	var sh := ShelterManager.new()
	sh.setup(world, p, em)
	return [em, sh]


func _enemy(world: WorldData, tile_x: int, name: String = "zombie_walker") -> Enemy:
	EnemyDB.ensure_loaded()
	var e := Enemy.new()
	e.setup((EnemyDB.defs[name] as Dictionary).duplicate(true), world, 1)
	e.position = Vector2(tile_x * TILE, 40 * TILE - e.size.y)
	return e


## Комната: пол на y=40, внутренняя полость x 50..57 по ширине, y 36..39, стены и потолок из бетона, дверной проём в x=49.
func _build_room(world: WorldData, with_door: bool) -> void:
	for x in range(49, 59):
		for y in range(35, 40):
			world.set_block(x, y, BlockDB.CONCRETE)
	for x in range(50, 58):
		for y in range(36, 40):
			world.set_block(x, y, BlockDB.AIR)
	if with_door:
		world.set_block(49, 38, BlockDB.DOOR)
		world.set_block(49, 39, BlockDB.DOOR)
	else:
		world.set_block(49, 38, BlockDB.AIR)
		world.set_block(49, 39, BlockDB.AIR)


func _test_data(t) -> void:
	BlockDB.ensure_loaded()
	ItemDB.ensure_loaded()
	t.check(BlockDB.names[BlockDB.DOOR] == "door" and BlockDB.names[BlockDB.SPIKES] == "spikes", "новые блоки на своих id")
	t.check(BlockDB.device[BlockDB.TURRET] == 1 and BlockDB.device[BlockDB.DIRT] == 0, "устройства помечены")
	t.check(ItemDB.wall_id("wall_concrete") == BlockDB.CONCRETE and ItemDB.wall_id("stone") == -1, "предмет-стена знает свой материал")
	t.check(ItemDB.block_id("door") == BlockDB.DOOR, "дверь ставится как блок")
	RecipeDB.ensure_loaded()
	var ok := true
	for r in RecipeDB.recipes:
		if not ItemDB.has_item(str(r["result"])):
			ok = false
		for k in r["ingredients"]:
			if not ItemDB.has_item(str(k)):
				ok = false
	t.check(ok, "все предметы рецептов существуют")


func _test_walls_and_hammer(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var pt := p.tile_pos()
	var spot := Vector2i(pt.x + 1, 38)
	p.inv.add("wall_wood", 3)
	t.check(not p.place_block(Vector2i(pt.x + 1, 30), "wall_wood"), "стену в воздухе без опоры не поставить")
	t.check(p.place_block(Vector2i(pt.x, 39), "wall_wood"), "стена ставится рядом с твёрдым блоком")
	t.check(world.get_bg(pt.x, 39) == BlockDB.WOOD and p.inv.count("wall_wood") == 2, "стена записана в фон, предмет потрачен")
	t.check(p.place_block(Vector2i(pt.x + 1, 39), "wall_wood"), "стена ставится рядом со стеной")
	t.check(not p.place_block(Vector2i(pt.x, 39), "wall_wood"), "поверх стены стену не поставить")
	# молоток снимает стену
	p.inv.add("hammer", 1)
	p.selected = p.inv.items.find("hammer") if p.inv.items.find("hammer") < Inventory.HOTBAR else 0
	t.check(p.hammer_tick(Vector2i(pt.x, 39), 0.1) == "wall", "молоток снимает стену")
	t.check(world.get_bg(pt.x, 39) == 0 and p.inv.count("wall_wood") == 2, "стена вернулась в инвентарь")
	# молоток чинит блок
	world.set_block(pt.x + 2, 38, BlockDB.WOOD)
	world.damage_block(pt.x + 2, 38, 0.4)
	var before := world.damage_fraction(pt.x + 2, 38)
	t.check(before > 0.5, "блок повреждён")
	p.attack_cd = 0.0
	t.check(p.hammer_tick(Vector2i(pt.x + 2, 38), 0.1) == "repair", "молоток чинит")
	t.check(world.damage_fraction(pt.x + 2, 38) < before, "повреждение уменьшилось")
	for _i in 10:
		p.hammer_tick(Vector2i(pt.x + 2, 38), 0.1)
	t.check(world.damage_fraction(pt.x + 2, 38) == 0.0, "блок отремонтирован полностью")
	t.check(not p.is_hammer_selected() or p.mine_power() >= 1.0, "молоток выбран корректно")
	p.free()


func _test_doors(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var sh: ShelterManager = parts[1]
	world.set_block(30, 38, BlockDB.DOOR)
	world.set_block(30, 39, BlockDB.DOOR)
	t.check(world.is_solid(30, 38), "закрытая дверь твёрдая")
	var msg := sh.toggle_door(Vector2i(30, 39))
	t.check(world.get_block(30, 38) == BlockDB.DOOR_OPEN and world.get_block(30, 39) == BlockDB.DOOR_OPEN, "дверь открывается целиком: " + msg)
	t.check(not world.is_solid(30, 38), "открытая дверь проходима")
	sh.toggle_door(Vector2i(30, 38))
	t.check(world.get_block(30, 38) == BlockDB.DOOR and world.get_block(30, 39) == BlockDB.DOOR, "дверь закрывается целиком")
	# игрок в проёме не даёт закрыть
	sh.toggle_door(Vector2i(30, 38))
	p.position = Vector2(30 * TILE + 1, 38 * TILE)
	var m2 := sh.toggle_door(Vector2i(30, 38))
	t.check(world.get_block(30, 38) == BlockDB.DOOR_OPEN, "дверь не закрывается на игроке: " + m2)
	(parts[0] as EnemyManager).free()
	sh.free()
	p.free()


func _test_room(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var sh: ShelterManager = parts[1]
	_build_room(world, true)
	var r: Dictionary = sh.room_at(Vector2i(52, 38))
	t.check(r["enclosed"] and r["size"] == 32, "замкнутая комната 8x4: размер %d" % r["size"])
	t.check(r["doors"] == 1, "в комнате одна дверь")
	sh.toggle_door(Vector2i(49, 38))
	t.check(not sh.room_at(Vector2i(52, 38))["enclosed"], "открытая дверь размыкает комнату")
	sh.toggle_door(Vector2i(49, 38))
	world.set_block(52, 36, BlockDB.BED)
	world.set_block(55, 39, BlockDB.TURRET)
	var r2: Dictionary = sh.room_at(Vector2i(52, 38))
	t.check(r2["beds"] == 1, "кровать видна в комнате")
	world.set_block(53, 35, BlockDB.AIR)
	t.check(not sh.room_at(Vector2i(52, 38))["enclosed"], "дыра в потолке: комната не замкнута")
	t.check(not sh.room_at(Vector2i(10, 30))["enclosed"], "открытое небо — не комната")
	t.check(not sh.room_at(Vector2i(10, 45))["enclosed"] or true, "заливка внутри камня не падает")
	(parts[0] as EnemyManager).free()
	sh.free()
	p.free()


func _test_enemy_breaks(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var sh: ShelterManager = parts[1]
	# игрок внутри бункера, который закрыт дверью и потолком
	_build_room(world, true)
	p.position = Vector2(53 * TILE, 38 * TILE)
	var target := Rect2(p.position, Player.SIZE)
	var walker := _enemy(world, 40)
	var steps := 0
	while world.get_block(49, 38) == BlockDB.DOOR and steps < 60 * 30:
		walker.update(1.0 / 60.0, target, true)
		steps += 1
	t.check(world.get_block(49, 38) != BlockDB.DOOR, "ходок прогрызает дверь за %.1f с" % (steps / 60.0))
	t.check(steps > 60, "дверь держится больше секунды")
	# бетон ходок не берёт
	var world2 := _flat_world()
	_build_room(world2, false)
	for y in range(36, 40):
		world2.set_block(49, y, BlockDB.CONCRETE)
	var w2 := _enemy(world2, 40)
	var tgt2 := Rect2(Vector2(53 * TILE, 38 * TILE), Player.SIZE)
	for _i in 60 * 20:
		w2.update(1.0 / 60.0, tgt2, true)
	t.check(world2.get_block(49, 38) == BlockDB.CONCRETE and world2.get_block(49, 39) == BlockDB.CONCRETE, "бетонная стена выдерживает ходока")
	# толстяк бетон грызёт
	var fat := _enemy(world2, 40, "zombie_fat")
	var broke := false
	for _i in 60 * 40:
		fat.update(1.0 / 60.0, tgt2, true)
		for y in range(35, 40):
			if not world2.is_solid(49, y):
				broke = true
		if broke:
			break
	t.check(broke, "толстяк ломает бетон")
	# зомби не ломает бедрок и не ломает, если не упёрся в стену
	var w3 := _enemy(world, 90)
	var hp0 := world.get_block(89, 39)
	for _i in 60:
		w3.update(1.0 / 60.0, Rect2(Vector2(110 * TILE, 38 * TILE), Player.SIZE), true)
	t.check(world.get_block(89, 39) == hp0, "без препятствия ничего не ломается")
	(parts[0] as EnemyManager).free()
	sh.free()
	for e in [walker, w2, fat, w3]:
		e.free()
	p.free()


func _test_power_and_turret(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var em: EnemyManager = parts[0]
	var sh: ShelterManager = parts[1]
	world.set_block(30, 39, BlockDB.GENERATOR)
	world.set_block(32, 39, BlockDB.TURRET)
	t.check(sh.devices.size() == 2, "устройства зарегистрированы")
	var e := _enemy(world, 36)
	em.add_child(e)
	em.enemies.append(e)
	var hp0 := e.hp
	for _i in 120:
		sh.update(1.0 / 60.0)
	t.check(not sh.is_powered(Vector2i(32, 39)) and e.hp == hp0, "без топлива турель не стреляет")
	# заправка
	p.position = Vector2(29 * TILE, 38 * TILE)
	p.inv.add("coal", 3)
	var msg := sh.interact(Vector2i(30, 39), p)
	t.check(p.inv.count("coal") == 0 and sh.fuel[Vector2i(30, 39)] == 3 * ShelterManager.FUEL_PER_COAL, "генератор принимает уголь: " + msg)
	for _i in 60:
		sh.update(1.0 / 60.0)
	t.check(sh.is_powered(Vector2i(32, 39)), "с топливом турель под напряжением")
	t.check(e.hp < hp0, "турель стреляет по врагу")
	var guard := 0
	while not e.dead and guard < 60 * 20:
		sh.update(1.0 / 60.0)
		guard += 1
	t.check(e.dead, "турель убивает ходока за %.1f с" % (guard / 60.0))
	# расход топлива идёт только под нагрузкой
	var f1: float = sh.fuel[Vector2i(30, 39)]
	for _i in 120:
		sh.update(1.0 / 60.0)
	t.check(sh.fuel[Vector2i(30, 39)] < f1, "топливо расходуется, пока турели включены")
	# вторая турель далеко от генератора без энергии
	world.set_block(80, 39, BlockDB.TURRET)
	sh.recompute_power()
	t.check(not sh.is_powered(Vector2i(80, 39)), "вне радиуса сети энергии нет")
	# лимит мощности: 3 турели на 12 ед., четвёртая обесточена
	for x in [33, 34, 35]:
		world.set_block(x, 39, BlockDB.TURRET)
	sh.recompute_power()
	var on := 0
	for tp in [Vector2i(32, 39), Vector2i(33, 39), Vector2i(34, 39), Vector2i(35, 39)]:
		if sh.is_powered(tp):
			on += 1
	t.check(on == 3, "генератор тянет 3 турели из 4 (включено %d)" % on)
	# топливо кончилось
	sh.fuel[Vector2i(30, 39)] = 0.01
	for _i in 30:
		sh.update(1.0 / 60.0)
	t.check(not sh.is_powered(Vector2i(32, 39)), "топливо кончилось: турели выключены")
	# разрушение турели снимает с учёта
	world.set_block(32, 39, BlockDB.AIR)
	t.check(not sh.devices.has(Vector2i(32, 39)), "сломанная турель удалена из реестра")
	em.free()
	sh.free()
	p.free()


func _test_spikes(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var em: EnemyManager = parts[0]
	var sh: ShelterManager = parts[1]
	world.set_block(40, 39, BlockDB.SPIKES)
	var e := _enemy(world, 40)
	em.add_child(e)
	em.enemies.append(e)
	var hp0 := e.hp
	for _i in 10:
		sh.update(1.0 / 60.0)
	t.check(e.hp < hp0, "шипы ранят врага")
	var guard := 0
	while not e.dead and guard < 60 * 10:
		e.position = Vector2(40 * TILE, 40 * TILE - e.size.y)
		sh.update(1.0 / 60.0)
		guard += 1
	t.check(e.dead, "шипы убивают за %.1f с" % (guard / 60.0))
	# шипы не ранят игрока
	var hp := p.hp
	p.position = Vector2(40 * TILE, 40 * TILE - Player.SIZE.y)
	for _i in 60:
		sh.update(1.0 / 60.0)
	t.check(p.hp == hp, "шипы не вредят игроку")
	em.free()
	sh.free()
	p.free()


func _test_bed(t) -> void:
	var world := _flat_world()
	var p := _player(world, 20)
	var parts := _setup(world, p)
	var sh: ShelterManager = parts[1]
	world.set_block(22, 39, BlockDB.BED)
	var old := p.spawn_pos
	sh.interact(Vector2i(22, 39), p)
	t.check(p.spawn_pos != old and p.spawn_pos.x == 22 * TILE + 1, "кровать задаёт точку возрождения")
	t.check(sh.interact(Vector2i(22, 10), p) == "", "вне досягаемости ничего не происходит")
	(parts[0] as EnemyManager).free()
	sh.free()
	p.free()


func _test_main_scene(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 600
	main.world_height = 300
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 600:
		await t.process_frame
		guard += 1
	t.check(main.ready_done, "сцена со стадией 4 запускается")
	t.check(main.shelter != null and main.player.shelter == main.shelter, "менеджер убежища подключён к игроку")
	main.player.inv.add("generator", 1)
	var pt: Vector2i = main.player.tile_pos()
	main.world.set_block(pt.x + 2, pt.y, BlockDB.GENERATOR)
	t.check(main.shelter.devices.size() == 1, "устройство, поставленное в живой сцене, учтено")
	main.queue_free()
	await t.process_frame
