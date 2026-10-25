extends RefCounted
## Этап 3: враги и бой. Критерий из ТЗ: ночью появляется орда, героя можно убить и можно победить орду.

const TILE := 16


func run(t) -> void:
	_test_clock(t)
	_test_enemy_db(t)
	_test_enemy_ai(t)
	_test_player_damage(t)
	_test_death_and_tombstone(t)
	_test_melee(t)
	_test_gun(t)
	_test_waves(t)
	_test_horde_defeat(t)
	await _test_main_scene(t)


func _flat_world(w: int = 200, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	world.biome.fill(WorldGen.BIOME_RUINS)
	return world


func _player(world: WorldData, tile_x: int) -> Player:
	var p := Player.new()
	p.world = world
	p.position = Vector2(tile_x * TILE, 0)
	for _i in 120:
		p.physics_step(1.0 / 60.0, 0.0, false)
	p.spawn_pos = Vector2(5 * TILE, 40 * TILE - Player.SIZE.y)
	return p


func _walker() -> Dictionary:
	EnemyDB.ensure_loaded()
	return (EnemyDB.defs["zombie_walker"] as Dictionary).duplicate(true)


func _enemy_at(world: WorldData, tile_x: int, def: Dictionary = {}, night: int = 1) -> Enemy:
	var e := Enemy.new()
	e.setup(def if not def.is_empty() else _walker(), world, night)
	e.position = Vector2(tile_x * TILE, 40 * TILE - e.size.y)
	return e


func _test_clock(t) -> void:
	var c := DayClock.new()
	var nights := []
	var dawns := [0]
	c.night_started.connect(func(n: int) -> void: nights.append(n))
	c.dawn.connect(func() -> void: dawns[0] += 1)
	t.check(not c.is_night() and c.darkness() == 0.0, "утро: светло")
	c.time = 0.8
	t.check(c.is_night() and c.darkness() == 1.0, "глубокая ночь: темно")
	c.time = 0.5
	t.check(c.darkness() == 0.0, "полдень: светло")
	var prev := 0.0
	var monotonic := true
	for i in 21:
		c.time = 0.5 + i * 0.01
		var d := c.darkness()
		if d < prev - 0.0001:
			monotonic = false
		prev = d
	t.check(monotonic and prev > 0.99, "вечером темнота нарастает плавно")
	c.time = 0.0
	t.check(c.clock_text() == "06:00", "время 0 показывается как 06:00")
	c.time = 0.5
	t.check(c.clock_text() == "18:00", "середина суток показывается как 18:00")
	c.time = 0.1
	c.day = 1
	for _i in 960:
		c.advance(1.0)
	t.check(c.day == 3, "за две минуты суток проходит 2 дня")
	t.check(nights == [1, 2] and dawns[0] == 2, "две ночи и два рассвета, номера ночей 1 и 2")
	t.check(c.tint() == Color.WHITE, "днём цвет без затемнения")


func _test_enemy_db(t) -> void:
	EnemyDB.ensure_loaded()
	t.check(EnemyDB.defs.size() >= 3, "есть минимум 3 типа врагов")
	var ok := true
	for d in EnemyDB.defs.values():
		if float(d["hp"]) <= 0.0 or float(d["speed"]) <= 0.0 or float(d["damage"]) <= 0.0:
			ok = false
		for drop in d["drops"]:
			if not ItemDB.has_item(str(drop["item"])):
				ok = false
	t.check(ok, "характеристики врагов положительные, добыча существует")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var only_walkers := true
	for _i in 100:
		if EnemyDB.pick(1, rng)["name"] != "zombie_walker":
			only_walkers = false
	t.check(only_walkers, "в первую ночь приходят только ходоки")
	var seen := {}
	for _i in 600:
		seen[EnemyDB.pick(3, rng)["name"]] = true
	t.check(seen.size() == 3, "к третьей ночи приходят все три типа")


func _test_enemy_ai(t) -> void:
	var world := _flat_world()
	var target := Rect2(Vector2(100 * TILE, 40 * TILE - Player.SIZE.y), Player.SIZE)

	var e := _enemy_at(world, 90)
	var d0 := absf(e.center().x - target.get_center().x)
	var touched := false
	for _i in 400:
		touched = e.update(1.0 / 60.0, target, true) or touched
	t.check(touched, "орда доходит до игрока и касается его")
	t.check(absf(e.center().x - target.get_center().x) < d0, "враг приблизился")

	var far := _enemy_at(world, 70)
	var x0 := far.position.x
	for _i in 120:
		far.update(1.0 / 60.0, target, false)
	t.check(absf(far.position.x - x0) < 100.0, "днём враг далеко от игрока не бросается в погоню")

	var w2 := _flat_world()
	for y in [38, 39]:
		w2.fg[y * w2.width + 95] = BlockDB.STONE
	var jumper := _enemy_at(w2, 90)
	for _i in 900:
		jumper.update(1.0 / 60.0, target, true)
	t.check(jumper.position.x > 96 * TILE, "враг перепрыгивает стену в 2 блока")

	var w3 := _flat_world()
	for y in range(30, 40):
		w3.fg[y * w3.width + 95] = BlockDB.STONE
	var blocked := _enemy_at(w3, 90)
	for _i in 900:
		blocked.update(1.0 / 60.0, target, true)
	t.check(blocked.position.x + blocked.size.x <= 95 * TILE + 0.01, "высокая стена останавливает врага")

	var scaled := _enemy_at(world, 50, {}, 5)
	t.check(scaled.max_hp > e.max_hp * 1.5 and scaled.damage > e.damage, "в пятую ночь враги сильнее первой")
	for n in [e, far, jumper, blocked, scaled]:
		n.free()


func _test_player_damage(t) -> void:
	var world := _flat_world()
	var p := _player(world, 100)
	var from_left := p.center().x - 30.0
	t.check(p.take_damage(10.0, from_left) and p.hp == 90.0, "удар отнимает здоровье")
	t.check(not p.take_damage(10.0, from_left) and p.hp == 90.0, "сразу после удара игрок неуязвим")
	t.check(p.vel.x > 0.0 and p.vel.y < 0.0, "удар отбрасывает от врага")
	for _i in 60:
		p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(p.take_damage(10.0, from_left) and p.hp == 80.0, "после паузы урон снова проходит")
	for _i in 240:
		p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(p.hp == 80.0, "первые 4 секунды после боя лечения нет")
	for _i in 600:
		p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(p.hp > 90.0, "потом здоровье восстанавливается (%.0f)" % p.hp)
	p.free()


func _test_death_and_tombstone(t) -> void:
	var world := _flat_world()
	var p := _player(world, 100)
	p.add_item("dirt", 10)
	p.add_item("stone", 3)
	p.add_item("wood_pick", 1)
	var died := [0]
	p.died.connect(func() -> void: died[0] += 1)
	var death_tile := p.tile_pos()
	p.take_damage(500.0, p.center().x + 20.0)
	t.check(died[0] == 1 and p.deaths == 1, "смерть сообщается один раз")
	t.check(p.hp == p.max_hp and p.position == p.spawn_pos, "игрок воскресает на точке старта со здоровьем")
	t.check(p.item_count("dirt") == 5 and p.item_count("stone") == 2 and p.item_count("wood_pick") == 1, "потеряна половина стопок, одиночные вещи остались")
	var spot := Vector2i(-1, -1)
	for key in world.tombstones.keys():
		spot = key
	t.check(spot.x >= 0 and world.get_block(spot.x, spot.y) == BlockDB.TOMBSTONE, "на месте гибели стоит надгробие")
	t.check(absi(spot.x - death_tile.x) <= 1, "надгробие возле места смерти")
	t.check(world.tombstones[spot].get("dirt", 0) == 5 and world.tombstones[spot].get("stone", 0) == 1, "в надгробии потерянные вещи")

	p.position = Vector2(spot.x * TILE - 20.0, 40 * TILE - Player.SIZE.y)
	p.invuln = 0.0
	var broke := false
	for _i in 60:
		broke = broke or p.mine_tick(spot, 0.05)
	t.check(broke and p.item_count("dirt") == 10 and p.item_count("stone") == 3, "вещи возвращаются из надгробия")
	t.check(world.get_block(spot.x, spot.y) == BlockDB.AIR and not world.tombstones.has(spot), "надгробие исчезло")

	# Инвентарь полон: надгробие остаётся с остатком, ничего не теряется.
	var q := _player(world, 120)
	var spot2 := Vector2i(q.tile_pos().x + 1, 39)
	world.set_block(spot2.x, spot2.y, BlockDB.TOMBSTONE)
	world.tombstones[spot2] = {"dirt": 5}
	for i in Inventory.SIZE:
		q.inv.add("wood_pick", 1)
	for _i in 60:
		q.mine_tick(spot2, 0.05)
	t.check(world.get_block(spot2.x, spot2.y) == BlockDB.TOMBSTONE and world.tombstones[spot2]["dirt"] == 5, "при полном инвентаре вещи остаются на надгробии")
	p.free()
	q.free()


func _test_melee(t) -> void:
	var world := _flat_world()
	var p := _player(world, 100)
	var clock := DayClock.new()
	var combat := EnemyManager.new()
	combat.setup(world, p, clock)
	combat.day_spawns = false
	var aim_right := Vector2(p.center().x + 200.0, p.center().y)

	t.check(not p.try_attack(aim_right), "без оружия в руках не бьёт")
	p.inv.add("wood_club", 1)
	t.check(p.is_weapon_selected() and p.selected_item() == "wood_club", "дубина в выбранной ячейке")

	var def := _walker()
	def["drops"] = [{"item": "scrap", "chance": 1.0, "min": 2, "max": 2}]
	var front := combat.spawn_enemy(def, 102)
	var behind := combat.spawn_enemy(def, 97)
	var far := combat.spawn_enemy(def, 120)
	var hp0 := front.hp
	t.check(p.try_attack(aim_right), "атака проходит")
	t.check(is_equal_approx(front.hp, hp0 - 12.0), "дубина наносит 12 урона врагу впереди")
	t.check(behind.hp == behind.max_hp and far.hp == far.max_hp, "враги сзади и далеко не задеты")
	t.check(not p.try_attack(aim_right) and is_equal_approx(front.hp, hp0 - 12.0), "пока не прошла перезарядка, второй удар невозможен")
	for _i in 40:
		p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(p.try_attack(aim_right) and is_equal_approx(front.hp, hp0 - 24.0), "после перезарядки бьёт снова")

	for _i in 40:
		p.physics_step(1.0 / 60.0, 0.0, false)
	front.hp = 5.0
	front.position = Vector2(102 * TILE, 40 * TILE - front.size.y)
	p.try_attack(aim_right)
	t.check(combat.kills == 1 and not combat.enemies.has(front), "добитый враг исчезает и засчитывается")
	t.check(p.item_count("scrap") == 2, "с врага выпала добыча")
	for e in combat.enemies.duplicate():
		e.free()
	combat.free()
	p.free()


func _test_gun(t) -> void:
	var world := _flat_world()
	var p := _player(world, 100)
	p.invuln = 1000.0
	var clock := DayClock.new()
	var combat := EnemyManager.new()
	combat.setup(world, p, clock)
	combat.day_spawns = false
	p.inv.add("pistol", 1)
	var aim := Vector2(p.center().x + 300.0, p.center().y)
	t.check(not p.try_attack(aim), "без патронов пистолет не стреляет")
	p.inv.add("bullet", 3)
	var target := combat.spawn_enemy(_walker(), 110)
	target.speed = 0.0
	t.check(p.try_attack(aim) and combat.projectiles.size() == 1 and p.item_count("bullet") == 2, "выстрел создаёт пулю и тратит патрон")
	for _i in 60:
		combat.update(1.0 / 60.0)
	t.check(combat.projectiles.is_empty() and is_equal_approx(target.hp, target.max_hp - 14.0), "пуля попала во врага (14 урона)")

	for _i in 30:
		p.physics_step(1.0 / 60.0, 0.0, false)
	world.fg[39 * world.width + 105] = BlockDB.STONE
	world.fg[38 * world.width + 105] = BlockDB.STONE
	var hp_before := target.hp
	p.try_attack(Vector2(p.center().x + 300.0, 39 * TILE + 8.0))
	for _i in 60:
		combat.update(1.0 / 60.0)
	t.check(combat.projectiles.is_empty() and target.hp == hp_before, "стена останавливает пулю")
	t.check(p.item_count("bullet") == 1, "второй патрон потрачен")
	for e in combat.enemies.duplicate():
		e.free()
	combat.free()
	p.free()


func _make_night_setup(world: WorldData, tile_x: int) -> Array:
	var p := _player(world, tile_x)
	p.max_hp = 1.0e9
	p.hp = 1.0e9
	var clock := DayClock.new()
	var combat := EnemyManager.new()
	combat.setup(world, p, clock)
	combat.day_spawns = false
	return [p, clock, combat]


func _test_waves(t) -> void:
	t.check(EnemyManager.wave_size(5) > EnemyManager.wave_size(1), "с каждой ночью волна больше")
	t.check(EnemyManager.wave_size(100) <= 45, "размер волны ограничен")
	var world := _flat_world(400, 64, 40)
	var s := _make_night_setup(world, 200)
	var p: Player = s[0]
	var clock: DayClock = s[1]
	var combat: EnemyManager = s[2]
	clock.time = 0.60
	for _i in 22:
		clock.advance(0.5)
	t.check(clock.is_night() and combat.wave_budget == EnemyManager.wave_size(1), "с наступлением ночи объявлена волна")

	var seen := {}
	var min_dist := 1.0e9
	var all_walkers := true
	var inside_blocks := false
	var peak := 0
	var closest := 1.0e9
	for _i in 900:
		clock.advance(0.1)
		combat.update(0.1)
		p.physics_step(0.1, 0.0, false)
		peak = maxi(peak, combat.enemies.size())
		for e in combat.enemies:
			if not seen.has(e):
				seen[e] = true
				min_dist = minf(min_dist, absf(e.center().x - p.center().x))
				if e.def["name"] != "zombie_walker":
					all_walkers = false
				if TileCollider.collides(world, e.position, e.size):
					inside_blocks = true
			closest = minf(closest, e.center().distance_to(p.center()))
	t.check(seen.size() >= 6, "за ночь появилось %d врагов" % seen.size())
	t.check(peak <= EnemyManager.max_alive(1), "одновременно не больше %d (было %d)" % [EnemyManager.max_alive(1), peak])
	t.check(min_dist >= 27.0 * TILE, "враги появляются за краем экрана (%.0f px)" % min_dist)
	t.check(not inside_blocks, "никто не появляется внутри блоков")
	t.check(all_walkers, "в первую ночь только ходоки")
	t.check(closest < 40.0, "орда дошла до игрока")

	clock.time = 0.935
	clock.advance(5.0)
	t.check(not clock.is_night() and combat.enemies.is_empty() and combat.wave_budget == 0, "на рассвете орда исчезает")
	for e in combat.enemies.duplicate():
		e.free()
	combat.free()
	p.free()


func _test_horde_defeat(t) -> void:
	# Игрок с железным мечом на ровном месте одолевает ходячую орду первой ночи.
	var world := _flat_world(400, 64, 40)
	var s := _make_night_setup(world, 200)
	var p: Player = s[0]
	var clock: DayClock = s[1]
	var combat: EnemyManager = s[2]
	p.max_hp = 100.0
	p.hp = 100.0
	p.inv.add("iron_sword", 1)
	clock.time = 0.60
	for _i in 22:
		clock.advance(0.5)
	var died := [false]
	p.died.connect(func() -> void: died[0] = true)
	for _i in 6000:
		clock.advance(0.05)
		combat.update(0.05)
		# Бот: бьёт в сторону ближайшего врага.
		var nearest: Enemy = null
		var best := 1.0e9
		for e in combat.enemies:
			var d := absf(e.center().x - p.center().x)
			if d < best:
				best = d
				nearest = e
		p.physics_step(0.05, 0.0, false)
		if nearest != null and best < 70.0:
			p.try_attack(nearest.center())
		if not clock.is_night() or (combat.wave_budget == 0 and combat.enemies.is_empty()):
			break
	t.check(combat.kills >= EnemyManager.wave_size(1) - 1, "орда первой ночи побеждена: убито %d из %d" % [combat.kills, EnemyManager.wave_size(1)])
	t.check(not died[0], "игрок с мечом пережил ночь (здоровье %.0f, убито %d)" % [p.hp, combat.kills])

	# Без оружия та же ночь опасна: герой погибает.
	var s2 := _make_night_setup(world, 200)
	var q: Player = s2[0]
	var clock2: DayClock = s2[1]
	var combat2: EnemyManager = s2[2]
	q.max_hp = 100.0
	q.hp = 100.0
	var q_died := [false]
	q.died.connect(func() -> void: q_died[0] = true)
	clock2.time = 0.60
	for _i in 22:
		clock2.advance(0.5)
	for _i in 4000:
		clock2.advance(0.05)
		combat2.update(0.05)
		q.physics_step(0.05, 0.0, false)
		if q_died[0]:
			break
	t.check(q_died[0], "безоружного героя орда убивает")
	for c in [combat, combat2]:
		for e in c.enemies.duplicate():
			e.free()
		c.free()
	p.free()
	q.free()


func _test_main_scene(t) -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main.world_width = 256
	main.world_height = 160
	t.root.add_child(main)
	for _i in 60:
		await t.process_frame
		if main.ready_done:
			break
	t.check(main.ready_done and main.enemies != null and main.clock != null, "главная сцена содержит врагов и часы")
	if main.ready_done:
		main.enemies.day_spawns = false
		main.clock.time = 0.8
		await t.process_frame
		await t.process_frame
		t.check(main.tint.color.r < 0.9, "ночью картинка затемняется")
		t.check(main.hud.hp_bar.value == main.player.max_hp, "полоска здоровья показывает полное здоровье")
		t.check(main.hud.label.text.contains("День"), "в интерфейсе виден день и время")
	main.queue_free()
	await t.process_frame
