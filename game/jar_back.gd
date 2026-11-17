class_name JarBack
extends Node2D
## Behind the plants: backlit glass, and the light itself falling in shafts.

var world: World
var shafts: Node2D
var tex: ImageTexture
var shown := -1


func setup(w: World) -> void:
	world = w
	shafts = Node2D.new()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.58, 0.2);
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float streak(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}
void fragment() {
	// UV.x runs along the rays, UV.y across them.
	float t = texture(TEXTURE, UV).r;
	float beams = 0.62 + 0.38 * streak(UV.y * 46.0) + 0.16 * streak(UV.y * 173.0);
	float reach = mix(1.15, 0.7, UV.x);
	COLOR = vec4(tint.rgb, t * t * beams * reach * tint.a);
}
"""
	mat.shader = sh
	shafts.material = mat
	shafts.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shafts.draw.connect(_draw_shafts)
	add_child(shafts)


func _process(_delta: float) -> void:
	if shown != world.light_version:
		shown = world.light_version
		var l := world.light
		var img := Image.create_from_data(l.nd, l.nu, false, Image.FORMAT_RF, l.trans.to_byte_array())
		img.convert(Image.FORMAT_L8)
		tex = ImageTexture.create_from_image(img)
		shafts.queue_redraw()


func _draw() -> void:
	var w := world.jar_w
	var h := world.jar_h
	var top := Color(0.10, 0.17, 0.18)
	var mid := Color(0.07, 0.12, 0.13)
	var low := Color(0.04, 0.07, 0.08)
	draw_polygon(PackedVector2Array([Vector2(0, -h), Vector2(w, -h), Vector2(w, -h * 0.45), Vector2(0, -h * 0.45)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, -h * 0.45), Vector2(w, -h * 0.45), Vector2(w, 90), Vector2(0, 90)]), PackedColorArray([mid, mid, low, low]))
	if world.kind == "hillside":
		# Distant hills, far behind the forest.
		for layer in 2:
			var hills := PackedVector2Array()
			for k in 61:
				var x := w * k / 60.0
				hills.append(Vector2(x, -h * (0.32 - layer * 0.12) - 55.0 * sin(k * 0.31 + layer * 2.0) - 30.0 * sin(k * 0.11 + 1.0)))
			hills.append(Vector2(w, 90.0))
			hills.append(Vector2(0.0, 90.0))
			draw_colored_polygon(hills, Color(0.07, 0.11, 0.11) if layer == 0 else Color(0.05, 0.08, 0.08))


func _draw_shafts() -> void:
	if tex == null:
		return
	var l := world.light
	var p := Vector2(l.cs, l.sn)
	var t := Vector2(-l.sn, l.cs)
	var u1 := l.u0 + l.nu * l.cell
	var d1 := l.d0 + l.nd * l.cell
	var pts := PackedVector2Array([p * l.u0 + t * l.d0, p * l.u0 + t * d1, p * u1 + t * d1, p * u1 + t * l.d0])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	shafts.draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, tex)
