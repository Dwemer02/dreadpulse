extends RefCounted
## where 조건 평가. 여러 조건이 함께 오면 AND.
##
## ship_state.gd를 preload하지 않는다 — 덕타이핑으로 다룬다 (targeting.gd와 같은 이유).
##
## 알 수 없는 조건 키는 거짓이다. 오타 난 조건이 조용히 항상 참이 되는 것보다
## 조용히 항상 거짓인 편이 배치 리포트에서 눈에 띈다. 같은 이유로, where 자체가
## Dictionary가 아닌 값(문자열/배열 등 — 저작 실수로 잘못 채워진 값)이 들어오면
## 역시 거짓으로 닫는다. null(조건 없음)만 예외로 참이다.

const K = preload("res://sim/sim_const.gd")

const CONDITIONS: Array[String] = [
	"resonance_at_least", "material_at_least",
	"before_seconds", "after_seconds",
	"every_nth_fire", "every_nth_accumulated",
	"is_host", "event_field", "source_faction", "source_keyword",
	"hull_below_ratio", "fires_remaining_at_most", "has_broken_own",
	"own_ship", "enemy_ship",
]

## ctx: {own_ship, enemy_ship, part, event, tick, source_part, accum, accum_prev}
static func evaluate(where: Variant, ctx: Dictionary) -> bool:
	if where == null:
		return true
	if not (where is Dictionary):
		# 저작 실수(where에 Dictionary가 아닌 값)도 fail closed — 조용히 항상 참이
		# 되는 것보다 조용히 항상 거짓인 편이 배치 리포트에서 눈에 띈다.
		return false
	var conditions: Dictionary = where
	for key: String in conditions:
		if not _one(key, conditions[key], ctx):
			return false
	return true

## 카탈로그 검증용 — 알 수 없는 조건 키를 열거한다.
static func unknown_keys(where: Variant) -> Array[String]:
	var out: Array[String] = []
	if where == null or not (where is Dictionary):
		return out
	for key: String in (where as Dictionary):
		if not CONDITIONS.has(key):
			out.append(key)
	return out

static func _one(key: String, value: Variant, ctx: Dictionary) -> bool:
	var ship: RefCounted = ctx["own_ship"]
	var part: RefCounted = ctx.get("part", null)
	var event: Dictionary = ctx.get("event", {})
	var tick: int = int(ctx.get("tick", 0))

	match key:
		"resonance_at_least":
			# prime_oscillator Relic이 요구치를 낮춘다
			return ship.resonance >= maxi(0, int(value) - ship.resonance_discount)
		"material_at_least":
			return ship.material >= int(value)
		"before_seconds":
			return tick < K.secs_to_ticks(float(value))
		"after_seconds":
			return tick >= K.secs_to_ticks(float(value))
		"every_nth_fire":
			var n: int = int(value)
			return n > 0 and part != null and part.fires_used > 0 and part.fires_used % n == 0
		"every_nth_accumulated":
			var spec: Dictionary = value
			var step: int = int(spec.get("n", 0))
			if step <= 0:
				return false
			var before: int = int(ctx.get("accum_prev", 0))
			var after: int = int(ctx.get("accum", 0))
			return (after / step) > (before / step)
		"is_host":
			var same: bool = part != null \
				and str(event.get("slot", "")) == part.slot_id \
				and str(event.get("ship", "")) == ship.side
			return same == bool(value)
		"event_field":
			var spec2: Dictionary = value
			var field: String = str(spec2.get("field", ""))
			if not event.has(field):
				return false
			return event[field] == spec2.get("equals", null)
		"source_faction":
			return str(event.get("faction", "")) == str(value)
		"source_keyword":
			var source: RefCounted = ctx.get("source_part", null)
			return source != null and source.has_keyword(str(value))
		"hull_below_ratio":
			return ship.hull_ratio() < float(value)
		"fires_remaining_at_most":
			return part != null and part.is_limited() and part.fires_remaining <= int(value)
		"has_broken_own":
			return (not ship.broken_parts().is_empty()) == bool(value)
		"own_ship":
			return (str(event.get("ship", "")) == ship.side) == bool(value)
		"enemy_ship":
			return (str(event.get("ship", "")) != ship.side) == bool(value)
	return false
