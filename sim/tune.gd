class_name T
extends RefCounted
## Every tunable number in the simulation lives here.
## World units are roughly centimetres; y points down, so "up" is negative y.

# --- mechanics (weight breaks) ---
const GRAV := 240.0          # also set in project.godot for fallen wood
const RHO := 1.0             # wood mass per r^2 * length
const LEAF_M := 1.4          # leaf mass per optical width
const E := 2.4e8             # stiffness: joint spring = E r^4 / len
const SIGMA := 3.4e6         # strength: joint breaks at SIGMA r^3
const ZETA := 0.55           # sway damping ratio
const CREEP := 0.5           # how fast strained wood takes a permanent set
const COLLIDER_R := 1.2      # stems thinner than this let falling wood through
const GROUND_K := 0.2

# --- light feeds ---
const KAPPA := 0.8           # leaf opacity per optical width
const LIGHT_CELL := 14.0

# --- life ---
const C_WOOD := 1.0          # energy per unit wood volume
const C_LEAF := 2.0          # energy per optical leaf width
const C_ROOT := 1.0
const U_WOOD := 0.008        # upkeep per second per unit
const U_LEAF := 0.06
const U_ROOT := 0.004
const SEG_CAP := 40
const MAX_ORDER := 4
const SEED_FRAC := 0.35

# --- soil ---
const RICH0 := 2500.0        # starting richness per column (in wood-volume units)
const RICH_K := 700.0        # half-saturation of growth on richness
const LEAF_N := 3.0          # nutrient held per optical leaf width

# --- population ---
const MAX_PLANTS := 170
const MAX_SEEDS := 320
const MAX_LOGS := 60
const SPACING := 9.0
