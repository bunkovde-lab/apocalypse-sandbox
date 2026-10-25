class_name Projectile
extends Node2D
## Пуля. Летит по прямой, исчезает при попадании в блок или врага.

var world: WorldData
var velocity := Vector2.ZERO
var damage := 10.0
var life := 1.2
var hostile := false             # true: летит во врага игрока, то есть бьёт героя
var hero: Player
var color := Color("ffd966")


## Возвращает false, когда пуля должна исчезнуть.
func step(delta: float, enemies: Array) -> bool:
	life -= delta
	if life <= 0.0:
		return false
	var move := velocity * delta
	var steps := maxi(1, ceili(move.length() / 4.0))
	var d := move / steps
	for _i in steps:
		position += d
		if world.is_solid(floori(position.x / 16.0), floori(position.y / 16.0)):
			return false
		if hostile:
			if hero != null and hero.hp > 0.0 and Rect2(hero.position, Player.SIZE).has_point(position):
				hero.take_damage(damage, position.x - signf(velocity.x) * 8.0)
				return false
			continue
		for e in enemies:
			if is_instance_valid(e) and not e.dead and e.rect().has_point(position):
				e.take_damage(damage, 1 if velocity.x >= 0.0 else -1)
				return false
	return true


func _draw() -> void:
	draw_rect(Rect2(-2, -1, 4, 2) if not hostile else Rect2(-3, -3, 6, 6), color)
