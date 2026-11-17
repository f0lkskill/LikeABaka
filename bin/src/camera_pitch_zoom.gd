extends Camera3D

## 摄像机 BGM 分段缩放控制器。
##
## 按 [member segment_duration] 分段统计 BGM 的频谱重心与峰值，
## 在段边界用 [member segment_transition_duration] 秒的缓动切换 FOV，
## 段内保持稳定，形成阶梯式镜头变化。
## [member zoom_strength_deg] 控制缩放幅度，[member transition_curve] 选择过渡曲线。
## 额外创建一条静音提前音轨，让 FOV 参数提前 [member lookahead_seconds] 秒读取。
## 不循环 BGM；BGM 播放结束后由 [GlobalManager] 退出进程。

## 用于主播放音频频谱分析的音频总线名称。
const ANALYZER_BUS := "BGM_Analyzer"
## 用于提前读取的静音音频总线名称。
const LOOKAHEAD_BUS := "BGM_Lookahead"
## 估算频谱重心时使用的频段边界，单位为赫兹。
const BANDS := [60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
## 按组循环的分段强调系数，用于形成连续数段的“大/小”段落。
const SEGMENT_ACCENTS := [1.0, -1.0, 0.5, -0.6, 0.8, -0.8]

## BGM 播放器节点路径，用于绑定分析和播放总线。
@export var bgm_path: NodePath = ^"../../BGM"
## 提前读取的音频秒数；会创建一条静音音轨专门用于分析未来音频。
@export_range(0.0, 3.0, 0.05) var lookahead_seconds: float = 1.0
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
@export var centroid_min_hz: float = 200.0
## 频谱重心映射上限，单位为赫兹。
@export var centroid_max_hz: float = 2000.0

@export_group("Camera Sway")
## 是否启用摄像机左右呼吸摇晃。
@export var sway_enabled: bool = true
## 左右平移距离，在摄像机竖直平面内移动。
@export_range(0.0, 5.0, 0.01) var sway_distance: float = 2.2
## 竖直方向的小幅起伏，与左右运动组成很小的莫比乌斯式循环。
@export_range(0.0, 2.0, 0.01) var sway_vertical_distance: float = 0.5
## 可选的极小滚转，增加环路的扭转感。
@export_range(0.0, 3.0, 0.01) var sway_roll_degrees: float = 0.25
## 可选的小幅偏航角度；0 表示只做平移摇头。
@export_range(0.0, 5.0, 0.01) var sway_degrees: float = 0.0
## 主呼吸周期，单位为秒。
@export_range(0.5, 30.0, 0.1) var sway_period: float = 6.0
## 次级波形强度，让运动不完全机械。
@export_range(0.0, 1.0, 0.01) var sway_secondary_strength: float = 0.35

## 当前 BGM 播放器。
var _bgm: AudioStreamPlayer
## 当前频谱分析器实例。
var _analyzer: AudioEffectSpectrumAnalyzerInstance
## 分析器所在总线索引，未初始化时为 -1。
var _bus_index: int = -1
## 提前读取用的静音播放器。
var _lookahead_player: AudioStreamPlayer
## 提前读取音轨的频谱分析器实例。
var _lookahead_analyzer: AudioEffectSpectrumAnalyzerInstance
## 提前读取音轨所在总线索引。
var _lookahead_bus_index: int = -1
## 初始 FOV，用作缩放基准。
var _base_fov: float
## 当前不受外部偏移影响的基础 FOV。
var _base_fov_current: float
## 外部事件叠加到 FOV 上的偏移角，单位为度。
@export_range(-60.0, 60.0, 0.1) var fov_offset_degrees: float = 0.0:
	set(value):
		fov_offset_degrees = value
		_fov_offset = value
		if is_node_ready():
			_apply_fov_value()
## 当前实际使用的 FOV 偏移缓存。
var _fov_offset: float = 0.0
## FOV 偏移的渐变 Tween。
var _fov_offset_tween: Tween
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
## 摄像机初始旋转，摇晃在此基础上叠加。
var _base_rotation: Vector3
## 摄像机初始本地位置。
var _base_position: Vector3
## 呼吸摇晃累计时间。
var _sway_time: float = 0.0


## 初始化基准 FOV、BGM 引用和分析器总线。
func _ready() -> void:
	_base_fov = fov
	_base_fov_current = fov
	_fov_from = fov
	_fov_to = fov
	_base_rotation = rotation
	_base_position = position
	_bgm = get_node_or_null(bgm_path) as AudioStreamPlayer
	_setup_analyzer_bus()
	_setup_lookahead()


## 给 FOV 叠加一个可正可负、带渐变的外部偏移。
## [param offset_degrees] 偏移角度；正数扩大 FOV，负数缩小 FOV，单位为度。
## [param duration] 渐变时长；小于等于 0 时立即应用。
func set_fov_offset(offset_degrees: float, duration: float = 0.5) -> void:
	if _fov_offset_tween != null and _fov_offset_tween.is_valid():
		_fov_offset_tween.kill()
	if duration <= 0.0:
		_set_fov_offset_value(offset_degrees)
		return
	_fov_offset_tween = create_tween()
	_fov_offset_tween.tween_method(
		_set_fov_offset_value,
		_fov_offset,
		offset_degrees,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 立即设置 FOV 偏移并刷新摄像机 FOV。
## [param value] 偏移角度，单位为度。
func _set_fov_offset_value(value: float) -> void:
	fov_offset_degrees = value


## 把基础 FOV 与外部偏移合并后写回 Camera3D。
func _apply_fov_value() -> void:
	fov = clampf(_base_fov_current + _fov_offset, 1.0, 179.0)


## 叠加轻微、非机械的摄像机呼吸摇摆。
## 左右为主，叠加很小的高度起伏和滚转，形成微型莫比乌斯式回路。
## [param delta] 本帧时间，单位为秒。
func _update_sway(delta: float) -> void:
	if not sway_enabled:
		position = _base_position
		rotation = _base_rotation
		return
	_sway_time += delta
	var period := maxf(sway_period, 0.001)
	var phase := _sway_time * TAU / period
	# 主波 + 次级波 + 很慢的漂移，避免完全周期性的机械感。
	var horizontal := sin(phase)
	horizontal += sin(phase * 1.618 + 1.1) * sway_secondary_strength
	horizontal += sin(phase * 0.37 + 0.5) * 0.15
	horizontal /= (1.0 + sway_secondary_strength + 0.15)
	var vertical := sin(phase * 2.0 + 0.9)
	var roll := sin(phase * 1.618 + 0.7)
	position = _base_position + Vector3(
		sway_distance * horizontal,
		sway_vertical_distance * vertical,
		0.0
	)
	rotation = Vector3(
		_base_rotation.x,
		_base_rotation.y + deg_to_rad(sway_degrees) * horizontal,
		_base_rotation.z + deg_to_rad(sway_roll_degrees) * roll
	)


## 累积当前分段的音频数据，并在到达段边界时更新目标 FOV。
## 这里只推进动画状态，不直接改变 FOV 数值。
## [param delta] 本帧时间，单位为秒。
func _process(delta: float) -> void:
	_update_sway(delta)
	_update_lookahead()
	_update_fov_transition(delta)
	_apply_fov_value()
	var use_lookahead := (
		_lookahead_analyzer != null
		and _lookahead_player != null
		and _lookahead_player.playing
	)
	var analyzer := _lookahead_analyzer if use_lookahead else _analyzer
	var bus_index := _lookahead_bus_index if use_lookahead else _bus_index
	if analyzer == null:
		return
	var centroid := _estimate_centroid(analyzer)
	var peak := clampf(
		db_to_linear(AudioServer.get_bus_peak_volume_left_db(bus_index, 0)),
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


## 让提前读取音轨保持领先主 BGM [member lookahead_seconds] 秒。
## 超出音频结尾后停止提前音轨，自动回退到主音轨分析。
func _update_lookahead() -> void:
	if _bgm == null or _lookahead_player == null or _bgm.stream == null:
		return
	if not _bgm.playing:
		return
	var expected := _bgm.get_playback_position() + lookahead_seconds
	if expected >= _bgm.stream.get_length() - 0.02:
		return
	if not _lookahead_player.playing:
		_lookahead_player.play(expected)
	elif absf(_lookahead_player.get_playback_position() - expected) > 0.15:
		_lookahead_player.seek(expected)


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
	_fov_from = _base_fov_current
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
		_base_fov_current = _fov_to
		return
	_transition_elapsed = minf(_transition_elapsed + delta, segment_transition_duration)
	var t := _transition_elapsed / segment_transition_duration
	_base_fov_current = lerpf(_fov_from, _fov_to, _ease_transition(t))


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


## 创建提前读取用的静音音轨和分析总线。
## 静音总线仍然会经过频谱效果器，但不会输出到听感中。
func _setup_lookahead() -> void:
	if _bgm == null:
		return
	var bus_index := AudioServer.get_bus_index(LOOKAHEAD_BUS)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, LOOKAHEAD_BUS)
		AudioServer.set_bus_send(bus_index, "Master")
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	if AudioServer.get_bus_effect_count(bus_index) == 0:
		var analyzer_effect := AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(bus_index, analyzer_effect)
	_lookahead_bus_index = bus_index
	_lookahead_analyzer = AudioServer.get_bus_effect_instance(bus_index, 0) as AudioEffectSpectrumAnalyzerInstance
	_lookahead_player = AudioStreamPlayer.new()
	_lookahead_player.name = "BGM_Lookahead"
	_lookahead_player.stream = _bgm.stream
	_lookahead_player.bus = LOOKAHEAD_BUS
	add_child(_lookahead_player)


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


## 用多个频段的能量加权估算指定分析器的频谱重心。
## [param analyzer] 要采样的频谱分析器实例。
## 返回频谱重心，单位为赫兹；无有效信号时返回 0。
func _estimate_centroid(analyzer: AudioEffectSpectrumAnalyzerInstance) -> float:
	if analyzer == null:
		return 0.0
	var weighted := 0.0
	var total := 0.0
	for i in BANDS.size() - 1:
		var low: float = BANDS[i]
		var high: float = BANDS[i + 1]
		var magnitude := analyzer.get_magnitude_for_frequency_range(low, high)
		var energy := maxf(magnitude.x, magnitude.y)
		if energy <= 0.0:
			continue
		weighted += sqrt(low * high) * energy
		total += energy
	if total <= 0.000001:
		return 0.0
	return weighted / total
