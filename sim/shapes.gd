class_name Shapes
extends RefCounted
## The field guide's memory. Living plants are grouped by how alike their habits
## are; a plant that grows up far from every known shape founds a new one.

const RADIUS := 0.4

var list: Array[Dictionary] = []
var used_names := {}


func nearest(g: Genome) -> Array:
	var best := -1
	var best_d := 1e9
	for s in list:
		var d := g.distance_to(s.h)
		if d < best_d:
			best_d = d
			best = s.id
	return [best, best_d]


## The shape a seedling belongs to: its parent's if it is still close, else the
## nearest known one, else none yet.
func classify(g: Genome, hint: int) -> int:
	if hint >= 0 and g.distance_to(list[hint].h) < RADIUS:
		return hint
	var near := nearest(g)
	return near[0] if near[1] < RADIUS else -1


func found(g: Genome, time: float, parent: int, rng: RandomNumberGenerator) -> Dictionary:
	var s := {
		"id": list.size(),
		"name": _name(g, rng),
		"h": g.h.duplicate(),
		"hue": g.hue,
		"born": time,
		"parent": parent,
		"alive": 0,
		"total": 0,
		"tallest": 0.0,
		"stamps": [],
	}
	list.append(s)
	return s


func _name(g: Genome, rng: RandomNumberGenerator) -> String:
	var h := g.h
	var nouns: Array
	var reach := h[Genome.REACH]
	var fork := h[Genome.FORK]
	var wood := h[Genome.WOOD]
	var leaf := h[Genome.LEAF]
	if h[Genome.PATIENCE] < 0.15:
		nouns = ["Weed", "Tuft", "Sprig", "Scrub", "Whisker"]
	elif h[Genome.THRIFT] > 0.8:
		nouns = ["Lurker", "Sleeper", "Hermit", "Shadecap", "Moss-arm"]
	elif reach > 0.78:
		nouns = ["Chaser", "Sickle", "Hook", "Sunhound", "Crook"]
	elif fork < 0.25 and wood < 0.3:
		nouns = ["Thread", "Whip", "Reed", "Wand", "Lash"]
	elif fork < 0.3:
		nouns = ["Pole", "Spire", "Mast", "Needle", "Column"]
	elif fork > 0.65 and leaf > 0.6:
		nouns = ["Parasol", "Umbrella", "Awning", "Table", "Brim"]
	elif fork > 0.6:
		nouns = ["Plume", "Feather", "Broom", "Fan", "Spray"]
	elif h[Genome.ROOT] > 0.75:
		nouns = ["Anchor", "Boll", "Stump", "Keel", "Fist"]
	else:
		nouns = ["Bough", "Sapling", "Crown", "Antler", "Fork"]
	var adjs: Array = []
	if wood < 0.25:
		adjs += ["Hanging", "Trembling", "Thin", "Limp"]
	if wood > 0.75:
		adjs += ["Stout", "Iron", "Stubborn"]
	if reach > 0.6:
		adjs += ["Leaning", "Bowing", "Thirsty"]
	if h[Genome.SEED] < 0.25:
		adjs += ["Drifting", "Dusty", "Scatter"]
	if h[Genome.SEED] > 0.75:
		adjs += ["Plump", "Heavy", "Knuckle"]
	if h[Genome.THRIFT] > 0.65:
		adjs += ["Patient", "Quiet", "Dim"]
	if h[Genome.THRIFT] < 0.25:
		adjs += ["Hungry", "Quick", "Greedy"]
	if leaf < 0.25:
		adjs += ["Feathered", "Lace", "Fine"]
	if leaf > 0.75:
		adjs += ["Broad", "Paddle", "Shady"]
	var hue := g.hue
	if hue < 0.12 or hue > 0.92:
		adjs += ["Rust", "Ember"]
	elif hue < 0.2:
		adjs += ["Golden", "Amber"]
	elif hue < 0.45:
		adjs += ["Green", "Moss"]
	elif hue < 0.6:
		adjs += ["Pale", "Teal", "Sea"]
	elif hue < 0.75:
		adjs += ["Blue", "Dusk"]
	else:
		adjs += ["Violet", "Plum"]
	for attempt in 30:
		var candidate: String = adjs[rng.randi() % adjs.size()] + " " + nouns[rng.randi() % nouns.size()]
		if not used_names.has(candidate):
			used_names[candidate] = true
			return candidate
	var fallback: String = adjs[0] + " " + nouns[0] + " " + str(list.size() + 1)
	used_names[fallback] = true
	return fallback
