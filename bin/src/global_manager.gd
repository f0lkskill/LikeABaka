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

## 当前绑定的歌词环模板。
var _lyric_ring: LyricRing


## 初始化并绑定歌词环模板。
func _ready() -> void:
	_bind_lyric_ring()


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


## 确保歌词环已绑定。
func _ensure_lyric_ring() -> void:
	if _lyric_ring == null:
		_bind_lyric_ring()


## 转发歌词开始信号。
func _on_line_spawned(index: int, time: float, text: String) -> void:
	lyric_line_started.emit(index, time, text)


## 转发歌词销毁信号。
func _on_line_destroyed(index: int, text: String) -> void:
	lyric_line_destroyed.emit(index, text)


## 转发播放完成信号。
func _on_playback_finished() -> void:
	lyrics_finished.emit()
