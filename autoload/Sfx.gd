extends Node
## Procedural toy-sound synthesizer. Until real audio assets are dropped into
## res://assets/audio/, every effect is generated at startup as a small PCM buffer:
## plastic clicks, rubber-band twangs, hollow toy pops. Play with Sfx.play("name")
## or Sfx.play_at("name", position) for 3D.

const RATE := 22050
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	_streams["shoot"] = _synth(0.09, func(t, n): return _sq(t, 620.0 - 2600.0 * t) * exp(-28.0 * t) + n * 0.35 * exp(-40.0 * t))
	_streams["shoot_heavy"] = _synth(0.25, func(t, n): return _sq(t, 210.0 - 320.0 * t) * exp(-11.0 * t) + n * 0.5 * exp(-18.0 * t))
	_streams["twang"] = _synth(0.22, func(t, _n): return sin(TAU * (140.0 + 30.0 * sin(TAU * 26.0 * t)) * t) * exp(-9.0 * t))
	_streams["hit"] = _synth(0.06, func(t, n): return n * exp(-55.0 * t) + _sq(t, 900.0) * 0.3 * exp(-60.0 * t))
	_streams["hurt"] = _synth(0.18, func(t, _n): return _sq(t, 330.0 - 240.0 * t) * exp(-13.0 * t))
	_streams["death"] = _synth(0.5, func(t, _n): return _sq(t, 240.0 - 190.0 * t) * exp(-5.0 * t) * 0.8)
	_streams["reload"] = _synth(0.16, func(t, n): return (n * 0.6 + _sq(t, 1400.0) * 0.4) * (exp(-70.0 * t) + 0.8 * exp(-70.0 * max(t - 0.09, 0.0)) * float(t > 0.09)))
	_streams["pickup"] = _synth(0.3, func(t, _n): return sin(TAU * (523.0 if t < 0.12 else 784.0) * t) * exp(-8.0 * t))
	_streams["objective"] = _synth(0.55, func(t, _n): return sin(TAU * (392.0 if t < 0.15 else (523.0 if t < 0.3 else 659.0)) * t) * exp(-4.0 * t))
	_streams["click"] = _synth(0.04, func(t, n): return n * exp(-90.0 * t))
	_streams["step"] = _synth(0.05, func(t, n): return n * 0.5 * exp(-70.0 * t))
	_streams["explosion"] = _synth(0.6, func(t, n): return n * exp(-6.0 * t) + sin(TAU * 55.0 * t) * 0.6 * exp(-7.0 * t))
	_streams["engine"] = _synth(0.4, func(t, n): return _sq(t, 70.0 + 8.0 * sin(TAU * 9.0 * t)) * 0.35 + n * 0.08)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	if name not in _streams:
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			p.play()
			return

func play_at(name: String, position: Vector3, volume_db: float = 0.0) -> void:
	if name not in _streams:
		return
	var tree := get_tree()
	if tree.current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.max_distance = 60.0
	tree.current_scene.add_child(p)
	p.global_position = position
	p.play()
	p.finished.connect(p.queue_free)

# --- synthesis helpers ---

func _sq(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0

func _synth(length: float, wave: Callable) -> AudioStreamWAV:
	var frames := int(length * RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / RATE
		var v: float = clampf(wave.call(t, randf_range(-1.0, 1.0)), -1.0, 1.0)
		# short fade-in kills clicks
		v *= minf(t * 400.0, 1.0) * 0.55
		var s := int(v * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
