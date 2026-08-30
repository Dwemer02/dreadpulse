extends SceneTree
## 배치 검증 러너 — 스펙 §10의 지표를 숫자로 낸다.
## 실행: godot --headless --path . --script res://tests/run_batch.gd
##
## Phase 0b 현재 **Reclaimer 한 팩션만** 구현되어 있다. 지표 A(dual-use 균형) ·
## D(팩션 차이) · E(혼종 밸런스)는 여러 팩션과 무작위 빌드 집단을 전제하므로
## 측정할 수 없다. 조용히 빼지 않고 "측정 불가"로 사유와 함께 출력한다 —
## 빠진 지표를 통과한 지표처럼 읽는 것이 가장 나쁜 실패다.
##
## 이 러너는 리포트 도구다. 지표 미달은 exit code를 바꾸지 않는다
## (밸런스 수치는 전부 플레이스홀더다). 시뮬레이션 자체가 실패했을 때만 exit 1.

const K = preload("res://sim/sim_const.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")

const SEEDS: int = 20
const REPORT_PATH := "res://tests/out/batch_report.txt"
## "파손 직후 패배"의 판정 창 (§10.C)
const LATE_BREAK_WINDOW: float = 5.0

var _lines: Array[String] = []

func _init() -> void:
	var catalog: RefCounted = Content.load_catalog()
	if not catalog.ok():
		for e: String in catalog.errors:
			print("  CATALOG ERROR  %s" % e)
		quit(1)
		return

	var runs: Array = []
	for build_id: String in Content.build_ids():
		for enemy_id: String in Content.enemy_ids():
			for s: int in range(1, SEEDS + 1):
				var prepared: Dictionary = Content.prepare(catalog, build_id, enemy_id, s)
				if prepared["sim"] == null:
					for e: String in prepared["errors"]:
						print("  BUILD ERROR  %s" % e)
					quit(1)
					return
				var sim: RefCounted = prepared["sim"]
				runs.append({
					"build": build_id, "enemy": enemy_id, "seed": s,
					"log": sim.run(), "winner": sim.winner,
					"limits": _initial_limits(catalog, build_id, enemy_id),
				})

	_say("")
	_say("THE FIRST DIVERGENCE — 배치 리포트")
	_say("빌드 %d종 × 적 %d종 × 시드 %d = 전투 %d판"
		% [Content.build_ids().size(), Content.enemy_ids().size(), SEEDS, runs.size()])
	_say("구현된 팩션: %s" % ", ".join(Content.IMPLEMENTED_FACTIONS))

	_report_overview(runs)
	_report_chains(runs)
	_report_destruction(runs)
	_report_unmeasurable()
	_report_main_chains(runs)

	for line: String in _lines:
		print(line)
	_write_report()
	quit(0)

# --- 지표 ---

func _report_overview(runs: Array) -> void:
	_head("개요")
	var by_enemy: Dictionary = {}
	for run: Dictionary in runs:
		var key: String = "%s vs %s" % [run["build"], run["enemy"]]
		if not by_enemy.has(key):
			by_enemy[key] = {"n": 0, "win": 0, "draw": 0, "elapsed": 0.0}
		var bucket: Dictionary = by_enemy[key]
		bucket["n"] = int(bucket["n"]) + 1
		if str(run["winner"]) == "player":
			bucket["win"] = int(bucket["win"]) + 1
		elif str(run["winner"]) == "draw":
			bucket["draw"] = int(bucket["draw"]) + 1
		bucket["elapsed"] = float(bucket["elapsed"]) + _elapsed(run["log"])
	for key: String in by_enemy:
		var b: Dictionary = by_enemy[key]
		var n: int = int(b["n"])
		_say("  %-34s 승률 %5.1f%%  무승부 %2d  평균 %5.1f초"
			% [key, 100.0 * float(b["win"]) / float(n), int(b["draw"]),
				float(b["elapsed"]) / float(n)])

func _report_chains(runs: Array) -> void:
	_head("B. Trigger Engine이 읽히는가")
	var total_chains: int = 0
	var depth_sum: int = 0
	var deep_chains: int = 0
	var deep_depth_sum: int = 0
	var longest: int = 0
	var capped: int = 0
	var rate_cap_entries: int = 0
	var fires: int = 0

	for run: Dictionary in runs:
		for chain: Dictionary in Analysis.chains(run["log"]):
			var depth: int = int(chain["depth"])
			total_chains += 1
			depth_sum += depth
			longest = maxi(longest, depth)
			if depth >= 2:
				deep_chains += 1
				deep_depth_sum += depth
		for event: Dictionary in run["log"]:
			match str(event["type"]):
				"chain_capped":
					capped += 1
				"part_fired":
					fires += 1
				"part_fire_blocked":
					if str(event.get("reason", "")) == "rate_cap":
						rate_cap_entries += 1

	_say("  전체 연쇄 평균 단계      %.2f  (연쇄 %d개)"
		% [float(depth_sum) / maxf(1.0, float(total_chains)), total_chains])
	_say("  2단계 이상 연쇄 평균     %.2f  (%d개, 전체의 %.1f%%)  %s"
		% [float(deep_depth_sum) / maxf(1.0, float(deep_chains)), deep_chains,
			100.0 * float(deep_chains) / maxf(1.0, float(total_chains)),
			_verdict(deep_chains > 0, "연쇄 발생", "연쇄가 전혀 없다")])
	_say("  최장 연쇄                %d  %s"
		% [longest, _verdict(longest <= K.MAX_CHAIN_DEPTH, "상한 이내", "상한 초과")])
	_say("  chain_capped             %d  %s"
		% [capped, _verdict(capped == 0, "통과", "설계 결함 — 0이어야 한다")])
	_say("  rate_cap 진입            %d회 (발동 %d회 중)" % [rate_cap_entries, fires])
	_say("  ※ 불발 이벤트는 같은 사유가 이어지는 동안 한 번만 방출된다. 따라서 위 수치는")
	_say("     '막힌 발동 횟수'가 아니라 '막힌 상태에 새로 진입한 횟수'다.")

func _report_destruction(runs: Array) -> void:
	_head("C. 파괴선이 재밌는가")
	var causes: Dictionary = {"threshold": 0, "fires_exhausted": 0, "effect": 0}
	var destroyed: int = 0
	var restored: int = 0
	var prevented_reinforce: int = 0
	var prevented_indestructible: int = 0
	var decided: int = 0
	var late_break_loss: int = 0
	var limited_parts: int = 0
	var consumed_ratio_sum: float = 0.0

	for run: Dictionary in runs:
		var log: Array = run["log"]
		var end_t: float = _elapsed(log)
		var loser: String = ""
		if str(run["winner"]) == "player":
			loser = "enemy"
		elif str(run["winner"]) == "enemy":
			loser = "player"
		if loser != "":
			decided += 1

		# 슬롯별 마지막 남은 횟수. 초기값은 카탈로그(정의)가 알려준다.
		var remaining: Dictionary = {}
		var late_break: bool = false
		for event: Dictionary in log:
			var ship: String = str(event.get("ship", ""))
			match str(event["type"]):
				"part_destroyed":
					destroyed += 1
					var cause: String = str(event.get("cause", "effect"))
					causes[cause] = int(causes.get(cause, 0)) + 1
					if ship == loser and end_t - float(event["t"]) <= LATE_BREAK_WINDOW:
						late_break = true
				"part_restored":
					restored += 1
				"reinforce_consumed":
					prevented_reinforce += 1
				"break_prevented":
					prevented_indestructible += 1
				"fires_changed":
					remaining["%s/%s" % [ship, event["slot"]]] = int(event["remaining"])
		if late_break:
			late_break_loss += 1

		for key: String in run["limits"]:
			var initial: int = int(run["limits"][key])
			if initial <= 0:
				continue
			limited_parts += 1
			var left: int = int(remaining.get(key, initial))
			consumed_ratio_sum += float(initial - left) / float(initial)

	var n: float = float(runs.size())
	var avg_broken: float = float(destroyed) / n
	var late_ratio: float = float(late_break_loss) / maxf(1.0, float(decided))
	var consumed: float = consumed_ratio_sum / maxf(1.0, float(limited_parts))
	var attempts: int = destroyed + restored + prevented_reinforce + prevented_indestructible

	_say("  전투당 평균 파손 수      %.2f  %s"
		% [avg_broken, _verdict(avg_broken >= 1.5 and avg_broken <= 3.5, "1.5~3.5", "범위 밖")])
	_say("    원인별 — 파괴선 %d / 발동 제한 소진 %d / 효과 %d"
		% [int(causes["threshold"]), int(causes["fires_exhausted"]), int(causes["effect"])])
	_say("  파손 %.0f초 내 패배       %.1f%%  %s"
		% [LATE_BREAK_WINDOW, 100.0 * late_ratio,
			_verdict(late_ratio <= 0.2, "20% 이하", "파괴가 즉사로 읽힌다")])
	_say("  되돌린 비율              %.1f%% (복구 %d / 보강 %d / 파괴 불가 %d, 시도 %d)"
		% [100.0 * float(restored + prevented_reinforce + prevented_indestructible)
			/ maxf(1.0, float(attempts)),
			restored, prevented_reinforce, prevented_indestructible, attempts])
	_say("  파괴 불가 유예           %d건  %s"
		% [prevented_indestructible,
			"[PASS] 작동 확인" if prevented_indestructible > 0 else "[N/A] 아래 참고"])
	_say("  발동 제한 소진율         %.1f%%  %s"
		% [100.0 * consumed,
			_verdict(consumed >= 0.5, "50% 이상", "제한이 밸런스에 관여하지 않는다")])
	_say("")
	_say("  ※ 이 절의 FAIL 두 개는 튜닝이 아니라 구조에서 온다. 판단이 필요하다:")
	_say("     · 평균 파손 수 — Frame의 파괴선이 함선당 3개이므로 승부가 난 전투에서는")
	_say("       패자 혼자 3회를 통과한다. 양측 합 1.5~3.5는 파괴선 3개와 양립하기 어렵다.")
	_say("       지표를 고치든가(예: 패자 제외 / 상한 완화) 파괴선 수를 줄여야 한다.")
	_say("     · 파손 5초 내 패배 — 마지막 파괴선 25%는 정의상 죽기 직전에 통과한다.")
	_say("       이 지표는 사실상 '남은 25% 체력이 5초 이상 버티는가'를 묻는다.")
	_say("       전투가 짧아질수록 자동으로 악화되므로 전투 길이와 함께 읽어야 한다.")
	_say("     · 파괴 불가 유예 — 임시 파괴 불가를 주는 콘텐츠(Aeonic temporal_anchor)가")
	_say("       아직 없다. Core의 영구 파괴 불가는 파괴선 후보에서 미리 제외되므로")
	_say("       유예 이벤트를 만들지 않는다. Aeonic 구현 전까지는 측정 불가다.")

func _report_unmeasurable() -> void:
	_head("측정 불가 지표")
	_say("  A. Dual-use 균형   — 무작위 생성 빌드 집단이 필요하다")
	_say("  D. 팩션 차이       — 팩션 3종이 필요하다. 현재 %s만 구현됨"
		% ", ".join(Content.IMPLEMENTED_FACTIONS))
	_say("  E. 혼종 밸런스     — 위와 같음. 혼종 빌드는 팩션이 둘 이상이어야 만들 수 있다")

func _report_main_chains(runs: Array) -> void:
	_head("MAIN CHAIN (§56 요약)")
	var merged: Dictionary = {}
	for run: Dictionary in runs:
		for entry: Array in Analysis.signature_ranking(run["log"]):
			merged[entry[0]] = int(merged.get(entry[0], 0)) + int(entry[1])
	var ranked: Array = []
	for sig: String in merged:
		ranked.append([sig, int(merged[sig])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	if ranked.is_empty():
		_say("  (2단계 이상 연쇄가 없다)")
		return
	for i: int in mini(5, ranked.size()):
		_say("  %-52s ×%d" % [ranked[i][0], int(ranked[i][1])])

# --- 보조 ---

## 빌드의 슬롯별 초기 발동 횟수. 카탈로그(정의)를 읽는다 — 런타임 상태가 아니다.
## 무제한 파츠는 여기 포함되지 않는다. drain_fires로 수명이 확정되는 경우는
## 소진율의 분모를 흐리므로 제외한다 — 측정 대상은 "처음부터 제한이 걸린 파츠"다.
func _initial_limits(catalog: RefCounted, player_id: String, enemy_id: String) -> Dictionary:
	var out: Dictionary = {}
	for pair: Array in [["player", player_id], ["enemy", enemy_id]]:
		var build: Dictionary = Content.read_build(pair[1])
		for slot_id: String in build.get("slots", {}):
			var entry: Dictionary = build["slots"][slot_id]
			var spec: Dictionary = catalog.merge(str(entry["part"]), str(entry.get("augment", "")))
			var limit: int = int(spec["fire_limit"])
			if limit == K.UNLIMITED:
				continue
			out["%s/%s" % [pair[0], slot_id]] = limit
	return out

func _elapsed(log: Array) -> float:
	if log.is_empty():
		return 0.0
	return float((log[log.size() - 1] as Dictionary).get("t", 0.0))

func _verdict(ok: bool, pass_text: String, fail_text: String) -> String:
	if ok:
		return "[PASS] %s" % pass_text
	return "[FAIL] %s" % fail_text

func _head(title: String) -> void:
	_say("")
	_say("── %s %s" % [title, "─".repeat(maxi(2, 56 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		print("")
		print("  (리포트 파일을 쓸 수 없다: %s)" % REPORT_PATH)
		return
	f.store_string("\n".join(_lines) + "\n")
	print("")
	print("리포트 저장: %s" % REPORT_PATH)
