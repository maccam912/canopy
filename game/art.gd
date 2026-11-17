class_name Art
extends RefCounted
## Every texture in the game is drawn here in code; there are no image files.

static var _leaf: Texture2D
static var _glow: Texture2D


static func leaf() -> Texture2D:
	if _leaf != null:
		return _leaf
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := absf((y + 0.5) / h - 0.5) * 2.0
			# A pointed blade: widest a third of the way along.
			var half := pow(sin(PI * pow(u, 0.75)), 0.8) * 0.92
			var edge := clampf((half - v) * 7.0, 0.0, 1.0)
			var shade := 0.82 + 0.18 * (1.0 - v / maxf(half, 0.01))
			if v < 0.07:
				shade = 1.0
			if u < 0.1:
				edge = maxf(edge, clampf((0.09 - v) * 12.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(shade, shade, shade, edge))
	_leaf = ImageTexture.create_from_image(img)
	return _leaf


static func glow() -> Texture2D:
	if _glow != null:
		return _glow
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5 - s * 0.5, y + 0.5 - s * 0.5).length() / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_glow = ImageTexture.create_from_image(img)
	return _glow
