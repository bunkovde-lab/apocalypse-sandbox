class_name SaveSystem
extends RefCounted
## Сохранения. Мир не пишется целиком: хранится seed и только изменённые чанки (fg и bg).
## При загрузке мир генерируется заново из seed, затем поверх кладутся изменённые чанки.

const VERSION := 1
const PATH := "user://save.dat"


static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func delete(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------- Сбор состояния ----------

static func _chunk_bytes(world: WorldData, arr: PackedByteArray, c: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	var x0 := c.x * WorldData.CHUNK
	var y0 := c.y * WorldData.CHUNK
	var x1 := mini(x0 + WorldData.CHUNK, world.width)
	var y1 := mini(y0 + WorldData.CHUNK, world.height)
	for y in range(y0, y1):
		out.append_array(arr.slice(y * world.width + x0, y * world.width + x1))
	return out.compress(FileAccess.COMPRESSION_ZSTD)


static func _put_chunk(world: WorldData, arr: PackedByteArray, c: Vector2i, data: PackedByteArray) -> void:
	var x0 := c.x * WorldData.CHUNK
	var y0 := c.y * WorldData.CHUNK
	var x1 := mini(x0 + WorldData.CHUNK, world.width)
	var y1 := mini(y0 + WorldData.CHUNK, world.height)
	var w := x1 - x0
	var raw := data.decompress((y1 - y0) * w, FileAccess.COMPRESSION_ZSTD)
	for y in range(y0, y1):
		for x in range(x0, x1):
			arr[y * world.width + x] = raw[(y - y0) * w + (x - x0)]


static func capture(ctx: Dictionary) -> Dictionary:
	var world: WorldData = ctx["world"]
	var player: Player = ctx["player"]
	var clock: DayClock = ctx["clock"]
	var shelter: ShelterManager = ctx["shelter"]
	var sm: SurvivorManager = ctx["survivors"]
	var data := {"version": VERSION, "seed": world.seed_value, "width": world.width, "height": world.height}
	var chunks := {}
	for c in world.dirty_chunks:
		chunks[c] = {"fg": _chunk_bytes(world, world.fg, c), "bg": _chunk_bytes(world, world.bg, c)}
	data["chunks"] = chunks
	data["damage"] = world.damage.duplicate()
	data["tombstones"] = world.tombstones.duplicate(true)
	data["seals_open"] = world.seals_open.duplicate()
	data["progress"] = {"flags": Progress.flags.duplicate(), "ending": Progress.ending}
	data["difficulty"] = Settings.difficulty
	data["player"] = {
		"pos": player.position, "hp": player.hp, "rad": player.rad, "deaths": player.deaths,
		"items": player.inv.items.duplicate(), "counts": player.inv.counts.duplicate(),
		"selected": player.selected, "equip": player.equip.duplicate(), "jet": player.jet_fuel,
		"spawn": player.spawn_pos,
	}
	data["clock"] = {"time": clock.time, "day": clock.day}
	data["shelter"] = {"fuel": shelter.fuel.duplicate(), "food": shelter.reserve_food, "water": shelter.reserve_water}
	var res := []
	for s in sm.residents:
		res.append(_survivor_data(s))
	var strd := []
	for s in sm.stranded:
		if is_instance_valid(s):
			strd.append(_survivor_data(s))
	data["survivors"] = {"residents": res, "stranded": strd, "counter": sm.name_counter, "cap": sm.resident_cap}
	if ctx.has("director") and ctx["director"] != null:
		var d: EventDirector = ctx["director"]
		data["director"] = {"pending": d.pending.duplicate(true), "layer_time": d.layer_time.duplicate()}
	if ctx.has("minimap") and ctx["minimap"] != null:
		data["explored"] = (ctx["minimap"] as Minimap).explored.compress(FileAccess.COMPRESSION_ZSTD)
		data["explored_size"] = (ctx["minimap"] as Minimap).explored.size()
	return data


static func _survivor_data(s: Survivor) -> Dictionary:
	return {"name": s.survivor_name, "skills": s.skills.duplicate(), "role": s.role, "resident": s.resident,
		"home": s.home, "station": s.station, "pos": s.position, "deadline": s.deadline, "signal": s.signal_event}


static func write(data: Dictionary, path: String = PATH) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(data, true)
	f.close()
	return true


static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v: Variant = f.get_var(true)
	f.close()
	if typeof(v) != TYPE_DICTIONARY or int((v as Dictionary).get("version", 0)) != VERSION:
		return {}
	return v


# ---------- Восстановление ----------

## Создаёт мир: генерация из seed и поверх изменённые чанки.
static func build_world(data: Dictionary) -> WorldData:
	var world := WorldGen.generate(int(data["seed"]), int(data["width"]), int(data["height"]))
	world.dirty_chunks.clear()
	var chunks: Dictionary = data["chunks"]
	for c in chunks:
		_put_chunk(world, world.fg, c, chunks[c]["fg"])
		_put_chunk(world, world.bg, c, chunks[c]["bg"])
		world.dirty_chunks[c] = true
	world.damage = (data["damage"] as Dictionary).duplicate()
	world.tombstones = (data["tombstones"] as Dictionary).duplicate(true)
	world.seals_open = (data["seals_open"] as Dictionary).duplicate()
	return world


static func apply(data: Dictionary, ctx: Dictionary) -> void:
	var player: Player = ctx["player"]
	var clock: DayClock = ctx["clock"]
	var shelter: ShelterManager = ctx["shelter"]
	var sm: SurvivorManager = ctx["survivors"]
	Progress.flags = (data["progress"]["flags"] as Dictionary).duplicate()
	Progress.ending = str(data["progress"]["ending"])
	Settings.difficulty = int(data["difficulty"])
	var pd: Dictionary = data["player"]
	player.position = pd["pos"]
	player.hp = float(pd["hp"])
	player.rad = float(pd["rad"])
	player.deaths = int(pd["deaths"])
	player.inv.items = pd["items"]
	player.inv.counts = pd["counts"]
	player.selected = int(pd["selected"])
	player.equip = (pd["equip"] as Dictionary).duplicate()
	player.jet_fuel = float(pd["jet"])
	player.spawn_pos = pd["spawn"]
	player.vel = Vector2.ZERO
	clock.time = float(data["clock"]["time"])
	clock.day = int(data["clock"]["day"])
	shelter.rescan()
	shelter.fuel = (data["shelter"]["fuel"] as Dictionary).duplicate()
	shelter.reserve_food = float(data["shelter"]["food"])
	shelter.reserve_water = float(data["shelter"]["water"])
	shelter.recompute_power()
	# выжившие
	for s in sm.residents + sm.stranded:
		if is_instance_valid(s):
			s.queue_free()
	sm.residents.clear()
	sm.stranded.clear()
	var sd: Dictionary = data["survivors"]
	sm.name_counter = int(sd["counter"])
	sm.resident_cap = int(sd["cap"])
	for e in sd["residents"]:
		sm.residents.append(_make_survivor(sm, e))
	for e in sd["stranded"]:
		sm.stranded.append(_make_survivor(sm, e))
	shelter.evaluate()
	if data.has("director") and ctx.has("director") and ctx["director"] != null:
		var d: EventDirector = ctx["director"]
		d.pending = (data["director"]["pending"] as Array).duplicate(true)
		d.layer_time = (data["director"]["layer_time"] as Dictionary).duplicate()
	if data.has("explored") and ctx.has("minimap") and ctx["minimap"] != null:
		var m: Minimap = ctx["minimap"]
		var raw := (data["explored"] as PackedByteArray).decompress(int(data["explored_size"]), FileAccess.COMPRESSION_ZSTD)
		if raw.size() == m.explored.size():
			m.explored = raw


static func _make_survivor(sm: SurvivorManager, e: Dictionary) -> Survivor:
	var s := Survivor.new()
	s.world = sm.world
	s.survivor_name = str(e["name"])
	s.skills = (e["skills"] as Dictionary).duplicate()
	s.role = str(e["role"])
	s.resident = bool(e["resident"])
	s.home = e["home"]
	s.station = e["station"]
	s.position = e["pos"]
	s.deadline = float(e["deadline"])
	s.signal_event = bool(e["signal"])
	sm.add_child(s)
	return s
