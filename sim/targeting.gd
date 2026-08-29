extends RefCounted
## 대상 셀렉터 해석.
##
## ship_state.gd를 preload하지 않는다 — 함선 객체를 인자로 받아 덕타이핑으로 쓴다.
## preload 순환을 막고, 가짜 함선으로 단독 테스트할 수 있게 하기 위함이다.
##
## 함선 자체를 겨냥하는 op(deal_damage / gain_shield / repair 등)는 target을 쓰지 않고
## 암묵적으로 적함 또는 자함에 적용된다. 여기서 해석하는 것은 파츠 셀렉터뿐이다.

const SELECTORS: Array[String] = [
	"self", "host", "linked",
	"random_own_active", "slowest_own", "random_broken_own",
	"all_own_active", "all_own_limited", "random_own_limited",
]

## ctx: {own_ship, enemy_ship, part, rng}
## 항상 파츠 배열을 돌려준다. 대상이 없으면 빈 배열.
static func resolve(selector: String, ctx: Dictionary) -> Array:
	var ship: RefCounted = ctx["own_ship"]
	var owner: RefCounted = ctx["part"]

	match selector:
		"self", "host":
			# 병합된 문맥에서 host와 self는 같다 — AUGMENT 트리거는 숙주 파츠가 소유한다
			return [owner] if owner != null else []
		"linked":
			return _linked(ship, owner)
		"all_own_active":
			return ship.alive_parts()
		"all_own_limited":
			return ship.limited_parts()
		"random_own_active":
			return _pick_one(ship.alive_parts(), ctx["rng"])
		"random_own_limited":
			return _pick_one(ship.limited_parts(), ctx["rng"])
		"random_broken_own":
			return _pick_one(ship.broken_parts(), ctx["rng"])
		"slowest_own":
			return _slowest(ship)
	return []

static func _linked(ship: RefCounted, owner: RefCounted) -> Array:
	if owner == null or not ship.links.has(owner.slot_id):
		return []
	var out: Array = []
	for slot_id: String in ship.links[owner.slot_id]:
		var p: RefCounted = ship.get_part(slot_id)
		if p != null and not p.broken:
			out.append(p)
	return out

static func _pick_one(pool: Array, rng: RandomNumberGenerator) -> Array:
	if pool.is_empty():
		return []
	return [pool[rng.randi_range(0, pool.size() - 1)]]

## 남은 쿨타임이 가장 큰 파츠. 동점이면 슬롯 순서가 이긴다 (결정론).
## 첫 후보를 무조건 채택한 뒤 비교한다 — 고정 센티넬(-1 등)을 쓰면 잔여 쿨타임이
## 그 센티넬보다 작은 상태(예: 진행도가 쿨타임을 넘겨 잔여가 음수인 경우)에서
## 어떤 파츠도 선택되지 못하는 결함이 생긴다.
static func _slowest(ship: RefCounted) -> Array:
	var candidates: Array = ship.alive_parts()
	if candidates.is_empty():
		return []
	var best: RefCounted = candidates[0]
	var best_remaining: int = best.cooldown_units - best.progress_units
	for i: int in range(1, candidates.size()):
		var p: RefCounted = candidates[i]
		var remaining: int = p.cooldown_units - p.progress_units
		if remaining > best_remaining:
			best_remaining = remaining
			best = p
	return [best]
