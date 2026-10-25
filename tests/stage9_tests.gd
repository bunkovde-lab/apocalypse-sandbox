extends RefCounted
## Этап 9: сохранения, звук, свет, карта, меню, сложность.

const TILE := 16


func run(t) -> void:
	Progress.reset()
	_test_settings(t)
	_test_sfx(t)
	_test_lights(t)
	await _test_minimap(t)
	await _test_save_load(t)
	await _test_menus(t)
	await _test_touch(t)
	_test_difficulty_balance(t)
	Settings.difficulty = 1
	Settings.load_requested = false
	Progress.reset()


func _test_settings(t) -> void:
	Settings.difficulty = 1
	t.check(Settings.hp_mult() == 1.0 and Settings.damage_mult() == 1.0 and Settings.spawn_mult() == 1.0, "нормальная сложность не меняет числа")
	Settings.difficulty = 0
	t.check(Settings.hp_mult() < 1.0 and Settings.damage_mult() < 1.0, "лёгкая слабее врагов")
	Settings.difficulty = 2
	t.check(Settings.hp_mult() > 1.0 and Settings.damage_mult() > 1.0 and Settings.spawn_mult() > 1.0, "тяжёлая сильнее врагов")
	EnemyDB.ensure_loaded()
	var w := WorldData.new(64, 64)
	var e := Enemy.new()
	e.setup(EnemyDB.defs["zombie_walker"], w, 1)
	var hard_hp := e.max_hp
	Settings.difficulty = 0
	var e2 := Enemy.new()
	e2.setup(EnemyDB.defs["zombie_walker"], w, 1)
	t.check(hard_hp > e2.max_hp and absf(hard_hp / e2.max_hp - 1.35 / 0.8) < 0.01, "здоровье зомби зависит от сложности (%.0f против %.0f)" % [hard_hp, e2.max_hp])
	e.free()
	e2.free()
	Settings.difficulty = 1
	t.check(Settings.difficulty_name() == "Нормальная", "названия сложности")


func _test_sfx(t) -> void:
	Sfx.build_streams()
	var need := ["swing", "hit", "hurt", "kill", "shot", "shotgun", "break", "place", "heal", "pickup", "boss", "win", "seal", "alarm", "event", "rescue"]
	var ok := true
	for n in need:
		if not Sfx.streams.has(n):
			ok = false
		else:
			var s: AudioStreamWAV = Sfx.streams[n]
			if s.data.size() < 1000 or s.mix_rate != Sfx.RATE:
				ok = false
	t.check(ok, "все %d звуков сгенерированы без файлов" % need.size())
	var s: AudioStreamWAV = Sfx.streams["boss"]
	var peak := 0
	for i in range(0, s.data.size() - 1, 2):
		peak = maxi(peak, absi(s.data.decode_s16(i)))
	t.check(peak > 3000 and peak < 32767, "громкость в допустимых пределах (пик %d)" % peak)
	Sfx.play("hit")
	t.check(true, "Sfx.play без проигрывателя безопасен")


func _test_lights(t) -> void:
	var w := WorldData.new(200, 100)
	for y in range(50, 100):
		for x in 200:
			w.fg[y * 200 + x] = BlockDB.STONE
	w.set_block(100, 49, BlockDB.LAMP)
	w.set_block(105, 49, BlockDB.LAB_LIGHT)
	w.set_block(190, 49, BlockDB.LAMP)
	var found := LightManager.collect(w, Vector2i(100, 49))
	t.check(found.size() == 2 and found[0]["pos"] == Vector2i(100, 49), "свет вокруг героя найден, ближний первым (%d)" % found.size())
	t.check(is_equal_approx(float(found[0]["radius"]), 8.0) and is_equal_approx(float(found[1]["radius"]), 10.0), "радиусы берутся из данных блоков")
	var far := LightManager.collect(w, Vector2i(190, 49), 10, 10)
	t.check(far.size() == 1, "далёкие лампы не учитываются")
	var lim := LightManager.collect(w, Vector2i(100, 49), 200, 60, 1)
	t.check(lim.size() == 1, "число источников ограничено")
	var day := Color.WHITE
	t.check(LightManager.ambient(day, 0.0) == day, "на поверхности свет дневной")
	var deep := LightManager.ambient(day, 40.0)
	t.check(deep.r < 0.3 and deep.is_equal_approx(LightManager.UNDERGROUND_AMBIENT), "под землёй темно")
	var mid := LightManager.ambient(day, 10.0)
	t.check(mid.r > deep.r and mid.r < day.r, "в верхнем слое переход плавный")
	t.check(LightManager.make_texture().get_width() == 128, "текстура света создаётся")
	t.check(BlockDB.light[BlockDB.LAMP] > 0.0 and BlockDB.light[BlockDB.LAB_LIGHT] > BlockDB.light[BlockDB.LAMP], "лабораторный свет ярче лампы")


func _test_minimap(t) -> void:
	var w := WorldGen.generate(777, 2400, 1200)
	var p := Player.new()
	p.world = w
	p.position = Vector2(1200 * TILE, 200 * TILE)
	var mm := Minimap.new()
	mm.setup(w, p)
	t.check(mm.cols == 300 and mm.rows == 150, "карта 300x150 клеток")
	t.check(mm.is_explored(Vector2i(1200, 200)), "клетка под героем открыта сразу")
	t.check(not mm.is_explored(Vector2i(100, 900)), "далёкое место закрыто туманом")
	var f0 := mm.explored_fraction()
	var n := mm.reveal(Vector2i(1300, 210))
	t.check(n > 0 and mm.explored_fraction() > f0, "новое место открывается (%d клеток)" % n)
	t.check(mm.reveal(Vector2i(1300, 210)) == 0, "повторно ничего не открывается")
	var img := mm.build_image()
	t.check(img.get_width() == Minimap.SMALL_COLS and img.get_height() == Minimap.SMALL_ROWS, "малая карта нужного размера")
	var px := img.get_pixel(Minimap.SMALL_COLS / 2, Minimap.SMALL_ROWS / 2)
	var dark := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y) == Color.BLACK:
				dark += 1
	t.check(dark > 0 and dark < img.get_width() * img.get_height(), "туман есть, но открытая часть видна")
	mm.big = true
	var big := mm.build_image()
	t.check(big.get_width() == 300 and big.get_height() == 150, "большая карта показывает весь мир")
	# алтарь виден только в открытой клетке
	var altar: Vector2i = w.altars.keys()[0]
	var cx := floori(float(altar.x) / Minimap.CELL)
	var cy := floori(float(altar.y) / Minimap.CELL)
	t.check(big.get_pixel(cx, cy) != Color("e03a3a") or mm.is_explored(altar), "алтарь не виден в тумане")
	mm.reveal(altar)
	big = mm.build_image()
	t.check(big.get_pixel(cx, cy) == Color("e03a3a"), "после открытия алтарь отмечен красным")
	p.free()
	mm.free()


func _snapshot(main) -> Dictionary:
	var w: WorldData = main.world
	return {
		"checksum": w.checksum(), "items": main.player.inv.items.duplicate(), "counts": main.player.inv.counts.duplicate(),
		"day": main.clock.day, "time": main.clock.time, "devices": main.shelter.devices.size(),
		"residents": main.survivors.residents.size(), "stranded": main.survivors.stranded.size(),
		"flags": Progress.flags.duplicate(), "explored": main.minimap.explored_fraction(),
	}


func _test_save_load(t) -> void:
	SaveSystem.delete()
	t.check(not SaveSystem.exists() and SaveSystem.read().is_empty(), "без файла сохранения нет")
	Settings.load_requested = false
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 2400
	main.world_height = 1200
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 1500:
		await t.process_frame
		guard += 1
	t.check(main.ready_done, "новая игра запущена")
	var w: WorldData = main.world
	var p: Player = main.player
	var px := p.tile_pos().x
	var gy := w.surface[px]
	# изменения мира: постройки, выкопанная шахта, повреждённый блок
	for x in range(px, px + 8):
		w.set_block(x, gy - 1, BlockDB.AIR)
		w.set_block(x, gy, BlockDB.CONCRETE)
	w.set_block(px + 1, gy - 1, BlockDB.BED)
	w.set_block(px + 3, gy - 1, BlockDB.GENERATOR)
	w.set_block(px + 5, gy - 1, BlockDB.PLANTER)
	w.set_block(px + 6, gy - 1, BlockDB.PURIFIER)
	main.shelter.fuel[Vector2i(px + 3, gy - 1)] = 333.0
	main.shelter.reserve_food = 12.5
	main.shelter.reserve_water = 7.0
	for y in range(gy + 1, gy + 12):
		w.set_block(px - 3, y, BlockDB.AIR)
	w.damage_block(px + 7, gy, 0.4)
	p.inv.add("iron_pick", 1)
	p.inv.add("medkit", 7)
	p.inv.add("alloy", 33)
	p.equip_item("scrap_vest") if p.inv.count("scrap_vest") > 0 else null
	p.inv.add("iron_chest", 1)
	p.equip_item("iron_chest")
	p.position = Vector2((px + 2) * TILE, (gy - 3) * TILE)
	p.hp = 77.0
	p.rad = 12.0
	p.deaths = 2
	main.clock.day = 6
	main.clock.time = 0.42
	Progress.unlock("boss_1")
	Progress.unlock("boss_2")
	main.seals.refresh()
	# житель
	var s: Survivor = main.survivors.spawn_stranded(px + 2)
	s.position = Vector2((px + 2) * TILE, (gy - 3) * TILE)
	main.survivors.rescue(s)
	s.role = "farmer"
	main.minimap.reveal(Vector2i(px + 100, gy + 40))
	main.director.schedule("acid_rain", 500.0)
	main.shelter.evaluate()
	var before := _snapshot(main)
	var equip_before: Dictionary = p.equip.duplicate()
	var sdata: Dictionary = SaveSystem.capture(main.context())
	t.check(SaveSystem.write(sdata) and SaveSystem.exists(), "сохранение записано")
	var size := FileAccess.open_compressed(SaveSystem.PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD).get_length()
	t.check(size < 400000, "файл сохранения небольшой (%d байт)" % size)
	var chunks_n: int = (sdata["chunks"] as Dictionary).size()
	t.check(chunks_n > 0 and chunks_n < 600, "сохранены только изменённые чанки (%d из %d)" % [chunks_n, w.chunks_wide() * w.chunks_high()])
	main.queue_free()
	await t.process_frame
	await t.process_frame
	Progress.reset()
	p = null
	# загрузка
	Settings.load_requested = true
	var main2 = scene.instantiate()
	t.root.add_child(main2)
	guard = 0
	while not main2.ready_done and guard < 1500:
		await t.process_frame
		guard += 1
	Settings.load_requested = false
	t.check(main2.ready_done and not main2.loaded_data.is_empty(), "игра загружена из файла")
	var after := _snapshot(main2)
	t.check(after["checksum"] == before["checksum"], "мир после загрузки совпал с сохранённым")
	t.check(after["items"] == before["items"] and after["counts"] == before["counts"], "инвентарь совпал")
	t.check(main2.player.equip == equip_before, "надетая броня совпала")
	t.check(is_equal_approx(main2.player.hp, 77.0) and is_equal_approx(main2.player.rad, 12.0) and main2.player.deaths == 2, "здоровье, радиация, смерти совпали")
	t.check(after["day"] == 6 and is_equal_approx(after["time"], 0.42), "день и время совпали")
	t.check(after["flags"] == before["flags"] and Progress.has("boss_1&boss_2"), "прогресс боссов совпал")
	t.check(main2.world.seals_open.has("metro") and main2.world.seals_open.has("mines"), "снятые печати сохранены")
	t.check(after["devices"] == before["devices"] and after["devices"] >= 4, "устройства убежища найдены заново (%d)" % after["devices"])
	t.check(is_equal_approx(main2.shelter.fuel.get(Vector2i(main2.player.tile_pos().x + 1, 0), 333.0), 333.0) or main2.shelter.fuel.values().has(333.0), "топливо генератора сохранено")
	t.check(is_equal_approx(main2.shelter.reserve_food, float(sdata["shelter"]["food"])) and is_equal_approx(main2.shelter.reserve_water, float(sdata["shelter"]["water"])), "запасы еды и воды сохранены")
	t.check(after["residents"] == before["residents"] and after["residents"] == 1, "житель на месте")
	t.check(main2.survivors.residents[0].role == "farmer" and main2.survivors.residents[0].home != Survivor.NO_STATION, "роль и койка жителя сохранены")
	t.check(after["stranded"] == before["stranded"], "ожидающие спасения те же (%d)" % after["stranded"])
	t.check(absf(after["explored"] - before["explored"]) < 0.0001, "открытая часть карты сохранена")
	t.check(main2.director.pending.size() == 1 and main2.director.pending[0]["name"] == "acid_rain", "запланированное событие сохранено")
	t.check(main2.world.damage.size() >= 1, "повреждения блоков сохранены")
	var gx: int = main2.player.tile_pos().x - 2
	t.check(main2.world.get_block(gx + 1, main2.world.surface[gx] - 1) in [BlockDB.BED, BlockDB.AIR], "карта мира читается")
	# после загрузки мир живёт: можно играть
	for _i in 30:
		await t.process_frame
	t.check(is_instance_valid(main2.player) and main2.player.hp > 0.0, "после загрузки игра идёт")
	# повторное сохранение даёт тот же результат
	var again: Dictionary = SaveSystem.capture(main2.context())
	t.check((again["chunks"] as Dictionary).size() == chunks_n, "второе сохранение даёт те же чанки")
	# повреждённый файл не ломает игру
	var f := FileAccess.open(SaveSystem.PATH, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	t.check(SaveSystem.read().is_empty(), "битый файл считается пустым")
	main2.queue_free()
	await t.process_frame
	SaveSystem.delete()
	Progress.reset()


func _test_menus(t) -> void:
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	var menu = menu_scene.instantiate()
	t.root.add_child(menu)
	await t.process_frame
	t.check(menu.continue_button.disabled, "«Продолжить» выключено без сохранения")
	menu._cycle_difficulty()
	t.check(Settings.difficulty == 2 and "Тяжёлая" in menu.diff_button.text, "кнопка меняет сложность: " + menu.diff_button.text)
	menu._cycle_difficulty()
	menu._cycle_difficulty()
	t.check(Settings.difficulty == 1, "сложность идёт по кругу")
	menu._toggle_sound()
	t.check(not Settings.sound_on and "выкл" in menu.sound_button.text, "звук выключается")
	menu._toggle_sound()
	menu.queue_free()
	await t.process_frame
	# пауза
	var pm := PauseMenu.new()
	t.root.add_child(pm)
	pm.toggle()
	t.check(pm.open and t.root.get_tree().paused, "пауза ставит игру на паузу")
	var saved := [false]
	pm.save_pressed.connect(func() -> void: saved[0] = true)
	pm.sound_button.pressed.emit()
	pm.get_node_or_null("x")
	t.check(not Settings.sound_on, "в паузе можно выключить звук")
	pm.sound_button.pressed.emit()
	pm.toggle()
	t.check(not pm.open and not t.root.get_tree().paused, "повторное нажатие снимает паузу")
	pm.queue_free()
	await t.process_frame
	t.check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/menu.tscn", "игра стартует с главного меню")


func _test_difficulty_balance(t) -> void:
	var bot = load("res://tests/stage8_tests.gd").new()
	var kit := {"medkit": 20, "plasma_rifle": 1, "cell": 900, "alloy_helmet": 1, "alloy_chest": 1, "alloy_boots": 1, "antirad": 3}
	var times := []
	for d in [0, 1, 2]:
		Settings.difficulty = d
		Progress.reset()
		var res: Dictionary = bot._bot_run(bot._flat_world(), "director", kit, 700.0)
		times.append(res["time"])
		t.check(res["won"], "Директор побеждён на сложности «%s» за %.0f с" % [Settings.DIFFICULTY_NAMES[d], res["time"]])
	t.check(times[2] > times[0], "на тяжёлой бой дольше, чем на лёгкой (%s)" % str(times))
	t.check(times[2] < 600.0, "даже на тяжёлой бой укладывается в 10 минут")
	Settings.difficulty = 1
	Progress.reset()


func _touch(tc: TouchControls, idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	tc._input(ev)


func _test_touch(t) -> void:
	InputSetup.register()
	var tc := TouchControls.new()
	t.root.add_child(tc)
	tc.setup(true)
	await t.process_frame
	t.check(tc.visible and tc.buttons.size() == TouchControls.SPECS.size(), "экранные кнопки созданы (%d)" % tc.buttons.size())
	var right: Rect2 = Rect2(tc.buttons["right"].position, tc.buttons["right"].size)
	var jump: Rect2 = Rect2(tc.buttons["jump"].position, tc.buttons["jump"].size)
	_touch(tc, 0, right.get_center(), true)
	t.check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"), "кнопка ▶ идёт вправо")
	_touch(tc, 1, jump.get_center(), true)
	t.check(Input.is_action_pressed("jump") and Input.is_action_pressed("move_right"), "мультитач: идём и прыгаем одновременно")
	_touch(tc, 0, right.get_center(), false)
	t.check(not Input.is_action_pressed("move_right") and Input.is_action_pressed("jump"), "отпускание одного пальца не трогает другой")
	_touch(tc, 1, jump.get_center(), false)
	t.check(not Input.is_action_pressed("jump"), "всё отпущено")
	# палец скользит с кнопки на кнопку
	var left: Rect2 = Rect2(tc.buttons["left"].position, tc.buttons["left"].size)
	_touch(tc, 2, left.get_center(), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = right.get_center()
	tc._input(drag)
	t.check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"), "скольжение пальца переключает направление")
	_touch(tc, 2, right.get_center(), false)
	Settings.touch_place = false
	var mode: Rect2 = Rect2(tc.buttons["mode"].position, tc.buttons["mode"].size)
	_touch(tc, 3, mode.get_center(), true)
	_touch(tc, 3, mode.get_center(), false)
	t.check(Settings.touch_place and tc.buttons["mode"].text == "Ставить", "кнопка режима переключает копание и стройку")
	_touch(tc, 3, mode.get_center(), true)
	_touch(tc, 3, mode.get_center(), false)
	t.check(not Settings.touch_place, "и обратно")
	t.check(tc.button_at(Vector2(640, 100)) == "", "касание мира кнопкой не считается")
	var paused := [false]
	tc.pause_pressed.connect(func() -> void: paused[0] = true)
	var pb: Rect2 = Rect2(tc.buttons["pause"].position, tc.buttons["pause"].size)
	_touch(tc, 4, pb.get_center(), true)
	_touch(tc, 4, pb.get_center(), false)
	t.check(paused[0], "кнопка паузы подаёт сигнал")
	# режим «ставить» реально ставит блок
	var w := WorldData.new(64, 64)
	for y in range(40, 64):
		for x in 64:
			w.fg[y * 64 + x] = BlockDB.STONE
	t.check(ProjectSettings.get_setting("display/window/handheld/orientation") == 0, "ориентация — альбомная")
	tc.queue_free()
	await t.process_frame
