extends RefCounted
## 이벤트 하나를 양측 모든 파츠의 트리거에 매칭하고 실행한다.
##
## 순회 순서는 고정이다 — ships 배열 순서 → 함선의 파츠 순서(= 슬롯 정의 순서) →
## 파츠의 트리거 순서. 결정론 계약이 이 순서에 의존한다.

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")

## ships는 [player, enemy] 순서. sim은 emit/force_fire/schedule/rng/chain_depth/tick을 제공한다.
static func dispatch(event: Dictionary, ships: Array, sim: RefCounted) -> void:
	var depth: int = int(event.get("chain_depth", 0))
	for i: int in ships.size():
		var ship: RefCounted = ships[i]
		var foe: RefCounted = ships[1 - i] if ships.size() == 2 else null

		# Relic 트리거 — 슬롯을 차지하지 않는 함선 수준 보유자.
		_run_list(ship.relic_triggers, ship.relic_trigger_fires, ship.relic_trigger_accum,
			null, ship, foe, event, depth, sim)

		for part: RefCounted in ship.parts:
			# 파손 파츠는 효과가 정지한다. 붙어 있던 Augment 트리거도 함께.
			if part.broken:
				continue
			_run_list(part.triggers, part.trigger_fires, part.trigger_accum,
				part, ship, foe, event, depth, sim)

## trigger.get("where", {})가 Dictionary가 아닌 값(저작 실수)을 돌려줄 수 있다.
## GDScript는 타입 지정 Dictionary 변수에 비-Dictionary 값을 대입하면 그 자체가
## SCRIPT ERROR다 — `.has()`를 걸기 전에 반드시 이 헬퍼로 안전하게 걸러야 한다.
## (최종 조건 평가는 conditions.gd의 fail-closed 정책에 맡긴다 — 원본 값을 그대로 넘긴다.)
static func _where_dict(trigger: Dictionary) -> Dictionary:
	var raw: Variant = trigger.get("where", {})
	if raw is Dictionary:
		return raw
	return {}

static func _run_list(triggers: Array, fires: Array, accums: Variant,
		owner: RefCounted, ship: RefCounted, foe: RefCounted,
		event: Dictionary, depth: int, sim: RefCounted) -> void:
	for index: int in triggers.size():
		var trigger: Dictionary = triggers[index]
		if not _matches(trigger, ship, event):
			continue

		var max_fires: int = int(trigger.get("max_fires", -1))
		if max_fires >= 0 and int(fires[index]) >= max_fires:
			continue

		var where: Dictionary = _where_dict(trigger)
		var accum_prev: int = 0
		var accum: int = 0
		if accums != null and where.has("every_nth_accumulated"):
			var spec: Dictionary = where["every_nth_accumulated"]
			var field: String = str(spec.get("field", "amount"))
			accum_prev = int(accums[index])
			accum = accum_prev + int(event.get(field, 0))
			# 조건이 거짓이어도 누적은 계속된다 — 이벤트 스트림의 러닝 토탈이기 때문이다.
			# (max_fires에 걸려 여기 도달하지 못한 트리거는 누적하지 않는다 — 그 트리거는
			# 이후 무엇이 오든 다시는 발동할 수 없으므로 누적을 계속할 이유가 없다.)
			accums[index] = accum

		# source_part는 이벤트가 난 함선에서 찾아야 한다.
		# 양쪽 함선이 같은 Frame을 쓰면 슬롯 이름이 동일하므로(core, weapon_1, ...),
		# 트리거 소유자의 함선(ship)에서 찾으면 적함 이벤트에 대해 조용히 엉뚱한
		# 파츠를 집는다 — 크래시도 null도 아니라서 발견하기 어렵다.
		var event_ship: RefCounted = ship if str(event.get("ship", "")) == ship.side else foe
		var source_part: RefCounted = null
		if event_ship != null and event.has("slot"):
			source_part = event_ship.get_part(str(event["slot"]))

		var ctx: Dictionary = {
			"sim": sim, "own_ship": ship, "enemy_ship": foe, "part": owner,
			"event": event, "tick": sim.tick, "rng": sim.rng,
			"source_part": source_part,
			"accum": accum, "accum_prev": accum_prev,
			"damage_mult": 1.0,
		}
		# where는 원본 그대로 넘긴다 — Dictionary도 null도 아닌 저작 실수는
		# conditions.gd가 이미 fail-closed(거짓)로 처리한다.
		if not Conditions.evaluate(trigger.get("where", null), ctx):
			continue

		# 깊이 상한을 넘으면 실행하지 않고 흔적을 남긴다
		if depth + 1 > K.MAX_CHAIN_DEPTH:
			sim.emit("chain_capped", ship.side, {
				"slot": owner.slot_id if owner != null else "relic",
				"part_id": owner.part_id if owner != null else "relic",
				"depth": depth,
			})
			continue

		fires[index] = int(fires[index]) + 1
		var restore_depth: int = sim.chain_depth
		sim.chain_depth = depth + 1
		Actions.run_block(trigger.get("do", []), ctx)
		sim.chain_depth = restore_depth

static func _matches(trigger: Dictionary, ship: RefCounted, event: Dictionary) -> bool:
	if str(trigger.get("on", "")) != str(event.get("type", "")):
		return false
	# 기본 범위는 자함이다. enemy_ship을 명시한 트리거만 적함 이벤트를 본다 —
	# 이 기본값이 없으면 모든 파츠가 적의 모든 이벤트에 반응해 체인이 폭발한다.
	var where: Dictionary = _where_dict(trigger)
	if str(event.get("ship", "")) != ship.side and not where.has("enemy_ship"):
		return false
	return true
