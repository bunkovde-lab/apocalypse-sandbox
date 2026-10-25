class_name TileCollider
extends RefCounted
## Столкновения прямоугольника с сеткой блоков без физического движка.
## Быстро, детерминированно и проверяется тестами.

const TILE := 16
const STEP := 6.0   # максимальный сдвиг за один подшаг, меньше размера блока


static func collides(world: WorldData, pos: Vector2, size: Vector2) -> bool:
	var x0 := floori(pos.x / TILE)
	var x1 := floori((pos.x + size.x - 0.001) / TILE)
	var y0 := floori(pos.y / TILE)
	var y1 := floori((pos.y + size.y - 0.001) / TILE)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if world.is_solid(tx, ty):
				return true
	return false


## Двигает прямоугольник (pos = левый верхний угол) по скорости vel за delta секунд.
## Возвращает {pos, vel, on_floor, hit_wall, hit_ceiling}. Ступеньку высотой в блок проходит сама.
static func move(world: WorldData, pos: Vector2, size: Vector2, vel: Vector2, delta: float) -> Dictionary:
	var on_floor := false
	var hit_wall := false
	var hit_ceiling := false
	var disp := vel * delta
	var steps := maxi(1, ceili(maxf(absf(disp.x), absf(disp.y)) / STEP))
	var d := disp / steps
	for _i in steps:
		if d.x != 0.0:
			var nx := pos.x + d.x
			if collides(world, Vector2(nx, pos.y), size):
				var stepped := false
				if vel.y >= 0.0 and collides(world, pos + Vector2(0, 1), size):
					var up := Vector2(nx, pos.y - TILE)
					if not collides(world, up, size):
						pos = up
						stepped = true
				if not stepped:
					if d.x > 0.0:
						pos.x = floorf((nx + size.x) / TILE) * TILE - size.x
					else:
						pos.x = (floorf(nx / TILE) + 1.0) * TILE
					vel.x = 0.0
					d.x = 0.0
					hit_wall = true
			else:
				pos.x = nx
		if d.y != 0.0:
			var ny := pos.y + d.y
			if collides(world, Vector2(pos.x, ny), size):
				if d.y > 0.0:
					pos.y = floorf((ny + size.y) / TILE) * TILE - size.y
					on_floor = true
				else:
					pos.y = (floorf(ny / TILE) + 1.0) * TILE
					hit_ceiling = true
				vel.y = 0.0
				d.y = 0.0
			else:
				pos.y = ny
	return {"pos": pos, "vel": vel, "on_floor": on_floor, "hit_wall": hit_wall, "hit_ceiling": hit_ceiling}
