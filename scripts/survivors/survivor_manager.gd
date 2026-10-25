class_name SurvivorManager
extends Node2D
## Выжившие: спасение (клавиша E), койки, роли, работа на базе, уход при кризисе, новые жители.

signal message(text: String)

const NAMES := ["Анна", "Игорь", "Мария", "Пётр", "Лена", "Саша", "Олег", "Вера", "Макс", "Нина", "Глеб", "Юля"]
const INTERACT_DIST := 64.0

var world: WorldData
var player: Player
var shelter: ShelterManager
var clock: DayClock
var residents: Array[Survivor] = []
var stranded: Array[Survivor] = []
var resident_cap := 4
var rng := RandomNumberGenerator.new()
var assign_timer := 0.0
var crisis_time := 0.0
var name_counter := 0


func setup(w: WorldData, p: Player, sh: ShelterManager, c: DayClock) -> void:
	Balance.ensure_loaded()
	world = w
	player = p
	shelter = sh
	clock = c
	resident_cap = int(Balance.g("start_resident_cap"))
	rng.seed = w.seed_value + 7
	sh.survivors = self
	p.survivors = self
	if clock != null:
		clock.dawn.connect(_on_dawn)


func _physics_process(delta: float) -> void:
	update(delta)


func _new_survivor() -> Survivor:
	var s := Survivor.new()
	s.world = world
	s.survivor_name = NAMES[name_counter % NAMES.size()]
	name_counter += 1
	for r in Survivor.ROLES:
		s.skills[r] = rng.randi_range(1, 3)
	add_child(s)
	return s


## Выживший, ожидающий спасения на поверхности в колонке tile_x.
func spawn_stranded(tile_x: int) -> Survivor:
	var s := _new_survivor()
	s.position = Vector2(tile_x * 16 + 1, world.surface[tile_x] * 16 - Survivor.SIZE.y)
	stranded.append(s)
	return s


func max_residents() -> int:
	return mini(resident_cap, int(Balance.g("max_residents")))


## Койки, за которыми ещё никто не закреплён.
func free_beds() -> Array[Vector2i]:
	var taken := {}
	for r in residents:
		taken[r.home] = true
	var beds: Array[Vector2i] = []
	for p in shelter.devices:
		if shelter.devices[p] == BlockDB.BED and not taken.has(p):
			beds.append(p)
	return beds


func _become_resident(s: Survivor, bed: Vector2i) -> void:
	stranded.erase(s)
	s.resident = true
	s.home = bed
	s.role = s.best_role(rng)
	s.teleport_home()
	residents.append(s)
	shelter.evaluate()


## Принять выжившего на базу. Возвращает сообщение для игрока.
func rescue(s: Survivor) -> String:
	if residents.size() >= max_residents():
		return "Лимит жителей: %d. Нужна стабильность и новые койки." % max_residents()
	var beds := free_beds()
	if beds.is_empty():
		return "%s просит койку: поставьте кровать на базе." % s.survivor_name
	_become_resident(s, beds[0])
	return "%s спасён и стал жителем: %s." % [s.survivor_name, Survivor.ROLE_TITLES[s.role]]


## E рядом с выжившим: спасти или сменить роль. Возвращает "" если рядом никого нет.
func interact_at(world_pos: Vector2, p: Player) -> String:
	for s in stranded + residents:
		if s.rect().grow(8.0).has_point(world_pos) and p.center().distance_to(s.center()) <= INTERACT_DIST:
			if not s.resident:
				return rescue(s)
			s.cycle_role()
			return "%s: теперь %s." % [s.survivor_name, Survivor.ROLE_TITLES[s.role]]
	return ""


func update(delta: float) -> void:
	if world == null or shelter == null:
		return
	shelter.manned.clear()
	var wm := shelter.work_mult()
	assign_timer -= delta
	var reassign := assign_timer <= 0.0
	if reassign:
		assign_timer = 0.5
	for s in residents:
		if reassign:
			_assign_station(s)
		s.update(delta)
		if s.working and wm > 0.0:
			shelter.manned[s.station] = true
		if s.role == "builder" and wm > 0.0:
			_repair_around(s, delta * wm)
	_crisis_logic(delta)


func _assign_station(s: Survivor) -> void:
	var want := BlockDB.PLANTER if s.role == "farmer" else (BlockDB.PURIFIER if s.role == "engineer" else -1)
	if s.station != Survivor.NO_STATION and (want < 0 or shelter.devices.get(s.station, -1) != want):
		s.station = Survivor.NO_STATION
	if want < 0 or s.station != Survivor.NO_STATION:
		return
	var taken := {}
	for r in residents:
		if r != s and r.station != Survivor.NO_STATION:
			taken[r.station] = true
	var best := Survivor.NO_STATION
	var best_d := 1e9
	for p in shelter.devices:
		if shelter.devices[p] != want or taken.has(p):
			continue
		var d := absf(p.x - s.home.x) + absf(p.y - s.home.y)
		if d < best_d and d <= 40.0:
			best_d = d
			best = p
	s.station = best


## Строитель чинит повреждённые блоки вокруг себя.
func _repair_around(s: Survivor, dt: float) -> void:
	if world.damage.is_empty():
		return
	var c := Vector2(s.center().x / 16.0, s.center().y / 16.0)
	var radius := Balance.g("repair_radius")
	var level := float(s.skills.get("builder", 1))
	for idx in world.damage.keys():
		var x: int = idx % world.width
		var y: int = idx / world.width
		if Vector2(x + 0.5, y + 0.5).distance_to(c) <= radius:
			world.repair_block(x, y, Balance.g("repair_rate") * (0.5 + 0.5 * level) * dt)


func _crisis_logic(delta: float) -> void:
	if shelter.state == Stability.CRISIS and not residents.is_empty():
		crisis_time += delta
		if crisis_time >= Balance.g("leave_after"):
			crisis_time = Balance.g("leave_after") - Balance.g("leave_interval")
			var gone: Survivor = residents.pop_back()
			message.emit("%s ушёл из убежища: слишком тяжело." % gone.survivor_name)
			gone.queue_free()
			shelter.evaluate()
	else:
		crisis_time = 0.0


## На рассвете при процветании к базе приходит новый житель.
func _on_dawn() -> void:
	arrive_newcomer()


func arrive_newcomer() -> Survivor:
	if shelter.state != Stability.PROSPERITY or residents.size() >= max_residents():
		return null
	var beds := free_beds()
	if beds.is_empty():
		return null
	var s := _new_survivor()
	_become_resident(s, beds[0])
	message.emit("%s пришёл к убежищу сам и остался." % s.survivor_name)
	return s
