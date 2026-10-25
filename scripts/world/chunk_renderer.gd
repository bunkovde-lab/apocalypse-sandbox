class_name ChunkRenderer
extends Node2D
## Показывает только ближайшие к игроку чанки: для каждого свой узел с двумя слоями
## (блоки и фоновые стены). Дальние чанки удаляются, поэтому память не растёт.

const TILE := 16

class ChunkView extends RefCounted:
	var root: Node2D
	var fg: TileMapLayer
	var bg: TileMapLayer

var world: WorldData
var tile_set: TileSet
var views := {}                      # Vector2i -> ChunkView
var queue: Array[Vector2i] = []
var radius := Vector2i(3, 2)         # сколько чанков держать вокруг игрока


func setup(w: WorldData, ts: TileSet) -> void:
	world = w
	tile_set = ts
	world.block_changed.connect(_on_block_changed)


func update_view(center_tile: Vector2i) -> void:
	var cs := WorldData.CHUNK
	var cc := Vector2i(floori(center_tile.x / float(cs)), floori(center_tile.y / float(cs)))
	var maxc := Vector2i(world.chunks_wide() - 1, world.chunks_high() - 1)
	var lo := Vector2i(maxi(cc.x - radius.x, 0), maxi(cc.y - radius.y, 0))
	var hi := Vector2i(mini(cc.x + radius.x, maxc.x), mini(cc.y + radius.y, maxc.y))

	var kept: Array[Vector2i] = []
	for key in queue:
		if absi(key.x - cc.x) <= radius.x and absi(key.y - cc.y) <= radius.y:
			kept.append(key)
	queue = kept

	var wanted: Array[Vector2i] = []
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cy)
			if not views.has(key) and not queue.has(key):
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(cc) < b.distance_squared_to(cc))
	queue.append_array(wanted)

	for key in views.keys():
		if absi(key.x - cc.x) > radius.x + 1 or absi(key.y - cc.y) > radius.y + 1:
			_unload_chunk(key)


func process_queue(max_chunks: int = 2) -> void:
	var n := 0
	while n < max_chunks and not queue.is_empty():
		_load_chunk(queue.pop_front())
		n += 1


func flush() -> void:
	while not queue.is_empty():
		_load_chunk(queue.pop_front())


func loaded_count() -> int:
	return views.size()


func get_view(key: Vector2i) -> ChunkView:
	return views.get(key)


func _make_layer(modulate_color: Color) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.rendering_quadrant_size = 32
	layer.collision_enabled = false
	layer.navigation_enabled = false
	layer.modulate = modulate_color
	return layer


func _load_chunk(key: Vector2i) -> void:
	if views.has(key):
		return
	var cs := WorldData.CHUNK
	var view := ChunkView.new()
	view.root = Node2D.new()
	view.root.position = Vector2(key.x * cs * TILE, key.y * cs * TILE)
	view.bg = _make_layer(Color(0.42, 0.42, 0.48))
	view.fg = _make_layer(Color.WHITE)
	view.root.add_child(view.bg)
	view.root.add_child(view.fg)
	add_child(view.root)
	var x0 := key.x * cs
	var y0 := key.y * cs
	for y in range(y0, mini(y0 + cs, world.height)):
		for x in range(x0, mini(x0 + cs, world.width)):
			_paint(view, x, y, true)
	views[key] = view


func _unload_chunk(key: Vector2i) -> void:
	var view: ChunkView = views[key]
	views.erase(key)
	remove_child(view.root)
	view.root.queue_free()


func _paint(view: ChunkView, x: int, y: int, fresh: bool) -> void:
	var cs := WorldData.CHUNK
	var local := Vector2i(x % cs, y % cs)
	var id := world.get_block(x, y)
	if id != BlockDB.AIR:
		view.fg.set_cell(local, 0, Vector2i(id, 0))
		if not fresh:
			view.bg.erase_cell(local)
		return
	if not fresh:
		view.fg.erase_cell(local)
	var wall := world.get_bg(x, y)
	if wall != 0:
		view.bg.set_cell(local, 0, Vector2i(wall, 0))
	elif not fresh:
		view.bg.erase_cell(local)


func _on_block_changed(x: int, y: int) -> void:
	var key := world.chunk_of(x, y)
	if views.has(key):
		_paint(views[key], x, y, false)
