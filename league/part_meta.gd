extends RefCounted
## 파츠 하나의 "AI가 읽을 수 있는 요약". 기획서 §6의 메타데이터다.
##
## **손으로 쓰지 않고 파츠 정의에서 뽑아낸다.** 이유는 part_text.gd와 같다 —
## 설명을 데이터에 따로 두면 파츠를 고칠 때 두 곳을 고쳐야 하고 반드시 어긋난다.
## 90종에 메타데이터를 손으로 붙이면 그 어긋남이 AI의 판단 근거가 된다.
##
## 대신 대가가 있다: **op이 늘 때마다 아래 표에 한 줄을 추가해야 한다.**
## `uncovered_ops`가 그걸 눈에 띄게 하고, 테스트가 OPS 전수를 확인한다.
##
## 본체(active)와 증강(augment)을 분리해서 뽑는다 (§6). 같은 파츠라도 어느 자리에
## 쓰느냐에 따라 완전히 다른 기능이기 때문이다.

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")

## op이 만드는 이벤트. **actions.gd의 emit과 짝이 맞아야 한다** —
## 어긋나면 AI가 존재하지 않는 연결을 믿거나 있는 연결을 못 본다.
##
## side는 그 이벤트가 어느 함선 이름으로 방출되는지다.
##   own    자함
##   enemy  적함 (상태이상은 **맞는 쪽**으로 방출된다)
##   target 대상 파츠가 속한 함선 (아군일 수도 적일 수도 있다)
##
## `after`는 그 op이 **나중에 간접적으로** 만드는 이벤트다. 과열을 부여하면 언젠가
## 과열 틱이 돌고, 재생을 걸면 회복이 난다. RC03이 corrosion_ticked를 구독하는 것처럼
## 실제 연결의 절반이 이 간접 경로에 있으므로 함께 센다.
const OP_EFFECTS: Dictionary = {
	"deal_damage":         {"emits": [["damage_dealt", "own"]], "fn": "attack", "hits": "direct"},
	"gain_shield":         {"emits": [["shield_gained", "own"]], "fn": "defend"},
	"repair":              {"emits": [["repaired", "own"]], "fn": "heal"},
	"apply_regen":         {"emits": [["regen_applied", "own"]],
							"after": [["regen_ticked", "own"], ["repaired", "own"]], "fn": "heal"},
	"apply_overheat":      {"emits": [["overheat_applied", "enemy"]],
							"after": [["overheat_ticked", "enemy"]],
							"fn": "attack", "hits": "overheat"},
	"cleanse_overheat":    {"emits": [["overheat_cleansed", "enemy"]], "fn": "convert"},
	"apply_corrosion":     {"emits": [["corrosion_applied", "target"]],
							"after": [["corrosion_ticked", "target"]],
							"fn": "attack", "hits": "corrosion"},
	"cleanse_corrosion":   {"emits": [["corrosion_cleansed", "target"]], "fn": "cleanse"},
	"apply_fracture":      {"emits": [["fracture_applied", "enemy"]],
							"after": [["collapsed", "enemy"]],
							"fn": "attack", "hits": "fracture"},
	"apply_stasis":        {"emits": [["stasis_applied", "target"]],
							"after": [["stasis_ended", "target"]], "fn": "time"},
	"accelerate":          {"emits": [["speed_changed", "own"]], "fn": "time"},
	"slow":                {"emits": [["speed_changed", "own"]], "fn": "time"},
	"charge":              {"emits": [["charge_applied", "target"]], "fn": "time"},
	"shorten_cooldown":    {"emits": [["cooldown_shortened", "own"]], "fn": "time"},
	"drain_fires":         {"emits": [["fires_changed", "own"]], "fn": "attack"},
	"restore_fires":       {"emits": [["fires_changed", "own"]], "fn": "restore"},
	"make_indestructible": {"emits": [["indestructible_applied", "own"]], "fn": "defend"},
	"reinforce":           {"emits": [["reinforce_gained", "own"]], "fn": "defend"},
	"destroy_part":        {"emits": [["part_destroyed", "own"]], "fn": "sacrifice"},
	"destroy_self":        {"emits": [["part_destroyed", "own"]], "fn": "sacrifice"},
	"restore_part":        {"emits": [["part_restored", "own"]], "fn": "restore"},
	"grow":                {"emits": [["growth_changed", "own"]], "fn": "growth"},
	"gain_material":       {"emits": [["material_gained", "own"]], "fn": "produce"},
	"spend_material":      {"emits": [["material_spent", "own"]], "fn": "convert"},
	"gain_resonance":      {"emits": [["resonance_gained", "own"]], "fn": "produce"},
	"fire_part":           {"emits": [["part_fired", "own"]], "fn": "time"},
	"multi_fire":          {"emits": [["multi_fire_queued", "own"], ["part_fired", "own"]],
							"fn": "time"},
}

## 파츠가 발동하기만 해도 나는 이벤트. 트리거 파츠(패시브)는 발동하지 않으므로 없다.
const FIRE_EVENTS: Array = [["part_fired", "own"]]

## 트리거·전제 조건 중 "이 파츠가 무언가를 필요로 한다"는 신호.
## 병목 판정(§5.3의 "현재 병목의 해소")이 이걸 읽는다.
const GATING_CONDITIONS: Array[String] = [
	"material_at_least", "resonance_at_least", "is_accelerated",
	"has_broken_own", "has_exhausted_own", "has_other_own",
	"enemy_overheat_at_least", "enemy_fracture_ratio_at_least",
	"designated_corrosion_at_least",
]

## 파츠 정의에서 본체 메타데이터를 뽑는다.
static func of_body(def: Dictionary) -> Dictionary:
	var active: Dictionary = def.get("active", {})
	var meta: Dictionary = _blank(def)
	meta["role"] = str(def.get("base_role", ""))
	meta["passive"] = not active.has("cooldown")
	meta["cooldown"] = float(active.get("cooldown", 0.0))
	meta["fire_limit"] = int(active.get("fire_limit", K.UNLIMITED))

	var cost: int = int((active.get("cost", {}) as Dictionary).get("material", 0))
	if cost > 0:
		meta["consumes"]["material"] = int(meta["consumes"].get("material", 0)) + cost
		(meta["emits"] as Array).append(["material_spent", "own"])
		(meta["prerequisites"] as Array).append("material")
	_collect_conditions(meta, active.get("require", null))

	if not meta["passive"]:
		for pair: Array in FIRE_EVENTS:
			_add_event(meta["emits"], pair)
	_scan_block(meta, active.get("on_fire", []), true)
	for tr: Variant in active.get("triggers", []):
		_scan_trigger(meta, tr as Dictionary)
	_finish(meta)
	return meta

## 증강 메타데이터. 증강은 **트리거 뭉치**이므로 쿨타임이 없고, 숙주가 무엇이냐에 따라
## 발동 빈도가 달라진다. 그래서 초당 출력이 아니라 "1회 발동당 출력"으로만 잰다.
static func of_augment(def: Dictionary) -> Dictionary:
	var meta: Dictionary = _blank(def)
	meta["role"] = str(def.get("base_role", ""))
	meta["passive"] = true
	if not def.has("augment"):
		# 증강 블록이 없는 파츠도 빈 메타데이터를 갖는다 — 조회 필드가 없으면
		# 소비자가 매번 존재 여부를 확인해야 하고, 한 곳만 빠뜨려도 런타임 에러다.
		meta["usable"] = false
		_finish(meta)
		return meta
	var aug: Dictionary = def["augment"]
	meta["add_keywords"] = (aug.get("add_keywords", []) as Array).duplicate()
	for tr: Variant in aug.get("triggers", []):
		_scan_trigger(meta, tr as Dictionary)
	_finish(meta)
	return meta

# --- 내부 ---

static func _blank(def: Dictionary) -> Dictionary:
	return {
		"part_id": str(def.get("id", "")),
		"faction": str(def.get("faction", "")),
		"archetype": str(def.get("archetype", "")),
		"usable": true,
		"produces": {},          # 자원 -> 1회당 양
		"consumes": {},
		"emits": [],             # [[event, side], ...] — 간접(after)까지 포함한다
		"listens": [],           # [[event, side], ...]
		"prerequisites": [],     # material / accelerated / broken_own / ...
		"functions": [],         # attack / defend / heal / time / produce / convert / ...
		"damage_paths": [],      # direct / overheat / corrosion / fracture
		# 숙주 한정 트리거만 갖는가. 참이면 이 단위는 자기 숙주하고만 연결된다.
		"host_only": false,
		# 발동 뒤 스스로 파괴되는가. 초당 출력 추정이 이걸 반드시 봐야 한다 —
		# 보지 않으면 한 발 쏘고 죽는 파츠가 영구 무기보다 높게 평가된다 (r5 §7.1).
		"one_shot": false,
		"burst_output": 0,       # 1회 발동당 피해 상당량
		"burst_sustain": 0,      # 1회 발동당 회복·보호막 상당량
		"trigger_output": 0,     # 트리거 1회당 피해 상당량
		"trigger_sustain": 0,
		"uncovered_ops": [],
	}

static func _scan_trigger(meta: Dictionary, trigger: Dictionary) -> void:
	var where: Variant = trigger.get("where", null)
	var side: String = "own"
	if where is Dictionary and bool((where as Dictionary).get("enemy_ship", false)):
		side = "enemy"
	# **숙주 한정 트리거는 숙주 하나만 듣는다.** is_host / source_is_host가 그 표시다.
	#
	# 이걸 무시하면 "숙주 발동 시" 증강이 보드의 **모든** 본체와 연결된 것으로 세어져,
	# 연결 수가 정규화 상한을 넘어 포화한다. 포화한 특징은 어떤 후보를 골라도 1.0이라
	# 전략 사이의 차이를 만들지 못한다 — 실측에서 네 전략 전부 연결 1.00이 나왔다.
	if where is Dictionary and (bool((where as Dictionary).get("is_host", false))
			or bool((where as Dictionary).get("source_is_host", false))):
		meta["host_only"] = true
	_add_event(meta["listens"], [str(trigger.get("on", "")), side])
	_collect_conditions(meta, where)
	_scan_block(meta, trigger.get("do", []), false)

static func _scan_block(meta: Dictionary, block: Array, on_fire: bool) -> void:
	for item: Variant in block:
		var action: Dictionary = item
		var op: String = str(action.get("op", ""))
		_collect_conditions(meta, action.get("where", null))
		if not OP_EFFECTS.has(op):
			# 조용히 0점 처리하지 않는다 (§5.3) — 모르는 op은 coverage 경고로 노출한다.
			if not (meta["uncovered_ops"] as Array).has(op):
				(meta["uncovered_ops"] as Array).append(op)
			continue
		var spec: Dictionary = OP_EFFECTS[op]
		for pair: Variant in spec.get("emits", []):
			_add_event(meta["emits"], pair as Array)
		for pair2: Variant in spec.get("after", []):
			_add_event(meta["emits"], pair2 as Array)
		if op == "destroy_self":
			meta["one_shot"] = true
		var fn: String = str(spec.get("fn", ""))
		if fn != "" and not (meta["functions"] as Array).has(fn):
			(meta["functions"] as Array).append(fn)
		if spec.has("hits"):
			var path: String = str(spec["hits"])
			if not (meta["damage_paths"] as Array).has(path):
				(meta["damage_paths"] as Array).append(path)
		_account(meta, op, action, on_fire)

## 수치 기여. **거친 추정이다** (§5.3) — 성장분·적층 비례분은 지금 값을 모르므로
## 기본 수치만 센다. 그 사실을 태그로 남겨 평가자가 할인할 수 있게 한다.
static func _account(meta: Dictionary, op: String, action: Dictionary, on_fire: bool) -> void:
	var output_key: String = "burst_output" if on_fire else "trigger_output"
	var sustain_key: String = "burst_sustain" if on_fire else "trigger_sustain"
	match op:
		"deal_damage":
			meta[output_key] = int(meta[output_key]) + int(action.get("amount", 0))
		"apply_overheat":
			# 과열 1적층은 여러 틱에 걸쳐 아프다. 직접 피해와 같은 단위로 두면
			# 부여형 파츠가 과소평가되므로 대략 2배로 환산한다.
			meta[output_key] = int(meta[output_key]) + int(action.get("stacks", 0)) * 2
		"apply_fracture":
			meta[output_key] = int(meta[output_key]) + int(action.get("amount", 0))
		"apply_corrosion":
			# 부식은 **적이 발동해야** 아프다. 적 행동 의존이므로 절반만 인정한다.
			meta[output_key] = int(meta[output_key]) + int(action.get("stacks", 0))
		"repair", "gain_shield":
			meta[sustain_key] = int(meta[sustain_key]) + int(action.get("amount", 0))
		"apply_regen":
			# Regen은 2초마다 회복한다. 지속시간 안의 실제 회복 횟수만 인정한다.
			var duration: float = float(action.get("duration", 0.0))
			var ticks: int = 3 if duration < 0.0 else int(duration / 2.0)
			meta[sustain_key] = int(meta[sustain_key]) + int(action.get("amount", 0)) * ticks
		"gain_material":
			_add_amount(meta["produces"], "material", int(action.get("amount", 0)))
		"gain_resonance":
			_add_amount(meta["produces"], "resonance", int(action.get("amount", 0)))
		"spend_material":
			_add_amount(meta["consumes"], "material", int(action.get("amount", 0)))
		"multi_fire":
			_add_amount(meta["consumes"], "material", int(action.get("cost_material", 0)))

static func _add_amount(bag: Dictionary, key: String, amount: int) -> void:
	if amount > 0:
		bag[key] = int(bag.get(key, 0)) + amount

static func _add_event(list: Array, pair: Array) -> void:
	if str(pair[0]) == "":
		return
	for existing: Variant in list:
		if str((existing as Array)[0]) == str(pair[0]) \
				and str((existing as Array)[1]) == str(pair[1]):
			return
	list.append([str(pair[0]), str(pair[1])])

static func _collect_conditions(meta: Dictionary, where: Variant) -> void:
	if not (where is Dictionary):
		return
	for key: String in (where as Dictionary):
		if GATING_CONDITIONS.has(key) and not (meta["prerequisites"] as Array).has(key):
			(meta["prerequisites"] as Array).append(key)

## 이벤트 목록을 조회용 Dictionary로 굳힌다.
##
## 성능이 이유다. 연결 판정은 800명 × 15라운드 × 수백 후보만큼 돌고, 배열끼리
## 이중 루프로 비교하면 그 자체가 배치의 병목이 된다. 키는 "이벤트@방향"이다 —
## 방향을 키에 넣어야 "적함에 나는 과열 틱을 자함 스코프로 듣는" 가짜 연결이
## 애초에 만들어지지 않는다.
static func _freeze(meta: Dictionary) -> void:
	for field: String in ["emits", "listens"]:
		var keys: Dictionary = {}
		for pair: Variant in meta[field]:
			keys["%s@%s" % [str((pair as Array)[0]), str((pair as Array)[1])]] = true
		meta[field + "_keys"] = keys

## 이 파츠가 **채워줄 수 있는 전제**의 이름. build_graph의 병목 이름과 같은 어휘다.
##
## 미래 가치 평가의 재료다 (r5 피드백 §2.3): "가까운 획득으로 실제 열릴 수 있는 연결"을
## 재려면 "누가 이 병목을 풀 수 있는가"를 알아야 한다. 병목 개수만 세면 **작동하지 않는
## 상태 자체가 미래 가치로 보상된다** — r5에서 실제로 그랬다.
static func supplies_of(meta: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var emits: Dictionary = meta.get("emits_keys", {})
	if int((meta["produces"] as Dictionary).get("material", 0)) > 0:
		out["material"] = true
	if int((meta["produces"] as Dictionary).get("resonance", 0)) > 0:
		out["resonance"] = true
	for pair: Array in [
			["speed_changed@own", "accelerate"],
			["overheat_applied@enemy", "overheat"],
			["corrosion_applied@target", "corrosion"],
			["fracture_applied@enemy", "fracture"],
			["part_destroyed@own", "has_broken_own"],
			["fires_changed@own", "has_exhausted_own"],
	]:
		if emits.has(str(pair[0])):
			out[str(pair[1])] = true
	# 이벤트 병목은 "event:<이름>"으로 적힌다. 방향은 병목 쪽에서 이미 걸렀으므로
	# 여기서는 이름만 맞추면 된다.
	for key: String in emits:
		out["event:" + key.get_slice("@", 0)] = true
	return out

## 파츠 여러 종이 함께 채울 수 있는 전제의 합집합.
## 창고 보유분과 팩션 풀 전체에 각각 쓴다.
static func supplies_of_parts(index: Dictionary, part_ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for part_id: Variant in part_ids:
		if not index.has(str(part_id)):
			continue
		for slot: String in ["body", "augment"]:
			var meta: Dictionary = (index[str(part_id)] as Dictionary)[slot]
			if not bool(meta.get("usable", true)):
				continue
			for need: String in supplies_of(meta):
				out[need] = true
	return out

static func _finish(meta: Dictionary) -> void:
	_freeze(meta)
	# 어휘가 하나도 없는 단위 — 효과 없는 리그 Core가 이것이다.
	# **평가 단위로 세면 안 된다.** r5에서는 이 Core가 늘 "침묵 파츠"로 잡혀
	# dead가 한 번도 0이 되지 않았고, potential에 0.25가 상수로 깔렸다.
	meta["inert"] = (meta["emits"] as Array).is_empty() \
		and (meta["listens"] as Array).is_empty() \
		and (meta["produces"] as Dictionary).is_empty() \
		and (meta["consumes"] as Dictionary).is_empty()
	# 시동 요구 — 처음부터 그냥 도는 파츠인가, 무언가를 받아야 시작하는가.
	meta["startup_required"] = not (meta["prerequisites"] as Array).is_empty() \
		or bool(meta["passive"])
	meta["coverage"] = "partial" if not (meta["uncovered_ops"] as Array).is_empty() else "auto"

## 카탈로그 전체의 메타데이터를 한 번에 만든다. 전투마다 다시 뽑으면 800명 × 15라운드가
## 감당이 안 된다 — 배치 시작에 한 번 만들고 계속 읽는다.
static func build_index(catalog: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for part_id: String in catalog.parts:
		var def: Dictionary = catalog.parts[part_id]
		out[part_id] = {"body": of_body(def), "augment": of_augment(def)}
	return out

## coverage 리포트 (§14의 "90종 모두 지원하는지 coverage 보고").
## 어떤 파츠의 어떤 op이 추정에서 빠졌는지 그대로 돌려준다.
static func coverage_report(index: Dictionary) -> Dictionary:
	var partial: Array[String] = []
	var ops: Dictionary = {}
	for part_id: String in index:
		for slot: String in ["body", "augment"]:
			var meta: Dictionary = (index[part_id] as Dictionary)[slot]
			for op: Variant in meta["uncovered_ops"]:
				ops[str(op)] = int(ops.get(str(op), 0)) + 1
				if not partial.has(part_id):
					partial.append(part_id)
	return {"partial_parts": partial, "uncovered_ops": ops,
		"total": index.size(), "covered": index.size() - partial.size()}
