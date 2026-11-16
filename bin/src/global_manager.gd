@tool
## 场景全局管理器。
##
## 挂载在场景根节点，统一提供场景级接口。
## 歌词环的具体实现由 [LyricRing] 模板负责，本脚本只负责绑定、
## 转发信号与提供稳定的全局调用入口。
class_name GlobalManager
extends Node3D

## 一条歌词开始显示时发出。
signal lyric_line_started(index: int, time: float, text: String)
## 一条歌词转到不可见半圈并被销毁时发出。
signal lyric_line_destroyed(index: int, text: String)
## 全部歌词播放完毕时发出。
signal lyrics_finished

## 歌词环模板节点路径。
@export var lyric_ring_path: NodePath = ^"LyricRing":
	set(value):
		lyric_ring_path = value
		_bind_lyric_ring()
## BGM 播放器路径；播放结束时自动退出进程。
@export var bgm_path: NodePath = ^"BGM":
	set(value):
		bgm_path = value
		_bind_bgm()
## 舞台根节点路径；旋转时摄像机会作为它的子节点同步移动。
@export var stage_path: NodePath = ^"stage":
	set(value):
		stage_path = value
		_bind_performance()
## 角色 Sprite3D 路径，用于切换角色立绘集合。
@export var character_path: NodePath = ^"charactor/C1":
	set(value):
		character_path = value
		_bind_performance()
## 每隔多少句歌词自动触发一次舞台旋转。
@export_range(1, 16, 1) var rotate_every_lines: int = 3
## 是否自动按歌词句数触发旋转。
@export var auto_rotate_with_lyrics: bool = true
## 舞台旋转 180 度所需时间。
@export_range(0.1, 5.0, 0.05) var rotate_duration: float = 1.2

## 当前绑定的歌词环模板。
var _lyric_ring: LyricRing
## 当前绑定的 BGM 播放器。
var _bgm: AudioStreamPlayer
## 当前舞台根节点。
var _stage: Node3D
## 当前角色节点。
var _character: Node
## 是否正在执行旋转，避免重叠旋转。
var _rotating: bool = false
## 已收到的歌词句数。
var _line_count: int = 0


## 初始化并绑定歌词环模板。
func _ready() -> void:
	_bind_lyric_ring()
	_bind_bgm()
	_bind_performance()


## 从指定时间开始播放歌词。
## [param from_time] 起始秒数；小于 0 时使用模板的 start_time。
func play_lyrics(from_time: float = -1.0) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.play(from_time)


## 暂停歌词播放。
func pause_lyrics() -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.pause()


## 停止歌词播放并清空当前歌词。
func stop_lyrics() -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.stop()


## 跳转到指定歌词时间。
## [param time] 目标秒数。
func seek_lyrics(time: float) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.seek(time)


## 载入 LRC 歌词文件。
## [param path] 可选的新路径；留空时使用模板当前路径。
## 返回是否成功解析出歌词。
func load_lyrics(path: String = "") -> bool:
	_ensure_lyric_ring()
	if _lyric_ring == null:
		return false
	return _lyric_ring.load_lyrics(path)


## 直接传入歌词时间轴。
## [param entries] 每一项为包含 time 和 text 的字典。
func set_lyrics(entries: Array) -> void:
	_ensure_lyric_ring()
	if _lyric_ring != null:
		_lyric_ring.set_lyrics(entries)


## 让舞台旋转 180 度，并同步切换角色立绘集合。
## 摄像机作为舞台子节点会一起旋转，角色立绘保持原位，因此旋转后呈现背面。
## 旋转使用 Inverted Check 曲线，结束后复位旋转状态。
func rotate_stage_and_switch_character() -> void:
	if Engine.is_editor_hint() or _rotating:
		return
	_bind_performance()
	if _stage == null:
		return
	_rotating = true
	if _character != null and _character.has_method("switch_character_set"):
		_character.switch_character_set()
	var start_angle := _stage.rotation.y
	var target_angle := start_angle + PI
	var tween := create_tween()
	tween.tween_method(
		_set_stage_rotation.bind(start_angle, target_angle),
		0.0,
		1.0,
		rotate_duration
	)
	tween.finished.connect(_on_stage_rotation_finished)


## 当前歌词时间轴时钟，单位为秒。
func get_lyric_time() -> float:
	_ensure_lyric_ring()
	return _lyric_ring.get_playback_time() if _lyric_ring != null else 0.0


## 是否正在播放歌词。
func is_lyrics_playing() -> bool:
	_ensure_lyric_ring()
	return _lyric_ring.is_playing() if _lyric_ring != null else false


## 当前最新活动歌词文本。
func get_lyric_text() -> String:
	_ensure_lyric_ring()
	return _lyric_ring.get_current_text() if _lyric_ring != null else ""


## 解析并绑定歌词环模板，同时转发其信号。
func _bind_lyric_ring() -> void:
	if not is_node_ready():
		return
	if _lyric_ring != null:
		if _lyric_ring.line_spawned.is_connected(_on_line_spawned):
			_lyric_ring.line_spawned.disconnect(_on_line_spawned)
		if _lyric_ring.line_destroyed.is_connected(_on_line_destroyed):
			_lyric_ring.line_destroyed.disconnect(_on_line_destroyed)
		if _lyric_ring.playback_finished.is_connected(_on_playback_finished):
			_lyric_ring.playback_finished.disconnect(_on_playback_finished)
	_lyric_ring = get_node_or_null(lyric_ring_path) as LyricRing
	if _lyric_ring == null:
		push_warning("GlobalManager: 找不到歌词环模板节点: %s" % lyric_ring_path)
		return
	if not _lyric_ring.line_spawned.is_connected(_on_line_spawned):
		_lyric_ring.line_spawned.connect(_on_line_spawned)
	if not _lyric_ring.line_destroyed.is_connected(_on_line_destroyed):
		_lyric_ring.line_destroyed.connect(_on_line_destroyed)
	if not _lyric_ring.playback_finished.is_connected(_on_playback_finished):
		_lyric_ring.playback_finished.connect(_on_playback_finished)


## 绑定舞台和角色节点。
func _bind_performance() -> void:
	if not is_node_ready():
		return
	_stage = get_node_or_null(stage_path) as Node3D
	_character = get_node_or_null(character_path)


## 设置当前舞台的旋转角度，供 Tween 逐帧调用。
## [param progress] 线性进度，范围 0 到 1。
## [param start_angle] 起始角度，单位为弧度。
## [param target_angle] 目标角度，单位为弧度。
func _set_stage_rotation(progress: float, start_angle: float, target_angle: float) -> void:
	if _stage == null:
		return
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	_stage.rotation.y = lerpf(start_angle, target_angle, eased)


## 旋转完成时清除旋转锁。
func _on_stage_rotation_finished() -> void:
	_rotating = false


## 绑定 BGM，并在播放结束后退出进程。
func _bind_bgm() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return
	if _bgm != null and _bgm.finished.is_connected(_on_bgm_finished):
		_bgm.finished.disconnect(_on_bgm_finished)
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	if _bgm == null:
		push_warning("GlobalManager: 找不到 BGM 节点: %s" % bgm_path)
		return
	if not _bgm.finished.is_connected(_on_bgm_finished):
		_bgm.finished.connect(_on_bgm_finished)


## 确保歌词环已绑定。
func _ensure_lyric_ring() -> void:
	if _lyric_ring == null:
		_bind_lyric_ring()


## BGM 播放结束，退出进程。
func _on_bgm_finished() -> void:
	get_tree().quit()


## 转发歌词开始信号，并按配置每若干句触发一次舞台旋转。
func _on_line_spawned(index: int, time: float, text: String) -> void:
	lyric_line_started.emit(index, time, text)
	_line_count += 1
	if auto_rotate_with_lyrics and rotate_every_lines > 0:
		if _line_count % rotate_every_lines == 0:
			rotate_stage_and_switch_character()


## 转发歌词销毁信号。
func _on_line_destroyed(index: int, text: String) -> void:
	lyric_line_destroyed.emit(index, text)


## 转发播放完成信号。
func _on_playback_finished() -> void:
	lyrics_finished.emit()
