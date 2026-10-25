class_name Projectile
extends Node2D
## Пуля. Летит по прямой, исчезает при попадании в блок или врага.

var world: WorldData
var velocity := Vector2.ZERO
var damage := 10.0
var life := 1.2


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
		for e in enemies:
			if is_instance_valid(e) and not e.dead and e.rect().has_point(position):
				e.take_damage(damage, 1 if velocity.x >= 0.0 else -1)
				return false
	return true


func _draw() -> void:
	draw_rect(Rect2(-2, -1, 4, 2), Color("ffd966"))
