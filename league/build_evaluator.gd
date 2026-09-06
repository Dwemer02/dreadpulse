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
}

## 공격 불능은 큰 결점이다 (§4.2). 점수로 표현하되 첫 전투에서는 아예 무효 처리한다.
const NOT_OPERATIONAL_PENALTY: float = 12.0

## 전략별 가중치. 없는 전략 이름이 들어오면 즉시 전력형으로 읽지 않고 실패한다 —
## 오타 난 전략이 조용히 다른 AI가 되면 배치 전체가 거짓이 된다.
static func weights_of(strategy: String) -> Dictionary:
	assert(WEIGHTS.has(strategy), "알 수 없는 전략: %s" % strategy)
	return WEIGHTS[strategy]

## 행동 하나의 점수. before/after는 Graph.analyze()의 결과다.
## goal은 엔진 투자형이 들고 있는 목표 병목 이름(없으면 빈 문자열).
static func score(before: Dictionary, after: Dictionary, strategy: String,
		goal: String = "") -> Dictionary:
	var w: Dictionary = weights_of(strategy)
	var f: Dictionary = features(before, after, float(w["sustain_bias"]), goal)

	var total: float = 0.0
	total += float(w["current"]) * float(f["current"])
	total += float(w["connection"]) * float(f["connection"])
	total += float(w["relief"]) * float(f["relief"])
	total += float(w["potential"]) * float(f["potential"])
	total -= float(w["loss"]) * float(f["loss"])
	total -= float(w["waste"]) * float(f["waste"])
	if not bool(after["operational"]):
		total -= NOT_OPERATIONAL_PENALTY
	return {"total": total, "features": f}

## 평가 요소 6종. 전부 0~1이며 고정 기준으로 정규화한다.
static func features(before: Dictionary, after: Dictionary, sustain_bias: float,
		goal: String) -> Dictionary:
	var attack: float = _unit(float(after["output"]) / OUTPUT_FULL)
	var defend: float = _unit(float(after["sustain"]) / SUSTAIN_FULL)
	# 안정성 AI는 같은 "현재 기여" 안에서 방어·실효 회복 비중을 높인다 (§5.3).
	var current: float = attack * (1.0 - sustain_bias) + defend * sustain_bias

	var links_after: int = (after["connections"] as Array).size()
	var links_before: int = (before["connections"] as Array).size()
	var connection: float = _unit(float(links_after) / CONNECTION_FULL)

	# 병목 해소 = 침묵하던 파츠가 실제로 돌기 시작한 수.
	# 목표 병목을 콕 집어 없앴으면 가산한다 (엔진 투자형의 목표 유지, §5.5).
	var dead_before: int = (before["dead"] as Array).size()
	var dead_after: int = (after["dead"] as Array).size()
	var relief: float = _unit(float(maxi(0, dead_before - dead_after)) / DEAD_FULL)
	if goal != "" and int((before["missing"] as Dictionary).get(goal, 0)) > 0 \
			and int((after["missing"] as Dictionary).get(goal, 0)) == 0:
		relief = _unit(relief + 0.5)

	# 추가 획득 하나로 열릴 연결 = "딱 하나만 더 있으면 도는" 파츠 수.
	# 이미 도는 것에는 점수를 주지 않는다 — 그건 current가 세는 몫이다.
	var potential: float = _unit(float(_near_misses(after)) / DEAD_FULL)

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
	}

## "딱 하나만 더 채우면 도는" 파츠 수. 전제가 두 개 이상 비면 한 번의 획득으로
## 열리지 않으므로 세지 않는다.
static func _near_misses(analysis: Dictionary) -> int:
	var count: int = 0
	for unit: Variant in analysis["dead"]:
		var meta: Dictionary = (unit as Dictionary)["meta"]
		var needs: int = (meta["prerequisites"] as Array).size()
		if bool(meta["passive"]):
			needs += 1
		if needs <= 1:
			count += 1
	return count

static func _unit(value: float) -> float:
	return clampf(value, 0.0, 1.0)
