@tool
## 圆柱歌词环模板。
##
## 从 LRC 文件读取时间轴歌词，在圆柱表面逐行生成文字。
## 每个歌词行按时间出现，随文字环一起滚动；滚动半圈后自动销毁。
## 所有外观、尺寸与运动参数都可以通过导出属性或公开方法配置。
class_name LyricRing
extends Node3D

## 一条歌词开始显示时发出。
signal line_spawned(index: int, time: float, text: String)
## 一条歌词转到镜头不可见半圈并被销毁时发出。
signal line_destroyed(index: int, text: String)
## 全部歌词播放完毕且没有活动歌词时发出。
signal playback_finished

## 一条正在显示的歌词。
class ActiveLine:
	var index: int = -1
	var text: String = ""
	var node: Node3D
	var labels: Array[Label3D] = []
	var depth_labels: Array[Label3D] = []
	var start_angle_deg: float = 0.0
	var scroll_direction: float = 1.0
	var angular_span_deg: float = 0.0
	var travel_deg: float = 0.0
	var speed_deg: float = 0.0
	var destroy_travel_deg: float = 180.0
	var elapsed: float = 0.0
	var move_duration: float = 1.0
	var lane: int = 0
	var vertical_offset: float = 0.0

@export_group("Source")
## 作为文字环尺寸基准的圆柱网格节点路径。
@export var stage_mesh_path: NodePath = ^"../stage/CollisionShape3D/MeshInstance3D":
	set(value):
		stage_mesh_path = value
		if is_node_ready():
			_resolve_mesh()
			_apply_layout()
## LRC 歌词文件路径。
@export_file("*.txt") var lyrics_path: String = "res://bin/data/song.txt":
	set(value):
		lyrics_path = value
		if is_node_ready():
			load_lyrics()
			if Engine.is_editor_hint():
				_show_editor_preview()
			elif auto_play:
				play()
## 歌词时间轴起点，单位为秒；默认从 0 秒开始。
@export var start_time: float = 0.0:
	set(value):
		start_time = value
		if is_node_ready() and Engine.is_editor_hint():
			_show_editor_preview()
## 是否在场景就绪后自动播放歌词。
@export var auto_play: bool = true

@export_group("Text Style")
## 自定义字体；留空时使用支持中日文的系统字体。
@export var font: Font:
	set(value):
		font = value
		_refresh_active_styles()
## 是否使用粗体；系统字体直接使用粗体字重，自定义字体使用加粗变体。
@export var bold: bool = true:
	set(value):
		bold = value
		if _fallback_font != null:
			_fallback_font.font_weight = 700 if bold else 400
		_custom_font_variation = null
		_refresh_active_styles()
@export_range(1, 512, 1) var font_size: int = 224:
	set(value):
		font_size = value
		_refresh_active_styles()
## 每个字体像素对应的世界尺寸。
@export var pixel_size: float = 0.035:
	set(value):
		pixel_size = value
		_refresh_active_styles()
## 文字颜色。
@export var text_color: Color = Color(1, 1, 1, 1):
	set(value):
		text_color = value
		_refresh_active_styles()
## 文字描边宽度。
@export_range(0, 64, 1) var outline_size: int = 36:
	set(value):
		outline_size = value
		_refresh_active_styles()
## 文字描边颜色。
@export var outline_color: Color = Color(0, 0, 0, 1):
	set(value):
		outline_color = value
		_refresh_active_styles()
## 3D 文字厚度；通过多层暗色背面文字模拟挤出效果。
@export_range(0.0, 3.0, 0.05) var text_depth: float = 1.2:
	set(value):
		text_depth = maxf(0.0, value)
		if is_node_ready():
			for line in _active_lines:
				_create_depth_labels(line)
			_apply_layout()
## 3D 文字厚度层数；越高越平滑，但节点也越多。
@export_range(0, 12, 1) var text_depth_layers: int = 8:
	set(value):
		text_depth_layers = maxi(0, value)
		if is_node_ready():
			for line in _active_lines:
				_create_depth_labels(line)
			_apply_layout()
## 3D 文字背面的颜色。
@export var text_depth_color: Color = Color(0.12, 0.12, 0.12, 1):
	set(value):
		text_depth_color = value
		_refresh_depth_styles()
## 是否双面显示文字。
@export var double_sided: bool = false:
	set(value):
		double_sided = value
		_refresh_active_styles()

@export_group("Ring")
## 相对圆柱半径的偏移量；正值向外，负值向内。
@export var radius_padding: float = -0.2:
	set(value):
		radius_padding = value
		_apply_layout()
## 第一层歌词相对圆柱顶面的垂直偏移。
@export var vertical_offset: float = 6.5:
	set(value):
		vertical_offset = value
		_apply_vertical_lanes()
## 垂直方向可同时容纳的歌词层数；新歌词会占用空层。
@export_range(1, 16, 1) var vertical_lane_count: int = 4:
	set(value):
		vertical_lane_count = maxi(1, value)
		_normalize_lanes()
## 相邻歌词层之间的垂直间距。
@export var line_vertical_spacing: float = 9.8:
	set(value):
		line_vertical_spacing = value
		_apply_vertical_lanes()
## 椭圆缩放，X/Z 分别控制两个轴向的半径倍率。
@export var ellipse_scale: Vector2 = Vector2(1, 1):
	set(value):
		ellipse_scale = value
		_apply_layout()
## 文字是否朝向圆柱内部。
@export var face_inward: bool = true:
	set(value):
		face_inward = value
		_apply_layout()
## 每个字符沿圆周占用的世界空间弧长；越大歌词越舒展。
@export var character_spacing: float = 6.4:
	set(value):
		character_spacing = value
		_apply_layout()
## 歌词进入文字环时的参考中心角度，单位为度；反向歌词从对侧进入。
@export_range(0.0, 360.0, 0.1) var entry_angle_deg: float = 90.0
## 屏幕外的额外角度余量，确保歌词在画面外生成和销毁。
@export_range(0.0, 90.0, 0.1) var offscreen_margin_deg: float = 8.0
## 可见半圈的角度；歌词从一侧屏幕外滚到另一侧屏幕外。
@export_range(1.0, 720.0, 1.0) var destroy_after_degrees: float = 180.0:
	set(value):
		destroy_after_degrees = value
## 是否让相邻歌词交替反向滚动。
@export var alternate_direction: bool = true

@export_group("Timing")
## 在下一句出现前提前多少秒完成滚动。
@export var finish_lead_time: float = 0.0:
	set(value):
		finish_lead_time = maxf(0.0, value)
## 最后一句没有下一句时间时使用的滚动时长，单位为秒。
@export var fallback_duration: float = 4.0:
	set(value):
		fallback_duration = maxf(0.1, value)
## 单句滚动时长上限；下一句间隔很长时，歌词会提前滚完并消失。
@export_range(0.1, 10.0, 0.1) var max_line_duration: float = 4.2:
	set(value):
		max_line_duration = maxf(0.1, value)
## 单句滚动时长下限，避免极短间隔时歌词滚得过快。
@export_range(0.1, 5.0, 0.1) var min_line_duration: float = 0.6:
	set(value):
		min_line_duration = clampf(value, 0.1, max_line_duration)
## 允许与下一句重叠的时长，让整体滚动更慢，但冲突时间不会太长。
@export_range(0.0, 1.5, 0.05) var max_overlap_time: float = 0.35:
	set(value):
		max_overlap_time = maxf(0.0, value)
## 滚动曲线的缓动方式：线性、正弦、三次、五次。
@export_enum("Linear", "Sine", "Cubic", "Quint") var easing_mode: int = 2
## 生成后的淡入时长，单位为秒；过早结束时会自动缩短。
@export_range(0.0, 2.0, 0.05) var fade_in_duration: float = 0.5:
	set(value):
		fade_in_duration = maxf(0.0, value)
## 销毁前的淡出时长，单位为秒；过早结束时会自动缩短。
@export_range(0.0, 2.0, 0.05) var fade_out_duration: float = 0.5:
	set(value):
		fade_out_duration = maxf(0.0, value)
## 单句最多滚动的角度；限制在一圈以内，避免尾句再次绕回正面。
@export_range(90.0, 359.0, 1.0) var max_travel_degrees: float = 330.0:
	set(value):
		max_travel_degrees = clampf(value, 90.0, 359.0)
## 滚动速度下限，单位为度/秒。
@export_range(0.0, 720.0, 1.0) var min_scroll_speed_deg: float = 0.0:
	set(value):
		min_scroll_speed_deg = maxf(0.0, value)
## 滚动速度上限，单位为度/秒；达到上限时允许歌词与下一句少量重叠。
@export_range(1.0, 1440.0, 1.0) var max_scroll_speed_deg: float = 1440.0:
	set(value):
		max_scroll_speed_deg = maxf(min_scroll_speed_deg, value)

## 解析后的歌词时间轴，每项包含 time 和 text。
var _entries: Array[Dictionary] = []
## 当前活动的歌词行。
var _active_lines: Array[ActiveLine] = []
## 舞台圆柱网格。
var _mesh_instance: MeshInstance3D
## 缺省中文字体，仅在 font 为空时使用。
var _fallback_font: SystemFont
## 自定义字体的粗体变体缓存。
var _custom_font_variation: FontVariation
## 粗体变体对应的原始字体。
var _custom_font_source: Font
## 歌词时间轴时钟，单位为秒。
var _clock: float = 0.0
## 下一条待生成歌词的索引。
var _next_index: int = 0
## 是否正在播放歌词。
var _playing: bool = false
## 是否已经发出播放完成信号。
var _finished_emitted: bool = false
## 已生成歌词序号，用于决定是否反向滚动。
var _spawn_serial: int = 0
## 下一条歌词优先使用的垂直层，实现逐层向上循环。
var _lane_cursor: int = 0


## 初始化节点并在运行或编辑器预览中显示歌词。
func _ready() -> void:
	_resolve_mesh()
	load_lyrics()
	if Engine.is_editor_hint():
		_show_editor_preview()
	elif auto_play:
		play()


## 每帧推进歌词时间与各自滚动角度，并销毁已经离开可见半圈的歌词。
## [param delta] 距上一帧的时间，单位为秒。
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _playing:
		return
	_clock += delta
	for line in _active_lines:
		line.elapsed += delta
		var progress := clampf(line.elapsed / maxf(line.move_duration, 0.01), 0.0, 1.0)
		var eased := _ease_progress(progress)
		line.travel_deg = line.destroy_travel_deg * eased
		_apply_line_alpha(line)
	# 先销毁到达终点的歌词，再生成下一句，避免新旧歌词在同一帧重叠。
	_destroy_finished_lines()
	_spawn_due_lines()
	_apply_layout()
	if _active_lines.is_empty() and _next_index >= _entries.size():
		_playing = false
		if not _finished_emitted:
			_finished_emitted = true
			playback_finished.emit()


## 载入 LRC 歌词文件。
## [param path] 可选的新路径；传入后会同时更新 [member lyrics_path]。
## 返回是否成功解析出至少一条歌词。
func load_lyrics(path: String = "") -> bool:
	if not path.is_empty():
		lyrics_path = path
	_entries.clear()
	_clear_active_lines()
	_playing = false
	_finished_emitted = false
	_spawn_serial = 0
	_lane_cursor = 0
	var file := FileAccess.open(lyrics_path, FileAccess.READ)
	if file == null:
		push_error("LyricRing: 无法打开歌词文件: %s" % lyrics_path)
		return false
	var source := file.get_as_text()
	file.close()
	_entries = _parse_lrc(source)
	if _entries.is_empty():
		push_warning("LyricRing: 歌词文件没有有效时间轴: %s" % lyrics_path)
		return false
	return true


## 直接传入歌词时间轴，适合由其他系统动态生成歌词。
## [param entries] 每一项为包含 time（秒）和 text（歌词）的字典。
func set_lyrics(entries: Array) -> void:
	_entries.clear()
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var time := float(entry.get("time", 0.0))
		var text := str(entry.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		_entries.append({"time": time, "text": text})
	_entries.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	_playing = false
	_finished_emitted = false
	_spawn_serial = 0
	_lane_cursor = 0
	_clock = start_time
	_next_index = _find_index_at_or_after(start_time)
	_clear_active_lines()
	if Engine.is_editor_hint():
		_show_editor_preview()


## 从指定时间开始播放歌词。
## [param from_time] 起始秒数；小于 0 时使用 [member start_time]。
func play(from_time: float = -1.0) -> void:
	if _entries.is_empty() and not load_lyrics():
		return
	if from_time < 0.0:
		from_time = start_time
	_clear_active_lines()
	_clock = maxf(0.0, from_time)
	_next_index = _find_index_at_or_after(_clock)
	_finished_emitted = false
	_spawn_serial = 0
	_lane_cursor = 0
	_playing = true


## 暂停歌词时间轴；当前歌词保持显示但停止滚动。
func pause() -> void:
	_playing = false


## 停止播放并清空所有活动歌词。
func stop() -> void:
	_playing = false
	_clear_active_lines()
	_clock = start_time
	_next_index = _find_index_at_or_after(start_time)
	_finished_emitted = false
	_spawn_serial = 0
	_lane_cursor = 0


## 跳转到指定时间；播放状态保持不变。
## [param time] 目标秒数。
func seek(time: float) -> void:
	_clock = maxf(0.0, time)
	_next_index = _find_index_at_or_after(_clock)
	_clear_active_lines()
	_finished_emitted = false
	_spawn_serial = 0
	_lane_cursor = 0


## 清空当前显示的所有歌词，但保留已解析的时间轴。
func clear() -> void:
	_playing = false
	_clear_active_lines()
	_spawn_serial = 0
	_lane_cursor = 0


## 清空歌词时间轴和当前显示内容。
func clear_lyrics() -> void:
	_entries.clear()
	clear()


## 是否正在播放歌词。
func is_playing() -> bool:
	return _playing


## 当前歌词时间轴时钟，单位为秒。
func get_playback_time() -> float:
	return _clock


## 当前最新活动歌词的文本；没有活动歌词时返回空字符串。
func get_current_text() -> String:
	if _active_lines.is_empty():
		return ""
	return _active_lines[_active_lines.size() - 1].text


## 当前活动歌词行数。
func get_active_line_count() -> int:
	return _active_lines.size()


## 已解析的歌词条数。
func get_lyric_count() -> int:
	return _entries.size()


## 返回歌词时间轴副本。
func get_lyrics() -> Array[Dictionary]:
	return _entries.duplicate(true)


## 批量设置文字样式，适合运行时换肤或外部参数注入。
func set_text_style(
	new_font: Font,
	new_font_size: int,
	new_pixel_size: float,
	new_text_color: Color,
	new_outline_size: int,
	new_outline_color: Color
) -> void:
	font = new_font
	font_size = new_font_size
	pixel_size = new_pixel_size
	text_color = new_text_color
	outline_size = new_outline_size
	outline_color = new_outline_color


## 批量设置文字环几何参数，适合运行时根据舞台尺寸调整。
func configure_ring(
	new_radius_padding: float,
	new_vertical_offset: float,
	new_ellipse_scale: Vector2,
	new_face_inward: bool,
	new_character_spacing: float
) -> void:
	radius_padding = new_radius_padding
	vertical_offset = new_vertical_offset
	ellipse_scale = new_ellipse_scale
	face_inward = new_face_inward
	character_spacing = new_character_spacing


## 批量设置滚动时间参数。
func configure_timing(
	new_finish_lead_time: float,
	new_fallback_duration: float,
	new_min_speed_deg: float,
	new_max_speed_deg: float,
	new_destroy_after_degrees: float
) -> void:
	finish_lead_time = new_finish_lead_time
	fallback_duration = new_fallback_duration
	min_scroll_speed_deg = new_min_speed_deg
	max_scroll_speed_deg = new_max_speed_deg
	destroy_after_degrees = new_destroy_after_degrees


## 解析 LRC 文本，返回按时间排序的歌词条目。
## [param source] LRC 文件内容。
func _parse_lrc(source: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var regex := RegEx.new()
	var error := regex.compile("^\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\]\\s*(.*)$")
	if error != OK:
		push_error("LyricRing: LRC 正则表达式编译失败")
		return entries
	for raw_line in source.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var result := regex.search(line)
		if result == null:
			continue
		var minutes := int(result.get_string(1))
		var seconds := int(result.get_string(2))
		var fraction := result.get_string(3)
		var time := float(minutes * 60 + seconds)
		if not fraction.is_empty():
			time += float("0." + fraction)
		var text := result.get_string(4).strip_edges()
		if text.is_empty():
			continue
		entries.append({"time": time, "text": text})
	entries.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	return entries


## 返回第一条时间大于等于 [param time] 的歌词索引。
func _find_index_at_or_after(time: float) -> int:
	for i in _entries.size():
		if float(_entries[i]["time"]) >= time - 0.0001:
			return i
	return _entries.size()


## 生成所有已经到达时间的歌词行。
func _spawn_due_lines() -> void:
	while _next_index < _entries.size():
		var entry := _entries[_next_index]
		if float(entry["time"]) > _clock + 0.0001:
			break
		_spawn_line(_next_index, entry)
		_next_index += 1


## 生成一条歌词行。
## [param index] 歌词在时间轴中的索引。
## [param entry] 包含 time 和 text 的歌词数据。
func _spawn_line(index: int, entry: Dictionary) -> void:
	var text := str(entry.get("text", ""))
	if text.is_empty():
		return
	var line := ActiveLine.new()
	line.index = index
	line.text = text
	# 默认在下一句出现前滚完；间隔过长时按上限提前结束，避免缓慢绕圈。
	var start_time := float(entry.get("time", 0.0))
	var next_time := start_time + fallback_duration
	if index + 1 < _entries.size():
		next_time = float(_entries[index + 1]["time"])
	var finish_time := next_time - finish_lead_time
	if finish_time <= start_time:
		finish_time = next_time
	var available := maxf(0.05, finish_time - start_time)
	var allowed_duration := available + max_overlap_time
	var duration := clampf(allowed_duration, min_line_duration, max_line_duration)
	var span_deg := _get_step_deg() * float(maxi(0, text.length() - 1))
	line.angular_span_deg = span_deg
	# 整行从一侧屏幕外移动到另一侧屏幕外，需要额外走过左右余量和整行宽度。
	line.destroy_travel_deg = minf(
		destroy_after_degrees + offscreen_margin_deg * 2.0 + span_deg,
		max_travel_degrees
	)
	var average_speed := line.destroy_travel_deg / maxf(duration, 0.01)
	if average_speed > max_scroll_speed_deg:
		duration = line.destroy_travel_deg / maxf(max_scroll_speed_deg, 0.01)
	if min_scroll_speed_deg > 0.0 and average_speed < min_scroll_speed_deg:
		duration = line.destroy_travel_deg / min_scroll_speed_deg
	duration = clampf(duration, 0.05, max_line_duration)
	line.move_duration = minf(duration, allowed_duration)
	line.speed_deg = line.destroy_travel_deg / maxf(line.move_duration, 0.01)
	line.elapsed = 0.0
	line.travel_deg = 0.0
	# 相邻歌词交替反向：第一行向角度增大方向滚动，第二行向反方向滚动。
	var reverse := alternate_direction and (_spawn_serial % 2 == 1)
	_spawn_serial += 1
	line.scroll_direction = -1.0 if reverse else 1.0
	var half_span := span_deg * 0.5
	if reverse:
		line.start_angle_deg = entry_angle_deg + 180.0 + offscreen_margin_deg + half_span
	else:
		line.start_angle_deg = entry_angle_deg - offscreen_margin_deg - half_span
	line.lane = _claim_lane()
	line.vertical_offset = vertical_offset + float(line.lane) * line_vertical_spacing
	line.node = Node3D.new()
	line.node.name = "LyricLine_%04d" % index
	add_child(line.node)
	for i in text.length():
		var label := Label3D.new()
		label.text = text.substr(i, 1)
		_apply_style_to_label(label)
		line.node.add_child(label)
		line.labels.append(label)
	_create_depth_labels(line)
	_apply_line_alpha(line)
	_active_lines.append(line)
	line_spawned.emit(index, start_time, text)


## 将当前样式应用到一个字符标签。
func _apply_style_to_label(label: Label3D) -> void:
	var resolved_font := _get_font()
	if resolved_font != null:
		label.font = resolved_font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = text_color
	label.outline_size = outline_size
	label.outline_modulate = outline_color
	label.shaded = false
	label.double_sided = double_sided
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## 为一条歌词创建背面厚度层，形成 3D 挤出效果。
func _create_depth_labels(line: ActiveLine) -> void:
	for label in line.depth_labels:
		if is_instance_valid(label):
			label.queue_free()
	line.depth_labels.clear()
	if text_depth <= 0.0 or text_depth_layers <= 0:
		return
	for front_label in line.labels:
		for layer in text_depth_layers:
			var depth_label := Label3D.new()
			depth_label.text = front_label.text
			_apply_depth_style_to_label(depth_label)
			line.node.add_child(depth_label)
			line.depth_labels.append(depth_label)


## 将厚度层样式应用到一个背面字符标签。
func _apply_depth_style_to_label(label: Label3D) -> void:
	var resolved_font := _get_font()
	if resolved_font != null:
		label.font = resolved_font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = text_depth_color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = double_sided
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## 刷新所有活动歌词的厚度层样式。
func _refresh_depth_styles() -> void:
	if not is_node_ready():
		return
	for line in _active_lines:
		for label in line.depth_labels:
			_apply_depth_style_to_label(label)


## 按滚动进度计算缓动后的时间比例。
func _ease_progress(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match easing_mode:
		1:
			return 0.5 - 0.5 * cos(PI * t)
		2:
			return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5
		3:
			return 16.0 * t * t * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 5.0) * 0.5
		_:
			return t


## 根据已播放时间应用淡入淡出透明度。
func _apply_line_alpha(line: ActiveLine) -> void:
	var in_duration := minf(fade_in_duration, line.move_duration * 0.5)
	var out_duration := minf(fade_out_duration, line.move_duration * 0.5)
	var alpha := 1.0
	if in_duration > 0.0:
		alpha = minf(alpha, line.elapsed / in_duration)
	if out_duration > 0.0:
		alpha = minf(alpha, (line.move_duration - line.elapsed) / out_duration)
	alpha = clampf(alpha, 0.0, 1.0)
	var color := text_color
	color.a *= alpha
	var outline := outline_color
	outline.a *= alpha
	for label in line.labels:
		label.modulate = color
		label.outline_modulate = outline
	var depth := text_depth_color
	depth.a *= alpha
	for label in line.depth_labels:
		label.modulate = depth


## 返回可用字体；未指定字体时回退到支持中日文的系统字体。
func _get_font() -> Font:
	if font != null:
		if not bold:
			return font
		if _custom_font_variation == null or _custom_font_source != font:
			var variation := FontVariation.new()
			variation.base_font = font
			variation.variation_embolden = 1.0
			_custom_font_variation = variation
			_custom_font_source = font
		return _custom_font_variation
	if _fallback_font == null:
		_fallback_font = SystemFont.new()
		_fallback_font.font_names = PackedStringArray([
			"Yu Gothic",
			"Meiryo",
			"MS Gothic",
			"Microsoft YaHei",
			"Noto Sans CJK JP",
			"sans-serif",
		])
	_fallback_font.font_weight = 700 if bold else 400
	return _fallback_font


## 当前字符间距对应的角度步长，单位为度。
func _get_step_deg() -> float:
	if _mesh_instance == null or not (_mesh_instance.mesh is CylinderMesh):
		return 0.0
	var cylinder := _mesh_instance.mesh as CylinderMesh
	var mesh_transform := _mesh_instance.global_transform
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_padding
	var radius_x := radius * mesh_transform.basis.x.length() * ellipse_scale.x
	var radius_z := radius * mesh_transform.basis.z.length() * ellipse_scale.y
	var spacing_radius := maxf((radius_x + radius_z) * 0.5, 0.001)
	return rad_to_deg(character_spacing / spacing_radius)


## 根据圆柱网格和当前旋转角度计算所有活动歌词的变换。
func _apply_layout() -> void:
	if _mesh_instance == null or _active_lines.is_empty():
		return
	var cylinder := _mesh_instance.mesh as CylinderMesh
	if cylinder == null:
		return
	var mesh_transform := _mesh_instance.global_transform
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_padding
	var radius_x := radius * mesh_transform.basis.x.length() * ellipse_scale.x
	var radius_z := radius * mesh_transform.basis.z.length() * ellipse_scale.y
	var x_axis := mesh_transform.basis.x.normalized()
	var z_axis := mesh_transform.basis.z.normalized()
	var up_axis := mesh_transform.basis.y.normalized()
	var top_world := mesh_transform * Vector3(0.0, cylinder.height * 0.5, 0.0)
	# 将世界空间字符间距换算为角度间距，使不同半径下字距保持稳定。
	var spacing_radius := maxf((radius_x + radius_z) * 0.5, 0.001)
	var step := character_spacing / spacing_radius
	# 朝内显示时反转排列方向，避免从内侧看歌词左右颠倒。
	var direction := -1.0 if face_inward else 1.0
	for line in _active_lines:
		# 反向歌词使用相反的滚动方向，进入点也换到对侧。
		var travel := line.travel_deg * line.scroll_direction
		var center_angle := deg_to_rad(line.start_angle_deg + travel)
		var line_center := top_world + up_axis * line.vertical_offset
		var count := line.labels.size()
		line.angular_span_deg = rad_to_deg(step * float(maxi(0, count - 1)))
		line.destroy_travel_deg = minf(
			destroy_after_degrees + offscreen_margin_deg * 2.0 + line.angular_span_deg,
			max_travel_degrees
		)
		var half := (float(count) - 1.0) * 0.5
		for i in count:
			var angle := center_angle + step * (float(i) - half) * direction
			var sin_angle := sin(angle)
			var cos_angle := cos(angle)
			var position := line_center + x_axis * (radius_x * sin_angle) + z_axis * (radius_z * cos_angle)
			var normal := (x_axis * (radius_z * sin_angle) + z_axis * (radius_x * cos_angle)).normalized()
			if face_inward:
				normal = -normal
			var basis := Basis.looking_at(-normal, up_axis)
			line.labels[i].global_transform = Transform3D(basis, position)
			if text_depth > 0.0 and text_depth_layers > 0:
				var depth_step := text_depth / float(text_depth_layers)
				for layer in text_depth_layers:
					var depth_index := i * text_depth_layers + layer
					if depth_index >= line.depth_labels.size():
						break
					var depth_position := position - basis.z * (depth_step * float(layer + 1))
					line.depth_labels[depth_index].global_transform = Transform3D(basis, depth_position)


## 为一条新歌词分配垂直层。
## 从游标位置开始寻找空层，使连续歌词自然向上换行。
## 所有层都占用时，才会提前销毁最早的一条歌词。
func _claim_lane() -> int:
	var used: Dictionary = {}
	for line in _active_lines:
		used[line.lane] = true
	for offset in vertical_lane_count:
		var lane := (_lane_cursor + offset) % vertical_lane_count
		if not used.has(lane):
			_lane_cursor = (lane + 1) % vertical_lane_count
			return lane
	var oldest := _active_lines[0]
	var lane := oldest.lane
	_destroy_line(oldest)
	_lane_cursor = (lane + 1) % vertical_lane_count
	return lane


## 销毁指定歌词行并从活动列表移除。
func _destroy_line(line: ActiveLine) -> void:
	_active_lines.erase(line)
	if is_instance_valid(line.node):
		line.node.queue_free()
	line_destroyed.emit(line.index, line.text)


## 销毁已经完成滚动的歌词行。
## 先离场再生成下一句，避免新旧歌词在同一帧重叠。
func _destroy_finished_lines() -> void:
	for i in range(_active_lines.size() - 1, -1, -1):
		var line := _active_lines[i]
		if line.elapsed < line.move_duration:
			continue
		_destroy_line(line)


## 按当前层数和间距刷新所有活动歌词的垂直位置。
func _apply_vertical_lanes() -> void:
	if not is_node_ready():
		return
	for line in _active_lines:
		line.vertical_offset = vertical_offset + float(line.lane) * line_vertical_spacing
	_apply_layout()


## 层数变化时压缩活动歌词，超出的最早歌词会被销毁。
func _normalize_lanes() -> void:
	if not is_node_ready():
		return
	while _active_lines.size() > vertical_lane_count:
		_destroy_line(_active_lines[0])
	for i in _active_lines.size():
		_active_lines[i].lane = i
	_apply_vertical_lanes()


## 立即清除所有活动歌词节点。
func _clear_active_lines() -> void:
	for line in _active_lines:
		if is_instance_valid(line.node):
			line.node.queue_free()
	_active_lines.clear()


## 在编辑器中静态显示开始时间对应的歌词，便于调整参数。
func _show_editor_preview() -> void:
	_clear_active_lines()
	_next_index = _find_index_at_or_after(start_time)
	if _next_index >= _entries.size():
		return
	_clock = start_time
	_spawn_line(_next_index, _entries[_next_index])
	# 预览时停在滚动中点，便于调整字号、层距和进入角度。
	if not _active_lines.is_empty():
		var preview_line := _active_lines[_active_lines.size() - 1]
		preview_line.elapsed = preview_line.move_duration * 0.5
		preview_line.travel_deg = preview_line.destroy_travel_deg * 0.5
		_apply_line_alpha(preview_line)
	_apply_layout()


## 刷新所有活动歌词的文字样式。
func _refresh_active_styles() -> void:
	if not is_node_ready():
		return
	for line in _active_lines:
		for label in line.labels:
			_apply_style_to_label(label)
		for label in line.depth_labels:
			_apply_depth_style_to_label(label)
	_apply_layout()


## 解析舞台网格节点。
func _resolve_mesh() -> void:
	_mesh_instance = get_node_or_null(stage_mesh_path) as MeshInstance3D
	if _mesh_instance == null:
		push_warning("LyricRing: 找不到舞台网格节点: %s" % stage_mesh_path)
