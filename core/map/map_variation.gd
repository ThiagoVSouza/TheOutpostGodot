class_name MapVariation
extends RefCounted

## Deterministic per-coordinate variation, ported byte-for-byte from the legacy renderer's
## `variation.ts`. The same (seed, x, y, channel) always produces the same value, so a map renders
## identically on every load without storing any per-cell data. The port must match exactly or a
## map authored against the old renderer would pick different tile variants here.
##
## The reference is 32-bit unsigned integer math (`Math.imul`, `>>> 0`). GDScript ints are 64-bit
## signed, so every step masks back to 32 bits and the multiply is done in 16-bit halves to avoid
## overflowing 64 bits before the mask.

const MASK32: int = 0xFFFFFFFF


## 32-bit unsigned multiply keeping the low 32 bits, matching JS `Math.imul`. Splitting the left
## operand into 16-bit halves keeps every intermediate product under 2^48, well inside int64.
static func _imul(a: int, b: int) -> int:
	a &= MASK32
	b &= MASK32
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) & 0xFFFF) * b
	return (lo + ((hi & 0xFFFF) << 16)) & MASK32


## The mixing hash from `variation.ts` (a MurmurHash-style finalizer). Inputs are masked to 32 bits;
## right shifts act as logical `>>>` because the running value is always kept non-negative.
static func hash32(seed: int, x: int, y: int, channel: int) -> int:
	var h := (seed ^ 0x9e3779b9) & MASK32
	h = _imul(h ^ (x & MASK32), 0x85ebca6b)
	h = (h ^ (h >> 13)) & MASK32
	h = _imul(h ^ (y & MASK32), 0xc2b2ae35)
	h = (h ^ (h >> 16)) & MASK32
	h = _imul(h ^ (channel & MASK32), 0x27d4eb2f)
	h = (h ^ (h >> 15)) & MASK32
	return h


## Pick one of `count` variants for a cell. A single variant (or none) is always index 0, so a biome
## with one texture never calls the hash.
static func pick_variant(seed: int, x: int, y: int, channel: int, count: int) -> int:
	if count <= 1:
		return 0
	return hash32(seed, x, y, channel) % count
