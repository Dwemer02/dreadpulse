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
	"every_nth_occurrence",
	"is_host", "source_is_host", "event_field", "source_faction", "source_keyword",
	"hull_below_ratio", "fires_remaining_at_most", "has_broken_own",
	"is_accelerated", "own_ship", "enemy_ship",
]

## 이벤트 발생을 **세는** 조건. 나머지 조건이 전부 통과한 뒤에만 세야 한다 —
## 먼저 세면 게이트(is_host 등)를 통과하지 못한 이벤트까지 누적되어
## "숙주가 3회 수리할 때마다"가 조용히 "함선이 3회 수리할 때마다"로 바뀐다.
## trigger_engine이 이 목록을 보고 평가 순서를 둘로 나눈다.
const COUNTING_KEYS: Array[String] = ["every_nth_accumulated", "every_nth_occurrence"]

## where에서 카운팅 조건 키를 찾는다. 없으면 빈 문자열. 둘 이상은 저작 실수다.
static func counting_key(where: Variant) -> String:
	if not (where is Dictionary):
		return ""
	for key: String in COUNTING_KEYS:
		if (where as Dictionary).has(key):
			return key
	return ""

## 카운팅 조건을 뺀 나머지 게이트. null(조건 없음)은 그대로 null.
static func without_counting(where: Variant) -> Variant:
	if not (where is Dictionary):
		return where
	var key: String = counting_key(where)
	if key == "":
		return where
	var out: Dictionary = (where as Dictionary).duplicate()
	out.erase(key)
	return out

## ctx: {own_ship, enemy_ship, part, event, tick, source_part, accum, accum_prev}
## tick이 ctx에 없으면 0(전투 시작)으로 평가된다.
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

## 카탈로그 검증용 — 문제가 있는 키를 열거한다. 빈 배열이면 이상 없음.
## null은 "조건 없음"이므로 정상이지만, Dictionary도 null도 아닌 값은
## 작성 실수다 — evaluate()가 전투 시점에 거짓으로 닫아 파츠가 조용히
## 죽으므로, 로드 시점에 반드시 잡아야 한다.
static func unknown_keys(where: Variant) -> Array[String]:
	var out: Array[String] = []
	if where == null:
		return out
	if not (where is Dictionary):
		out.append("<where가 Dictionary가 아니다: %s>" % type_string(typeof(where)))
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
		"every_nth_occurrence":
			# accum/accum_prev는 trigger_engine이 발생 횟수로 채운다.
			var step2: int = int(value)
			if step2 <= 0:
				return false
			return (int(ctx.get("accum", 0)) / step2) > (int(ctx.get("accum_prev", 0)) / step2)
		"is_accelerated":
			return (part != null and part.accel_ticks != 0) == bool(value)
		"source_is_host":
			# 상태이상 이벤트는 **맞은 쪽** 함선으로 방출된다. 그래서 슬롯만 비교하면
			# 양쪽 함선이 같은 Frame을 쓸 때 이름이 겹쳐 엉뚱한 파츠를 숙주로 본다.
			# source_ship까지 함께 봐야 한다.
			var same_source: bool = part != null 				and str(event.get("source_slot", "")) == part.slot_id 				and str(event.get("source_ship", "")) == ship.side
			return same_source == bool(value)
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
			# source_keyword와 같은 곳(ctx.source_part)을 본다. source_part가 없으면
			# 이벤트가 faction 필드를 직접 실어 보내는 경우(예: part_fired)로 물러선다.
			var src: RefCounted = ctx.get("source_part", null)
			if src != null:
				return src.faction == str(value)
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
