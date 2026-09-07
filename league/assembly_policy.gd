extends RefCounted
## 전략 하나가 "무엇을 할지" 고른다. 기획서 §5.2·§5.4·§5.5.
##
## 팩션 이름·파츠 ID·완성 레시피를 우선순위로 하드코딩하지 않는다 (§5). 전략의 차이는
## 전부 build_evaluator의 가중치와 목표 유지 규칙에서만 나온다 — 그래야 "AI가 이 파츠를
## 이해하지 못한 것인가, 파츠가 약한 것인가"를 나중에 구분할 수 있다.
##
## 상대 빌드·비공개 보상·전투 난수·미래 제안을 받지 않는다 (§5.5 마지막).
##
## **예외가 하나 있다: 고정 레시피 추종형** (r5b §7.2). 그 비교군의 존재 이유가
## "이전에 성공한 조합을 목표로 고정한다"이므로 파츠 ID 목록을 미리 안다. 목표는
## 첫 시작 파츠를 받기 전에 정해지고 런 도중 바뀌지 않으며, 미래 제안은 여전히
## 보지 않는다. 유연형 4종은 이 경로를 타지 않는다 — recipe_id가 빈 문자열이다.

const Generator = preload("res://league/candidate_generator.gd")
const Graph = preload("res://league/build_graph.gd")
const Evaluator = preload("res://league/build_evaluator.gd")
const Inventory = preload("res://run/inventory.gd")
const PartMeta = preload("res://league/part_meta.gd")
const Recipes = preload("res://league/recipes.gd")

var strategy: String = "immediate"
var config: RefCounted            # LeagueConfig

## 엔진 투자형의 목표. **특정 파츠 ID가 아니라 필요한 자원·이벤트·기능 이름**이다 (§5.5).
var goal: String = ""
var goal_stale_choices: int = 0

## 고정 레시피형의 목표 레시피 id. 유연형은 빈 문자열이고, 한번 정해지면 바뀌지 않는다.
var recipe_id: String = ""

func setup(strategy_id: String, league_config: RefCounted,
		fixed_recipe_id: String = "") -> void:
	strategy = strategy_id
	config = league_config
	recipe_id = fixed_recipe_id

## 보상 하나를 이미 인벤토리에 넣은 상태에서, 무엇을 할지 정한다.
##
## ctx: {catalog, slots, meta_index, allow_augment, require_operational, rng}
## 반환: {inventory, chain, score, features, shortlist, goal, goal_reason}
func decide(inv: RefCounted, ctx: Dictionary) -> Dictionary:
	var before: Dictionary = _analyze(inv, ctx)
	_refresh_goal(before)

	# 폭 우선 탐색. **통과 못 한 상태도 계속 펼친다**는 것이 요점이다.
	#
	# 첫 전투 준비는 "획득한 파츠를 전부 본체로 놓아라"를 요구한다. 파츠 하나를 놓은
	# 중간 상태는 그 요구를 아직 만족하지 못하지만, 거기서 하나 더 놓아야 만족한다 —
	# 중간 상태를 탐색에서 버리면 유효한 조립에 영원히 도달하지 못한다.
	var seen: Dictionary = {}
	var accepted: Array = []
	var frontier: Array = []
	var root: Dictionary = _visit(inv, [], before, ctx, seen, accepted)
	if not root.is_empty():
		frontier.append(root)

	for _depth: int in config.candidate_depth:
		var next: Array = []
		for state: Dictionary in frontier:
			for action: Dictionary in Generator.expand(state["inventory"], ctx):
				var chain: Array = (state["chain"] as Array).duplicate()
				chain.append(action)
				var entry: Dictionary = _visit(action["result"], chain, before, ctx,
					seen, accepted)
				if not entry.is_empty():
					next.append(entry)
		if next.is_empty():
			break
		# 깊이·후보 수는 모든 AI에 동일하다 — 성능을 이유로 특정 전략만 좁히지 않는다 (§5.2).
		next.sort_custom(_by_score)
		frontier = next.slice(0, mini(config.beam_width, next.size()))

	if accepted.is_empty():
		# **0점으로 돌려주면 안 된다.** 초반 점수는 흔히 음수다(빈 본체 자리·공격 불능
		# 페널티). 실패 신호가 0이면 그것이 정상 후보를 이겨서, 조립할 수 있는 파츠를
		# 두고 "아무것도 안 함"을 고르는 일이 생긴다 — 실제로 시작 조립 실패의 원인이었다.
		return {"valid": false, "inventory": inv, "chain": [], "score": -INF,
			"features": {}, "shortlist": [], "goal": goal,
			"candidate_counts": {"visited": seen.size(), "accepted": 0,
				"shortlisted": 0,
				"reward_uses": {"body": 0, "augment": 0, "storage": 0, "gone": 0}},
			"best_potential": 0.0, "chosen_use": "", "keep_score": -INF,
			"recipe": Recipes.progress(recipe_id, inv), "recipe_id": recipe_id,
			"goal_reason": "유효한 조립 후보 없음"}

	accepted.sort_custom(_by_score)
	var shortlist: Array = _shortlist(accepted)
	var reward_uses: Dictionary = _count_reward_uses(accepted)
	var picked: Dictionary = _pick(shortlist, ctx["rng"])
	_note_progress(before, picked)
	return {
		"valid": true,
		"inventory": picked["inventory"], "chain": picked["chain"],
		"score": picked["score"], "features": picked["features"],
		"shortlist": _log_of(shortlist),
		# 후보 수를 단계별로 남긴다. shortlist(잘린 상위 몇 개)만으로는
		# "쓸 수 있는 다른 선택지가 몇 개였는지" 셀 수 없다 (§9.1).
		"candidate_counts": {
			"visited": seen.size(), "accepted": accepted.size(),
			"shortlisted": shortlist.size(),
			# 이 보상을 본체/증강/보관으로 쓴 **합법 후보 수**를 따로 센다.
			# accepted 합계만으로는 "본체 후보가 아예 없었다"와 "있었지만 낮게
			# 평가됐다"를 구별할 수 없다 — §5.1이 요구한 2단계와 3단계의 분리다.
			"reward_uses": reward_uses,
		},
		# 이 선택에서 가장 높게 평가된 **미래 가치**. 최종 선택의 potential만 보면
		# 준비 후보가 있었는데 낮게 평가된 경우가 0으로 보인다 (§5.1).
		"best_potential": _best_of(accepted, "potential"),
		# §9.1의 "즉시 유효 제안률"을 재려면 **아무것도 안 했을 때의 점수**가
		# 있어야 한다. 그것보다 나은 후보가 하나도 없으면 그 제안은 이 참가자에게
		# 쓸모가 없었던 것이고, 최고 점수의 절대값만으로는 그것을 알 수 없다.
		"keep_score": _keep_score(accepted),
		"chosen_use": str(picked["reward_use"]),
		"recipe": picked["recipe"],
		"recipe_id": recipe_id,
		"goal": goal, "goal_reason": _goal_reason,
	}

# --- 내부 ---

var _goal_reason: String = ""

## 이번 보상 개체가 이 보드에서 어떻게 쓰였는가. "body" | "augment" | "storage" | "gone".
static func _reward_use(inv: RefCounted, uid: int) -> String:
	if uid == Inventory.NONE:
		return ""
	if inv.part_id_of(uid) == "":
		return "gone"          # 폐기됐다
	for slot_id: String in inv.board:
		var entry: Dictionary = inv.board[slot_id]
		if int(entry.get("active", Inventory.NONE)) == uid:
			return "body"
		if int(entry.get("augment", Inventory.NONE)) == uid:
			return "augment"
	return "storage"

static func _count_reward_uses(accepted: Array) -> Dictionary:
	var out: Dictionary = {"body": 0, "augment": 0, "storage": 0, "gone": 0}
	for entry: Dictionary in accepted:
		var use: String = str(entry["reward_use"])
		if out.has(use):
			out[use] = int(out[use]) + 1
	return out

## 아무 조작도 하지 않은 상태의 점수. 보상은 이미 창고에 들어와 있으므로
## "유지"는 곧 **그 보상을 창고에 둔 채 보드를 그대로 두는 것**이다.
static func _keep_score(accepted: Array) -> float:
	for entry: Dictionary in accepted:
		if (entry["chain"] as Array).is_empty():
			return float(entry["score"])
	return -INF

## 합법 후보 전체에서 그 특징의 최대값.
static func _best_of(accepted: Array, key: String) -> float:
	var best: float = 0.0
	for entry: Dictionary in accepted:
		best = maxf(best, float((entry["features"] as Dictionary).get(key, 0.0)))
	return best

## 공급 근접도는 **후보 상태마다 다시 계산한다**. 창고에 무엇이 남았는지가
## 후보마다 달라지기 때문이다 — 창고 파츠를 보드에 올리면 그 파츠는 더 이상
## "곧 채울 수 있는 공급원"이 아니다.
func _analyze(inv: RefCounted, ctx: Dictionary) -> Dictionary:
	return Graph.analyze(Generator.placed_units(inv, ctx["catalog"], ctx["meta_index"]),
		int(ctx.get("body_slots", 0)), _supply(inv, ctx))

## 병목 이름 -> 근접도. 창고에 있으면 1.0, 이 참가자의 풀에서 구할 수 있으면 0.5.
## 풀에서 아예 구할 수 없는 병목은 넣지 않는다 — 미래 가치로 인정하지 않는다.
func _supply(inv: RefCounted, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = (ctx.get("pool_supply", {}) as Dictionary).duplicate()
	var stored: Array[String] = []
	for item: Dictionary in inv.unplaced():
		stored.append(str(item["part_id"]))
	for need: String in PartMeta.supplies_of_parts(ctx["meta_index"], stored):
		out[need] = 1.0
	return out

## 상태 하나를 평가한다. 이미 본 보드면 null.
##
## 반환하는 것과 accepted에 넣는 것은 다르다:
##   반환  = 계속 펼칠 수 있는 상태 (제약을 아직 못 채워도 된다)
##   채택  = 실제로 고를 수 있는 상태 (제약을 전부 만족한다)
##
## 첫 전투 준비의 두 요구는 시점이 다르다 (§4.2).
##   min_bodies   획득한 파츠를 전부 본체로 놓아야 한다 — 매 선택마다
##   operational  실제 공격 경로가 있어야 한다 — 마지막 선택에서만
func _visit(inv: RefCounted, chain: Array, before: Dictionary, ctx: Dictionary,
		seen: Dictionary, accepted: Array) -> Dictionary:
	var sig: String = Generator.signature(inv)
	if seen.has(sig):
		return {}
	seen[sig] = true

	var after: Dictionary = _analyze(inv, ctx)
	var recipe: Dictionary = Recipes.progress(recipe_id, inv)
	var result: Dictionary = Evaluator.score(before, after, strategy, goal,
		{"recipe_progress": float(recipe["progress"])})
	var entry: Dictionary = {
		"inventory": inv, "chain": chain, "signature": sig,
		"score": float(result["total"]), "features": result["features"],
		"analysis": after, "recipe": recipe,
		# 이번 보상 개체가 이 후보에서 어떻게 쓰였는가. §5.1의 2단계
		# "합법적인 본체·증강·보관 후보가 생성됐는가"를 세는 자리다.
		"reward_use": _reward_use(inv, int(ctx.get("reward_uid", Inventory.NONE))),
	}

	var bodies: int = inv.board.size() - _core_slots(inv, ctx)
	var ok: bool = bodies >= int(ctx.get("min_bodies", 0))
	if ok and bool(ctx.get("require_operational", false)) and not bool(after["operational"]):
		ok = false
	# 유지 행동은 항상 후보에 있다 (§5.4). 시작 준비만 예외이고, 그건 min_bodies가 막는다.
	if ok:
		accepted.append(entry)
	return entry

func _core_slots(inv: RefCounted, ctx: Dictionary) -> int:
	var count: int = 0
	for slot_def: Dictionary in ctx["slots"]:
		if str(slot_def["role"]) == "core" and inv.board.has(str(slot_def["id"])):
			count += 1
	return count

static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	# 동점 정렬은 안정적인 행동 ID로 (§5.4). 보드 서명이 그 역할을 한다 —
	# 사전순은 임의지만 **재현 가능**하다는 것이 요점이다.
	return str(a["signature"]) < str(b["signature"])

## 최고점에서 고정 허용 폭 이내인 후보만 남기고, 중복을 없앤 상위 3개를 돌려준다.
func _shortlist(scored: Array) -> Array:
	var best: float = float(scored[0]["score"])
	var out: Array = []
	for entry: Dictionary in scored:
		if float(entry["score"]) < best - config.shortlist_score_gap:
			break
		out.append(entry)
		if out.size() >= config.shortlist_size:
			break
	return out

## 순위 확률 60/30/10. 후보가 적으면 정규화한다 (§5.4).
## 확률 선택은 별도 시드를 쓴다 — 전투 난수와 섞이면 재현이 흐려진다.
func _pick(shortlist: Array, rng: RandomNumberGenerator) -> Dictionary:
	if shortlist.size() == 1:
		return shortlist[0]
	# **실제 동점이면 그룹 안에서 균등 선택한다** (§6.3).
	# 고정 정렬 뒤 60/30/10을 적용하면 먼저 나열된 후보가 유리해진다 — 점수가 같은데
	# 순서 때문에 60%를 받는 것은 평가가 아니라 정렬의 결과다.
	var top: float = float(shortlist[0]["score"])
	var tied: Array = []
	for entry: Dictionary in shortlist:
		if is_equal_approx(float(entry["score"]), top):
			tied.append(entry)
	if tied.size() == shortlist.size():
		return tied[rng.randi_range(0, tied.size() - 1)]
	var total: int = 0
	for i: int in shortlist.size():
		total += config.rank_weights[mini(i, config.rank_weights.size() - 1)]
	var roll: int = rng.randi_range(0, total - 1)
	for i2: int in shortlist.size():
		var w: int = config.rank_weights[mini(i2, config.rank_weights.size() - 1)]
		if roll < w:
			return shortlist[i2]
		roll -= w
	return shortlist[shortlist.size() - 1]

## 엔진 투자형의 목표 유지 (§5.5). 다른 전략은 목표를 갖지 않는다.
##
## 목표는 **지금 가장 많은 파츠를 침묵시키고 있는 병목**이다. 파츠 ID가 아니라
## 자원·이벤트 이름이므로, 그 병목을 푸는 파츠가 무엇이든 진전으로 인정된다.
func _refresh_goal(before: Dictionary) -> void:
	if strategy != "engine":
		goal = ""
		return
	var missing: Dictionary = before["missing"]
	if goal != "" and int(missing.get(goal, 0)) > 0 \
			and goal_stale_choices < config.goal_reconsider_after:
		_goal_reason = "목표 유지: %s" % goal
		return
	var best: String = ""
	var best_count: int = 0
	for need: String in missing:
		if int(missing[need]) > best_count:
			best_count = int(missing[need])
			best = need
	if best == goal:
		_goal_reason = "목표 유지: %s (대안 없음)" % goal if goal != "" else "목표 없음"
		return
	_goal_reason = "목표 %s → %s" % [goal if goal != "" else "없음", best if best != "" else "없음"]
	goal = best
	goal_stale_choices = 0

## 이번 선택이 목표에 진전이 있었는지 센다. 3회 연속 진전이 없으면 목표를 다시 고른다.
func _note_progress(before: Dictionary, picked: Dictionary) -> void:
	if strategy != "engine" or goal == "":
		return
	var after: Dictionary = picked["analysis"]
	var was: int = int((before["missing"] as Dictionary).get(goal, 0))
	var now: int = int((after["missing"] as Dictionary).get(goal, 0))
	if now < was:
		goal_stale_choices = 0
	else:
		goal_stale_choices += 1

## 선택 로그에 남길 상위 후보들. 점수만이 아니라 요소별 점수까지 남긴다 (§11.1) —
## "왜 이걸 골랐나"를 나중에 사람이 읽어야 하기 때문이다.
func _log_of(shortlist: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in shortlist:
		var steps: Array[String] = []
		for action: Variant in entry["chain"]:
			steps.append(Generator.describe(action as Dictionary, entry["inventory"]))
		out.append({
			"action": "유지" if steps.is_empty() else " → ".join(steps),
			# **원 정밀도로 남긴다.** 0.01로 깎으면 "동점"이 실제 동점인지 반올림
			# 결과인지 구별할 수 없다 — r5b에서 정확히 그랬다 (§6.3·§10.1).
			"score": float(entry["score"]),
			"signature": str(entry["signature"]),
			"reward_use": str(entry["reward_use"]),
			"features": _rounded(entry["features"]),
		})
	return out

static func _rounded(features: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in features:
		var value: Variant = features[key]
		out[key] = snappedf(float(value), 0.01) if value is float else value
	return out
