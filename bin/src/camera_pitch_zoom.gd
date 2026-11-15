extends Camera3D

## 每次新歌词出现时采样 BGM 的频谱重心，用一次短促的 FOV 过渡表现音调变化。
## 不再每帧持续缩放，避免产生不必要的“呼吸”效果。

const ANALYZER_BUS := "BGM_Analyzer"
const BANDS := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]

@export var bgm_path: NodePath = ^"../../BGM"
@export var lyric_ring_path: NodePath = ^"../../LyricRing"
@export_range(0.0, 30.0, 0.5) var zoom_strength_deg: float = 20.0
@export_range(0.05, 2.0, 0.05) var zoom_duration: float = 0.35
## 当前 BGM 短于歌词时间轴，循环后分析器才能在歌词段持续获得输入。
@export var loop_bgm: bool = true

var _bgm: AudioStreamPlayer
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _base_fov: float
var _zoom_tween: Tween
var _zoom_token: int = 0


func _ready() -> void:
	_base_fov = fov
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	_setup_analyzer_bus()
	if loop_bgm and _bgm != null:
		_bgm.finished.connect(_restart_bgm)
	var lyric_ring := get_node_or_null(lyric_ring_path)
	if lyric_ring != null and lyric_ring.has_signal("line_spawned"):
		lyric_ring.line_spawned.connect(_on_line_spawned)


func _on_line_spawned(_index: int, _time: float, _text: String) -> void:
	_zoom_token += 1
	var token := _zoom_token
	# 等待一个短缓冲，确保第一句也能拿到分析器数据。
	await get_tree().create_timer(0.06).timeout
	if token != _zoom_token or not is_inside_tree():
		return
	var centroid := _estimate_centroid()
	if centroid <= 0.0:
		return
	var tone := clampf(inverse_lerp(1400.0, 1900.0, centroid), 0.0, 1.0)
	var target_fov := clampf(
		_base_fov - (tone - 0.5) * zoom_strength_deg,
		30.0,
		100.0
	)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "fov", target_fov, zoom_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _restart_bgm() -> void:
	if _bgm != null:
		_bgm.play()


func _setup_analyzer_bus() -> void:
	var bus_index := AudioServer.get_bus_index(ANALYZER_BUS)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, ANALYZER_BUS)
		AudioServer.set_bus_send(bus_index, "Master")
	if AudioServer.get_bus_effect_count(bus_index) == 0:
		var analyzer_effect := AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_index, analyzer_effect)
	_analyzer = AudioServer.get_bus_effect_instance(bus_index, 0) as AudioEffectSpectrumAnalyzerInstance
	if _bgm != null:
		_bgm.bus = ANALYZER_BUS


func _estimate_centroid() -> float:
	if _analyzer == null:
		return 0.0
	var weighted := 0.0
	var total := 0.0
	for i in BANDS.size() - 1:
		var low: float = BANDS[i]
		var high: float = BANDS[i + 1]
		var magnitude := _analyzer.get_magnitude_for_frequency_range(low, high)
		var energy := maxf(magnitude.x, magnitude.y)
		if energy <= 0.0:
			continue
		weighted += sqrt(low * high) * energy
		total += energy
	if total <= 0.000001:
		return 0.0
	return weighted / total
