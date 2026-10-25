class_name EventDirector
extends Node
## События (ТЗ, раздел 7) и радиация. Каждое событие начинается с предупреждения за WARNING секунд.
## Ночная волна живёт в EnemyManager, здесь: кислотный дождь, пыльная буря, сигнал бедствия, рейд,
## обвал, выброс радиации, тревога корпорации.

signal message(text: String)
signal event_started(name: String)
signal event_ended(name: String)

const WARNING := 25.0
const TITLES := {
	"acid_rain": "Кислотный дождь", "dust_storm": "Пыльная буря", "distress_signal": "Сигнал бедствия",
	"raid": "Рейд мародёров", "cave_in": "Обвал", "radiation_burst": "Выброс радиации", "corp_alarm": "Тревога корпорации",
}
const DURATIONS := {"acid_rain": 75.0, "dust_storm": 90.0, "distress_signal": 240.0, "raid": 1.0,
	"cave_in": 1.0, "radiation_burst": 35.0, "corp_alarm": 45.0}
const ACID_VICTIMS := [BlockDB.WOOD, BlockDB.DOOR, BlockDB.DOOR_OPEN, BlockDB.SCRAP, BlockDB.RAIN_COLLECTOR,
	BlockDB.PLANTER, BlockDB.BED, BlockDB.LADDER]

var world: WorldData
var player: Player
var combat: EnemyManager
var survivors: SurvivorManager
var shelter: ShelterManager
var clock: DayClock
var rng := RandomNumberGenerator.new()
var pending: Array = []        # {name, t, warned}
var active := {}               # name -> секунд до конца
var layer_time := {}           # слой -> секунд, проведённых игроком
var alarm_cooldown := 0.0
var alarm_wave_timer := 0.0
var tick := 0.0


func setup(w: WorldData, p: Player, c: EnemyManager, sm: SurvivorManager, sh: ShelterManager, clk: DayClock) -> void:
	world = w
	player = p
	combat = c
	survivors = sm
	shelter = sh
	clock = clk
	rng.seed = w.seed_value + 77
	clock.dawn.connect(roll_daily)
	clock.night_started.connect(_on_night)


func _physics_process(delta: float) -> void:
	update(delta)


func is_active(name: String) -> bool:
	return active.has(name)


func active_text() -> String:
	var parts := PackedStringArray()
	for n in active:
		if n != "raid" and n != "cave_in":
			parts.append("%s (%d с)" % [TITLES[n], int(active[n])])
	for p in pending:
		if p["warned"]:
			parts.append("скоро: %s (%d с)" % [TITLES[p["name"]], int(maxf(0.0, p["t"]))])
	return "  |  ".join(parts)


## Ставит событие в очередь: оно начнётся через delay секунд, за WARNING секунд игрок получит предупреждение.
func schedule(name: String, delay: float) -> void:
	for p in pending:
		if p["name"] == name:
			return
	if active.has(name):
		return
	pending.append({"name": name, "t": delay, "warned": false})


func roll_daily() -> void:
	var day := clock.day
	if day >= 2 and rng.randf() < 0.22:
		schedule("acid_rain", rng.randf_range(40.0, 260.0))
	if day >= 2 and rng.randf() < 0.25:
		schedule("dust_storm", rng.randf_range(40.0, 260.0))
	if day >= 2 and survivors != null and survivors.stranded.size() < 3 and rng.randf() < 0.35:
		schedule("distress_signal", rng.randf_range(30.0, 200.0))


func _on_night(night: int) -> void:
	var has_base := survivors != null and not survivors.residents.is_empty()
	if night >= 3 and (has_base or Progress.has("boss_1")) and rng.randf() < 0.4:
		schedule("raid", WARNING + 5.0)


func update(delta: float) -> void:
	if world == null:
		return
	# очередь и предупреждения
	for i in range(pending.size() - 1, -1, -1):
		var p: Dictionary = pending[i]
		p["t"] -= delta
		if not p["warned"] and p["t"] <= WARNING:
			p["warned"] = true
			message.emit("Через %d с: %s!" % [int(maxf(0.0, p["t"])), TITLES[p["name"]].to_lower()])
		if p["t"] <= 0.0:
			pending.remove_at(i)
			start(str(p["name"]))
	# активные
	for n in active.keys():
		active[n] -= delta
		_effect(n, delta)
		if active[n] <= 0.0:
			end(str(n))
	_zone_triggers(delta)
	_radiation(delta)


func start(name: String) -> void:
	active[name] = float(DURATIONS[name])
	event_started.emit(name)
	match name:
		"dust_storm":
			combat.spawn_mult = 2.0
			message.emit("Пыльная буря! В пустоши радиация и мутанты.")
		"acid_rain":
			message.emit("Кислотный дождь! Спрячьтесь под крышу.")
		"distress_signal":
			_signal_start()
		"raid":
			_raid_start()
		"cave_in":
			cave_in()
		"radiation_burst":
			message.emit("Выброс радиации! Нужен защитный костюм.")
		"corp_alarm":
			message.emit("Тревога корпорации! Дроны летят на шум.")
			alarm_wave_timer = 0.0


func end(name: String) -> void:
	active.erase(name)
	event_ended.emit(name)
	match name:
		"dust_storm":
			combat.spawn_mult = 1.0
			message.emit("Пыльная буря стихла.")
		"acid_rain":
			message.emit("Кислотный дождь закончился.")
		"radiation_burst":
			message.emit("Выброс радиации закончился.")
		"corp_alarm":
			message.emit("Тревога корпорации отменена.")


func _effect(name: String, delta: float) -> void:
	match name:
		"acid_rain":
			tick -= delta
			if tick <= 0.0:
				tick = 1.0
				acid_pass(1.0)
			if player.hp > 0.0 and sky_open(player.tile_pos().x, player.tile_pos().y):
				player.apply_dot(1.2 * delta)
		"corp_alarm":
			alarm_wave_timer -= delta
			if alarm_wave_timer <= 0.0:
				alarm_wave_timer = 12.0
				spawn_drones(2)
		"distress_signal":
			pass


func sky_open(x: int, y: int) -> bool:
	for yy in range(y - 1, -1, -1):
		if world.is_solid(x, yy):
			return false
	return true


## Кислота разъедает верхние слабые блоки в колонках вокруг игрока. Возвращает число повреждённых блоков.
func acid_pass(seconds: float) -> int:
	var hits := 0
	var cx := player.tile_pos().x
	for x in range(cx - 40, cx + 41):
		if x < 0 or x >= world.width:
			continue
		var y := 0
		while y < world.height and world.get_block(x, y) == BlockDB.AIR:
			y += 1
		if y >= world.height:
			continue
		var id := world.get_block(x, y)
		if ACID_VICTIMS.has(id):
			world.damage_block(x, y, 0.08 * seconds)
			hits += 1
	return hits


# ----- Сигнал бедствия -----

func _signal_start() -> void:
	if survivors == null:
		return
	var side := 1 if rng.randf() < 0.5 else -1
	var x := clampi(player.tile_pos().x + side * rng.randi_range(70, 110), 6, world.width - 7)
	var s := survivors.spawn_stranded(x)
	s.deadline = DURATIONS["distress_signal"]
	s.signal_event = true
	var dir := "востоке" if side > 0 else "западе"
	message.emit("Сигнал бедствия на %s, около %d блоков! Успейте спасти." % [dir, absi(x - player.tile_pos().x)])


# ----- Рейд -----

func raid_size() -> int:
	return mini(3 + clock.day / 2, 8)


func _raid_start() -> void:
	var n := raid_size()
	var scale := 1 + Progress.boss_count()
	var weak := shelter != null and shelter.state <= Stability.TENSION
	var made := 0
	for _i in n:
		for _attempt in 10:
			var side := 1 if rng.randf() < 0.5 else -1
			var x := clampi(player.tile_pos().x + side * rng.randi_range(30, 42), 4, world.width - 5)
			var e := combat.spawn_enemy(EnemyDB.defs["raider"], x, scale)
			if e != null:
				if weak:
					e.max_hp *= 1.25
					e.hp = e.max_hp
				made += 1
				break
	message.emit("Рейд! Мародёры штурмуют базу (%d)." % made)


# ----- Обвал -----

## Обрушивает свод в шахте рядом с игроком. Возвращает число заваленных клеток.
func cave_in() -> int:
	var pt := player.tile_pos()
	var layer := Layers.at_y(pt.y)
	if layer.is_empty():
		return 0
	for _attempt in 80:
		var x := pt.x + rng.randi_range(-16, 16)
		var y := pt.y + rng.randi_range(-4, 4)
		if absi(x - pt.x) < 7 or world.is_solid(x, y) or y < int(layer["y0"]) or y > int(layer["y1"]):
			continue
		var filled := 0
		var hero_box := Rect2(player.position, Player.SIZE).grow(24.0)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy > 10:
					continue
				var tx := x + dx
				var ty := y + dy
				if world.get_block(tx, ty) != BlockDB.AIR:
					continue
				if hero_box.intersects(Rect2(tx * 16, ty * 16, 16, 16)):
					continue
				var id := BlockDB.STONE
				var r := rng.randf()
				if r < 0.12:
					id = BlockDB.IRON_ORE
				elif r < 0.2:
					id = BlockDB.COPPER_ORE
				elif r < 0.25:
					id = BlockDB.CRYSTAL
				elif r < 0.3:
					id = BlockDB.COAL
				world.set_block(tx, ty, id)
				filled += 1
		if filled > 0:
			message.emit("Обвал! Часть пещеры обрушилась, открылись жилы руды.")
			return filled
	return 0


# ----- Зоны: слой, тревога корпорации, радиация -----

func _zone_triggers(delta: float) -> void:
	alarm_cooldown = maxf(0.0, alarm_cooldown - delta)
	var pt := player.tile_pos()
	var layer := Layers.at_y(pt.y)
	if not layer.is_empty():
		var id: String = layer["id"]
		layer_time[id] = float(layer_time.get(id, 0.0)) + delta
		if id == "mines" and layer_time[id] >= 90.0:
			layer_time[id] = 0.0
			if rng.randf() < 0.5:
				schedule("cave_in", 6.0)
		if (id == "labs" or id == "reactor") and layer_time[id] >= 150.0:
			layer_time[id] = 0.0
			if rng.randf() < 0.5:
				schedule("radiation_burst", WARNING)
	# тревога срабатывает, когда игрок заходит в корпоративный район над землёй
	var col := clampi(pt.x, 0, world.width - 1)
	if world.biome[col] == WorldGen.BIOME_CORPORATE and pt.y <= world.surface[col] + 2 \
			and alarm_cooldown <= 0.0 and not active.has("corp_alarm") and world.width >= 2000:
		alarm_cooldown = 150.0
		start("corp_alarm")


func spawn_drones(n: int) -> int:
	var made := 0
	var scale := 1 + Progress.boss_count()
	for _i in n:
		var side := 1 if rng.randf() < 0.5 else -1
		var x := clampi(player.tile_pos().x + side * rng.randi_range(18, 30), 4, world.width - 5)
		var y := maxi(2, world.surface[x] - 8)
		var e := combat.spawn_at(EnemyDB.defs["security_drone"], Vector2(x * 16.0, y * 16.0), scale)
		if e != null:
			made += 1
	return made


## Скорость набора радиации в точке (в секунду), без учёта защиты.
func radiation_rate() -> float:
	var pt := player.tile_pos()
	var rate := 0.0
	var layer := Layers.at_y(pt.y)
	var col := clampi(pt.x, 0, world.width - 1)
	if not layer.is_empty():
		if layer["id"] == "labs":
			rate = 1.5
		elif layer["id"] == "reactor":
			rate = 4.0
		if active.has("radiation_burst") and (layer["id"] == "labs" or layer["id"] == "reactor"):
			rate *= 3.0
	elif active.has("dust_storm") and world.biome[col] == WorldGen.BIOME_WASTELAND and pt.y <= world.surface[col] + 2:
		rate = 2.0
	return rate


func _radiation(_delta: float) -> void:
	player.rad_source = radiation_rate()
