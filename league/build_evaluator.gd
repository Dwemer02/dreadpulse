extends RefCounted
## 빌드 하나에 점수를 매긴다. 기획서 §5.3의 평가 요소 6종과 가중치표가 여기 있다.
##
## **비교 단위는 파츠 점수가 아니라 행동 후 전체 빌드다** (§5.1). 그래서 이 클래스는
## "행동 전 분석"과 "행동 후 분석" 두 개를 받는다 — 상실 페널티와 병목 해소는
## 차이로만 잴 수 있기 때문이다.
##
## 정규화는 **고정 기준**이다 (§5.3). 후보 집합마다 최솟값·최댓값을 다시 잡으면
## 같은 빌드가 어떤 후보들과 함께 평가되느냐에 따라 다른 점수를 받는다.
##
## 여기 있는 숫자는 전부 "구현을 시작하기 위한 제안"이고 검증된 밸런스가 아니다.

const Graph = preload("res://league/build_graph.gd")

## 고정 정규화 기준. 이 값들이 0~1의 "1"이 무엇인지를 정한다.
const OUTPUT_FULL: float = 8.0      # 초당 피해 상당량
const SUSTAIN_FULL: float = 6.0     # 초당 회복·보호막 상당량
const CONNECTION_FULL: float = 8.0  # 실제 연결 수
const DEAD_FULL: float = 4.0        # 침묵 중인 파츠 수
const SURPLUS_FULL: float = 8.0     # 쓰이지 않는 자원량
## 미래 가치의 "1". 근접도 1.0짜리 잠금 해제가 이만큼 모이면 만점이다.
const UNLOCK_FULL: float = 2.0
## 해소된 병목의 "1". 이름 붙은 병목이 이만큼 사라지면 만점이다.
const RESOLVED_FULL: float = 2.0

## 전략별 가중치 (§5.3의 표 그대로).
## 앞의 넷은 더하고 뒤의 둘은 뺀다.
const WEIGHTS: Dictionary = {
	"immediate": {"current": 5, "connection": 2, "relief": 3, "potential": 0,
				  "loss": 3, "waste": 2, "sustain_bias": 0.35},
	"engine":    {"current": 2, "connection": 4, "relief": 4, "potential": 4,
				  "loss": 4, "waste": 2, "sustain_bias": 0.40},
	"sustain":   {"current": 3, "connection": 2, "relief": 5, "potential": 1,
				  "loss": 4, "waste": 4, "sustain_bias": 0.70},
	"bridge":    {"current": 2, "connection": 5, "relief": 3, "potential": 3,
				  "loss": 3, "waste": 2, "sustain_bias": 0.40},
	# 고정 레시피 추종형 — 비교군이다 (r5b §7.2). 유연형 4종과 **같은 평가기·같은
	# 특징**을 쓰고, 열린 미래 가치(potential) 자리에 고정 목표 진행(recipe)을 넣는다.
	#
	# 나머지 가중치는 즉시 전력형을 그대로 복사했다. 새 가중치 조합을 발명하면
	# "고정 목표가 불리한가"와 "이 가중치가 불리한가"를 구별할 수 없기 때문이고,
	# §7.2가 허용한 "임시 전력·생존용 부품"을 실제로 쓸 수 있어야 하기 때문이다
	# (current 5). potential을 0으로 둔 것은 이 AI의 미래 가치가 전부 레시피
	# 진행이기 때문이다 — 열린 잠금 해제까지 함께 주면 이중 계산이 된다.
	#
	# recipe 가중치 4는 엔진 투자형의 potential 4와 같다. 계획 항의 크기를
	# 유연형 중 가장 강한 계획가와 맞춰야 "고정이라서 진 것"과 "계획 항이 작아서
	# 진 것"이 섞이지 않는다.
	"fixed_recipe": {"current": 5, "connection": 2, "relief": 3, "potential": 0,
				  "recipe": 4, "loss": 3, "waste": 2, "sustain_bias": 0.35},
}

## 이 전략이 고정 레시피를 추종하는가. 러너·리포터가 이 이름을 직접 쓰지 않도록 한다.
const RECIPE_STRATEGY := "fixed_recipe"

## 공격 불능은 큰 결점이다 (§4.2). 점수로 표현하되 첫 전투에서는 아예 무효 처리한다.
const NOT_OPERATIONAL_PENALTY: float = 12.0

## 전략별 가중치. 없는 전략 이름이 들어오면 즉시 전력형으로 읽지 않고 실패한다 —
## 오타 난 전략이 조용히 다른 AI가 되면 배치 전체가 거짓이 된다.
static func weights_of(strategy: String) -> Dictionary:
	assert(WEIGHTS.has(strategy), "알 수 없는 전략: %s" % strategy)
	return WEIGHTS[strategy]

## 행동 하나의 점수. before/after는 Graph.analyze()의 결과다.
## goal은 엔진 투자형이 들고 있는 목표 병목 이름(없으면 빈 문자열).
## extras: {recipe_progress} — 고정 레시피형의 목표 진행도 0~1. 다른 전략은 안 쓴다.
## Graph.analyze()의 결과에 섞지 않고 따로 받는다 — 빌드 그래프는 레시피를 모른다.
static func score(before: Dictionary, after: Dictionary, strategy: String,
		goal: String = "", extras: Dictionary = {}) -> Dictionary:
	var w: Dictionary = weights_of(strategy)
	var f: Dictionary = features(before, after, float(w["sustain_bias"]), goal)
	f["recipe"] = clampf(float(extras.get("recipe_progress", 0.0)), 0.0, 1.0)

	var total: float = 0.0
	total += float(w["current"]) * float(f["current"])
	total += float(w["connection"]) * float(f["connection"])
	total += float(w["relief"]) * float(f["relief"])
	total += float(w["potential"]) * float(f["potential"])
	# 진행도는 **수준**이지 증분이 아니다. 증분으로 두면 완성한 엔진을 그대로
	# 유지하는 선택이 0점이 되어, 완성 직후 목표를 허무는 쪽이 이긴다.
	total += float(w.get("recipe", 0)) * float(f["recipe"])
	total -= float(w["loss"]) * float(f["loss"])
	total -= float(w["waste"]) * float(f["waste"])
	if not bool(after["operational"]):
		total -= NOT_OPERATIONAL_PENALTY
	return {"total": total, "features": f}

## 평가 요소 6종. 전부 0~1이며 고정 기준으로 정규화한다.
static func features(before: Dictionary, after: Dictionary, sustain_bias: float,
		goal: String) -> Dictionary:
	# 초반 출력과 지속 출력을 **함께** 본다 (§6.1).
	# 60초만 보면 일회용 대형 피해가 과소평가되고, 15초만 보면 지속력이 무시된다.
	# 전략별 가중치는 건드리지 않는다 — 특징을 나누는 것과 가중치 조정은 다르다.
	var attack: float = _unit(
		(float(after["output"]) / OUTPUT_FULL
			+ float(after.get("output_early", after["output"])) / OUTPUT_FULL) * 0.5)
	var defend: float = _unit(
		(float(after["sustain"]) / SUSTAIN_FULL
			+ float(after.get("sustain_early", after["sustain"])) / SUSTAIN_FULL) * 0.5)
	# 안정성 AI는 같은 "현재 기여" 안에서 방어·실효 회복 비중을 높인다 (§5.3).
	var current: float = attack * (1.0 - sustain_bias) + defend * sustain_bias

	var links_after: int = (after["connections"] as Array).size()
	var links_before: int = (before["connections"] as Array).size()
	var connection: float = _unit(float(links_after) / CONNECTION_FULL)

	# 병목 해소 = **이름 붙은 병목이 실제로 사라진 것**.
	#
	# 옛 판본은 침묵 파츠 개수의 감소를 봤다. 그러면 침묵 파츠를 하나 빼기만 해도
	# 병목이 풀린 것으로 세어지고, 반대로 병목을 풀면서 다른 침묵 장치를 함께
	# 넣으면 상쇄되어 0이 된다 — 둘 다 틀렸다 (r5 피드백 §2.3.4).
	# 어떤 병목이 얼마나 해결됐는지를 그대로 세고, 로그에도 이름을 남긴다.
	var dead_after: int = (after["dead"] as Array).size()
	var resolved: Array[String] = resolved_needs(before, after)
	var relief: float = _unit(float(resolved.size()) / RESOLVED_FULL)
	# 목표 병목을 콕 집어 없앴으면 가산한다 (엔진 투자형의 목표 유지, §5.5).
	if goal != "" and resolved.has(goal):
		relief = _unit(relief + 0.5)

	# 추가 획득 하나로 열릴 연결. **개수가 아니라 근접도의 합**이다 —
	# "이 풀에서 실제로 구할 수 있고, 열리면 뭔가를 하는" 것만 센다 (§2.3.2).
	# 옛 판본은 침묵 파츠 개수를 셌고, 그래서 potential = dead/4가 되어
	# 작동하지 않는 상태 자체를 미래 가치로 보상했다.
	var potential: float = _unit(float(after.get("unlockable", 0.0)) / UNLOCK_FULL)

	# 상실 페널티 — 연결이 끊기거나 출력이 줄어든 만큼.
	var lost_links: float = _unit(float(maxi(0, links_before - links_after)) / CONNECTION_FULL)
	var lost_output: float = _unit(maxf(0.0, float(before["output"]) - float(after["output"]))
		/ OUTPUT_FULL)
	var loss: float = _unit(lost_links * 0.6 + lost_output * 0.4)

	# 과잉 — 쓰이지 않는 자원, 놓았지만 돌지 않는 파츠, 그리고 **비어 있는 본체 자리**.
	#
	# 마지막 항이 §5.1의 "증강으로 사용하는 파츠의 본체 기회비용"이다. 이게 없으면
	# 증강은 순수 이득으로 보이고(숙주는 그대로인데 트리거만 는다) AI가 본체 자리를
	# 비워둔 채 전부 증강으로 돌린다 — 첫 실행에서 실제로 그렇게 나왔다.
	var surplus_total: int = 0
	for res: String in (after["surplus"] as Dictionary):
		surplus_total += int((after["surplus"] as Dictionary)[res])
	var slots: int = maxi(1, int(after.get("body_slots", 0)))
	var idle_slots: float = float(int(after.get("empty_slots", 0))) / float(slots)
	var waste: float = _unit(float(surplus_total) / SURPLUS_FULL * 0.35
		+ float(dead_after) / DEAD_FULL * 0.35
		+ idle_slots * 0.30)

	return {
		"current": current, "connection": connection, "relief": relief,
		"potential": potential, "loss": loss, "waste": waste,
		"attack": attack, "defend": defend,
		"links": links_after, "dead": dead_after,
		# 원시 재료도 함께 남긴다 — 정규화된 0~1만 보면 "왜 이 값인가"를 복원할 수 없다.
		# r5에서 potential이 무엇을 세는지 로그만으로 알 수 없었던 것이 이 때문이다.
		"unlockable": snappedf(float(after.get("unlockable", 0.0)), 0.01),
		# 두 지평선을 로그에 남긴다 — 하나로 뭉갠 값만 보면 "왜 이 점수인가"를
		# 복원할 수 없다.
		"output_60s": snappedf(float(after["output"]), 0.01),
		"output_15s": snappedf(float(after.get("output_early", 0.0)), 0.01),
		"resolved": resolved,
		"empty_slots": int(after.get("empty_slots", 0)),
	}

## 이번 변경으로 **사라진 병목의 이름**. relief가 이걸 세고 로그가 이걸 남긴다.
##
## 이름을 남기는 것이 요점이다: "병목 2개 해소"만 적으면 나중에 그것이 실제 해소인지
## 침묵 파츠를 뺀 것인지 구별할 수 없다 (r5에서 정확히 그랬다).
static func resolved_needs(before: Dictionary, after: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var was: Dictionary = before["missing"]
	var now: Dictionary = after["missing"]
	for need: String in was:
		if int(was[need]) > 0 and int(now.get(need, 0)) == 0:
			out.append(need)
	return out

static func _unit(value: float) -> float:
	return clampf(value, 0.0, 1.0)
