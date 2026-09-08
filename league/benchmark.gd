extends RefCounted
## 고정 상대군 재전투 (r5b 피드백 §8.4).
##
## **왜 필요한가**: 같은 리그 안에서 서로 경쟁하면 모두 강해져도 전체 승패 합은 크게
## 달라지지 않는다. 리그 평균 승률이나 최종 생존 인원만으로는 조건을 고를 수 없다.
## 그래서 각 빌드를 **실험 전에 고정한 바깥 상대군**에 붙인다.
##
## 이 파일은 전투를 새로 구현하지 않는다 — `combat_adapter.fight()`를 그대로 부른다.
##
## 난수 처리 (§8.4 마지막): 고정 시드 묶음을 쓰고 **좌우를 교환해 두 번** 싸운다.
## 한쪽으로만 붙이면 선공·슬롯 순서 편향이 결과에 그대로 남는다.

const CombatAdapter = preload("res://league/combat_adapter.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Config = preload("res://league/league_config.gd")

## 고정 전투 시드. 리그 배치의 시드와 **분리한다** — 벤치마크 결과가 배치마다
## 달라지면 기준선이 아니다.
const SEEDS: Array[int] = [9001, 9002, 9003]

## 빌드 하나를 상대군 전체에 붙인다.
##
## rules는 combat_sim에 주입할 선택 규칙이다. 진단에서 초과 피해를 끄려면
## 빈 Dictionary를 넘긴다 — 그러면 시간 상한(120초)까지 가고 timeout이 된다.
##
## collect가 참이면 판별 결과를 **판 단위로** 함께 돌려준다 (per_match). ON/OFF를
## 짝지어 비교하려면 집계값만으로는 안 된다 — 승률 차이는 분모가 서로 다르기
## 때문에 "규칙과 무관하다"를 증명하지 못한다 (A~G 검토 §6.3). 기본은 꺼둔다:
## 참가자 수백 명 배치에서 이것을 JSON에 그대로 쓰면 파일이 폭발한다.
##
## 반환: {matches, wins, losses, draws, unresolved, errors, win_rate,
##        avg_elapsed, overtime_decided, per_stage, per_opponent, per_match}
static func run(catalog: RefCounted, config: RefCounted, build: Dictionary,
		opponents: Array, rules: Dictionary, label: String = "",
		seeds: Array[int] = SEEDS, collect: bool = false) -> Dictionary:
	var totals: Dictionary = _blank()
	var per_stage: Dictionary = {}
	var per_opponent: Array = []
	var per_match: Array = []

	for opponent: Dictionary in opponents:
		var row: Dictionary = _blank()
		for combat_seed: int in seeds:
			# 좌우 교환. 같은 시드에서 두 번 싸우고 둘 다 센다.
			_fight_into(row, catalog, config, build, opponent["build"],
				combat_seed, true, rules, per_match, str(opponent["id"]))
			_fight_into(row, catalog, config, build, opponent["build"],
				combat_seed, false, rules, per_match, str(opponent["id"]))
		var stage: String = str(opponent["stage"])
		if not per_stage.has(stage):
			per_stage[stage] = _blank()
		_merge(per_stage[stage], row)
		_merge(totals, row)
		per_opponent.append({
			"opponent": str(opponent["id"]), "stage": stage,
			"bucket": str(opponent["bucket"]), "result": _summed(row),
		})

	var out: Dictionary = _summed(totals)
	out["label"] = label
	out["per_stage"] = {}
	for stage2: String in per_stage:
		(out["per_stage"] as Dictionary)[stage2] = _summed(per_stage[stage2])
	out["per_opponent"] = per_opponent
	out["per_match"] = per_match if collect else []
	out["seeds"] = seeds
	out["opponents"] = opponents.size()
	return out

## 두 조건의 결과를 같은 상대·시드·좌우의 **짝**으로 센다 (A~G 검토 §6.3).
##
## 승률을 그냥 빼면 안 되는 이유: 한쪽에서 시간 안에 끝나지 않은 판은 그쪽 승률의
## 분모에서 빠진다. 그래서 두 승률은 서로 다른 표본의 값이고, 차이가 작다는 것이
## "규칙과 무관하다"를 뜻하지 않는다. 짝으로 보면 **무엇이 뒤집혔는지**와
## **무엇이 관측되지 않았는지**가 갈린다.
##
## 미해결을 패배로 바꾸지 않는다 — 결과가 아니라 한정 시간 안에 끝나지 않았다는
## 별도의 사실이다.
##
## 반환: {pairs, same, flipped, a_only, b_only, neither}
##   same     둘 다 결판났고 승패가 같다
##   flipped  둘 다 결판났지만 승패가 바뀌었다
##   a_only   a에서는 결판났지만 b에서는 아니다
##   b_only   그 반대
##   neither  둘 다 결판나지 않았다
static func pair(a_matches: Array, b_matches: Array) -> Dictionary:
	var index: Dictionary = {}
	for row: Variant in b_matches:
		index[match_key(row as Dictionary)] = str((row as Dictionary)["outcome"])
	var out: Dictionary = {"pairs": 0, "same": 0, "flipped": 0,
		"a_only": 0, "b_only": 0, "neither": 0}
	for row2: Variant in a_matches:
		var r: Dictionary = row2
		var key: String = match_key(r)
		if not index.has(key):
			continue
		out["pairs"] = int(out["pairs"]) + 1
		var a: String = str(r["outcome"])
		var b: String = str(index[key])
		var a_done: bool = _decided(a)
		var b_done: bool = _decided(b)
		if a_done and b_done:
			if a == b:
				out["same"] = int(out["same"]) + 1
			else:
				out["flipped"] = int(out["flipped"]) + 1
		elif a_done:
			out["a_only"] = int(out["a_only"]) + 1
		elif b_done:
			out["b_only"] = int(out["b_only"]) + 1
		else:
			out["neither"] = int(out["neither"]) + 1
	return out

## 판 하나를 가리키는 키. **셋 다 들어가야 한다** — 상대만으로 묶으면 시드 3개 ×
## 좌우 2번이 한 칸에 겹쳐 짝이 어긋난다.
static func match_key(row: Dictionary) -> String:
	return "%s|%d|%s" % [str(row["opponent"]), int(row["seed"]), str(row["side"])]

static func _decided(outcome: String) -> bool:
	return outcome == "win" or outcome == "loss" or outcome == "draw"

## 진단용 상대군 기본값 — 파일에서 읽는다.
static func default_opponents() -> Array:
	return Archive.load_all()

# --- 내부 ---

static func _blank() -> Dictionary:
	return {"matches": 0, "wins": 0, "losses": 0, "draws": 0, "unresolved": 0,
		"errors": 0, "ticks": 0.0, "overtime_decided": 0,
		# 선체 격차. **승률이 포화해도 남는 해상도**다 — 상대군 전원을 이기는
		# 빌드끼리도 얼마나 여유 있게 이겼는지는 다르다. 첫 실행에서 레시피
		# 완성 보드 셋이 전부 100%였고, 승률 표만으로는 Core 재질을 바꾼
		# 효과가 통째로 0으로 보였다.
		"margin": 0.0, "our_hull": 0.0, "their_hull": 0.0}

static func _merge(into: Dictionary, row: Dictionary) -> void:
	for key: String in row:
		into[key] = into[key] + row[key]

static func _summed(row: Dictionary) -> Dictionary:
	var decided: int = int(row["wins"]) + int(row["losses"]) + int(row["draws"])
	return {
		"matches": int(row["matches"]), "wins": int(row["wins"]),
		"losses": int(row["losses"]), "draws": int(row["draws"]),
		# 미해결은 승패에 섞지 않는다. 진단용 상한에 닿은 전투는 결과가 아니라
		# **관측 실패**다 (§11.2의 "OFF는 진단용 상한에서 unresolved로 기록").
		"unresolved": int(row["unresolved"]), "errors": int(row["errors"]),
		# 승률의 분모는 **결판난 전투**다. 미해결을 분모에 넣으면 초과 피해를 끈
		# 조건의 승률이 규칙 때문에 낮아 보인다.
		"win_rate": (float(row["wins"]) / float(decided)) if decided > 0 else 0.0,
		"decided": decided,
		"avg_margin": (float(row["margin"]) / float(row["matches"]))
			if int(row["matches"]) > 0 else 0.0,
		"avg_our_hull": (float(row["our_hull"]) / float(row["matches"]))
			if int(row["matches"]) > 0 else 0.0,
		"avg_their_hull": (float(row["their_hull"]) / float(row["matches"]))
			if int(row["matches"]) > 0 else 0.0,
		"avg_elapsed": (float(row["ticks"]) / float(row["matches"]))
			if int(row["matches"]) > 0 else 0.0,
		"overtime_decided": int(row["overtime_decided"]),
	}

## 한 판. `as_left`가 참이면 검사 대상이 player 쪽이다.
##
## per_match에 판별을 한 줄 남긴다. **판별은 한 곳에서만 정한다** — 집계에 더하는
## 자리와 기록하는 자리가 따로면 두 값이 어긋난다.
static func _fight_into(row: Dictionary, catalog: RefCounted, config: RefCounted,
		build: Dictionary, opponent: Dictionary, combat_seed: int, as_left: bool,
		rules: Dictionary, per_match: Array, opponent_id: String) -> void:
	# 좌우를 바꿔도 같은 시드를 쓰되 값은 다르게 판다 — 같은 시드로 두 번 돌리면
	# 두 번째가 첫 번째의 거울상이 되어 독립된 관측이 아니다.
	var mixed: int = Config.mix(["benchmark", combat_seed, "L" if as_left else "R",
		str(build.get("id", "")), str(opponent.get("id", ""))])
	var left: Dictionary = build if as_left else opponent
	var right: Dictionary = opponent if as_left else build
	var scoped: RefCounted = _with_rules(config, rules)
	var result: Dictionary = CombatAdapter.fight(catalog, scoped, left, right, mixed)

	row["matches"] = int(row["matches"]) + 1
	var outcome: String = _account(row, result, as_left)
	per_match.append({
		"opponent": opponent_id, "seed": combat_seed,
		"side": "L" if as_left else "R", "outcome": outcome,
		"elapsed": float(result.get("elapsed", 0.0)),
		"victory_kind": str(result.get("victory_kind", "")),
	})

## 한 판을 집계에 넣고 판별 문자열을 돌려준다.
static func _account(row: Dictionary, result: Dictionary, as_left: bool) -> String:
	if not bool(result["ok"]):
		row["errors"] = int(row["errors"]) + 1
		return "error"
	row["ticks"] = float(row["ticks"]) + float(result["elapsed"])
	# 좌우를 바꿔 싸우므로 "우리"가 어느 쪽인지 보고 격차를 잡는다.
	var hulls: Dictionary = result["hulls"]
	var ours: int = int(hulls["left"]) if as_left else int(hulls["right"])
	var theirs: int = int(hulls["right"]) if as_left else int(hulls["left"])
	row["our_hull"] = float(row["our_hull"]) + float(ours)
	row["their_hull"] = float(row["their_hull"]) + float(theirs)
	row["margin"] = float(row["margin"]) + float(ours - theirs)
	if str(result["victory_kind"]) == "overtime_kill":
		row["overtime_decided"] = int(row["overtime_decided"]) + 1

	var winner: String = str(result["winner"])
	if winner == "draw":
		# 시간 상한에 닿은 무승부는 **미해결**이다. 양측이 실제로 함께 죽은
		# 무승부(mutual_death)와는 다른 사실이므로 같은 칸에 넣지 않는다.
		if str(result["reason"]) == "timeout":
			row["unresolved"] = int(row["unresolved"]) + 1
			return "unresolved"
		row["draws"] = int(row["draws"]) + 1
		return "draw"
	var we_won: bool = (winner == "player") == as_left
	if we_won:
		row["wins"] = int(row["wins"]) + 1
		return "win"
	row["losses"] = int(row["losses"]) + 1
	return "loss"

## combat_adapter가 config.combat_rules()를 부르므로, 규칙을 갈아끼운 사본을 넘긴다.
## 원본 config를 건드리면 같은 배치의 다른 계산에 새어 나간다.
static func _with_rules(config: RefCounted, rules: Dictionary) -> RefCounted:
	var copy: RefCounted = Config.new()
	copy.frame_id = config.frame_id
	copy.core_id = config.core_id
	copy.batch_id = config.batch_id
	copy.overtime_start_seconds = float(rules.get("overtime_start_seconds", 0.0))
	copy.overtime_base_fraction = float(rules.get("overtime_base_fraction", 0.001))
	copy.overtime_reference_hull = int(rules.get("overtime_reference_hull", 0))
	copy.timeout_result = str(rules.get("timeout_result", "draw"))
	copy.neutral_damage_types = bool(rules.get("neutral_damage_types", false))
	return copy

## 리그 기본 규칙 (초과 피해 ON). 진단의 대조군이다.
static func league_rules(config: RefCounted) -> Dictionary:
	return config.combat_rules()

## 초과 피해 OFF. 시간 상한에 닿으면 timeout → 미해결로 기록된다.
static func no_overtime_rules() -> Dictionary:
	return {"overtime_start_seconds": 0.0, "timeout_result": "draw"}
