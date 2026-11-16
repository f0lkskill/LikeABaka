extends Camera3D

## 摄像机 BGM 分段缩放控制器。
##
## 按 [member segment_duration] 分段统计 BGM 的频谱重心与峰值，
## 在段边界用 [member segment_transition_duration] 秒的缓动切换 FOV，
## 段内保持稳定，形成阶梯式镜头变化。
## [member zoom_strength_deg] 控制缩放幅度，[member transition_curve] 选择过渡曲线。
## 不循环 BGM；BGM 播放结束后由 [GlobalManager] 退出进程。

## 用于频谱分析的音频总线名称。
const ANALYZER_BUS := "BGM_Analyzer"
## 估算频谱重心时使用的频段边界，单位为赫兹。
const BANDS := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
## 按组循环的分段强调系数，用于形成连续数段的“大/小”段落。
const SEGMENT_ACCENTS := [1.0, -1.0, 0.5, -0.6, 0.8, -0.8]

## BGM 播放器节点路径，用于绑定分析和播放总线。
@export var bgm_path: NodePath = ^"../../BGM"
## 音调/能量对 FOV 的最大偏移角度。
@export_range(0.0, 120.0, 0.5) var zoom_strength_deg: float = 75.0
## 每段持续时间；段内 FOV 保持不变。
@export_range(0.2, 8.0, 0.1) var segment_duration: float = 1.0
## 段边界 FOV 过渡时长；设为 0 时直接跳变。
@export_range(0.0, 2.0, 0.05) var segment_transition_duration: float = 0.6
## 段间缓动曲线：Smoothstep、Inverted Check 或 Sine。
@export_enum("Smoothstep", "Inverted Check", "Sine") var transition_curve: int = 1
## 总线峰值能量在分段目标中的权重。
@export_range(0.0, 1.0, 0.05) var energy_weight: float = 0.15
## 分段强调幅度；会按 [member accent_group_size] 连续作用数段。
@export_range(0.0, 0.3, 0.01) var segment_accent: float = 0.12
## 每个强调组包含的分段数；越大，“大/小”段落持续越久。
@export_range(1, 8, 1) var accent_group_size: int = 3
## 频谱重心映射下限，单位为赫兹。
@export var centroid_min_hz: float = 500.0
## 频谱重心映射上限，单位为赫兹。
@export var centroid_max_hz: float = 2000.0

## 当前 BGM 播放器。
var _bgm: AudioStreamPlayer
## 当前频谱分析器实例。
var _analyzer: AudioEffectSpectrumAnalyzerInstance
## 分析器所在总线索引，未初始化时为 -1。
var _bus_index: int = -1
## 初始 FOV，用作缩放基准。
var _base_fov: float
## 当前分段已经过的时间。
var _segment_elapsed: float = 0.0
## 已完成的分段数量，也用于强调分组。
var _segment_count: int = 0
## 当前分段内频谱重心的累计值。
var _centroid_sum: float = 0.0
## 当前分段内总线峰值的最大值。
var _peak_max: float = 0.0
## 当前分段内有效采样数量。
var _sample_count: int = 0
## 当前段过渡的起始 FOV。
var _fov_from: float = 75.0
## 当前段过渡的目标 FOV。
var _fov_to: float = 75.0
## 当前段过渡已经过的时间。
var _transition_elapsed: float = 0.0


## 初始化基准 FOV、BGM 引用和分析器总线。
func _ready() -> void:
	_base_fov = fov
	_fov_from = fov
	_fov_to = fov
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	_setup_analyzer_bus()


## 累积当前分段的音频数据，并在到达段边界时更新目标 FOV。
## 段内只推进过渡动画，不改变目标值。
## [param delta] 距上一帧的时间，单位为秒。
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


## 根据一段音频的平均重心与峰值计算新的 FOV 目标。
## [param average_centroid] 该段频谱重心的平均值，单位为赫兹。
## [param average_peak] 该段总线峰值的最大值，范围 0 到 1。
func _apply_segment(average_centroid: float, average_peak: float) -> void:
	var tone := clampf(
		inverse_lerp(centroid_min_hz, maxf(centroid_max_hz, centroid_min_hz + 1.0), average_centroid),
		0.0,
		1.0
	)
	var energy := clampf(average_peak, 0.0, 1.0)
	var accent_group := int(_segment_count / float(maxi(accent_group_size, 1)))
	var accent: float = float(SEGMENT_ACCENTS[accent_group % SEGMENT_ACCENTS.size()]) * segment_accent
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


## 推进段边界之间的 FOV 过渡。
## [param delta] 距上一帧的时间，单位为秒。
func _update_fov_transition(delta: float) -> void:
	if segment_transition_duration <= 0.0:
		fov = _fov_to
		return
	_transition_elapsed = minf(_transition_elapsed + delta, segment_transition_duration)
	var t := _transition_elapsed / segment_transition_duration
	fov = lerpf(_fov_from, _fov_to, _ease_transition(t))


## 将线性时间比例转换为段间缓动值。
## Inverted Check 前段靠近目标、尾段缓慢收束，适合更平缓的镜头变化。
## [param t] 线性时间比例，范围 0 到 1。
## 返回缓动后的时间比例。
func _ease_transition(t: float) -> float:
	match transition_curve:
		1:
			return 1.0 - pow(1.0 - t, 3.0)
		2:
			return 0.5 - 0.5 * cos(PI * t)
		_:
			return t * t * (3.0 - 2.0 * t)


## 创建或复用 [constant ANALYZER_BUS]，并绑定 BGM 到该总线。
## 若律动条脚本已经创建总线，则直接复用其分析器实例。
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


## 用多个频段的能量加权估算当前 BGM 的频谱重心。
## 返回频谱重心，单位为赫兹；无有效信号时返回 0。
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
