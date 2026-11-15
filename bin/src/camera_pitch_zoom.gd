extends Camera3D

## 实时采样 BGM 的频谱重心，持续微调摄像机 FOV。
## 不循环 BGM；BGM 结束后频谱静音，镜头会自然停在当前状态。

const ANALYZER_BUS := "BGM_Analyzer"
const BANDS := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]

@export var bgm_path: NodePath = ^"../../BGM"
@export_range(0.0, 30.0, 0.5) var zoom_strength_deg: float = 24.0
@export_range(0.5, 30.0, 0.1) var response_speed: float = 8.0

var _bgm: AudioStreamPlayer
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _base_fov: float
var _smoothed_centroid: float = 1500.0


func _ready() -> void:
	_base_fov = fov
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	_setup_analyzer_bus()


func _process(delta: float) -> void:
	if _analyzer == null:
		return
	var centroid := _estimate_centroid()
	if centroid > 0.0:
		_smoothed_centroid = lerpf(
			_smoothed_centroid,
			centroid,
			clampf(delta * response_speed, 0.0, 1.0)
		)
	var tone := clampf(inverse_lerp(1400.0, 1900.0, _smoothed_centroid), 0.0, 1.0)
	var target_fov := clampf(
		_base_fov - (tone - 0.5) * zoom_strength_deg,
		30.0,
		100.0
	)
	fov = lerpf(fov, target_fov, clampf(delta * response_speed, 0.0, 1.0))


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
