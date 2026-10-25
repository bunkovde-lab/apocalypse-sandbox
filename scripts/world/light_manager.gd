class_name LightManager
extends Node2D
## Освещение: тёмные подземелья и свет от ламп, светильников и самого героя.
## Блоки со светом берутся из BlockDB.light. Узлы PointLight2D переиспользуются из пула.

const TILE := 16
const MAX_LIGHTS := 40
const SCAN_RADIUS_X := 46
const SCAN_RADIUS_Y := 28
const PLAYER_LIGHT := 6.5            # радиус света героя в блоках
const UNDERGROUND_AMBIENT := Color(0.16, 0.17, 0.22)

var world: WorldData
var player: Player
var pool: Array[PointLight2D] = []
var hero_light := PointLight2D.new()
var texture: Texture2D
var timer := 0.0
var active_count := 0


static func make_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## Цвет окружающего света: днём и ночью по часам, под землёй тёмный. depth — глубина под поверхностью в блоках.
static func ambient(day_tint: Color, depth: float) -> Color:
	var k := clampf(depth / 20.0, 0.0, 1.0)
	return day_tint.lerp(UNDERGROUND_AMBIENT, k)


## Источники света в прямоугольнике вокруг tile: [{pos: Vector2i, radius: float}], ближайшие первыми.
static func collect(w: WorldData, tile: Vector2i, rx: int = SCAN_RADIUS_X, ry: int = SCAN_RADIUS_Y, limit: int = MAX_LIGHTS) -> Array:
	var found: Array = []
	for y in range(maxi(0, tile.y - ry), mini(w.height, tile.y + ry + 1)):
		for x in range(maxi(0, tile.x - rx), mini(w.width, tile.x + rx + 1)):
			var r := BlockDB.light[w.fg[y * w.width + x]]
			if r > 0.0:
				found.append({"pos": Vector2i(x, y), "radius": r})
	found.sort_custom(func(a, b) -> bool:
		return (a["pos"] - tile).length_squared() < (b["pos"] - tile).length_squared())
	if found.size() > limit:
		found.resize(limit)
	return found


func setup(w: WorldData, p: Player) -> void:
	world = w
	player = p
	texture = make_texture()
	hero_light.texture = texture
	hero_light.color = Color(1.0, 0.9, 0.7)
	hero_light.energy = 0.9
	hero_light.texture_scale = PLAYER_LIGHT * 2.0 * TILE / 128.0
	p.add_child(hero_light)
	hero_light.position = Player.SIZE * 0.5
	for i in MAX_LIGHTS:
		var l := PointLight2D.new()
		l.texture = texture
		l.enabled = false
		add_child(l)
		pool.append(l)


func refresh() -> void:
	var found := collect(world, player.tile_pos())
	active_count = found.size()
	for i in pool.size():
		var l := pool[i]
		if i < found.size():
			var d: Dictionary = found[i]
			l.enabled = true
			l.position = (Vector2(d["pos"]) + Vector2(0.5, 0.5)) * TILE
			l.texture_scale = float(d["radius"]) * 2.0 * TILE / 128.0
			var id := world.get_block(d["pos"].x, d["pos"].y)
			l.color = Color("a8ecff") if id == BlockDB.LAB_LIGHT else Color(1.0, 0.85, 0.55)
			l.energy = 1.1
		else:
			l.enabled = false


func _process(delta: float) -> void:
	if world == null:
		return
	timer -= delta
	if timer <= 0.0:
		timer = 0.4
		refresh()
