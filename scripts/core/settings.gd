class_name Settings
extends RefCounted
## Настройки игры, живущие между сценами: сложность, звук, запрос на загрузку сохранения.

const DIFFICULTY_NAMES := ["Лёгкая", "Нормальная", "Тяжёлая"]
const HP_MULT := [0.8, 1.0, 1.35]
const DAMAGE_MULT := [0.7, 1.0, 1.4]
const SPAWN_MULT := [0.8, 1.0, 1.3]

static var difficulty := 1
static var load_requested := false
static var sound_on := true
static var volume := 0.7
static var touch_place := false     # сенсорный режим: касание ставит блок вместо копания
static var force_touch := false


static func hp_mult() -> float:
	return HP_MULT[clampi(difficulty, 0, 2)]


static func damage_mult() -> float:
	return DAMAGE_MULT[clampi(difficulty, 0, 2)]


static func spawn_mult() -> float:
	return SPAWN_MULT[clampi(difficulty, 0, 2)]


static func difficulty_name() -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, 2)]
