extends Node

## AudioManager — procedural sound effects and ambient audio.
## Generates all sounds at runtime using synthesized waveforms.
## No external audio files required.

# ---- Sound pools (AudioStreamPlayer nodes) ----
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_pool_size: int = 12
var sfx_pool_index: int = 0

# Ambient layers
var ambience_player: AudioStreamPlayer = null
var music_player: AudioStreamPlayer = null

# Footstep timing
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.35

# Pregenerated sound buffers (AudioStreamWAV)
var sounds: Dictionary = {}

# Volume settings (linear, not dB)
var master_volume: float = 0.7
var sfx_volume: float = 0.8
var ambience_volume: float = 0.3
var music_volume: float = 0.4

func _ready() -> void:
	# Create SFX pool
	for i in range(sfx_pool_size):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		sfx_pool.append(player)

	# Ambient player
	ambience_player = AudioStreamPlayer.new()
	ambience_player.bus = "Master"
	add_child(ambience_player)

	# Music player
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)

	# Generate all sound effects
	_generate_sounds()

	# Connect to game signals
	if GameManager:
		GameManager.screen_shake_requested.connect(_on_screen_shake)
		GameManager.enemy_died.connect(_on_enemy_died)
		GameManager.game_over.connect(_on_game_over)
		GameManager.all_enemies_cleared.connect(_on_floor_cleared)

	if FloorManager:
		FloorManager.floor_changed.connect(_on_floor_changed)

func _process(delta: float) -> void:
	_process_hero_footsteps(delta)

# ---- SOUND GENERATION ----

func _generate_sounds() -> void:
	var sample_rate := 22050

	# Combat sounds
	sounds["sword_swing"] = _gen_sweep(sample_rate, 0.15, 200.0, 800.0, 0.5)
	sounds["melee_hit"] = _gen_impact(sample_rate, 0.12, 120.0, 0.6)
	sounds["enemy_hit"] = _gen_impact(sample_rate, 0.1, 180.0, 0.5)
	sounds["enemy_death"] = _gen_death_sound(sample_rate, 0.4, 100.0)

	# Spells
	sounds["fireball_cast"] = _gen_whoosh(sample_rate, 0.25, 300.0, 1200.0, 0.5)
	sounds["fireball_explode"] = _gen_explosion(sample_rate, 0.35, 80.0, 0.7)
	sounds["ice_shard"] = _gen_crystalline(sample_rate, 0.3, 1200.0, 0.4)
	sounds["lightning"] = _gen_crackle(sample_rate, 0.25, 0.6)
	sounds["heal"] = _gen_heal_chime(sample_rate, 0.5, 523.0, 0.4)
	sounds["ground_slam"] = _gen_slam(sample_rate, 0.4, 60.0, 0.8)

	# Movement
	sounds["footstep1"] = _gen_footstep(sample_rate, 0.08, 0.3, 0)
	sounds["footstep2"] = _gen_footstep(sample_rate, 0.08, 0.3, 1)
	sounds["footstep3"] = _gen_footstep(sample_rate, 0.08, 0.3, 2)

	# UI / World
	sounds["loot_pickup"] = _gen_coin(sample_rate, 0.2, 1400.0, 0.35)
	sounds["loot_rare"] = _gen_rare_pickup(sample_rate, 0.4, 880.0, 0.4)
	sounds["floor_transition"] = _gen_transition(sample_rate, 0.8, 400.0)
	sounds["level_up"] = _gen_fanfare(sample_rate, 0.6, 523.0, 0.5)
	sounds["boss_roar"] = _gen_roar(sample_rate, 0.7, 55.0, 0.7)

	# Ambient drone (looping)
	sounds["dungeon_ambience"] = _gen_ambient_drone(sample_rate, 4.0, 0.15)

# ---- PLAYBACK API ----

func play_sfx(sound_name: String, volume_scale: float = 1.0, pitch_variance: float = 0.1) -> void:
	if not sounds.has(sound_name):
		return
	var player = sfx_pool[sfx_pool_index]
	sfx_pool_index = (sfx_pool_index + 1) % sfx_pool_size
	player.stream = sounds[sound_name]
	player.volume_db = linear_to_db(sfx_volume * master_volume * volume_scale)
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.play()

func play_sfx_at_pitch(sound_name: String, pitch: float, volume_scale: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var player = sfx_pool[sfx_pool_index]
	sfx_pool_index = (sfx_pool_index + 1) % sfx_pool_size
	player.stream = sounds[sound_name]
	player.volume_db = linear_to_db(sfx_volume * master_volume * volume_scale)
	player.pitch_scale = pitch
	player.play()

func start_ambience() -> void:
	if sounds.has("dungeon_ambience"):
		ambience_player.stream = sounds["dungeon_ambience"]
		ambience_player.volume_db = linear_to_db(ambience_volume * master_volume)
		ambience_player.play()

func stop_ambience() -> void:
	ambience_player.stop()

# ---- EVENT HOOKS ----

func _process_hero_footsteps(delta: float) -> void:
	if not GameManager.hero or not is_instance_valid(GameManager.hero):
		return
	var hero = GameManager.hero
	if hero.is_dead or not hero.is_moving or hero.current_speed < 0.5:
		_footstep_timer = 0.0
		return

	_footstep_timer += delta
	if _footstep_timer >= _footstep_interval:
		_footstep_timer -= _footstep_interval
		var step_name = "footstep" + str(randi_range(1, 3))
		play_sfx(step_name, 0.5, 0.15)

func on_hero_attack() -> void:
	play_sfx("sword_swing", 0.7, 0.1)
	# Delayed hit sound
	get_tree().create_timer(0.15).timeout.connect(func():
		play_sfx("melee_hit", 0.6, 0.15)
	)

func on_hero_cast_fireball() -> void:
	play_sfx("fireball_cast", 0.8, 0.05)

func on_fireball_explode() -> void:
	play_sfx("fireball_explode", 0.9, 0.1)

func on_hero_cast_heal() -> void:
	play_sfx("heal", 0.7, 0.05)

func on_hero_cast_ice_shard() -> void:
	play_sfx("ice_shard", 0.7, 0.08)

func on_hero_cast_lightning() -> void:
	play_sfx("lightning", 0.8, 0.05)

func on_hero_cast_ground_slam() -> void:
	play_sfx("ground_slam", 1.0, 0.05)

func on_hero_take_damage() -> void:
	play_sfx("enemy_hit", 0.5, 0.2)

func on_enemy_take_damage() -> void:
	play_sfx("enemy_hit", 0.4, 0.2)

func on_loot_pickup(rarity: String = "common") -> void:
	if rarity in ["rare", "epic", "legendary"]:
		play_sfx("loot_rare", 0.7, 0.05)
	else:
		play_sfx("loot_pickup", 0.6, 0.15)

func on_boss_spawn() -> void:
	play_sfx("boss_roar", 1.0, 0.05)

func _on_screen_shake(_intensity: float, _duration: float) -> void:
	pass  # Screen shake already has visual — sound is handled at source

func _on_enemy_died(_enemy: Node3D) -> void:
	play_sfx("enemy_death", 0.6, 0.15)

func _on_game_over(won: bool) -> void:
	if won:
		play_sfx("level_up", 1.0, 0.0)
	else:
		play_sfx("boss_roar", 0.5, 0.0)

func _on_floor_cleared() -> void:
	play_sfx("level_up", 0.6, 0.0)

func _on_floor_changed(_floor_num: int) -> void:
	play_sfx("floor_transition", 0.8, 0.0)

# ---- PROCEDURAL SOUND GENERATORS ----

func _make_wav(sample_rate: int, data: PackedFloat32Array) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false

	# Convert float32 [-1, 1] to int16 packed bytes
	var byte_data = PackedByteArray()
	byte_data.resize(data.size() * 2)
	for i in range(data.size()):
		var sample = clampi(int(data[i] * 32767.0), -32768, 32767)
		byte_data[i * 2] = sample & 0xFF
		byte_data[i * 2 + 1] = (sample >> 8) & 0xFF
	wav.data = byte_data
	return wav

func _make_looping_wav(sample_rate: int, data: PackedFloat32Array) -> AudioStreamWAV:
	var wav = _make_wav(sample_rate, data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = data.size()
	return wav

func _envelope(t: float, attack: float, decay: float, sustain: float, release: float, total: float) -> float:
	if t < attack:
		return t / attack
	elif t < attack + decay:
		return 1.0 - (1.0 - sustain) * ((t - attack) / decay)
	elif t < total - release:
		return sustain
	else:
		var rel_t = (t - (total - release)) / release
		return sustain * (1.0 - rel_t)

# Sweep sound (sword swing)
func _gen_sweep(sr: int, dur: float, freq_start: float, freq_end: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.01, 0.05, 0.3, dur * 0.4, dur)
		var freq = lerpf(freq_start, freq_end, t / dur)
		var phase = t * freq * TAU
		data[i] = sin(phase) * env * vol * 0.5 + _noise() * env * vol * 0.3
	return _make_wav(sr, data)

# Impact thud
func _gen_impact(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 20.0)
		var f = freq * exp(-t * 8.0)
		data[i] = (sin(t * f * TAU) * 0.6 + _noise() * 0.4) * env * vol
	return _make_wav(sr, data)

# Enemy death
func _gen_death_sound(sr: int, dur: float, freq: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 5.0)
		var f = freq * exp(-t * 3.0)
		data[i] = (sin(t * f * TAU) * 0.5 + sin(t * f * 1.5 * TAU) * 0.3 + _noise() * 0.2) * env * 0.6
	return _make_wav(sr, data)

# Whoosh (fireball cast)
func _gen_whoosh(sr: int, dur: float, freq_start: float, freq_end: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.02, 0.08, 0.5, dur * 0.5, dur)
		var freq = lerpf(freq_start, freq_end, t / dur)
		data[i] = _noise() * env * vol * _bandpass_approx(freq, sr, i)
	return _make_wav(sr, data)

# Explosion
func _gen_explosion(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 6.0)
		var f = freq * exp(-t * 2.0)
		data[i] = (sin(t * f * TAU) * 0.4 + sin(t * f * 2.0 * TAU) * 0.2 + _noise() * 0.6) * env * vol
	return _make_wav(sr, data)

# Crystalline (ice shard)
func _gen_crystalline(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.005, 0.05, 0.3, dur * 0.6, dur)
		data[i] = (sin(t * freq * TAU) * 0.4 + sin(t * freq * 1.5 * TAU) * 0.3 + sin(t * freq * 2.0 * TAU) * 0.2) * env * vol
	return _make_wav(sr, data)

# Crackle (lightning)
func _gen_crackle(sr: int, dur: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 8.0) * (1.0 + sin(t * 200.0) * 0.3)
		var burst = 1.0 if randf() > 0.7 else 0.3
		data[i] = _noise() * env * vol * burst
	return _make_wav(sr, data)

# Heal chime
func _gen_heal_chime(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.02, 0.1, 0.4, dur * 0.5, dur)
		# Rising arpeggio effect
		var note_t = fmod(t * 4.0, 1.0)
		var note_idx = int(t * 4.0) % 4
		var freqs = [freq, freq * 1.25, freq * 1.5, freq * 2.0]  # Major chord arpeggio
		var f = freqs[note_idx]
		data[i] = sin(t * f * TAU) * env * vol * 0.7
	return _make_wav(sr, data)

# Ground slam
func _gen_slam(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 5.0)
		var f = freq * exp(-t * 1.5)
		data[i] = (sin(t * f * TAU) * 0.5 + sin(t * f * 0.5 * TAU) * 0.3 + _noise() * 0.4) * env * vol
	return _make_wav(sr, data)

# Footstep variants
func _gen_footstep(sr: int, dur: float, vol: float, variant: int) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	var freq_base = [250.0, 280.0, 220.0][variant]
	for i in range(samples):
		var t = float(i) / sr
		var env = exp(-t * 30.0)
		data[i] = (_noise() * 0.7 + sin(t * freq_base * TAU) * 0.3) * env * vol
	return _make_wav(sr, data)

# Coin pickup
func _gen_coin(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.005, 0.03, 0.3, dur * 0.5, dur)
		# Two-note ping
		var f = freq if t < dur * 0.4 else freq * 1.5
		data[i] = sin(t * f * TAU) * env * vol
	return _make_wav(sr, data)

# Rare loot pickup (sparkle)
func _gen_rare_pickup(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.01, 0.05, 0.5, dur * 0.4, dur)
		var note = int(t * 8.0) % 4
		var freqs = [freq, freq * 1.25, freq * 1.5, freq * 2.0]
		data[i] = sin(t * freqs[note] * TAU) * env * vol * 0.6
	return _make_wav(sr, data)

# Floor transition whoosh
func _gen_transition(sr: int, dur: float, freq: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.05, 0.2, 0.4, dur * 0.5, dur)
		var f = freq * exp(-t * 2.0)
		data[i] = (sin(t * f * TAU) * 0.3 + _noise() * 0.3) * env * 0.5
	return _make_wav(sr, data)

# Victory fanfare
func _gen_fanfare(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.02, 0.1, 0.6, dur * 0.3, dur)
		var note = int(t * 6.0) % 5
		var freqs = [freq, freq * 1.25, freq * 1.5, freq * 1.25, freq * 2.0]
		data[i] = (sin(t * freqs[note] * TAU) * 0.5 + sin(t * freqs[note] * 2.0 * TAU) * 0.3) * env * vol
	return _make_wav(sr, data)

# Boss roar
func _gen_roar(sr: int, dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		var env = _envelope(t, 0.05, 0.15, 0.6, dur * 0.4, dur)
		var f = freq * (1.0 + sin(t * 5.0) * 0.2)
		data[i] = (sin(t * f * TAU) * 0.3 + sin(t * f * 2.0 * TAU) * 0.2 + sin(t * f * 3.0 * TAU) * 0.15 + _noise() * 0.35) * env * vol
	return _make_wav(sr, data)

# Ambient dungeon drone (looping)
func _gen_ambient_drone(sr: int, dur: float, vol: float) -> AudioStreamWAV:
	var samples = int(sr * dur)
	var data = PackedFloat32Array()
	data.resize(samples)
	for i in range(samples):
		var t = float(i) / sr
		# Low rumble + wind noise
		var drone = sin(t * 40.0 * TAU) * 0.3 + sin(t * 60.0 * TAU) * 0.2 + sin(t * 80.0 * TAU) * 0.1
		var wind = _noise() * 0.15 * (0.5 + sin(t * 0.5 * TAU) * 0.5)
		# Occasional drip (every ~2 seconds)
		var drip_t = fmod(t, 2.0)
		var drip = 0.0
		if drip_t < 0.02:
			drip = sin(drip_t * 3000.0 * TAU) * exp(-drip_t * 200.0) * 0.4
		data[i] = (drone + wind + drip) * vol
	return _make_looping_wav(sr, data)

# ---- UTILITIES ----

var _noise_phase: float = 0.0

func _noise() -> float:
	return randf_range(-1.0, 1.0)

func _bandpass_approx(center_freq: float, sr: int, sample_idx: int) -> float:
	# Simple approximation of bandpass using modulated amplitude
	var t = float(sample_idx) / float(sr)
	return 0.5 + 0.5 * sin(t * center_freq * TAU)
