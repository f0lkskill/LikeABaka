@tool
## 场景全局管理器。
##
## 挂载在场景根节点，统一提供场景级接口与效果控制。
## 目前负责圆柱表面滚轴文字环的生成、布局和滚动，
## 后续可在此扩展其他全局功能。
class_name GlobalManager
extends Node3D

## 舞台圆柱网格的节点路径，文字环的尺寸以此节点为基准。
@export var stage_mesh_path: NodePath = ^"stage/CollisionShape3D/MeshInstance3D":
	set(value):
		stage_mesh_path = value
		_request_rebuild()
## 文字环容器节点路径；为空时会自动创建一个 TextRing 节点。
@export var text_ring_path: NodePath = ^"TextRing":
	set(value):
		text_ring_path = value
		_request_rebuild()

@export_group("Content")
## 环绕圆柱显示的文字内容。
@export_multiline var text: String = "LIKE A BAKA · ":
	set(value):
		text = value
		_request_rebuild()
## 文字重复次数，用于填满整个圆周。
@export_range(1, 12, 1) var repeat_count: int = 3:
	set(value):
		repeat_count = value
		_request_rebuild()
## 自定义字体；留空时使用项目默认字体。
@export var font: Font:
	set(value):
		font = value
		_request_rebuild()
## 字号。
@export var font_size: int = 160:
	set(value):
		font_size = value
		_request_rebuild()
## 每个字体像素对应的世界尺寸，决定文字的实际大小。
@export var pixel_size: float = 0.04:
	set(value):
		pixel_size = value
		_request_rebuild()
## 文字颜色。
@export var text_color: Color = Color(1, 1, 1, 1):
	set(value):
		text_color = value
		_request_rebuild()
## 文字描边宽度。
@export var outline_size: int = 12:
	set(value):
		outline_size = value
		_request_rebuild()
## 文字描边颜色。
@export var outline_color: Color = Color(0, 0, 0, 0.85):
	set(value):
		outline_color = value
		_request_rebuild()
## 是否双面显示文字。
@export var double_sided: bool = false:
	set(value):
		double_sided = value
		_request_rebuild()

@export_group("Ring")
## 相对圆柱半径的偏移量；正值向外，负值向内。
@export var radius_padding: float = -0.2:
	set(value):
		radius_padding = value
		_request_layout()
## 文字环相对圆柱顶面的垂直偏移。
@export var vertical_offset: float = 10.0:
	set(value):
		vertical_offset = value
		_request_layout()
## 椭圆缩放，X/Z 分别控制两个轴向的半径倍率。
@export var ellipse_scale: Vector2 = Vector2(1, 1):
	set(value):
		ellipse_scale = value
		_request_layout()
## 文字是否朝向圆柱内部。
@export var face_inward: bool = true:
	set(value):
		face_inward = value
		_request_layout()
## 滚动速度，单位为度/秒。
@export var scroll_speed_deg: float = 30.0
## 是否启用自动滚动。
@export var rolling: bool = true

## 当前生成的字符标签。
var _labels: Array[Label3D] = []
## 文字环容器。
var _ring: Node3D
## 作为布局基准的舞台网格。
var _mesh_instance: MeshInstance3D
## 当前累计滚动角度（度）。
var _scroll_deg: float = 0.0


## 初始化节点引用并生成初始文字环。
func _ready() -> void:
	_resolve_nodes()
	rebuild()


## 每帧推进滚动角度并刷新布局。
## [param delta] 距上一帧的时间，单位为秒。
func _process(delta: float) -> void:
	if rolling:
		# 将角度限制在 0~360 度，避免数值无限增长。
		_scroll_deg = fposmod(_scroll_deg + scroll_speed_deg * delta, 360.0)
	# 即使暂停滚动也刷新一次，保证圆柱尺寸变化时能立即跟随。
	_apply_layout()


## 设置文字内容并立即重建文字环。
func set_text(value: String) -> void:
	text = value


## 设置文字重复次数；小于 1 时按 1 处理。
func set_repeat_count(value: int) -> void:
	repeat_count = maxi(1, value)


## 设置滚动速度。
## [param degrees_per_second] 每秒滚动的角度。
func set_scroll_speed(degrees_per_second: float) -> void:
	scroll_speed_deg = degrees_per_second


## 开启或暂停自动滚动。
func set_rolling(value: bool) -> void:
	rolling = value


## 设置文字环相对圆柱顶面的高度。
func set_vertical_offset(value: float) -> void:
	vertical_offset = value


## 设置文字环半径偏移；正值向外，负值向内。
func set_radius_padding(value: float) -> void:
	radius_padding = value


## 设置椭圆半径缩放。
func set_ellipse_scale(value: Vector2) -> void:
	ellipse_scale = value


## 直接绑定舞台网格并重建文字环。
func set_stage_mesh(mesh_instance: MeshInstance3D) -> void:
	_mesh_instance = mesh_instance
	rebuild()


## 强制重建文字环。
func refresh() -> void:
	rebuild()


## 在节点就绪后请求重建，供属性 setter 调用。
func _request_rebuild() -> void:
	if is_node_ready():
		rebuild()


## 在节点就绪后请求刷新布局，供属性 setter 调用。
func _request_layout() -> void:
	if is_node_ready():
		_apply_layout()


## 返回文字环在世界空间中的 X/Z 半径。
func get_ring_radius() -> Vector2:
	if _mesh_instance == null or not (_mesh_instance.mesh is CylinderMesh):
		return Vector2.ZERO
	var cylinder := _mesh_instance.mesh as CylinderMesh
	# 锥形圆柱取较大的半径，保证文字环包住整个侧面。
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_padding
	# 网格的全局缩放会改变实际半径，因此用基向量长度还原世界尺寸。
	return Vector2(
		radius * _mesh_instance.global_transform.basis.x.length() * ellipse_scale.x,
		radius * _mesh_instance.global_transform.basis.z.length() * ellipse_scale.y
	)


## 解析节点引用；若文字环容器不存在则自动创建。
func _resolve_nodes() -> void:
	_mesh_instance = get_node_or_null(stage_mesh_path) as MeshInstance3D
	_ring = get_node_or_null(text_ring_path) as Node3D
	if _ring == null:
		# 场景中缺少容器时创建一个，方便直接运行。
		_ring = Node3D.new()
		_ring.name = "TextRing"
		add_child(_ring)


## 按当前参数销毁旧标签并重新生成文字环。
func rebuild() -> void:
	_resolve_nodes()
	# 延迟释放旧标签，避免在遍历子节点时直接修改树结构。
	for child in _ring.get_children():
		child.queue_free()
	_labels.clear()
	if _mesh_instance == null or not (_mesh_instance.mesh is CylinderMesh):
		return
	# 将文字重复拼接，直到足够填满整个圆周。
	var composed := ""
	for i in repeat_count:
		composed += text
	if composed.is_empty():
		return
	# 每个字符使用一个 Label3D，便于沿圆周独立定位和朝向。
	for i in composed.length():
		var label := Label3D.new()
		label.text = composed.substr(i, 1)
		label.font = font
		label.font_size = font_size
		label.pixel_size = pixel_size
		label.modulate = text_color
		label.outline_size = outline_size
		label.outline_modulate = outline_color
		label.shaded = false
		label.double_sided = double_sided
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# 文字只是装饰，不参与阴影和全局光照，避免额外开销。
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_ring.add_child(label)
		_labels.append(label)
	_apply_layout()


## 根据圆柱网格和当前滚动角度计算每个标签的变换。
func _apply_layout() -> void:
	if _mesh_instance == null or _labels.is_empty():
		return
	var cylinder := _mesh_instance.mesh as CylinderMesh
	if cylinder == null:
		return
	# 使用网格的全局变换，使文字环跟随舞台的移动、旋转和缩放。
	var mesh_transform := _mesh_instance.global_transform
	# 锥形圆柱取最大半径，椭圆缩放则分别作用于两个轴向。
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_padding
	var radius_x := radius * mesh_transform.basis.x.length() * ellipse_scale.x
	var radius_z := radius * mesh_transform.basis.z.length() * ellipse_scale.y
	# 归一化后的基向量用于确定局部坐标轴方向；长度已在半径中计入缩放。
	var x_axis := mesh_transform.basis.x.normalized()
	var z_axis := mesh_transform.basis.z.normalized()
	var up_axis := mesh_transform.basis.y.normalized()
	# 圆柱顶面中心再沿法线抬高 vertical_offset，得到文字环中心。
	var top_world := mesh_transform * Vector3(0.0, cylinder.height * 0.5, 0.0)
	var center := top_world + up_axis * vertical_offset
	# 均分圆周，让每个字符占据相同的角度间隔。
	var step := TAU / float(_labels.size())
	# 朝内显示时反转排列方向，避免从内侧看文字左右颠倒。
	var direction := -1.0 if face_inward else 1.0
	for i in _labels.size():
		# 基础角度叠加滚动角度，实现文字绕圆柱旋转。
		var angle := step * float(i) * direction + deg_to_rad(_scroll_deg)
		var sin_angle := sin(angle)
		var cos_angle := cos(angle)
		# 椭圆参数方程：x = rx * sin(a)，z = rz * cos(a)。
		var position := center + x_axis * (radius_x * sin_angle) + z_axis * (radius_z * cos_angle)
		# 椭圆法线需要同时考虑两个轴向的半径，才能让文字始终贴合表面。
		var normal := (x_axis * (radius_z * sin_angle) + z_axis * (radius_x * cos_angle)).normalized()
		if face_inward:
			normal = -normal
		# Label3D 的正面是 +Z，因此让 -Z 指向 -normal，使正面朝向 normal。
		var basis := Basis.looking_at(-normal, up_axis)
		_labels[i].global_transform = Transform3D(basis, position)
