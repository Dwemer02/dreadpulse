extends SceneTree
## 시험 항해의 헤드리스 점검. A~G 검토 §8.3의 "최소 검증" 중 **화면 없이 확인할 수
## 있는 것**을 전부 여기서 찍는다.
##
## 실행:
##   godot --headless --path . --script res://tests/run_voyage_check.gd -- \
##     --seeds=1,2,3 [--bench=1]
##
## 두 가지를 낸다.
##
##   1. 적 명부의 강도 — 고정 상대군 archive-1에서 잰 값 + 초과 피해 짝별 비교.
##      **이 값은 사람 플레이의 난이도가 아니다** (§6.1). 명부를 고칠 때 무엇이
##      어떻게 달라졌는지 비교할 기준선이다. `--bench=1`일 때만 돈다 (느리다).
##   2. 자동 조작으로 항해를 끝까지 돌린 기록 — 경계(4손실·마지막 전투·보관 한도)와
##      저장·재개·내보내기가 실제로 도는지.
##
## **자동 조작의 승률을 사람의 승률로 읽지 않는다.** 여기 정책은 "첫 합법 자리에
## 놓는다"이고, 판단이 없다.

const VoyageConfig = preload("res://voyage/voyage_config.gd")
const VoyageState = preload("res://voyage/voyage_state.gd")
const VoyageSave = preload("res://voyage/voyage_save.gd")
const Readout = preload("res://voyage/combat_readout.gd")
const Roster = preload("res://voyage/enemy_roster.gd")
const Brief = preload("res://voyage/enemy_brief.gd")
const Lab = preload("res://voyage/lab.gd")

const LeagueContent = preload("res://league/league_content.gd")
const LeagueConfig = preload("res://league/league_config.gd")
const Benchmark = preload("res://league/benchmark.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Inventory = preload("res://run/inventory.gd")
const AssemblyPolicy = preload("res://league/assembly_policy.gd")

var _content: RefCounted
var _roster: RefCounted
var _lines: Array[String] = []

func _init() -> void:
	_content = LeagueContent.new()
	_content.load_all()
	if not _content.ok():
		for e: String in _content.errors:
			print("  CONTENT  %s" % e)
		quit(1)
		return
	_roster = Roster.new()
	_roster.load_all()
	if not _roster.ok():
		for e2: String in _roster.errors:
			print("  ROSTER  %s" % e2)
		quit(1)
		return

	_head("시험 항해 점검")
	_say("적 명부 %s · 적 %d명 · 첫 경로 %d전투"
		% [_roster.version, _roster.all_ids().size(),
			_roster.path("first_path").size()])
	_say("프로필 %s · 평가기 %s"
		% [VoyageConfig.PROFILE_VERSION, LeagueConfig.EVALUATOR_VERSION])

	_report_roster()
	if _arg_int("bench", 0) == 1:
		_report_strength()
	_report_lab()
	for seed_value: int in _seeds():
		_play(seed_value, _arg("pilot", ""))

	print("\n".join(_lines))
	quit(0)

# --- 1. 명부 ---

func _report_roster() -> void:
	_head("적 명부 — 위협과 대응은 **실제 파츠 정의에서** 읽는다 (§6.2)")
	for enemy_id: String in _roster.all_ids():
		var entry: Dictionary = _roster.entry(enemy_id)
		var brief: Dictionary = Brief.of(entry["build"], _content.catalog,
			_content.meta_index)
		_say("")
		_say("  %-18s %-6s %s" % [enemy_id, str(entry["role"]),
			str(entry.get("name", ""))])
		_say("    출처   %s%s" % [str(entry.get("source", "")),
			" · 원본 R%d(획득 %d)" % [int(entry["stage_round"]),
				int(entry["acquisitions"])] if entry.has("stage_round") else ""])
		_say("    보드   %s" % _board_line(entry["build"]))
		_say("    위협   %s" % " · ".join(brief["threats"]))
		for answer: String in (brief["answers"] as Array):
			_say("    대응   %s" % answer)
	_say("")
	_say("  ※ 원본 라운드는 **획득 예산을 짐작하는 단서**이지 배치할 스테이지 번호가")
	_say("     아니다 (§6.1). 경로는 데이터로 두었으니 플레이해 보고 고친다.")

## 명부의 강도. **기존 상대군에서 잰 값이고 사람 난이도가 아니다.**
func _report_strength() -> void:
	var opponents: Array = Archive.load_all()
	var config: RefCounted = VoyageConfig.make(1).league
	_head("명부 강도 — 고정 상대군 %s에서 (사람 난이도가 아니다)"
		% str(Archive.manifest()["version"]))
	_say("  %-18s %7s %8s %8s %7s %7s %8s" % ["적", "승률", "격차", "평균초",
		"동일", "뒤집힘", "OFF미해결"])
	for enemy_id: String in _roster.all_ids():
		var build: Dictionary = _roster.build_of(enemy_id)
		var on: Dictionary = Benchmark.run(_content.catalog, config, build,
			opponents, config.combat_rules(), enemy_id, Benchmark.SEEDS, true)
		var off: Dictionary = Benchmark.run(_content.catalog, config, build,
			opponents, Benchmark.no_overtime_rules(), enemy_id,
			Benchmark.SEEDS, true)
		var paired: Dictionary = Benchmark.pair(on["per_match"], off["per_match"])
		_say("  %-18s %6.1f%% %+8.1f %8.1f %7d %7d %8d"
			% [enemy_id, 100.0 * float(on["win_rate"]), float(on["avg_margin"]),
				float(on["avg_elapsed"]), int(paired["same"]),
				int(paired["flipped"]), int(paired["a_only"])])
	_say("")
	_say("  ※ 승률의 분모는 결판난 판이다. 뒤의 세 열은 같은 상대·시드·좌우의 짝이며")
	_say("     'OFF미해결'은 초과 피해 없이 120초 안에 끝나지 않은 짝이다 (§6.3).")

# --- 2. 실험실 ---

func _report_lab() -> void:
	_head("조립 실험실 (H1) — 보드를 불러와 한 전투를 본다")
	var lab: RefCounted = Lab.new()
	lab.setup(VoyageConfig.make(1), _content, _roster)
	var loaded: Dictionary = lab.load_player("ve_lab_saturated")
	_say("  아군 불러오기 ve_lab_saturated: %s"
		% ("성공" if bool(loaded["ok"]) else str(loaded["error"])))
	lab.enemy_id = "ve_starter_ward"
	var fought: Dictionary = lab.fight()
	if not bool(fought["ok"]):
		_say("  전투 실패: %s" % str(fought["error"]))
		return
	_say("  아군 %s" % _board_line(lab.board_build()))
	_say("  상대 %s" % _board_line(_roster.build_of(lab.enemy_id)))
	_print_readout(lab.last_result, lab.board_build(), "    ")

	# 같은 시드로 다시 싸우면 같은 결과다 (§7.1의 "수정 후 재전투"의 전제).
	var first: String = "%s|%.2f" % [str(lab.last_result["winner"]),
		float(lab.last_result["elapsed"])]
	lab.fight()
	var again: String = "%s|%.2f" % [str(lab.last_result["winner"]),
		float(lab.last_result["elapsed"])]
	_say("  같은 시드 재전투: %s" % ("같은 결과" if first == again
		else "**다르다** %s vs %s" % [first, again]))

	# 임의 지급은 연습 기록이다.
	var granted: Dictionary = lab.grant("scrap_autocannon")
	_say("  임의 지급 scrap_autocannon: %s · 기록에 practice 표시 %s"
		% ["성공" if bool(granted["ok"]) else str(granted["error"]),
			str(bool((lab.history[lab.history.size() - 1] as Dictionary)["practice"]))])

# --- 3. 자동 항해 ---

## pilot이 비어 있으면 판단 없는 조작(첫 후보·첫 자리)이고, 전략 id를 주면 리그의
## `assembly_policy`가 고른다.
##
## **왜 리그 AI를 태우는가**: "이 경로가 애초에 이길 수 있는가"를 알아야 한다.
## 판단 없는 조작이 0승이면 경로가 어려운 것인지 조작이 나쁜 것인지 구별되지 않는다.
## 리그 AI는 사람이 아니지만 **적을 보지 않고도 조립은 하는** 하한선이다.
##
## 그리고 이것은 일관성 점검이기도 하다: AI가 고른 조립을 **사람 명령으로 그대로
## 재생**한다. 사람 경로로 표현할 수 없는 AI 조립이 있으면 여기서 드러난다.
func _play(seed_value: int, pilot: String) -> void:
	var state: RefCounted = VoyageState.new()
	state.setup(VoyageConfig.make(seed_value), _content, _roster)
	state.begin()
	_head("자동 항해 시드 %d — %s" % [seed_value,
		"리그 AI(%s)가 고른다" % pilot if pilot != ""
			else "**판단 없는 조작이다** (첫 후보·첫 자리)"])

	var guard: int = 0
	while state.status == "active" and guard < 200:
		guard += 1
		match state.phase:
			"choice":
				var brief: Dictionary = state.next_enemy_brief()
				_say("  보상 %d: %s" % [int(state.offer["index"]),
					str(state.offer["final"])])
				if not brief.is_empty():
					_say("    다음 상대 %s — %s" % [str(brief["id"]),
						" · ".join(brief["threats"])])
				var option: int = 0
				var chain: Array = []
				if pilot != "":
					var picked: Dictionary = _pilot_pick(state, pilot)
					option = int(picked["option"])
					chain = picked["chain"]
				var chose: Dictionary = state.choose(option)
				if not bool(chose["ok"]):
					_say("  선택 실패: %s" % str(chose["error"]))
					return
				# AI가 고른 조립을 **사람 명령으로 재생한다.**
				for action: Variant in chain:
					var replayed: Dictionary = state.command(action as Dictionary)
					if not bool(replayed["ok"]):
						_say("  AI 조립을 사람 명령으로 재생할 수 없다: %s — %s"
							% [str(action), str(replayed["error"])])
				if pilot != "":
					state.pending_uid = Inventory.NONE
			"assemble":
				_auto_place(state)
				if state.next_action() == "offer":
					state.open_offer()
				else:
					var launched: Dictionary = state.launch()
					if not bool(launched["ok"]):
						_say("  출격 실패: %s" % str(launched["error"]))
						return
			"result":
				_say("  전투 %d vs %-18s %s" % [int(state.last_result["combat"]),
					str(state.last_result["enemy_id"]),
					_result_line(state.last_result)])
				_print_readout(state.last_result, state.last_result["build"],
					"      ")
				state.continue_after_result()
			_:
				break
	_say("  %s" % state.progress_line())

	# 저장·재개·내보내기 (H4).
	var save_path: String = "user://voyage/check_%d.json" % seed_value
	var saved: Dictionary = VoyageSave.save(state, save_path)
	var loaded: Dictionary = VoyageSave.load_from(_content, _roster, save_path)
	var back: RefCounted = loaded.get("state", null)
	_say("  저장 %s · 재개 %s%s" % [
		"성공" if bool(saved["ok"]) else str(saved["error"]),
		"성공" if bool(loaded["ok"]) else str(loaded["error"]),
		"" if back == null else " · 같은 상태 %s" % str(
			back.acquisitions == state.acquisitions
			and back.status == state.status
			and str(back.inventory.owned) == str(state.inventory.owned))])
	var exported: Dictionary = VoyageSave.export_records(state)
	_say("  내보내기 %s → %s %s" % [
		"성공" if bool(exported["ok"]) else str(exported["error"]),
		str(exported["dir"]), str(exported["files"])])

## 리그 AI에게 "이 제안 중 무엇을 어떻게 쓸까"를 묻는다. 리그와 같은 방식이다 —
## 제안 파츠마다 복제본에 얹어 평가하고 최고점을 고른다.
##
## 반환: {option, chain}
func _pilot_pick(state: RefCounted, strategy: String) -> Dictionary:
	var policy: RefCounted = AssemblyPolicy.new()
	policy.setup(strategy, state.config.league, "")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = LeagueConfig.mix(["pilot", state.config.voyage_seed,
		int(state.offer["index"])])
	var ctx: Dictionary = state.ctx()
	# 시작 조립 동안에는 획득한 파츠를 전부 본체로 놓아야 한다 (§7.2의 3본체).
	ctx["min_bodies"] = (state.acquisitions + 1) if not state.start_complete() else 0
	ctx["require_operational"] = state.acquisitions + 1 >= 3 		and not state.start_complete()
	ctx["rng"] = rng
	var best: Dictionary = {}
	var best_option: int = 0
	var best_score: float = -1.0e30
	var final: Array = state.offer["final"]
	for i: int in final.size():
		var trial: RefCounted = state.inventory.clone()
		var reward_uid: int = trial.add(str(final[i]))
		var trial_ctx: Dictionary = ctx.duplicate()
		trial_ctx["reward_uid"] = reward_uid
		var decision: Dictionary = policy.decide(trial, trial_ctx)
		if not bool(decision.get("valid", false)):
			continue
		if float(decision["score"]) > best_score:
			best_score = float(decision["score"])
			best = decision
			best_option = i
	if best.is_empty():
		return {"option": 0, "chain": []}
	return {"option": best_option, "chain": best["chain"]}

## 첫 합법 자리에 놓는다. 못 놓으면 창고에 둔다. 보관이 넘치면 가장 오래된
## 비Core 파츠를 버린다 — **사람 화면에서는 사람이 고른다** (§7.3).
func _auto_place(state: RefCounted) -> void:
	var uid: int = int(state.pending_uid)
	if uid != Inventory.NONE:
		var targets: Dictionary = state.legal_targets(uid)
		if not (targets["bodies"] as Array).is_empty():
			state.command({"kind": "place", "uid": uid,
				"slot": str((targets["bodies"] as Array)[0])})
		state.pending_uid = Inventory.NONE
	while int(state.launch_check()["storage_over"]) > 0:
		var victim: int = Inventory.NONE
		for item: Dictionary in state.inventory.unplaced():
			victim = int(item["uid"])
			break
		if victim == Inventory.NONE:
			break
		state.command({"kind": "discard", "uid": victim})

# --- 출력 ---

func _print_readout(result: Dictionary, build: Dictionary, pad: String) -> void:
	var read: Dictionary = Readout.of(result, build, _content.catalog)
	_say("%s%s · %.1f초 · %s" % [pad, str(read["headline"]),
		float(read["elapsed"]), str(read["victory_line"])])
	_say("%s피해 %s · 회복 %d · 보호막 %d · 받은 선체 피해 %d" % [pad,
		str(read["damage"]), int((read["sustain"] as Dictionary)["repaired"]),
		int((read["sustain"] as Dictionary)["shield"]),
		int((read["taken"] as Dictionary)["hull"])])
	if not (read["links"] as Array).is_empty():
		_say("%s연결 %s" % [pad, " · ".join(read["links"])])
	for row: Variant in (read["slots"] as Array):
		var r: Dictionary = row
		if str(r["kind"]) == "fired" and int(r["outputs"]) > 0:
			continue   # 잘 돈 자리는 줄을 차지하지 않는다
		_say("%s  %-10s %-26s %-8s %s" % [pad, str(r["slot"]), str(r["part"]),
			str(r["kind"]), str(r["reason"])])

func _result_line(result: Dictionary) -> String:
	return "%s (%s · %.1f초 · 선체 %d:%d)" % [str(result["winner"]),
		str(result["victory_kind"]), float(result["elapsed"]),
		int((result["hulls"] as Dictionary)["left"]),
		int((result["hulls"] as Dictionary)["right"])]

func _board_line(build: Dictionary) -> String:
	var rows: Array[String] = []
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		if str(entry.get("part", "")) == "league_core":
			continue
		var augment: String = str(entry.get("augment", ""))
		rows.append("%s%s" % [str(entry.get("part", "")),
			"+" + augment if augment != "" else ""])
	rows.sort()
	return " · ".join(rows)

func _seeds() -> Array[int]:
	var out: Array[int] = []
	for token: String in _arg("seeds", "1,2").split(",", false):
		out.append(int(token.strip_edges()))
	return out

func _head(title: String) -> void:
	_say("")
	_say("── %s %s" % [title, "─".repeat(maxi(4, 66 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _arg(name: String, fallback: String) -> String:
	for token: String in OS.get_cmdline_user_args():
		if token.begins_with("--%s=" % name):
			return token.substr(name.length() + 3)
	return fallback

func _arg_int(name: String, fallback: int) -> int:
	return int(_arg(name, str(fallback)))
