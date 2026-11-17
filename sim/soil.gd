class_name Soil
extends RefCounted
## The soil has one property per column: richness. Roots drain it, rot returns
## it, and it seeps slowly sideways. Wetness softens the ground for a while.

const CW := 10.0

var n := 0
var width := 0.0
var height := PackedFloat32Array()   # surface y per column edge (n + 1 values)
var rich := PackedFloat32Array()
var wet := PackedFloat32Array()
var light := PackedFloat32Array()    # share of sunlight reaching the floor, 0..1


func setup(p_width: float, rng: RandomNumberGenerator, relief := 16.0) -> void:
	width = p_width
	n = int(ceil(width / CW))
	height.resize(n + 1)
	rich.resize(n)
	wet.resize(n)
	light.resize(n)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	for i in n + 1:
		var t := float(i) / n
		height[i] = -relief * (0.55 * sin(t * TAU * 1.0 + p1) + 0.3 * sin(t * TAU * 2.3 + p2) + 0.15 * sin(t * TAU * 5.1 + p3))
	for i in n:
		rich[i] = T.RICH0 * rng.randf_range(0.85, 1.15)
		wet[i] = 0.0
		light[i] = 1.0


func col(x: float) -> int:
	return clampi(int(x / CW), 0, n - 1)


func ground_y(x: float) -> float:
	var f := clampf(x / CW, 0.0, n - 0.001)
	var i := int(f)
	return lerpf(height[i], height[i + 1], f - i)


## Mean richness within spread of x, 0..1-ish after saturation.
func fertility(x: float, spread: float) -> float:
	var a := col(x - spread)
	var b := col(x + spread)
	var s := 0.0
	for i in range(a, b + 1):
		s += rich[i]
	s /= (b - a + 1)
	return s / (s + T.RICH_K)


## Roots drain richness. Returns how much was actually there to take.
func take(x: float, spread: float, amount: float) -> float:
	var a := col(x - spread)
	var b := col(x + spread)
	var total := 0.0
	for i in range(a, b + 1):
		total += rich[i]
	if total <= 0.0:
		return 0.0
	var got := minf(amount, total * 0.5)
	var f := 1.0 - got / total
	for i in range(a, b + 1):
		rich[i] *= f
	return got


func add(x0: float, x1: float, amount: float) -> void:
	var a := col(minf(x0, x1))
	var b := col(maxf(x0, x1))
	var each := amount / (b - a + 1)
	for i in range(a, b + 1):
		rich[i] += each


func water(x: float, amount: float) -> void:
	var c := col(x)
	for i in range(maxi(0, c - 3), mini(n, c + 4)):
		var fall := 1.0 - absf(i - c) / 4.0
		wet[i] = minf(1.0, wet[i] + amount * fall)
		rich[i] += amount * fall * 40.0


func wetness(x: float) -> float:
	return wet[col(x)]


func step(dt: float) -> void:
	# Richness seeps sideways; water drains downhill and dries.
	var k := minf(0.25, dt * 0.012)
	var prev := rich[0]
	for i in range(1, n):
		var cur := rich[i]
		var flow := (prev - cur) * k
		rich[i - 1] -= flow
		rich[i] += flow
		prev = rich[i]
	var dry := exp(-dt * 0.02)
	for i in n:
		wet[i] *= dry
	var kw := minf(0.3, dt * 0.05)
	for i in range(1, n):
		var slope := height[i + 1] - height[i - 1]   # positive: ground drops to the right
		var src := i - 1 if slope > 0.0 else i
		var dst := i if slope > 0.0 else i - 1
		var f := wet[src] * kw * minf(1.0, absf(slope) / 8.0)
		wet[src] -= f
		wet[dst] = minf(1.0, wet[dst] + f)
