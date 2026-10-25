class_name Progress
extends RefCounted
## Прогресс кампании: какие боссы побеждены и какие рецепты, слои и зоны открыты. Один на игру.
## Флаги вида boss_1..boss_9. Условие может объединять флаги знаком &, например "boss_5&boss_7".

static var flags := {}
static var ending := ""       # выбранная концовка: shutdown / control


static func reset() -> void:
	flags = {}
	ending = ""


static func unlock(flag: String) -> void:
	flags[flag] = true


static func has(requirement: String) -> bool:
	if requirement == "":
		return true
	for part in requirement.split("&"):
		if not flags.has(part.strip_edges()):
			return false
	return true


static func boss_count() -> int:
	var n := 0
	for k in flags:
		if str(k).begins_with("boss_"):
			n += 1
	return n


## Этап кампании 1..5 по таблице ТЗ (раздел 13): этап растёт, когда побеждены боссы текущего этапа.
static func stage() -> int:
	var st := 1
	if has("boss_1"):
		st = 2
	if has("boss_1&boss_2"):
		st = 3
	if has("boss_1&boss_2&boss_3&boss_4"):
		st = 4
	if has("boss_1&boss_2&boss_3&boss_4&boss_5&boss_6&boss_7"):
		st = 5
	return st


static func is_finished() -> bool:
	return has("boss_9")
