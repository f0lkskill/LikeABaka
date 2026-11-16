extends Camera3D

## 按 BGM 分段采样音调与能量，在段边界直接切换 FOV。
## 段内保持不变，形成更有张力的阶梯式镜头变化；不循环 BGM。

const ANALYZER_BUS := "BGM_Analyzer"
const BANDS := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
const SEGMENT_ACCENTS := [1.0, -0.8, 0.4, -1.0]

@export var bgm_path: NodePath = ^"../../BGM"
@export_range(0.0, 90.0, 0.5) var zoom_strength_deg: float = 60.0
@export_range(0.2, 8.0, 0.1) var segment_duration: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_transition_duration: float = 0.35
@export_range(0.0, 1.0, 0.05) var energy_weight: float = 0.15
@export_range(0.0, 0.3, 0.01) var segment_accent: float = 0.12
@export var centroid_min_hz: float = 500.0
@export var centroid_max_hz: float = 2000.0

var _bgm: AudioStreamPlayer
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _bus_index: int = -1
var _base_fov: float
var _segment_elapsed: float = 0.0
var _segment_count: int = 0
var _centroid_sum: float = 0.0
var _peak_max: float = 0.0
var _sample_count: int = 0
var _fov_from: float = 75.0
var _fov_to: float = 75.0
var _transition_elapsed: float = 0.0


func _ready() -> void:
	_base_fov = fov
	_fov_from = fov
	_fov_to = fov
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	_setup_analyzer_bus()


func _process(delta: float) -> void:
	if _analyzer == null:
		return
	var centroid := _estimate_centroid()
	var peak := clampf(
		db_to_linear(AudioServer.get_bus_peak_volume_left_db(_bus_index, 0)),
		0.0,
		1.0
	)
	# 第一段稍短，避免开场长时间没有变化。
	var target_duration := segment_duration if _segment_count > 0 else minf(segment_duration, 0.6)
	_segment_elapsed += delta
	if centroid > 0.0:
		_centroid_sum += centroid
		_peak_max = maxf(_peak_max, peak)
		_sample_count += 1
	if _segment_elapsed >= target_duration:
		if _sample_count > 0:
			_apply_segment(_centroid_sum / _sample_count, _peak_max)
		_segment_elapsed = 0.0
		_centroid_sum = 0.0
		_peak_max = 0.0
		_sample_count = 0
		_segment_count += 1
	_update_fov_transition(delta)


func _apply_segment(average_centroid: float, average_peak: float) -> void:
	var tone := clampf(
		inverse_lerp(centroid_min_hz, maxf(centroid_max_hz, centroid_min_hz + 1.0), average_centroid),
		0.0,
		1.0
	)
	var energy := clampf(average_peak, 0.0, 1.0)
	var accent: float = float(SEGMENT_ACCENTS[_segment_count % SEGMENT_ACCENTS.size()]) * segment_accent
	var value := clampf(
		tone * (1.0 - energy_weight) + energy * energy_weight + accent,
		0.0,
		1.0
	)
	_fov_from = fov
	_fov_to = clampf(
		_base_fov - (value - 0.5) * zoom_strength_deg,
		30.0,
		100.0
	)
	_transition_elapsed = 0.0


## 段边界之间用短暂缓动过渡，避免硬切；过渡结束后保持到下一段。
func _update_fov_transition(delta: float) -> void:
	if segment_transition_duration <= 0.0:
		fov = _fov_to
		return
	_transition_elapsed = minf(_transition_elapsed + delta, segment_transition_duration)
	var t := _transition_elapsed / segment_transition_duration
	var eased := t * t * (3.0 - 2.0 * t)
	fov = lerpf(_fov_from, _fov_to, eased)



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
	_bus_index = bus_index
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
