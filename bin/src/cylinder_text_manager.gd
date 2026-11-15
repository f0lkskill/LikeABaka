@tool
extends Node3D

@export var stage_mesh_path: NodePath = ^"stage/CollisionShape3D/MeshInstance3D":
	set(value):
		stage_mesh_path = value
		_request_rebuild()
@export var text_ring_path: NodePath = ^"TextRing":
	set(value):
		text_ring_path = value
		_request_rebuild()

@export_group("Content")
@export_multiline var text: String = "LIKE A BAKA · ":
	set(value):
		text = value
		_request_rebuild()
@export_range(1, 12, 1) var repeat_count: int = 3:
	set(value):
		repeat_count = value
		_request_rebuild()
@export var font: Font:
	set(value):
		font = value
		_request_rebuild()
@export var font_size: int = 160:
	set(value):
		font_size = value
		_request_rebuild()
@export var pixel_size: float = 0.04:
	set(value):
		pixel_size = value
		_request_rebuild()
@export var text_color: Color = Color(1, 1, 1, 1):
	set(value):
		text_color = value
		_request_rebuild()
@export var outline_size: int = 12:
	set(value):
		outline_size = value
		_request_rebuild()
@export var outline_color: Color = Color(0, 0, 0, 0.85):
	set(value):
		outline_color = value
		_request_rebuild()
@export var double_sided: bool = false:
	set(value):
		double_sided = value
		_request_rebuild()

@export_group("Ring")
@export var radius_padding: float = -0.2:
	set(value):
		radius_padding = value
		_request_layout()
@export var vertical_offset: float = 10.0:
	set(value):
		vertical_offset = value
		_request_layout()
@export var ellipse_scale: Vector2 = Vector2(1, 1):
	set(value):
		ellipse_scale = value
		_request_layout()
@export var face_inward: bool = true:
	set(value):
		face_inward = value
		_request_layout()
@export var scroll_speed_deg: float = 30.0
@export var rolling: bool = true

var _labels: Array[Label3D] = []
var _ring: Node3D
var _mesh_instance: MeshInstance3D
var _scroll_deg: float = 0.0


func _ready() -> void:
	_resolve_nodes()
	rebuild()


func _process(delta: float) -> void:
	if rolling:
		_scroll_deg = fposmod(_scroll_deg + scroll_speed_deg * delta, 360.0)
	_apply_layout()


func set_text(value: String) -> void:
	text = value


func set_repeat_count(value: int) -> void:
	repeat_count = maxi(1, value)


func set_scroll_speed(degrees_per_second: float) -> void:
	scroll_speed_deg = degrees_per_second


func set_rolling(value: bool) -> void:
	rolling = value


func set_vertical_offset(value: float) -> void:
	vertical_offset = value


func set_radius_padding(value: float) -> void:
	radius_padding = value


func set_ellipse_scale(value: Vector2) -> void:
	ellipse_scale = value


func set_stage_mesh(mesh_instance: MeshInstance3D) -> void:
	_mesh_instance = mesh_instance
	rebuild()


func refresh() -> void:
	rebuild()


func _request_rebuild() -> void:
	if is_node_ready():
		rebuild()


func _request_layout() -> void:
	if is_node_ready():
		_apply_layout()


func get_ring_radius() -> Vector2:
	if _mesh_instance == null or not (_mesh_instance.mesh is CylinderMesh):
		return Vector2.ZERO
	var cylinder := _mesh_instance.mesh as CylinderMesh
	var radius := maxf(cylinder.top_radius, cylinder.bottom_radius) + radius_padding
	return Vector2(
		radius * _mesh_instance.global_transform.basis.x.length() * ellipse_scale.x,
		radius * _mesh_instance.global_transform.basis.z.length() * ellipse_scale.y
	)


func _resolve_nodes() -> void:
	_mesh_instance = get_node_or_null(stage_mesh_path) as MeshInstance3D
	_ring = get_node_or_null(text_ring_path) as Node3D
	if _ring == null:
		_ring = Node3D.new()
		_ring.name = "TextRing"
		add_child(_ring)


func rebuild() -> void:
	_resolve_nodes()
	for child in _ring.get_children():
		child.queue_free()
	_labels.clear()
	if _mesh_instance == null or not (_mesh_instance.mesh is CylinderMesh):
		return
	var composed := ""
	for i in repeat_count:
		composed += text
	if composed.is_empty():
		return
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
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_ring.add_child(label)
		_labels.append(label)
	_apply_layout()


func _apply_layout() -> void:
	if _mesh_instance == null or _labels.is_empty():
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
	var center := top_world + up_axis * vertical_offset
	var step := TAU / float(_labels.size())
	var direction := -1.0 if face_inward else 1.0
	for i in _labels.size():
		var angle := step * float(i) * direction + deg_to_rad(_scroll_deg)
		var sin_angle := sin(angle)
		var cos_angle := cos(angle)
		var position := center + x_axis * (radius_x * sin_angle) + z_axis * (radius_z * cos_angle)
		var normal := (x_axis * (radius_z * sin_angle) + z_axis * (radius_x * cos_angle)).normalized()
		if face_inward:
			normal = -normal
		var basis := Basis.looking_at(-normal, up_axis)
		_labels[i].global_transform = Transform3D(basis, position)
