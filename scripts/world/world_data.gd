class_name WorldData
extends RefCounted
## Данные мира: два слоя блоков (основной и фоновые стены), высота поверхности и биом по колонкам.
## Здесь нет ни узлов, ни графики, поэтому всё тестируется без запуска сцены.

signal block_changed(x: int, y: int)

const CHUNK := 32

var width: int
var height: int
var seed_value := 0
var spawn_tile := Vector2i.ZERO

var fg := PackedByteArray()          # основной слой, id блока
var bg := PackedByteArray()          # стены: 0 = естественная (считается по глубине), 255 = убрана, иначе id
var surface := PackedInt32Array()    # y поверхности в каждой колонке
var biome := PackedByteArray()       # биом поверхности в каждой колонке

var damage := {}                     # индекс клетки -> накопленный урон
var dirty_chunks := {}               # Vector2i -> true (для сохранений)


func _init(w: int, h: int) -> void:
	BlockDB.ensure_loaded()
	width = w
	height = h
	fg.resize(w * h)
	bg.resize(w * h)
	surface.resize(w)
	biome.resize(w)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_block(x: int, y: int) -> int:
	if x < 0 or x >= width or y >= height:
		return BlockDB.BEDROCK
	if y < 0:
		return BlockDB.AIR
	return fg[y * width + x]


func is_solid(x: int, y: int) -> bool:
	return BlockDB.solid[get_block(x, y)] == 1


func get_bg(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0 or y >= height:
		return 0
	var v := bg[y * width + x]
	if v == 255:
		return 0
	if v != 0:
		return v
	var depth := y - surface[x]
	if depth <= 0:
		return 0
	return BlockDB.DIRT if depth < 10 else BlockDB.STONE


func set_block(x: int, y: int, id: int) -> void:
	if not in_bounds(x, y):
		return
	var idx := y * width + x
	if fg[idx] == id:
		return
	fg[idx] = id
	damage.erase(idx)
	_mark_dirty(x, y)
	block_changed.emit(x, y)


func set_bg(x: int, y: int, id: int) -> void:
	if not in_bounds(x, y):
		return
	bg[y * width + x] = 255 if id == 0 else id
	_mark_dirty(x, y)
	block_changed.emit(x, y)


## Наносит урон блоку. Возвращает true, если блок разрушен.
func damage_block(x: int, y: int, amount: float) -> bool:
	var id := get_block(x, y)
	if id == BlockDB.AIR:
		return false
	var h := BlockDB.hardness[id]
	if h < 0.0:
		return false
	var idx := y * width + x
	var total: float = damage.get(idx, 0.0) + amount
	if total >= h:
		set_block(x, y, BlockDB.AIR)
		return true
	damage[idx] = total
	return false


func damage_fraction(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	var id := fg[y * width + x]
	if id == BlockDB.AIR or BlockDB.hardness[id] <= 0.0:
		return 0.0
	return float(damage.get(y * width + x, 0.0)) / BlockDB.hardness[id]


func chunks_wide() -> int:
	return ceili(float(width) / CHUNK)


func chunks_high() -> int:
	return ceili(float(height) / CHUNK)


func chunk_of(x: int, y: int) -> Vector2i:
	return Vector2i(floori(x / float(CHUNK)), floori(y / float(CHUNK)))


func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(fg)
	ctx.update(surface.to_byte_array())
	return ctx.finish().hex_encode()


func _mark_dirty(x: int, y: int) -> void:
	dirty_chunks[chunk_of(x, y)] = true
