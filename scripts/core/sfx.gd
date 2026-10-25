class_name Sfx
extends Node
## Процедурный звук без файлов: короткие тона и шум собираются в AudioStreamWAV при первом запуске.
## Static-интерфейс: Sfx.play("hit") ничего не делает, пока в сцене нет узла-проигрывателя (тесты).

const RATE := 22050
const POOL := 8

static var instance: Sfx = null
static var streams := {}

var players: Array[AudioStreamPlayer] = []
var next := 0
var played := {}               # имя -> сколько раз вызывался (для тестов)


static func tone(freq: float, dur: float, kind: String = "sine", decay: float = 4.0, slide: float = 0.0, vol: float = 0.5) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 7.0 + dur * 100.0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq + slide * t
		phase += TAU * f / RATE
		var v := 0.0
		match kind:
			"sine":
				v = sin(phase)
			"square":
				v = 1.0 if sin(phase) > 0.0 else -1.0
			"saw":
				v = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			"noise":
				v = rng.randf_range(-1.0, 1.0)
		var env := exp(-decay * t / dur) * minf(1.0, float(i) / 80.0)
		var s := clampi(int(v * env * vol * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func build_streams() -> void:
	if not streams.is_empty():
		return
	streams = {
		"swing": tone(220.0, 0.12, "noise", 5.0, 0.0, 0.25),
		"hit": tone(160.0, 0.14, "square", 6.0, -300.0, 0.35),
		"hurt": tone(120.0, 0.25, "saw", 5.0, -200.0, 0.45),
		"kill": tone(300.0, 0.2, "square", 5.0, -900.0, 0.35),
		"shot": tone(900.0, 0.12, "saw", 7.0, -5000.0, 0.35),
		"shotgun": tone(150.0, 0.2, "noise", 6.0, 0.0, 0.5),
		"break": tone(90.0, 0.1, "noise", 7.0, 0.0, 0.35),
		"place": tone(300.0, 0.06, "sine", 6.0, -400.0, 0.4),
		"heal": tone(520.0, 0.3, "sine", 3.0, 600.0, 0.4),
		"pickup": tone(700.0, 0.1, "sine", 4.0, 900.0, 0.35),
		"boss": tone(70.0, 0.9, "saw", 2.5, 40.0, 0.55),
		"win": tone(440.0, 0.8, "sine", 2.0, 440.0, 0.5),
		"seal": tone(100.0, 0.7, "square", 2.5, 200.0, 0.45),
		"alarm": tone(600.0, 0.7, "square", 1.5, -200.0, 0.35),
		"event": tone(330.0, 0.5, "saw", 2.0, -100.0, 0.35),
		"rescue": tone(400.0, 0.5, "sine", 2.0, 500.0, 0.45),
	}


func _ready() -> void:
	build_streams()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _play(name: String) -> void:
	played[name] = int(played.get(name, 0)) + 1
	if not Settings.sound_on or not streams.has(name) or players.is_empty():
		return
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = streams[name]
	p.volume_db = linear_to_db(clampf(Settings.volume, 0.0, 1.0))
	p.play()


static func play(name: String) -> void:
	if instance != null:
		instance._play(name)
