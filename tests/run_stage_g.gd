extends SceneTree
## 단계 G — PvE 적 프리셋 후보 추출 (r5b 피드백 §12의 G행).
##
## 실행:
##   godot --headless --path . --script res://tests/run_stage_g.gd -- \
##     --runs=tests/out/league/k5-n5-...,tests/out/league/k5-n20-... --count=24
##
## 완료 기준: **"엔진 설명·약점·획득 단계·초과 피해 의존이 있는 후보 데이터"**.
## 넷 다 있어야 한다 — 빌드만 뽑아 놓으면 그것을 쓰는 사람이 "이게 무엇을 하는
## 적인가"와 "어느 난이도인가"를 다시 알아내야 한다.
##
##   엔진 설명    **실제 발동한 연결**로 쓴다 (§12.2). 정적 어휘가 아니다.
##   약점         고정 상대군 중 이 후보가 지는 구조
##   획득 단계    몇 라운드 스냅샷인가 — 그대로 난이도 곡선의 위치가 된다
##   초과 피해 의존 리그 전용 규칙이 없으면 못 이기는 후보인가 (§9.4)
##
## **이 리그의 승률을 실제 PvE 난이도로 해석하지 않는다** (기획서 §1.3). 여기서
## 내는 것은 후보와 그 후보를 읽는 데 필요한 사실이지, 난이도 확정이 아니다.

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Benchmark = preload("res://league/benchmark.gd")
const CombatAdapter = preload("res://league/combat_adapter.gd")
const EngineTrace = preload("res://league/engine_trace.gd")
const Profile = preload("res://league/build_profile.gd")
const Graph = preload("res://league/build_graph.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Inventory = preload("res://run/inventory.gd")

const OUT_ROOT := "res://tests/out/league"

## 후보를 뽑을 획득 단계. §12의 "단계별"이 이것이다 — 난이도 곡선의 위치가
## 곧 획득 단계다.
const STAGES: Array[int] = [2, 5, 8, 12]

var _lines: Array[String] = []
var _content: RefCounted
var _config: RefCounted

func _init() -> void:
	var runs: Array[String] = _arg_list("runs")
	var want: int = _arg_int("count", 24)
	if runs.is_empty():
		push_error("--runs=<리그 출력 폴더 목록>이 필요하다")
		quit(1)
		return

	_content = LeagueContent.new()
	_content.load_all()
	if not _content.ok():
		for e: String in _content.errors:
			print("  CONTENT  %s" % e)
		quit(1)
		return
	_config = Config.new()
	_config.capture_version()

	var opponents: Array = Archive.load_all()
	if opponents.is_empty():
		push_error("고정 상대군이 비어 있다")
		quit(1)
		return

	var pool: Array = []
	for run_dir: String in runs:
		for snap: Variant in _read_jsonl("%s/snapshots.jsonl" % run_dir):
			var row: Dictionary = snap
			if STAGES.has(int(row["round"])):
				row["run"] = run_dir.get_file()
				pool.append(row)
	if pool.is_empty():
		push_error("해당 라운드의 스냅샷이 없다")
		quit(1)
		return

	_head("단계 G — PvE 프리셋 후보")
	_say("입력 스냅샷 %d개 (라운드 %s) · 목표 후보 %d개"
		% [pool.size(), str(STAGES), want])
	_say("커밋 %s%s · 상대군 %s"
		% [_config.git_commit().substr(0, 10),
			" (작업 트리 변경 있음)" if _config.git_dirty() else "",
			str(Archive.manifest()["version"])])

	var picked: Array = _select(pool, want)
	_say("")
	_say("선정 %d개 — 라운드 × 구조 버킷으로 고르게 나눴다." % picked.size())

	var candidates: Array = []
	for entry: Dictionary in picked:
		candidates.append(_profile_candidate(entry, opponents))

	_report(candidates)
	var text: String = "\n".join(_lines)
	print(text)
	_write(text, candidates, runs)
	quit(0)

## 라운드 × 구조로 고르게 뽑는다. **강한 것만 뽑으면 프리셋이 전부 상위 난이도가 된다.**
## §12의 "단계별"은 난이도 스펙트럼을 요구하는 것이지 최강 목록이 아니다.
func _select(pool: Array, want: int) -> Array:
	# 라운드별로 먼저 나누고, 그 안에서 구조 버킷으로 나눈다.
	#
	# 첫 판본은 "라운드|버킷" 키 하나로 묶고 키를 정렬했는데, **문자열 정렬이라
	# "12"가 "2"보다 앞에 왔다.** 그래서 24개 중 21개가 12라운드에서 나오고
	# 5·8라운드는 하나도 못 들어왔다 — §12가 요구한 "단계별"이 무너진 것이다.
	# 난이도 스펙트럼이 목적이므로 **라운드 배분을 먼저 고정한다.**
	var by_stage: Dictionary = {}
	for stage_round: int in STAGES:
		by_stage[stage_round] = {}
	for snap: Dictionary in pool:
		var analysis: Dictionary = _analyze(snap["build"])
		if not bool(analysis["operational"]):
			continue   # 공격 불능은 프리셋 후보가 아니다
		var profile: Dictionary = Profile.of(analysis)
		snap["profile"] = profile
		snap["signature"] = _signature(snap["build"])
		var stage: Dictionary = by_stage[int(snap["round"])]
		var bucket: String = Profile.bucket_of(profile)
		if not stage.has(bucket):
			stage[bucket] = []
		(stage[bucket] as Array).append(snap)

	# 라운드마다 같은 몫을 준다. 어떤 라운드에 후보가 모자라면 남은 몫은
	# 다음 라운드가 가져간다 — 비우고 끝내지 않는다.
	var quota: int = maxi(1, want / maxi(1, STAGES.size()))
	var out: Array = []
	var seen_sig: Dictionary = {}
	for pass_index: int in 2:
		for stage_round2: int in STAGES:
			var target: int = quota if pass_index == 0 else want
			var taken: int = 0
			for o: Variant in out:
				if int((o as Dictionary)["round"]) == stage_round2:
					taken += 1
			var buckets: Dictionary = by_stage[stage_round2]
			var keys: Array = buckets.keys()
			keys.sort()
			var depth: int = 0
			while taken < target and out.size() < want and depth < 8:
				var added: int = 0
				for key: String in keys:
					if taken >= target or out.size() >= want:
						break
					var group: Array = buckets[key]
					if depth >= group.size():
						continue
					var snap2: Dictionary = group[depth]
					if seen_sig.has(str(snap2["signature"])):
						continue
					seen_sig[str(snap2["signature"])] = true
					out.append(snap2)
					taken += 1
					added += 1
				if added == 0:
					break
				depth += 1
	return out

## 후보 하나의 프리셋 데이터. 넷을 모두 채운다.
func _profile_candidate(snap: Dictionary, opponents: Array) -> Dictionary:
	# 강도·약점·초과 피해 의존 — 고정 상대군에서.
	var with_overtime: Dictionary = Benchmark.run(_content.catalog, _config,
		snap["build"], opponents, _config.combat_rules(), str(snap["snapshot_id"]))
	# 초과 피해가 없으면 어떻게 되는가. **미해결은 승패에 섞지 않는다** (§11.2).
	var without: Dictionary = Benchmark.run(_content.catalog, _config,
		snap["build"], opponents, Benchmark.no_overtime_rules(),
		str(snap["snapshot_id"]))

	# 약점 — 이 후보가 지는 상대의 구조.
	var weak_against: Array[String] = []
	for row: Variant in (with_overtime["per_opponent"] as Array):
		var entry: Dictionary = row
		if float((entry["result"] as Dictionary)["win_rate"]) < 0.5:
			weak_against.append(str(entry["bucket"]))
	var weakness: Dictionary = {}
	for bucket: String in weak_against:
		weakness[bucket] = int(weakness.get(bucket, 0)) + 1

	# 엔진 설명 — **실제 발동한 연결**로 (§12.2). 상대군 몇 명과 실제로 싸워 본다.
	var traces: Array = []
	for i: int in mini(4, opponents.size()):
		var opponent: Dictionary = opponents[i]
		var seed_value: int = Config.mix(["preset", str(snap["snapshot_id"]),
			str(opponent["id"])])
		var result: Dictionary = CombatAdapter.fight(_content.catalog, _config,
			snap["build"], opponent["build"], seed_value)
		if bool(result["ok"]):
			traces.append(EngineTrace.of_combat(result["log"], "player", snap["build"]))
	var merged: Dictionary = EngineTrace.merge(traces) if not traces.is_empty() \
		else {"fires": {}, "links": {}, "damage": {}, "idle": [], "combats": 0}

	return {
		# **배치 이름을 두 마디까지 쓴다.** 한 마디(k5)만 쓰면 시드 수가 다른 두
		# 배치의 같은 참가자 번호가 같은 id가 된다 — 실제로 preset_k5_p33_r5가
		# 두 번 나왔다.
		"id": "preset_%s-%s_%s" % [str(snap["run"]).get_slice("-", 0),
			str(snap["run"]).get_slice("-", 1),
			str(snap["snapshot_id"])],
		"source": {
			"run": str(snap["run"]), "snapshot_id": str(snap["snapshot_id"]),
			"participant": int(snap["participant"]), "strategy": str(snap["strategy"]),
			"pool": str(snap["pool"]), "seed": int(snap["seed"]),
		},
		# 획득 단계 — 그대로 난이도 곡선의 위치다.
		"stage_round": int(snap["round"]),
		"acquisitions": int(snap["acquisitions"]),
		"build": snap["build"],
		"storage": snap.get("storage", []),
		"structure": snap["profile"],
		# 엔진 설명 — 관측이지 어휘가 아니다.
		"engine": EngineTrace.describe(merged, snap["build"]),
		"engine_detail": merged,
		# 강도
		"benchmark": {
			"win_rate": float(with_overtime["win_rate"]),
			"avg_margin": float(with_overtime["avg_margin"]),
			"avg_elapsed": float(with_overtime["avg_elapsed"]),
		},
		# 약점
		"weak_against": weakness,
		# 초과 피해 의존
		"overtime": {
			"decided_with": int(with_overtime["overtime_decided"]),
			"win_rate_with": float(with_overtime["win_rate"]),
			"win_rate_without": float(without["win_rate"]),
			"unresolved_without": int(without["unresolved"]),
			"matches": int(with_overtime["matches"]),
		},
	}

func _report(candidates: Array) -> void:
	_head("프리셋 후보")
	_say("  %-26s %4s %7s %8s %8s %9s" % ["후보", "R", "승률", "격차",
		"초과의존", "미해결(OFF)"])
	for c: Dictionary in candidates:
		var ot: Dictionary = c["overtime"]
		var drop: float = float(ot["win_rate_with"]) - float(ot["win_rate_without"])
		_say("  %-26s %4d %6.1f%% %+8.1f %+7.1f%%p %9d"
			% [str(c["id"]), int(c["stage_round"]),
				100.0 * float((c["benchmark"] as Dictionary)["win_rate"]),
				float((c["benchmark"] as Dictionary)["avg_margin"]),
				100.0 * drop, int(ot["unresolved_without"])])
	_say("")
	_say("  ※ '초과의존'은 초과 피해를 껐을 때 승률이 얼마나 떨어지는가다. 값이 크면")
	_say("     **리그 전용 규칙으로 이긴 후보**이므로 본편에 그 규칙이 없다면 그대로")
	_say("     프리셋 강도로 쓸 수 없다 (§9.4).")
	_say("  ※ 미해결(OFF)은 초과 피해 없이 120초 안에 끝나지 않은 판이다. 승패에")
	_say("     섞지 않았다 — 결과가 아니라 관측 실패다 (§11.2).")

	_say("")
	_say("  엔진 설명 — **실제 발동한 연결**이다 (§12.2). 정적 어휘가 아니다.")
	for c2: Dictionary in candidates:
		_say("")
		_say("  %s  (R%d · %s · %s)" % [str(c2["id"]), int(c2["stage_round"]),
			str((c2["source"] as Dictionary)["strategy"]),
			str((c2["source"] as Dictionary)["pool"])])
		_say("    보드   %s" % _board_line(c2["build"]))
		_say("    엔진   %s" % str(c2["engine"]))
		var weak: Array[String] = []
		for bucket: String in (c2["weak_against"] as Dictionary):
			weak.append("%s(%d)" % [bucket, int((c2["weak_against"] as Dictionary)[bucket])])
		_say("    약점   %s" % ("없음 — 상대군 전원에게 우세" if weak.is_empty()
			else ", ".join(weak)))
	_say("")
	_say("  ※ 약점은 **고정 상대군 안에서**의 것이다. 상대군에 없는 구조에 대한")
	_say("     약점은 이 표가 말하지 않는다.")
	_say("  ※ **이 리그의 승률을 실제 PvE 난이도로 해석하지 않는다** (기획서 §1.3).")

# --- 보조 ---

func _board_line(build: Dictionary) -> String:
	var rows: Array[String] = []
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		if str(entry.get("part", "")) == _config.core_id:
			continue
		var augment: String = str(entry.get("augment", ""))
		rows.append("%s%s" % [str(entry.get("part", "")),
			"+" + augment if augment != "" else ""])
	rows.sort()
	return " · ".join(rows)

func _signature(build: Dictionary) -> String:
	var rows: Array[String] = []
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		rows.append("%s+%s" % [str(entry.get("part", "")), str(entry.get("augment", ""))])
	rows.sort()
	return "|".join(rows)

func _analyze(build: Dictionary) -> Dictionary:
	var inv: RefCounted = Inventory.new()
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		var uid: int = inv.add(str(entry.get("part", "")))
		var aug: int = Inventory.NONE
		if str(entry.get("augment", "")) != "":
			aug = inv.add(str(entry["augment"]))
		inv.place(slot_id, uid, aug)
	return Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index),
		_content.body_slot_count(_config), {})

func _read_jsonl(path: String) -> Array:
	var out: Array = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	file.close()
	return out

func _head(title: String) -> void:
	_lines.append("")
	_lines.append("── %s %s" % [title, "─".repeat(maxi(4, 62 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write(text: String, candidates: Array, runs: Array[String]) -> void:
	var run_id: String = "stageG-%s" \
		% Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var dir: String = "%s/%s" % [OUT_ROOT, run_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_store("%s/report.txt" % dir, text)
	_store("%s/presets.json" % dir, JSON.stringify({
		"run_id": run_id,
		"git_commit": _config.started_commit, "git_dirty": _config.started_dirty,
		"league_version": _config.league_version,
		"league_rules": _config.combat_rules(),
		"archive": Archive.manifest(),
		"source_runs": runs, "stages": STAGES,
		"candidates": candidates,
	}, "  "))
	print("")
	print("출력: %s" % dir)

func _store(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)

func _arg_list(name: String) -> Array[String]:
	var out: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			for piece: String in arg.split("=", true, 1)[1].split(","):
				if piece.strip_edges() != "":
					out.append(piece.strip_edges())
	return out

func _arg_int(name: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return int(arg.split("=", true, 1)[1])
	return fallback
