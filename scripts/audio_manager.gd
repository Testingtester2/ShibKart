extends Node
## AudioManager (autoload) — music beds + SFX for ShibKart.
##
## MUSIC: drop one looping mp3 per map at  res://assets/audio/music/<track_id>.mp3
##   (falls back to  <theme>.mp3, then silence). Menu uses  menu.mp3.
##   Crossfades on race start / return to menu. Loops seamlessly.
## SFX:  res://assets/audio/sfx/<name>.wav|.ogg|.mp3  (generate with
##   tools/generate_shibkart_audio.py, or drop your own). Missing = silent, no crash.
##
## Buses: Master -> Music, SFX (created at runtime). Volume/mute via set_bus_*().

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_EXT := [".mp3", ".ogg", ".wav"]
const SFX_EXT := [".wav", ".ogg", ".mp3"]
const MUSIC_DB := -6.0                    # nominal music level
const FADE := 1.1

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _using_a := true
var _cur_music := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _loop_sfx := {}                       # name -> AudioStreamPlayer (engine/offroad)
var _stream_cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_music_a = _mk_player("Music")
	_music_b = _mk_player("Music")
	for i in range(14):
		_sfx_pool.append(_mk_player("SFX"))
	_engine = _mk_player("SFX")

func _setup_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")

func _mk_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# ------------------------------------------------------------------ streams
func _load_stream(dir: String, name: String, exts: Array) -> AudioStream:
	var key := dir + name
	if _stream_cache.has(key):
		return _stream_cache[key]
	for ext in exts:
		var path: String = dir + name + ext
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			if s != null:
				_prepare_loop(s)
				_stream_cache[key] = s
				return s
	_stream_cache[key] = null
	return null

func _prepare_loop(s: AudioStream) -> void:
	# only music + explicit loop SFX loop; one-shots are handled by their own flag
	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamOggVorbis:
		s.loop = true

func _wav_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.data.size() / 2)     # 16-bit mono frames

# ------------------------------------------------------------------ music
func play_music(track_id: String, theme_id: String = "") -> void:
	if track_id == _cur_music:
		return
	_cur_music = track_id
	var s := _load_stream(MUSIC_DIR, track_id, MUSIC_EXT)
	if s == null and theme_id != "":
		s = _load_stream(MUSIC_DIR, theme_id, MUSIC_EXT)
	var newp := _music_b if _using_a else _music_a
	var oldp := _music_a if _using_a else _music_b
	_using_a = not _using_a
	if s == null:
		_fade(oldp, -60.0, FADE, true)          # nothing to play -> fade out
		return
	newp.stream = s
	newp.volume_db = -60.0
	newp.play()
	_fade(newp, MUSIC_DB, FADE, false)
	_fade(oldp, -60.0, FADE, true)

func stop_music() -> void:
	_cur_music = ""
	_fade(_music_a, -60.0, FADE, true)
	_fade(_music_b, -60.0, FADE, true)

func _fade(player: AudioStreamPlayer, to_db: float, t: float, stop_after: bool) -> void:
	if not is_instance_valid(player):
		return
	var tw := create_tween()
	tw.tween_property(player, "volume_db", to_db, t)
	if stop_after:
		tw.tween_callback(player.stop)

# ------------------------------------------------------------------ SFX
func play_sfx(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	var s := _load_stream(SFX_DIR, name, SFX_EXT)
	if s == null:
		return
	var p := _free_sfx()
	p.stream = s
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.volume_db = vol_db
	p.play()

func _free_sfx() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return _sfx_pool[0]

# looping SFX (engine, off-road rumble) — pitch/volume driven live
func loop_sfx(name: String) -> AudioStreamPlayer:
	if _loop_sfx.has(name) and is_instance_valid(_loop_sfx[name]):
		return _loop_sfx[name]
	var s := _load_stream(SFX_DIR, name, SFX_EXT)
	if s == null:
		return null
	_wav_loop(s)
	var p := _mk_player("SFX")
	p.stream = s
	_loop_sfx[name] = p
	return p

func engine_start() -> void:
	var p := loop_sfx("engine")
	if p and not p.playing:
		p.volume_db = -16.0            # soft background hum, not a drone
		p.play()

func engine_set(speed_frac: float) -> void:
	var p: AudioStreamPlayer = _loop_sfx.get("engine", null)
	if p and p.playing:
		p.pitch_scale = clampf(0.7 + speed_frac * 1.15, 0.7, 2.1)

func engine_stop() -> void:
	var p: AudioStreamPlayer = _loop_sfx.get("engine", null)
	if p:
		p.stop()

func offroad(active: bool) -> void:
	var p := loop_sfx("offroad")
	if p == null:
		return
	if active and not p.playing:
		p.volume_db = -17.0
		p.play()
	elif not active and p.playing:
		p.stop()

# ------------------------------------------------------------------ mixer
func set_bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(linear, 0.0001, 1.0)))

func get_bus_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 1.0

func set_bus_mute(bus: String, muted: bool) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_mute(i, muted)

func is_bus_muted(bus: String) -> bool:
	var i := AudioServer.get_bus_index(bus)
	return AudioServer.is_bus_mute(i) if i >= 0 else false
