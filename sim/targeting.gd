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
	"random_other_own", "slowest_other_own", "all_own_weapons",
	"random_enemy_active", "all_enemy_active", "slowest_enemy",
]

## 적 함선의 파츠를 지목하는 셀렉터. **디버프 전용**이다 —
## Corrosion 대상이 "개별 적 파츠"이고 정지·둔화가 적의 공급원을 겨냥하기 때문이다.
##
## `destroy_part`는 이 셀렉터를 쓸 수 없다. GDD §20이 직접 파괴기를 억제하고 있으며
## (주요 파괴 원인은 파괴선과 발동 제한 소진이다), 카탈로그가 조합을 거부한다.
const ENEMY_SELECTORS: Array[String] = [
	"random_enemy_active", "all_enemy_active", "slowest_enemy",
]

static func is_enemy_selector(selector: String) -> bool:
	return ENEMY_SELECTORS.has(selector)

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
		"random_other_own":
			return _pick_one(_others(ship, owner), ctx["rng"])
		"slowest_other_own":
			return _slowest_of(_others(ship, owner))
		"all_own_weapons":
			return _by_base_role(ship, "weapon")
		"random_own_limited":
			return _pick_one(ship.limited_parts(), ctx["rng"])
		"random_broken_own":
			return _pick_one(ship.broken_parts(), ctx["rng"])
		"slowest_own":
			return _slowest(ship)
		"all_enemy_active":
			return _foe(ctx).alive_parts() if _foe(ctx) != null else []
		"random_enemy_active":
			var foe: RefCounted = _foe(ctx)
			return _pick_one(foe.alive_parts(), ctx["rng"]) if foe != null else []
		"slowest_enemy":
			var foe2: RefCounted = _foe(ctx)
			return _slowest(foe2) if foe2 != null else []
	return []

## 적 함선. 단독 테스트에서 가짜 문맥이 enemy_ship을 안 넣는 경우가 있으므로
## 없으면 null을 돌려주고 호출부가 빈 배열로 처리한다.
static func _foe(ctx: Dictionary) -> RefCounted:
	return ctx.get("enemy_ship", null)

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

## 자신을 뺀 살아 있는 아군 파츠. "다른 파츠 하나를 가속" 계열이 쓴다 —
## 자신을 포함하면 "다른"이라는 말이 지켜지지 않고, 파츠가 스스로를 가속하는
## 자기강화가 조용히 섞인다.
static func _others(ship: RefCounted, owner: RefCounted) -> Array:
	var out: Array = []
	for p: RefCounted in ship.alive_parts():
		if p != owner:
			out.append(p)
	return out

## Base Role로 고른 살아 있는 아군 파츠. 슬롯 role이 아니라 **파츠의** Base Role을 본다 —
## flexible 슬롯에 꽂힌 무기도 무기다.
static func _by_base_role(ship: RefCounted, role: String) -> Array:
	var out: Array = []
	for p: RefCounted in ship.alive_parts():
		if p.base_role == role:
			out.append(p)
	return out

## 남은 쿨타임이 가장 큰 파츠. 동점이면 슬롯 순서가 이긴다 (결정론).
## 첫 후보를 무조건 채택한 뒤 비교한다 — 고정 센티넬(-1 등)을 쓰면 잔여 쿨타임이
## 그 센티넬보다 작은 상태(예: 진행도가 쿨타임을 넘겨 잔여가 음수인 경우)에서
## 어떤 파츠도 선택되지 못하는 결함이 생긴다.
static func _slowest(ship: RefCounted) -> Array:
	return _slowest_of(ship.alive_parts())

static func _slowest_of(candidates: Array) -> Array:
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
