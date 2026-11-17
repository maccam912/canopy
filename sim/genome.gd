class_name Genome
extends RefCounted
## Eight inherited habits, each 0..1, plus a lineage hue that only colours leaves.

enum { REACH, FORK, WOOD, LEAF, ROOT, SEED, PATIENCE, THRIFT, COUNT }

var h := PackedFloat32Array()
var hue := 0.3


static func make(values: Array, p_hue: float) -> Genome:
	var g := Genome.new()
	g.h = PackedFloat32Array(values)
	g.hue = p_hue
	return g


static func random(rng: RandomNumberGenerator) -> Genome:
	var g := Genome.new()
	g.h.resize(COUNT)
	for i in COUNT:
		g.h[i] = rng.randf()
	g.hue = rng.randf()
	return g


## A seed copies its parent's habits with small random nudges.
func child(rng: RandomNumberGenerator, nudge := 0.055) -> Genome:
	var g := Genome.new()
	g.h = h.duplicate()
	for i in COUNT:
		g.h[i] = clampf(g.h[i] + rng.randfn(0.0, nudge), 0.0, 1.0)
	g.hue = fposmod(hue + rng.randfn(0.0, 0.012), 1.0)
	return g


func distance(o: Genome) -> float:
	return distance_to(o.h)


func distance_to(v: PackedFloat32Array) -> float:
	var s := 0.0
	for i in COUNT:
		var d := h[i] - v[i]
		s += d * d
	return sqrt(s)
