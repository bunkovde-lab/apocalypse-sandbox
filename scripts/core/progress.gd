class_name Progress
extends RefCounted
## Прогресс кампании: какие боссы побеждены и какие рецепты открыты. Один на игру.

static var flags := {}


static func reset() -> void:
	flags = {}


static func unlock(flag: String) -> void:
	flags[flag] = true


static func has(flag: String) -> bool:
	return flag == "" or flags.has(flag)


## Этап кампании от 1 до 5: растёт с каждым побеждённым боссом (в первом срезе доступны два).
static func stage() -> int:
	var n := 0
	for k in flags:
		if str(k).begins_with("boss_"):
			n += 1
	return mini(1 + n, 5)
