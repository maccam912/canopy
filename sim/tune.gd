class_name T
extends RefCounted
## Every tunable number in the simulation lives here.
## World units are roughly centimetres; y points down, so "up" is negative y.

# --- mechanics (weight breaks) ---
const GRAV := 240.0          # also set in project.godot for fallen wood
const RHO := 1.0             # wood mass per r^2 * length
const LEAF_M := 1.4          # leaf mass per optical width
const E := 1.0e8             # stiffness: joint spring = E r^4 / len
const SIGMA := 1.1e6         # strength: joint breaks at SIGMA r^3
const ZETA := 0.55           # sway damping ratio
const CREEP := 0.5           # how fast strained wood takes a permanent set
const COLLIDER_R := 2.2      # stems thinner than this let falling wood through (saplings survive a domino run)
const GROUND_K := 0.2
const PUSH_GAIN := 0.08     # share of an outside force a stem takes up each step

# --- light feeds ---
const KAPPA := 0.8           # leaf opacity per optical width
const LIGHT_CELL := 14.0

# --- life ---
const C_WOOD := 0.4          # energy per unit wood volume
const C_LEAF := 2.0          # energy per optical leaf width
const C_ROOT := 1.0
const U_WOOD := 0.003        # upkeep per second per unit
const U_LEAF := 0.06
const U_ROOT := 0.004
const SEG_CAP := 40
const MAX_ORDER := 4
const SEED_FRAC := 0.35

# --- soil ---
const RICH0 := 6000.0        # starting richness per column (in wood-volume units)
const RICH_K := 1700.0        # half-saturation of growth on richness
const LEAF_N := 3.0          # nutrient held per optical leaf width

# --- population ---
const MAX_PLANTS := 170
const MAX_SEEDS := 320
const MAX_LOGS := 60
const SPACING := 9.0

# --- sizes that count ---
const FALL_VOL := 600.0       # wood volume that makes a break a "fall"
const LITTER_VOL := 60.0      # smaller pieces crumble instead of becoming objects
const YIELD_TIME := 0.3       # seconds of overload a joint takes before it lets go
