class_name Sound
extends Node
## There is no music: the forest is the instrument. Every sound is synthesised
## here at start-up, so the game ships no audio files.

const RATE := 22050
const SCALE := [0, 2, 4, 7, 9]   # pentatonic, so any run of falls is a phrase

var world: World
var bank := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var creak_wait := 0.0
var wind_player: AudioStreamPlayer
var rain_player: AudioStreamPlayer
var rain_level := 0.0
var muted := false


func setup(w: World) -> void:
	world = w
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	bank["note"] = _note(rng)
	bank["thud"] = _thud(rng)
	bank["creak"] = _creak(rng)
	bank["snap"] = _snap(rng)
	bank["snip"] = _snip(rng)
	bank["chime"] = _chime()
	bank["pop"] = _pop()
	bank["drip"] = _drip()
	for k in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = _noise_loop(rng, 0.045, 3.0)
	wind_player.volume_db = -30.0
	add_child(wind_player)
	wind_player.play()
	rain_player = AudioStreamPlayer.new()
	rain_player.stream = _noise_loop(rng, 0.5, 2.0)
	rain_player.volume_db = -60.0
	add_child(rain_player)
	rain_player.play()
	world.happened.connect(_on_event)


func play(name: String, pitch := 1.0, db := 0.0) -> void:
	if muted:
		return
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = bank[name]
	p.pitch_scale = clampf(pitch, 0.2, 4.0)
	p.volume_db = db
	p.play()


## Each falling trunk sounds one note: low for long trunks, high for short ones.
func note_for(length: float) -> float:
	var t := clampf((length - 50.0) / 600.0, 0.0, 1.0)
	var step := int(round((1.0 - t) * 12.0))     # 0 = lowest
	var semis: int = (step / 5) * 12 + SCALE[step % 5] - 12
	return pow(2.0, semis / 12.0)


func _on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"impact":
			var size := clampf(d.volume / 6000.0, 0.05, 1.0)
			play("note", note_for(d.length), lerpf(-16.0, -3.0, size))
			play("thud", lerpf(1.5, 0.7, size), lerpf(-20.0, -4.0, size) + clampf(d.speed / 300.0, 0.0, 1.0) * 3.0)
		"fall":
			play("snap", randf_range(0.7, 1.0) if d.volume > 3000.0 else randf_range(1.0, 1.4), -8.0)
		"break":
			if d.volume > 40.0:
				play("snap", randf_range(1.5, 2.1), -20.0)
		"sprout":
			play("pop", randf_range(0.9, 1.5), -26.0)
		"new_shape":
			play("chime", 1.0, -10.0)


func chime(pitch := 1.0) -> void:
	play("chime", pitch, -12.0)


func snip() -> void:
	play("snip", randf_range(0.9, 1.2), -10.0)


func drip() -> void:
	play("drip", randf_range(0.8, 1.6), -22.0)


func _process(delta: float) -> void:
	# Creaks rise in pitch as strain builds.
	creak_wait -= delta
	if creak_wait <= 0.0:
		creak_wait = 0.12
		var worst := 0.0
		var size := 0.0
		for p in world.plants:
			if p.awake and p.max_strain > worst and p.volume > 300.0:
				worst = p.max_strain
				size = p.volume
		if worst > 0.62 and randf() < (worst - 0.55) * 0.9:
			play("creak", lerpf(0.55, 1.5, clampf((worst - 0.6) / 0.6, 0.0, 1.0)) * lerpf(1.2, 0.8, clampf(size / 8000.0, 0.0, 1.0)), lerpf(-24.0, -9.0, clampf((worst - 0.6) / 0.5, 0.0, 1.0)))
			creak_wait = randf_range(0.25, 0.7)
	var blow := clampf(absf(world.wind) / 160.0 + absf(world.gust_power) / 90.0, 0.0, 1.0)
	wind_player.volume_db = lerpf(wind_player.volume_db, lerpf(-34.0, -8.0, blow), minf(1.0, delta * 3.0))
	wind_player.pitch_scale = lerpf(wind_player.pitch_scale, 0.8 + blow * 0.7, minf(1.0, delta * 2.0))
	rain_player.volume_db = lerpf(rain_player.volume_db, lerpf(-60.0, -14.0, rain_level), minf(1.0, delta * 6.0))
	rain_level = maxf(0.0, rain_level - delta * 3.0)


# -------------------------------------------------------------- synthesis ----

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## A struck wooden bar: a fundamental with the inharmonic overtones of a marimba.
func _note(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 1.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := 196.0
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * f * t) * exp(-t * 2.6)
		s += 0.45 * sin(TAU * f * 3.93 * t) * exp(-t * 7.0)
		s += 0.2 * sin(TAU * f * 9.2 * t) * exp(-t * 16.0)
		s += 0.25 * sin(TAU * f * 0.5 * t) * exp(-t * 2.0)
		if t < 0.012:
			s += rng.randf_range(-0.6, 0.6) * (1.0 - t / 0.012)
		out[i] = s * 0.55 * minf(1.0, t * 800.0)
	return _wav(out)


func _thud(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 70.0 * exp(-t * 6.0) + 38.0
		var s := sin(TAU * f * t) * exp(-t * 7.0)
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.08
		s += low * 1.6 * exp(-t * 14.0)
		out[i] = s * 0.8 * minf(1.0, t * 600.0)
	return _wav(out)


## Stick-slip: a quickening run of small wooden ticks through a hollow resonance.
func _creak(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var t_next := 0.0
	var ping_t := -1.0
	var ping_f := 600.0
	var ping_a := 0.0
	for i in n:
		var t := float(i) / RATE
		if t >= t_next:
			ping_t = t
			ping_f = rng.randf_range(480.0, 900.0)
			ping_a = rng.randf_range(0.4, 1.0)
			var rate := lerpf(26.0, 70.0, t / 0.55)
			t_next = t + rng.randf_range(0.7, 1.3) / rate
		var s := 0.0
		if ping_t >= 0.0:
			var dt := t - ping_t
			s = sin(TAU * ping_f * dt) * exp(-dt * 260.0) * ping_a
		var env := sin(PI * t / 0.55)
		out[i] = s * env * 0.7
	return _wav(out)


func _snap(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.35
		var s := low * exp(-t * 38.0) + 0.5 * sin(TAU * 340.0 * t) * exp(-t * 30.0)
		s += 0.3 * (noise - low) * exp(-t * 90.0)
		out[i] = s * 0.9
	return _wav(out)


func _snip(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) + sin(TAU * 2400.0 * t) * exp(-t * 80.0) * 0.5) * 0.5
	return _wav(out)


func _chime() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * 784.0 * t) * exp(-t * 3.0)
		if t > 0.16:
			s += sin(TAU * 1174.7 * (t - 0.16)) * exp(-(t - 0.16) * 3.0)
		s += 0.2 * sin(TAU * 1568.0 * t) * exp(-t * 6.0)
		out[i] = s * 0.3 * minf(1.0, t * 300.0)
	return _wav(out)


func _pop() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (500.0 + 2600.0 * t) * t) * exp(-t * 40.0) * 0.5
	return _wav(out)


func _drip() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (900.0 + 3500.0 * t) * t) * exp(-t * 30.0) * 0.45
	return _wav(out)


## A loop of soft filtered noise: wind when dark, rain when bright.
func _noise_loop(rng: RandomNumberGenerator, bright: float, seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var slow := 0.0
	for i in n:
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * bright
		slow += (noise - slow) * 0.002
		out[i] = low * (0.7 + slow * 8.0)
	# Crossfade the ends so the loop has no click.
	var fade := int(RATE * 0.25)
	for i in fade:
		var f := float(i) / fade
		out[i] = out[i] * f + out[n - fade + i] * (1.0 - f)
	out.resize(n - fade)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	for i in out.size():
		out[i] = out[i] / peak * 0.8
	return _wav(out, true)
