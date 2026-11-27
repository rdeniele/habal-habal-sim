class_name BackgroundAudio
extends AudioStreamPlayer
## Plays a long looping sound (menu music or a nature/city layer, see NatureSfx) made in code.
## Making it takes about a second, so it happens on a background thread
## (WorkerThreadPool) and the sound fades in when it's ready: no loading stutter.
## The finished sound is cached, so the second time it starts instantly.

static var _ready_streams: Dictionary = {}   # kind -> AudioStreamWAV

var kind := "music"          # "music" (menu) or a NatureSfx.loop() layer: "city", "wind", ...
var target_db := 0.0         # volume to fade to (change it any time, e.g. quieter at night)
var _task := -1
var _result: AudioStreamWAV


## kind: "music" or a NatureSfx layer. bus: "Music" or "SFX".
static func create(p_kind: String, p_bus: String, p_db: float) -> BackgroundAudio:
	var b := BackgroundAudio.new()
	b.kind = p_kind
	b.bus = p_bus
	b.target_db = p_db
	return b


func _ready() -> void:
	volume_db = -60.0
	if _ready_streams.has(kind):
		_start(_ready_streams[kind])
	else:
		_task = WorkerThreadPool.add_task(_generate)


func _generate() -> void:
	_result = NatureSfx.loop(kind)


func _process(delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_ready_streams[kind] = _result
		_start(_result)
	if playing:
		volume_db = move_toward(volume_db, target_db, delta * 20.0)   # gentle fade


func _start(s: AudioStream) -> void:
	stream = s
	play()


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
