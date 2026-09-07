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
## 반환: {matches, wins, losses, draws, unresolved, errors, win_rate,
##        avg_elapsed, overtime_decided, per_stage, per_opponent}
static func run(catalog: RefCounted, config: RefCounted, build: Dictionary,
		opponents: Array, rules: Dictionary, label: String = "") -> Dictionary:
	var totals: Dictionary = _blank()
	var per_stage: Dictionary = {}
	var per_opponent: Array = []

	for opponent: Dictionary in opponents:
		var row: Dictionary = _blank()
		for combat_seed: int in SEEDS:
			# 좌우 교환. 같은 시드에서 두 번 싸우고 둘 다 센다.
			_fight_into(row, catalog, config, build, opponent["build"],
				combat_seed, true, rules)
			_fight_into(row, catalog, config, build, opponent["build"],
				combat_seed, false, rules)
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
	out["seeds"] = SEEDS
	out["opponents"] = opponents.size()
	return out

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
static func _fight_into(row: Dictionary, catalog: RefCounted, config: RefCounted,
		build: Dictionary, opponent: Dictionary, combat_seed: int, as_left: bool,
		rules: Dictionary) -> void:
	# 좌우를 바꿔도 같은 시드를 쓰되 값은 다르게 판다 — 같은 시드로 두 번 돌리면
	# 두 번째가 첫 번째의 거울상이 되어 독립된 관측이 아니다.
	var mixed: int = Config.mix(["benchmark", combat_seed, "L" if as_left else "R",
		str(build.get("id", "")), str(opponent.get("id", ""))])
	var left: Dictionary = build if as_left else opponent
	var right: Dictionary = opponent if as_left else build
	var scoped: RefCounted = _with_rules(config, rules)
	var result: Dictionary = CombatAdapter.fight(catalog, scoped, left, right, mixed)

	row["matches"] = int(row["matches"]) + 1
	if not bool(result["ok"]):
		row["errors"] = int(row["errors"]) + 1
		return
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
		else:
			row["draws"] = int(row["draws"]) + 1
		return
	var we_won: bool = (winner == "player") == as_left
	if we_won:
		row["wins"] = int(row["wins"]) + 1
	else:
		row["losses"] = int(row["losses"]) + 1

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
