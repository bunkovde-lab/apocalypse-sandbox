extends RefCounted
## Этап 6: первый срез. Критерий из ТЗ: можно пройти от старта до второго босса.

const TILE := 16
var big: WorldData


func run(t) -> void:
	Progress.reset()
	_test_world(t)
	_test_walk_in(t)
	_test_loot_and_items(t)
	_test_enemy_pick(t)
	_test_raider_shooting(t)
	_test_clock_warning(t)
	_test_chief(t)
	_test_queen(t)
	_test_boss_reset(t)
	_test_camp(t)
	_test_recipes_unlock(t)
	_test_playthrough_sim(t)
	await _test_main_scene(t)
	Progress.reset()


func _flat_world(w: int = 240, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	return world


class Rig:
	var world: WorldData
	var p: Player
	var em: EnemyManager
	var bm: BossManager
	var clock := DayClock.new()

	func step(dt: float = 1.0 / 60.0, move: float = 0.0) -> void:
		p.physics_step(dt, move, false)
		em.update(dt)
		bm.update(dt)

	func free_all() -> void:
		bm.free()
		em.free()
		p.free()


func _rig(hero_x: int = 100) -> Rig:
	EnemyDB.ensure_loaded()
	var r := Rig.new()
	r.world = _flat_world()
	r.p = Player.new()
	r.p.world = r.world
	r.p.position = Vector2(hero_x * TILE, 38 * TILE)
	for _i in 30:
		r.p.physics_step(1.0 / 60.0, 0.0, false)
	r.p.spawn_pos = Vector2(10 * TILE, 38 * TILE)
	r.em = EnemyManager.new()
	r.em.world = r.world
	r.em.player = r.p
	r.em.clock = r.clock
	r.em.day_spawns = false
	r.em.rng.seed = 5
	r.p.combat = r.em
	r.bm = BossManager.new()
	r.bm.setup(r.world, r.p, r.em)
	return r


func _altar(r: Rig, block: int) -> Vector2i:
	var t := Vector2i(r.p.tile_pos().x + 2, 39)
	r.world.set_block(t.x, t.y, block)
	return t


func _test_world(t) -> void:
	var t0 := Time.get_ticks_msec()
	big = WorldGen.generate(20261025, 4200, 1200)
	t.check(Time.get_ticks_msec() - t0 < 10000, "мир с постройками создаётся быстрее 10 с (%d мс)" % (Time.get_ticks_msec() - t0))
	var types := {}
	var ruins := 0
	for s in big.structures:
		types[s["type"]] = true
		if s["type"] == "ruin":
			ruins += 1
	t.check(types.has("arena_raider") and types.has("arena_hive") and types.has("camp") and types.has("bunker"), "арены, лагерь и бункер созданы")
	t.check(ruins >= 8, "в руинах не меньше 8 зданий (%d)" % ruins)
	var biomes_ok := true
	for s in big.structures:
		if not s.has("rect") or s["type"] in ["arena_mine", "arena_nest"]:
			continue
		var r: Rect2i = s["rect"]
		var b := big.biome[r.position.x + r.size.x / 2]
		match s["type"]:
			"arena_raider", "ruin":
				biomes_ok = biomes_ok and b == WorldGen.BIOME_RUINS
			"arena_hive":
				biomes_ok = biomes_ok and b == WorldGen.BIOME_SWAMP
			"arena_wasteland":
				biomes_ok = biomes_ok and b == WorldGen.BIOME_WASTELAND
			"camp", "bunker":
				biomes_ok = biomes_ok and b == WorldGen.BIOME_RAIDERS
	t.check(biomes_ok, "каждая постройка в своём биоме")
	for s in big.structures:
		if s["type"] == "arena_raider":
			var a: Vector2i = s["altar"]
			t.check(big.get_block(a.x, a.y) == BlockDB.ALTAR_RAIDER and big.is_solid(a.x, a.y + 1), "алтарь Главаря стоит на твёрдом")
			var flat := true
			for x in range(a.x - 25, a.x + 26):
				if big.surface[x] != a.y + 2:
					flat = false
			t.check(flat, "арена Главаря плоская")
			t.check(absi(a.x - big.spawn_tile.x) > 150, "арена далеко от старта (%d блоков)" % absi(a.x - big.spawn_tile.x))
		elif s["type"] == "arena_hive":
			var a: Vector2i = s["altar"]
			t.check(big.get_block(a.x, a.y) == BlockDB.ALTAR_HIVE and big.is_solid(a.x, a.y + 1), "алтарь Королевы стоит на твёрдом")
			t.check(a.y > big.surface[a.x] + 25, "гнездо глубоко под землёй (%d блоков)" % (a.y - big.surface[a.x]))
	var near_spawn := true
	for x in range(big.spawn_tile.x - 24, big.spawn_tile.x + 25):
		var above := big.get_block(x, big.surface[x] - 1)
		if above == BlockDB.CONCRETE or above == BlockDB.LOOT:
			near_spawn = false
	t.check(near_spawn, "стартовая поляна свободна от построек")
	var crates := 0
	var consistent := true
	for pos in big.tombstones:
		if big.get_block(pos.x, pos.y) == BlockDB.LOOT:
			crates += 1
		else:
			consistent = false
	t.check(crates >= 15 and consistent, "ящиков с припасами %d, каждый на своём месте" % crates)
	var det := WorldGen.generate(20261025, 4200, 1200)
	t.check(det.checksum() == big.checksum() and det.structures.size() == big.structures.size(), "генерация с постройками детерминирована")


func _walk_from(world: WorldData, entry: Vector2i, target_x: int) -> Vector2:
	var p := Player.new()
	p.world = world
	p.position = Vector2(entry.x * TILE, (entry.y - 3) * TILE)
	for _i in 60 * 70:
		p.physics_step(1.0 / 60.0, 1.0, false)
		if p.position.x / TILE >= target_x:
			break
	var pos := p.position
	p.free()
	return pos


func _test_walk_in(t) -> void:
	for s in big.structures:
		if s["type"] == "arena_hive" or s["type"] == "bunker":
			var rect: Rect2i = s["rect"]
			var entry: Vector2i = s["entry"]
			var pos := _walk_from(big, entry, rect.position.x + 6)
			var inside := pos.x / TILE >= rect.position.x + 5 and pos.y / TILE > rect.position.y
			t.check(inside, "пешком по лестнице можно дойти в «%s» (x %.0f, y %.0f)" % [s["type"], pos.x / TILE, pos.y / TILE])
	# обратный путь: из камеры гнезда выбраться наверх по ступеням
	for s in big.structures:
		if s["type"] == "arena_hive":
			var entry: Vector2i = s["entry"]
			var rect: Rect2i = s["rect"]
			var p := Player.new()
			p.world = big
			p.position = Vector2((rect.position.x + 4) * TILE, (s["floor"] - 3) * TILE)
			for _i in 60 * 80:
				p.physics_step(1.0 / 60.0, -1.0, false)
			t.check(p.position.x / TILE <= entry.x + 4 and p.position.y / TILE < big.surface[entry.x] + 3, "из гнезда можно выйти по лестнице обратно (x %.0f, y %.0f)" % [p.position.x / TILE, p.position.y / TILE])
			p.free()


func _test_loot_and_items(t) -> void:
	var r := _rig()
	r.world.set_block(102, 39, BlockDB.LOOT)
	r.world.tombstones[Vector2i(102, 39)] = {"medkit": 2, "scrap": 5}
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	var done := false
	for _i in 60:
		if r.p.mine_tick(Vector2i(102, 39), 1.0 / 30.0):
			done = true
			break
	t.check(done and r.p.inv.count("medkit") == 2 and r.p.inv.count("scrap") == 5, "ящик с припасами отдаёт содержимое")
	t.check(r.world.get_block(102, 39) == BlockDB.AIR and not r.world.tombstones.has(Vector2i(102, 39)), "пустой ящик исчезает")
	# алтарь неразрушим
	r.world.set_block(103, 39, BlockDB.ALTAR_RAIDER)
	var broke := false
	for _i in 300:
		if r.p.mine_tick(Vector2i(103, 39), 0.1):
			broke = true
	t.check(not broke and r.world.get_block(103, 39) == BlockDB.ALTAR_RAIDER, "алтарь нельзя сломать")
	# аптечка
	r.p.hp = 30.0
	r.p.attack_cd = 0.0
	t.check(r.p.use_item("medkit") and is_equal_approx(r.p.hp, 80.0) and r.p.inv.count("medkit") == 1, "аптечка лечит на 50")
	r.p.attack_cd = 0.0
	r.p.hp = 100.0
	t.check(not r.p.use_item("medkit") and r.p.inv.count("medkit") == 1, "при полном здоровье аптечка не тратится")
	r.p.hp = 40.0
	r.p.attack_cd = 0.0
	r.p.selected = 0
	r.p.inv.items[0] = "medkit"
	r.p.inv.counts[0] = 3
	t.check(r.p.place_selected(Vector2i(101, 38)) and r.p.hp == 90.0, "ПКМ с аптечкой в руке лечит")
	r.free_all()


func _test_enemy_pick(t) -> void:
	EnemyDB.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bad := false
	var spores := 0
	for _i in 400:
		var d := EnemyDB.pick(5, rng, -1)
		if d.has("boss") or d["name"] == "raider" or d["name"] == "spore_crawler":
			bad = true
	for _i in 400:
		var d := EnemyDB.pick(1, rng, WorldGen.BIOME_SWAMP)
		if d["name"] == "spore_crawler":
			spores += 1
		if d.has("boss") or d["name"] == "raider":
			bad = true
	t.check(not bad, "боссы и мародёры не попадают в обычные волны")
	t.check(spores > 100, "в болотах заметная доля споровиков (%d из 400)" % spores)


func _test_raider_shooting(t) -> void:
	var r := _rig(100)
	var def: Dictionary = EnemyDB.defs["raider"]
	var e := r.em.spawn_at(def, Vector2(112 * TILE, 0), 1, 40.0 * TILE)
	e.shoot_timer = 0.0
	var hp0 := r.p.hp
	for _i in 60 * 6:
		r.step()
	t.check(r.p.hp < hp0, "мародёр стреляет и попадает с дистанции (%.0f урона)" % (hp0 - r.p.hp))
	t.check(absf(e.center().x - r.p.center().x) >= e.keep_dist * 0.8, "мародёр держит дистанцию (%.0f px)" % absf(e.center().x - r.p.center().x))
	# стена закрывает линию огня
	var r2 := _rig(100)
	for y in range(30, 40):
		r2.world.set_block(106, y, BlockDB.REINFORCED)
	var e2 := r2.em.spawn_at(def, Vector2(112 * TILE, 0), 1, 40.0 * TILE)
	e2.shoot_timer = 0.0
	var shots := 0
	for _i in 60 * 4:
		r2.p.hp = 100.0
		r2.step()
		for pr in r2.em.projectiles:
			if pr.hostile:
				shots += 1
	t.check(shots == 0, "за стеной мародёр не стреляет")
	r.free_all()
	r2.free_all()


func _test_clock_warning(t) -> void:
	var c := DayClock.new()
	var warns := [0]
	var nights := [0]
	c.night_warning.connect(func() -> void: warns[0] += 1)
	c.night_started.connect(func(_n: int) -> void: nights[0] += 1)
	var before_night := 0
	var seq := ""
	for _i in 60 * 480:
		var was := c.is_night()
		c.advance(1.0 / 60.0 * 1.0)
		if warns[0] > 0 and nights[0] == 0:
			seq = "warning_first"
		if not was and c.is_night() and before_night == 0:
			before_night = warns[0]
		if c.day > 1:
			break
	t.check(warns[0] == 1 and nights[0] == 1 and before_night == 1, "предупреждение о ночи приходит один раз и до сумерек")


func _test_chief(t) -> void:
	var r := _rig(100)
	var altar := _altar(r, BlockDB.ALTAR_RAIDER)
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	t.check("Нужен предмет" in r.bm.interact(altar, r.p) and not r.bm.is_active(), "без маяка босс не вызывается")
	r.p.inv.add("raider_beacon", 1)
	var msg := r.bm.interact(altar, r.p)
	t.check(r.bm.is_active() and r.p.inv.count("raider_beacon") == 0, "маяк тратится, Главарь появляется: " + msg)
	var boss: Boss = r.bm.boss
	t.check(boss.max_hp == 520.0 and boss.phase == 1, "Главарь: 520 HP, фаза 1")
	var again := r.bm.interact(altar, r.p)
	t.check("Босс уже здесь" in again, "второго босса не вызвать: " + again)
	var got := []
	r.bm.boss_changed.connect(func(n: String, hp: float, mx: float) -> void: got.append([n, hp, mx]))
	for _i in 30:
		r.step()
	t.check(got.size() > 0 and got.back()[0] == "Главарь мародёров", "полоска босса получает данные")
	# фаза 2
	boss.hp = boss.max_hp * 0.55
	for _i in 10:
		boss.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	t.check(boss.phase == 2 and boss.keep_dist > 100.0 and boss.retreat, "≤60% HP: фаза 2, держит дистанцию и отходит")
	r.p.hp = 100.0
	for _i in 120:
		r.step()
		r.p.hp = 100.0
	t.check(boss.minions.size() == 2, "в фазе 2 зовёт двух мародёров (%d)" % boss.minions.size())
	for _i in 60 * 40:
		r.step()
		r.p.hp = 100.0
	t.check(boss.minions.size() <= 4, "помощников не больше 4 (%d)" % boss.minions.size())
	# фаза 3
	boss.hp = boss.max_hp * 0.2
	boss.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	t.check(boss.phase == 3 and boss.speed > float(boss.def["speed"]) * 1.4, "≤25% HP: фаза 3, быстрее ×1.5")
	# смерть: награда, прогресс, помощники гибнут
	var msgs := []
	r.bm.message.connect(func(m: String) -> void: msgs.append(m))
	boss.take_damage(9999.0, 1)
	t.check(not r.bm.is_active() and Progress.has("boss_1"), "победа записана в прогресс")
	t.check(r.p.inv.count("iron_bar") >= 10 and r.p.inv.count("bullet") >= 20 and r.p.inv.count("medkit") >= 2, "награда в инвентаре")
	var alive := 0
	for e in r.em.enemies:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	t.check(alive == 0, "помощники погибли вместе с Главарём")
	t.check(msgs.size() == 1 and "армированный бетон" in msgs[0], "сообщение о победе и открытом рецепте")
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	var msg_again := r.bm.interact(altar, r.p)
	t.check("уже всё кончено" in msg_again, "повторно босса не вызвать: «%s» hero %s hp %.0f" % [msg_again, r.p.position, r.p.hp])
	r.free_all()


func _test_queen(t) -> void:
	var r := _rig(100)
	var altar := _altar(r, BlockDB.ALTAR_HIVE)
	r.p.inv.add("spore_lure", 1)
	r.bm.interact(altar, r.p)
	var q: Boss = r.bm.boss
	t.check(q != null and q.boss_id == 2 and q.max_hp == 700.0, "Королева-матка вызвана: 700 HP")
	t.check(not q.laying, "начинает в защитной фазе")
	var hp0 := q.hp
	q.take_damage(100.0, 1)
	t.check(is_equal_approx(hp0 - q.hp, 25.0), "броня: урон ×0.25 (получила %.0f из 100)" % (hp0 - q.hp))
	# цикл: защита 14 с, затем откладка яиц 6 с
	for _i in int(14.2 * 60):
		r.step()
		r.p.hp = 100.0
	t.check(q.laying, "через 14 с — фаза откладки яиц")
	var hp1 := q.hp
	q.take_damage(100.0, 1)
	t.check(is_equal_approx(hp1 - q.hp, 150.0), "в фазу откладки урон ×1.5 (%.0f из 100)" % (hp1 - q.hp))
	t.check(q.minions.size() >= 3, "в начале откладки вылупились споровики (%d)" % q.minions.size())
	t.check(q.speed == 0.0, "во время откладки стоит на месте")
	for _i in int(6.3 * 60):
		r.step()
		r.p.hp = 100.0
	t.check(not q.laying, "через 6 с снова броня")
	# плевок кислотой
	r.p.position = q.position - Vector2(150, 0)
	var spits := 0
	for _i in 60 * 6:
		r.step()
		r.p.hp = 100.0
		for pr in r.em.projectiles:
			if pr.hostile:
				spits += 1
	t.check(spits > 0, "защитная королева плюётся кислотой: spits %d laying %s dist %.0f hp %.0f cd %.2f" % [spits, q.laying, q.center().distance_to(r.p.center()), r.p.hp, q.spit_timer])
	# ярость на 50%
	q.hp = q.max_hp * 0.45
	q.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	t.check(q.speed > float(q.def["speed"]), "≤50% HP: быстрее")
	q.take_damage(99999.0, 1)
	t.check(Progress.has("boss_2") and r.p.inv.count("biomass") >= 12 and Progress.stage() == 3, "победа: биомасса, прогресс, этап 3")
	r.free_all()
	Progress.reset()


func _test_boss_reset(t) -> void:
	var r := _rig(100)
	var altar := _altar(r, BlockDB.ALTAR_RAIDER)
	r.p.inv.add("raider_beacon", 1)
	r.bm.interact(altar, r.p)
	t.check(r.bm.is_active(), "босс вызван")
	r.p.hp = 1.0
	r.p.invuln = 0.0
	r.p.take_damage(50.0, 0.0)
	t.check(not r.bm.is_active() and r.p.inv.count("raider_beacon") >= 1, "герой погиб: босс отступил, маяк возвращён")
	var n := 0
	for e in r.em.enemies:
		if is_instance_valid(e) and not e.dead:
			n += 1
	t.check(n == 0 and not Progress.has("boss_1"), "после сброса на арене чисто, прогресса нет")
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	r.bm.interact(altar, r.p)
	t.check(r.bm.is_active(), "бой можно начать заново")
	r.p.position = Vector2(200 * TILE, 38 * TILE)
	r.bm.boss.position = Vector2(5 * TILE, 38 * TILE)
	r.bm.update(0.1)
	t.check(not r.bm.is_active(), "игрок ушёл далеко: бой сброшен")
	r.free_all()


func _test_camp(t) -> void:
	var camp: Dictionary = {}
	for s in big.structures:
		if s["type"] == "camp":
			camp = s
	var r := _rig(100)
	r.world.structures = [camp.duplicate(true)]
	r.world.structures[0]["spawns"] = [Vector2i(104, 40), Vector2i(106, 40), Vector2i(108, 40)]
	r.world.structures[0]["rect"] = Rect2i(95, 31, 20, 10)
	var cm := CampManager.new()
	cm.setup(r.world, r.p, r.em, r.clock)
	cm.update(0.1)
	t.check(r.em.enemies.size() == 3, "рядом с лагерем появилась охрана (%d)" % r.em.enemies.size())
	cm.update(0.1)
	t.check(r.em.enemies.size() == 3, "повторно в тот же момент не спавнится")
	for e in r.em.enemies.duplicate():
		e.take_damage(9999.0, 1)
	cm.update(0.1)
	t.check(r.em.enemies.is_empty(), "перебитая охрана не возвращается в тот же день")
	r.clock.day += 1
	cm.update(0.1)
	t.check(r.em.enemies.size() == 3, "на следующий день охрана вернулась")
	for e in r.em.enemies.duplicate():
		e.free()
	r.em.enemies.clear()
	# далеко от лагеря охрана не появляется
	var r2 := _rig(100)
	r2.world.structures = [{"type": "camp", "rect": Rect2i(5000, 10, 20, 10), "spawns": [Vector2i(5004, 40)]}]
	var cm2 := CampManager.new()
	cm2.setup(r2.world, r2.p, r2.em, r2.clock)
	cm2.update(0.1)
	t.check(r2.em.enemies.is_empty(), "издалека лагерь спит")
	cm.free()
	cm2.free()
	r.free_all()
	r2.free_all()


func _test_recipes_unlock(t) -> void:
	Progress.reset()
	RecipeDB.ensure_loaded()
	var inv := Inventory.new()
	inv.add("concrete", 4)
	inv.add("iron_bar", 8)
	inv.add("scrap", 6)
	inv.add("copper_bar", 4)
	inv.add("biomass", 4)
	var st := {"forge": true, "workbench": true}
	var rc: Dictionary = {}
	var rp: Dictionary = {}
	for r in RecipeDB.recipes:
		if r["result"] == "reinforced_concrete":
			rc = r
		if r["result"] == "purifier2":
			rp = r
	t.check(not RecipeDB.is_craftable(inv, st, rc), "армированный бетон закрыт до победы над Главарём")
	t.check(not RecipeDB.is_craftable(inv, st, rp), "фильтр-очиститель закрыт до победы над Королевой")
	Progress.unlock("boss_1")
	t.check(RecipeDB.craft(inv, st, rc) and inv.count("reinforced_concrete") == 2, "после победы бетон крафтится")
	t.check(not RecipeDB.is_craftable(inv, st, rp), "второй рецепт всё ещё закрыт")
	Progress.unlock("boss_2")
	t.check(RecipeDB.craft(inv, st, rp) and inv.count("purifier2") == 1, "после второго босса крафтится фильтр")
	t.check(Progress.stage() == 3, "прогресс: этап 3")
	# армированный бетон держит даже толстяка
	var world := _flat_world()
	for y in range(34, 40):
		world.set_block(50, y, BlockDB.REINFORCED)
	EnemyDB.ensure_loaded()
	var fat := Enemy.new()
	fat.setup((EnemyDB.defs["zombie_fat"] as Dictionary).duplicate(true), world, 1)
	fat.position = Vector2(40 * TILE, 40 * TILE - fat.size.y)
	var tgt := Rect2(Vector2(60 * TILE, 38 * TILE), Player.SIZE)
	for _i in 60 * 40:
		fat.update(1.0 / 60.0, tgt, true)
	var intact := true
	for y in range(34, 40):
		if world.get_block(50, y) != BlockDB.REINFORCED:
			intact = false
	t.check(intact, "армированный бетон толстяк не ломает")
	fat.free()
	Progress.reset()


## Сквозной прогон: герой с добычей крафтит снаряжение, вызывает Главаря, побеждает, потом Королеву.
func _test_playthrough_sim(t) -> void:
	Progress.reset()
	var r := _rig(100)
	var inv := r.p.inv
	# добыча первой ночи и ящиков (как если бы мы её накопали)
	var haul := {"wood": 40, "stone": 30, "scrap": 30, "iron_ore": 60, "copper_ore": 30, "coal": 50, "mud": 14}
	for item in haul:
		inv.add(item, haul[item])
	RecipeDB.ensure_loaded()
	var st := {"workbench": true, "forge": true}
	var order := []
	for _i in 18:
		order.append("iron_bar")
	for _i in 9:
		order.append("copper_bar")
	order += ["iron_sword", "pistol", "bullet", "bullet", "bullet",
		"medkit", "medkit", "medkit", "medkit", "medkit", "medkit", "raider_beacon", "spore_lure"]
	var crafted := true
	for name in order:
		var done := false
		for rec in RecipeDB.recipes:
			if rec["result"] == name and RecipeDB.craft(inv, st, rec):
				done = true
				break
		if not done:
			crafted = false
			printerr("   не скрафтилось: ", name)
	t.check(crafted, "всё снаряжение и обе приманки крафтятся из добытого")
	t.check(inv.count("iron_sword") == 1 and inv.count("pistol") == 1 and inv.count("medkit") >= 6, "в рюкзаке меч, пистолет и аптечки")
	r.p.selected = inv.items.find("iron_sword") if inv.items.find("iron_sword") < 10 else 0
	var sword_slot := inv.items.find("iron_sword")
	var gun_slot := inv.items.find("pistol")
	# --- бой с Главарём ---
	var altar := _altar(r, BlockDB.ALTAR_RAIDER)
	r.bm.interact(altar, r.p)
	var res1 := _fight(r, sword_slot, gun_slot, 150.0, "boss_1")
	t.check(res1["won"], "герой побеждает Главаря за %.0f с (осталось HP %.0f, аптечек потрачено %d)" % [res1["time"], r.p.hp, res1["medkits"]])
	t.check(Progress.has("boss_1"), "после боя открыт этап 2")
	# восстановить силы и пополнить аптечки, как после отдыха на базе
	r.p.hp = r.p.max_hp
	inv.add("medkit", 4)
	# --- бой с Королевой ---
	for e in r.em.enemies.duplicate():
		r.em._remove(e)
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	var altar2 := Vector2i(r.p.tile_pos().x + 2, 39)
	r.world.set_block(altar2.x, altar2.y, BlockDB.ALTAR_HIVE)
	t.check(r.bm.interact(altar2, r.p) != "", "Королева вызвана алтарём улья")
	var res2 := _fight(r, sword_slot, gun_slot, 300.0, "boss_2")
	t.check(res2["won"], "герой побеждает Королеву за %.0f с (осталось HP %.0f, аптечек потрачено %d)" % [res2["time"], r.p.hp, res2["medkits"]])
	t.check(Progress.has("boss_2") and Progress.stage() == 3, "пройдено от старта до второго босса")
	r.free_all()

	# без снаряжения Главаря не победить
	Progress.reset()
	var r2 := _rig(100)
	var altar3 := _altar(r2, BlockDB.ALTAR_RAIDER)
	r2.p.inv.add("raider_beacon", 1)
	r2.bm.interact(altar3, r2.p)
	var lost := false
	for _i in 60 * 120:
		r2.step()
		_bot_act(r2, -1, -1)
		if r2.p.deaths > 0:
			lost = true
			break
	t.check(lost and not Progress.has("boss_1"), "безоружный герой Главарю проигрывает")
	r2.free_all()
	Progress.reset()


func _bot_act(r: Rig, sword_slot: int, gun_slot: int) -> void:
	var boss: Boss = r.bm.boss
	if boss == null or not is_instance_valid(boss):
		return
	# цель — ближайший живой враг
	var target: Enemy = boss
	var best := 1e9
	for e in r.em.enemies:
		if is_instance_valid(e) and not e.dead:
			var d := e.center().distance_to(r.p.center())
			if d < best:
				best = d
				target = e
	var to := target.center() - r.p.center()
	if r.p.hp < 45.0 and r.p.inv.count("medkit") > 0:
		r.p.selected = r.p.inv.items.find("medkit")
		r.p.use_item("medkit")
	if sword_slot < 0:
		return
	if absf(to.x) < 52.0:
		r.p.selected = sword_slot
		r.p.try_attack(target.center())
	elif absf(to.x) < 260.0 and r.p.inv.count("bullet") > 0:
		r.p.selected = gun_slot
		r.p.try_attack(target.center())


func _fight(r: Rig, sword_slot: int, gun_slot: int, limit: float, flag: String) -> Dictionary:
	var medkits0 := r.p.inv.count("medkit")
	var time := 0.0
	var dt := 1.0 / 60.0
	while time < limit and r.bm.is_active() and r.p.deaths == 0:
		var boss: Boss = r.bm.boss
		var to := boss.center().x - r.p.center().x
		var move := 0.0
		# сближаемся, пока не в зоне меча; не стоим вплотную к стрелкам
		if absf(to) > 46.0:
			move = signf(to)
		r.step(dt, move)
		_bot_act(r, sword_slot, gun_slot)
		time += dt
	return {"won": Progress.has(flag) and r.p.deaths == 0, "time": time, "medkits": medkits0 - r.p.inv.count("medkit")}


func _test_main_scene(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 2200
	main.world_height = 420
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 900:
		await t.process_frame
		guard += 1
	t.check(main.ready_done, "сцена со стадией 6 запускается")
	t.check(main.bosses != null and main.camps != null and main.player.bosses == main.bosses, "менеджеры боссов и лагерей подключены")
	var arena := false
	for s in main.world.structures:
		if s["type"] == "arena_raider":
			arena = true
	t.check(arena, "в мире сцены есть арена Главаря")
	main.player.inv.add("raider_beacon", 1)
	for s in main.world.structures:
		if s["type"] == "arena_raider":
			var a: Vector2i = s["altar"]
			main.player.position = Vector2((a.x - 2) * 16, (a.y - 1) * 16)
			t.check(main.bosses.interact(a, main.player) != "" and main.bosses.is_active(), "алтарь в сцене вызывает босса")
	await t.process_frame
	await t.process_frame
	t.check(main.hud.boss_bar.visible and main.hud.boss_label.text == "Главарь мародёров", "полоска босса видна в HUD")
	main.queue_free()
	await t.process_frame
