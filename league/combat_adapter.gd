extends RefCounted
## 실제 전투 시뮬레이터를 그대로 호출한다. 기획서 §1.3의
## "새로운 전투 규칙을 리그 안에서 임의로 구현하지 않는다"가 이 파일의 존재 이유다.
##
## 리그가 추가하는 것은 전부 combat_sim.rules로 주입하는 **선택 규칙**이고,
## 그 구현은 sim/combat_sim.gd 안에 있다 — 여기에 전투 로직은 한 줄도 없다.

const Content = preload("res://sim/content.gd")
const K = preload("res://sim/sim_const.gd")
const Analysis = preload("res://sim/event_analysis.gd")

## 기술적 안전 한도 (§9.3). 시뮬레이션 시간이 진행하지 않는 무한 트리거는
## 120초 제한으로 막을 수 없다. 도달했다고 게임상 패배시키지 않고 **오류로 격리**한다.
const MAX_EVENTS: int = 60000

## 전투 하나. 반환:
##   {ok, winner, reason, elapsed, hulls, overtime, victory_kind, summary, log, error}
static func fight(catalog: RefCounted, config: RefCounted, left_build: Dictionary,
		right_build: Dictionary, combat_seed: int) -> Dictionary:
	var prepared: Dictionary = Content.prepare_builds(catalog, left_build, right_build,
		combat_seed)
	if prepared["sim"] == null:
		return _error("assembly", str(prepared["errors"]))

	var sim: RefCounted = prepared["sim"]
	sim.rules = config.combat_rules()
	sim.setup_ready()
	while not sim.finished and sim.tick < K.MAX_COMBAT_TICKS:
		sim.step()
		if sim.log.size() > MAX_EVENTS:
			# 오류를 승리·무승부·0초 패배로 대체하지 않는다 (§8.3).
			return _error("event_limit",
				"이벤트 %d개 초과 (%.1f초)" % [sim.log.size(), K.ticks_to_secs(sim.tick)])
	if not sim.finished:
		sim._finish_by_timeout()

	return {
		"ok": true,
		"winner": sim.winner,
		"reason": _reason_of(sim),
		"elapsed": K.ticks_to_secs(sim.tick),
		"hulls": {"left": sim.player.hull, "right": sim.enemy.hull},
		"overtime": sim.overtime_damage_total,
		"victory_kind": _victory_kind(sim, config),
		"summary": {
			"left": Analysis.combat_summary(sim.log, "player"),
			"right": Analysis.combat_summary(sim.log, "enemy"),
		},
		"log": sim.log,
	}

static func _reason_of(sim: RefCounted) -> String:
	for i: int in range(sim.log.size() - 1, -1, -1):
		if str((sim.log[i] as Dictionary)["type"]) == "combat_end":
			return str((sim.log[i] as Dictionary).get("reason", ""))
	return ""

## 승리 방식 기록 (§9.4). 초과 피해가 결과를 갈랐는지 구별해야 한다 —
## 초과 피해는 리그 전용 규칙이므로 그것으로 이긴 빌드를 그대로 프리셋 강도로
## 쓸 수 없다.
static func _victory_kind(sim: RefCounted, config: RefCounted) -> String:
	if sim.winner == "draw":
		return "timeout_draw" if _reason_of(sim) == "timeout" else "mutual_death"
	if sim.overtime_damage_total <= 0:
		return "normal"
	# 초과 피해가 들어간 뒤에 끝났다. 마지막 선체 변화가 초과 피해였는지로 가른다.
	var loser: RefCounted = sim.enemy if sim.winner == "player" else sim.player
	for i: int in range(sim.log.size() - 1, -1, -1):
		var e: Dictionary = sim.log[i]
		if str(e.get("ship", "")) != loser.side:
			continue
		if str(e["type"]) == "overtime_damage":
			return "overtime_kill"
		if str(e["type"]) in ["hull_changed", "collapsed", "overheat_ticked"]:
			return "normal_after_overtime"
	return "normal_after_overtime"

static func _error(code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "detail": detail},
		"winner": "", "reason": code, "elapsed": 0.0,
		"hulls": {"left": 0, "right": 0}, "overtime": 0,
		"victory_kind": "simulation_error", "summary": {}, "log": []}
