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
	"most_corroded_own", "oldest_broken_own", "exhausted_other_own",
	"longest_base_cooldown_other_own", "event_part", "random_other_own_except_event",
	"random_enemy_active", "all_enemy_active", "slowest_enemy", "designated_enemy",
]

## 적 함선의 파츠를 지목하는 셀렉터. **디버프 전용**이다 —
## Corrosion 대상이 "개별 적 파츠"이고 정지·둔화가 적의 공급원을 겨냥하기 때문이다.
##
## `destroy_part`는 이 셀렉터를 쓸 수 없다. GDD §20이 직접 파괴기를 억제하고 있으며
## (주요 파괴 원인은 파괴선과 발동 제한 소진이다), 카탈로그가 조합을 거부한다.
const ENEMY_SELECTORS: Array[String] = [
	"random_enemy_active", "all_enemy_active", "slowest_enemy", "designated_enemy",
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
			return _pick_one(_time_targets(ship, owner), ctx["rng"])
		"slowest_other_own":
			return _slowest_of(_time_targets(ship, owner))
		"random_other_own_except_event":
			# AH06 「일식 축전기」 — 사건 원인 파츠와 자신을 뺀 무작위 아군.
			# 원인을 빼지 않으면 정지에 들어간 파츠를 자기가 다시 밀어 순환한다.
			var pool: Array = []
			var cause_slot: String = str((ctx.get("event", {}) as Dictionary).get("slot", ""))
			for p: RefCounted in _time_targets(ship, owner):
				if p.slot_id != cause_slot:
					pool.append(p)
			return _pick_one(pool, ctx["rng"])
		"event_part":
			# 지금 처리 중인 이벤트가 가리키는 파츠. RD07 「재기동 크랭크」의 "그 파츠".
			var src: RefCounted = ctx.get("source_part", null)
			return [src] if src != null and not src.broken else []
		"most_corroded_own":
			var corroded: RefCounted = ship.most_corroded_part()
			return [corroded] if corroded != null else []
		"oldest_broken_own":
			# Restore의 기본 대상 (기획서 §3.3). 동률이면 슬롯 정의 순서 — 결정론.
			var oldest: RefCounted = null
			for p: RefCounted in ship.broken_parts():
				if oldest == null or p.broken_at_tick < oldest.broken_at_tick:
					oldest = p
			return [oldest] if oldest != null else []
		"exhausted_other_own":
			# AT09 — 발동 횟수를 다 쓴 다른 아군. 파손된 파츠는 "활성"이 아니다.
			for p: RefCounted in ship.alive_parts():
				if p != owner and p.is_exhausted():
					return [p]
			return []
		"longest_base_cooldown_other_own":
			# RD08의 희생양. **기본** 쿨타임을 본다 — 지금 진행도가 아니라
			# "가치 있는 느린 지원 파츠"를 고르는 것이 이 파츠의 대가다.
			var victim: RefCounted = null
			for p: RefCounted in ship.alive_parts():
				if p == owner or p.passive or p.is_indestructible():
					continue
				if victim == null or p.base_cooldown_units > victim.base_cooldown_units:
					victim = p
			return [victim] if victim != null else []
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
		"designated_enemy":
			return _designated(ship, _foe(ctx))
	return []

## 「적 지정 파츠」. 한 번 정하면 유지된다 — 부식을 쌓는 파츠와 그것을 읽는 파츠가
## 같은 대상을 봐야 하기 때문이다 (RC02가 쌓고 RC07이 읽는다).
##
## 전투 전 지목 UI는 아직 없다. 기획서 §3.2.6이 함께 적은 재선정 규칙만 쓴다 —
## 활성 적 파츠 중 **남은 쿨다운이 가장 작은** 파츠. 동률이면 슬롯 정의 순서.
static func _designated(ship: RefCounted, foe: RefCounted) -> Array:
	if foe == null:
		return []
	var current: RefCounted = foe.get_part(ship.designated_slot) if ship.designated_slot != "" else null
	if current != null and not current.broken:
		return [current]
	var best: RefCounted = null
	var best_remaining: int = 0
	for p: RefCounted in foe.alive_parts():
		var remaining: int = p.cooldown_units - p.progress_units
		if best == null or remaining < best_remaining:
			best = p
			best_remaining = remaining
	if best == null:
		return []
	ship.designated_slot = best.slot_id
	return [best]

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
	return _slowest_of(_time_targets(ship, null))

## 시간 조작(가속·둔화·충전)을 걸 의미가 있는 다른 아군 파츠 (기획서 §3.2.6).
## 주기 없는 패시브와 소진된 파츠는 제외한다 — 걸어도 아무 일이 일어나지 않아서
## "다른 파츠 하나를 가속"이 조용히 허비되기 때문이다.
static func _time_targets(ship: RefCounted, owner: RefCounted) -> Array:
	var out: Array = []
	for p: RefCounted in ship.parts:
		if p != owner and p.accepts_time_effects():
			out.append(p)
	return out

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
