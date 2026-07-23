extends Node
## Premade audio first (res://assets/audio/<name>.ogg|.wav), synth fallback.
## 2D pool for UI/HUD; 3D pool for world emitters; dedicated loop players
## for continuous sounds (jetpack thruster — never restart-spam one-shots).

const RATE := 22050
const NAMES := [
	"shoot", "shoot_heavy", "twang", "hit", "hurt", "death", "reload",
	"pickup", "objective", "click", "step", "explosion", "engine", "ui_confirm",
	"jet_loop", "jet_ignite", "jet_hum",
]

var _streams: Dictionary = {}
var _step_variants: Array[AudioStream] = []
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool3d_i := 0
## Continuous loops keyed by name (jet_loop, jet_hum, engine…).
var _loops: Dictionary = {}

func _ready() -> void:
	for name in NAMES:
		_streams[name] = _load_or_synth(name)
	# Optional alts for variety.
	if ResourceLoader.exists("res://assets/audio/shoot_alt.ogg"):
		_streams["shoot_alt"] = load("res://assets/audio/shoot_alt.ogg")
	if ResourceLoader.exists("res://assets/audio/explosion_alt.ogg"):
		_streams["explosion_alt"] = load("res://assets/audio/explosion_alt.ogg")
	for i in 5:
		var path := "res://assets/audio/step_%d.ogg" % i
		if ResourceLoader.exists(path):
			_step_variants.append(load(path))
	if _step_variants.is_empty() and _streams.has("step"):
		_step_variants.append(_streams["step"])
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	for i in 10:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Master"
		p3.max_distance = 60.0
		add_child(p3)
		_pool3d.append(p3)

func _load_or_synth(name: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		var path := "res://assets/audio/%s%s" % [name, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return _synth_for(name)

func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var stream := _pick(name)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			p.play()
			return

func play_at(name: String, position: Vector3, volume_db: float = 0.0) -> void:
	var stream := _pick(name)
	if stream == null or _pool3d.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p: AudioStreamPlayer3D = _pool3d[_pool3d_i]
	_pool3d_i = (_pool3d_i + 1) % _pool3d.size()
	p.stop()
	# Must live under the 3D scene for correct spatialization.
	if p.get_parent() != scene:
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		scene.add_child(p)
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.global_position = position
	p.play()

## Start/keep a seamless loop. Safe to call every frame while active.
func start_loop(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := _ensure_loop(name)
	if p == null:
		return
	p.volume_db = volume_db
	p.pitch_scale = pitch
	if not p.playing:
		p.play()

func set_loop(name: String, volume_db: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p == null:
		return
	p.volume_db = volume_db
	p.pitch_scale = pitch

func stop_loop(name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p != null and p.playing:
		p.stop()

func is_loop_playing(name: String) -> bool:
	var p: AudioStreamPlayer = _loops.get(name)
	return p != null and p.playing

func _ensure_loop(name: String) -> AudioStreamPlayer:
	if _loops.has(name):
		return _loops[name]
	var src: AudioStream = _streams.get(name)
	if src == null:
		return null
	var stream := src.duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.data.size() / 2.0)
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = stream
	add_child(p)
	_loops[name] = p
	return p

func _pick(name: String) -> AudioStream:
	if name == "step" and not _step_variants.is_empty():
		return _step_variants[randi() % _step_variants.size()]
	if name == "shoot" and _streams.has("shoot_alt") and randf() < 0.45:
		return _streams["shoot_alt"]
	if name == "explosion" and _streams.has("explosion_alt") and randf() < 0.4:
		return _streams["explosion_alt"]
	return _streams.get(name)

func _synth_for(name: String) -> AudioStreamWAV:
	match name:
		"shoot":
			return _synth(0.09, func(t, n): return _sq(t, 620.0 - 2600.0 * t) * exp(-28.0 * t) + n * 0.35 * exp(-40.0 * t))
		"shoot_heavy":
			return _synth(0.25, func(t, n): return _sq(t, 210.0 - 320.0 * t) * exp(-11.0 * t) + n * 0.5 * exp(-18.0 * t))
		"twang":
			return _synth(0.22, func(t, _n): return sin(TAU * (140.0 + 30.0 * sin(TAU * 26.0 * t)) * t) * exp(-9.0 * t))
		"hit":
			return _synth(0.06, func(t, n): return n * exp(-55.0 * t) + _sq(t, 900.0) * 0.3 * exp(-60.0 * t))
		"hurt":
			return _synth(0.18, func(t, _n): return _sq(t, 330.0 - 240.0 * t) * exp(-13.0 * t))
		"death":
			return _synth(0.5, func(t, _n): return _sq(t, 240.0 - 190.0 * t) * exp(-5.0 * t) * 0.8)
		"reload":
			return _synth(0.16, func(t, n): return (n * 0.6 + _sq(t, 1400.0) * 0.4) * (exp(-70.0 * t) + 0.8 * exp(-70.0 * max(t - 0.09, 0.0)) * float(t > 0.09)))
		"pickup":
			return _synth(0.3, func(t, _n): return sin(TAU * (523.0 if t < 0.12 else 784.0) * t) * exp(-8.0 * t))
		"objective", "ui_confirm":
			return _synth(0.55, func(t, _n): return sin(TAU * (392.0 if t < 0.15 else (523.0 if t < 0.3 else 659.0)) * t) * exp(-4.0 * t))
		"click":
			return _synth(0.04, func(t, n): return n * exp(-90.0 * t))
		"step", "jet_ignite":
			return _synth(0.07, func(t, n): return n * 0.7 * exp(-55.0 * t) + _sq(t, 180.0) * 0.15 * exp(-40.0 * t))
		"jet_loop", "jet_hum", "engine":
			# Fallback rumble loop if files missing.
			return _synth(0.5, func(t, n): return _sq(t, 68.0 + 10.0 * sin(TAU * 11.0 * t)) * 0.4 + n * 0.12)
		"explosion":
			return _synth(0.6, func(t, n): return n * exp(-6.0 * t) + sin(TAU * 55.0 * t) * 0.6 * exp(-7.0 * t))
		_:
			return _synth(0.05, func(t, n): return n * exp(-80.0 * t))

func _sq(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0

func _synth(length: float, wave: Callable) -> AudioStreamWAV:
	var frames := int(length * RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / RATE
		var v: float = clampf(wave.call(t, randf_range(-1.0, 1.0)), -1.0, 1.0)
		v *= minf(t * 400.0, 1.0) * 0.55
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
