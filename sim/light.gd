class_name LightField
extends RefCounted
## Light feeds. Rays run in straight parallel lines from the sun. The jar is cut
## into a grid aligned with the rays: u runs across them, d runs along them. Each
## cell's leaves take a share of the light entering it and dim what lies behind,
## so shade is soft and layered.

var phi := 0.0          # sun angle from straight overhead; positive = sun to the right
var cs := 1.0
var sn := 0.0
var u0 := 0.0
var d0 := 0.0
var nu := 0
var nd := 0
var cell := T.LIGHT_CELL
var occ := PackedFloat32Array()    # optical leaf width per cell
var trans := PackedFloat32Array()  # light entering each cell, 0..1
var q := PackedFloat32Array()      # income per optical width for leaves in each cell
var jar_w := 0.0
var jar_h := 0.0
var row := PackedFloat32Array()

const SCATTER := 0.1


func begin(p_phi: float, w: float, h: float) -> void:
	phi = p_phi
	jar_w = w
	jar_h = h
	cs = cos(phi)
	sn = sin(phi)
	# Bounds of the jar (plus a margin above the lid and below the soil) in ray space.
	var top := -h - 40.0
	var bot := 60.0
	var us := [0.0 * cs + top * sn, w * cs + top * sn, 0.0 * cs + bot * sn, w * cs + bot * sn]
	var ds := [-0.0 * sn + top * cs, -w * sn + top * cs, -0.0 * sn + bot * cs, -w * sn + bot * cs]
	u0 = us.min() - cell
	d0 = ds.min() - cell
	nu = int(ceil((us.max() - u0) / cell)) + 2
	nd = int(ceil((ds.max() - d0) / cell)) + 2
	var size := nu * nd
	if occ.size() != size:
		occ.resize(size)
		trans.resize(size)
		q.resize(size)
	occ.fill(0.0)


func deposit(x: float, y: float, w: float, op: float) -> void:
	var u := x * cs + y * sn - u0
	var id := int((-x * sn + y * cs - d0) / cell)
	if id < 0 or id >= nd:
		return
	var lo := u - w * 0.5
	var hi := u + w * 0.5
	var i0 := maxi(0, int(lo / cell))
	var i1 := mini(nu - 1, int(hi / cell))
	for iu in range(i0, i1 + 1):
		var a := maxf(lo, iu * cell)
		var b := minf(hi, (iu + 1) * cell)
		if b > a:
			occ[iu * nd + id] += (b - a) * op


func solve() -> void:
	# March every ray one cell deeper at a time. Leaves take their share, and a
	# little light scatters sideways, so shadows soften with distance.
	var k := T.KAPPA / cell
	if row.size() != nu:
		row.resize(nu)
	row.fill(1.0)
	var last := nu - 1
	for id in nd:
		for iu in nu:
			var idx := iu * nd + id
			var l := row[iu]
			trans[idx] = l
			var o := occ[idx]
			if o > 0.0:
				var e := exp(-k * o)
				q[idx] = l * cell * (1.0 - e) / o
				row[iu] = l * e
		var prev := row[0]
		for iu in range(1, last):
			var cur := row[iu]
			row[iu] = cur + SCATTER * (prev + row[iu + 1] - 2.0 * cur)
			prev = cur


## Energy per second earned by a leaf of this width at this place.
func income(x: float, y: float, w: float, op: float) -> float:
	var u := x * cs + y * sn - u0
	var id := int((-x * sn + y * cs - d0) / cell)
	if id < 0 or id >= nd:
		return 0.0
	var lo := u - w * 0.5
	var hi := u + w * 0.5
	var i0 := maxi(0, int(lo / cell))
	var i1 := mini(nu - 1, int(hi / cell))
	var total := 0.0
	for iu in range(i0, i1 + 1):
		var a := maxf(lo, iu * cell)
		var b := minf(hi, (iu + 1) * cell)
		if b > a:
			total += (b - a) * op * q[iu * nd + id]
	return total


## Share of full sunlight arriving at a point, 0..1.
func sample(x: float, y: float) -> float:
	if nu == 0:
		return 1.0
	var iu := int((x * cs + y * sn - u0) / cell)
	var id := int((-x * sn + y * cs - d0) / cell)
	if iu < 0 or iu >= nu or id < 0 or id >= nd:
		return 1.0
	return trans[iu * nd + id]
