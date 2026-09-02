extends SceneTree
## Mini Iteration 리포트. 오토파일럿으로 런을 여러 번 돌려 설계 문서 §10의 지표를 낸다.
## 실행: godot --headless --path . --script res://tests/run_mini.gd
##
## **오토파일럿 수치는 하한선으로만 읽어야 한다.** "Tune이 재미있는가"는 사람이
## 조작해야 답이 나오는 질문이고, 여기 나오는 교체 수는 "규칙이 이렇게 하면 이 정도"다.
## 이 리포트가 답하는 것은 그보다 앞의 질문들이다 —
## 6전투가 완주 가능한가 · 어느 노드가 벽인가 · 쓰이지 않는 파츠가 있는가 ·
## Salvage 풀이 고갈되지 않는가.
##
## 밸런스 판정은 하지 않는다. 파츠 수치는 잠정이다.

const Content = preload("res://sim/content.gd")
const RunContent = preload("res://run/run_content.gd")
const MiniIteration = preload("res://run/mini_iteration.gd")
const Autopilot = preload("res://run/autopilot.gd")

const RUNS_PER_FACTION: int = 20
const REPORT_PATH := "res://tests/out/mini_report.txt"

var _lines: Array[String] = []

func _init() -> void:
	var catalog: RefCounted = Content.load_catalog()
	if not catalog.ok():
		for e: String in catalog.errors:
			print("  CATALOG  %s" % e)
		quit(1)
		return
	var content: RefCounted = RunContent.new()
	content.load_all()
	content.validate(catalog)
	if not content.ok():
		for e: String in content.errors:
			print("  RUN CONTENT  %s" % e)
		quit(1)
		return

	var runs: Array = []
	for faction: String in content.faction_ids():
		for s: int in range(1, RUNS_PER_FACTION + 1):
			var it: RefCounted = MiniIteration.new()
			it.setup(catalog, content)
			it.begin(faction, s)
			var result: String = Autopilot.play(it)
			runs.append({"faction": faction, "seed": s, "result": result, "history": it.history})

	_say("")
	_say("THE FIRST DIVERGENCE — Mini Iteration 리포트 (오토파일럿)")
	_say("팩션 %d종 × 시드 %d = 런 %d회 · 노드 %d개"
		% [content.faction_ids().size(), RUNS_PER_FACTION, runs.size(), content.node_count()])

	_report_completion(runs, content)
	_report_node_wall(runs, content)
	_report_tune(runs)
	_report_part_value(runs, catalog, content)
	_report_combat(runs)

	for line: String in _lines:
		print(line)
	_write()
	quit(0)

# --- 완주 ---

func _report_completion(runs: Array, content: RefCounted) -> void:
	_head("완주")
	var by_faction: Dictionary = {}
	for run: Dictionary in runs:
		var f: String = str(run["faction"])
		if not by_faction.has(f):
			by_faction[f] = {"n": 0, "won": 0, "combats": 0}
		var b: Dictionary = by_faction[f]
		b["n"] = int(b["n"]) + 1
		b["combats"] = int(b["combats"]) + (run["history"] as Array).size()
		if str(run["result"]) == "won":
			b["won"] = int(b["won"]) + 1
	for f: String in by_faction:
		var b: Dictionary = by_faction[f]
		_say("  %-10s 완주 %2d/%2d (%5.1f%%)   평균 %.1f전투 / %d"
			% [f, int(b["won"]), int(b["n"]),
				100.0 * float(b["won"]) / float(b["n"]),
				float(b["combats"]) / float(b["n"]), content.node_count()])

# --- 어느 노드가 벽인가 ---

func _report_node_wall(runs: Array, content: RefCounted) -> void:
	_head("노드별 승률 — 벽이 어디인가")
	var reached: Array[int] = []
	var won: Array[int] = []
	for i: int in content.node_count():
		reached.append(0)
		won.append(0)
	var picks: Dictionary = {}
	for run: Dictionary in runs:
		for record: Dictionary in run["history"]:
			var node: int = int(record["node"])
			reached[node] += 1
			if str(record["winner"]) == "player":
				won[node] += 1
			var key: String = "%d/%s" % [node, record["enemy"]]
			picks[key] = int(picks.get(key, 0)) + 1
	for i: int in content.node_count():
		var kind: String = str(content.node(i).get("kind", "combat"))
		var bar: String = "" if reached[i] == 0 else "#".repeat(int(round(20.0 * float(won[i]) / float(reached[i]))))
		_say("  노드 %d %-6s 도달 %3d  승 %3d  %5.1f%%  %s"
			% [i + 1, kind, reached[i], won[i],
				0.0 if reached[i] == 0 else 100.0 * float(won[i]) / float(reached[i]), bar])
	_say("")
	_say("  적 선택 분포 (오토파일럿은 상성이 유리한 쪽을 고른다):")
	for key: String in picks:
		_say("    %-40s %3d회" % [key, int(picks[key])])

# --- Tune 지표 (§10 핵심) ---

func _report_tune(runs: Array) -> void:
	_head("빌드 변화 — §10 핵심 지표")
	var combats: int = 0
	var active: int = 0
	var augment: int = 0
	var moved: int = 0
	var zero_tune: int = 0
	for run: Dictionary in runs:
		for record: Dictionary in run["history"]:
			var tune: Dictionary = record["tune"]
			combats += 1
			active += int(tune["active"])
			augment += int(tune["augment"])
			moved += int(tune["moved"])
			if int(tune["active"]) == 0 and int(tune["augment"]) == 0:
				zero_tune += 1
	var n: float = maxf(1.0, float(combats))
	_say("  전투당 Active 교체    %.2f  %s"
		% [float(active) / n, _verdict(active / n >= 1.0 and active / n <= 2.0)])
	_say("  전투당 Augment 변경   %.2f" % (float(augment) / n))
	_say("  전투당 슬롯 재배치    %.2f" % (float(moved) / n))
	_say("  아무것도 안 바꾼 전투 %.1f%% (%d/%d)"
		% [100.0 * float(zero_tune) / n, zero_tune, combats])
	_say("")
	_say("  ※ 목표는 전투당 1~2개다. 보드가 통째로 바뀌면 Tune이 아니라 Rebuild이고,")
	_say("     0에 가까우면 Tune 동기가 없다는 뜻이다. 다만 오토파일럿의 교체 수에는")
	_say("     빈 슬롯 채우기(Build)가 섞여 있으므로 초반 노드가 부풀어 보인다.")
	_say("     이 지표의 진짜 값은 사람이 플레이해야 나온다.")

# --- 파츠 가치 ---

func _report_part_value(runs: Array, catalog: RefCounted, content: RefCounted) -> void:
	_head("파츠 가치")
	var offered: Dictionary = {}
	var taken: Dictionary = {}
	var as_active: Dictionary = {}
	var as_augment: Dictionary = {}
	for run: Dictionary in runs:
		for record: Dictionary in run["history"]:
			for pid: Variant in record["offer"]:
				offered[str(pid)] = int(offered.get(str(pid), 0)) + 1
			if str(record["taken"]) != "":
				taken[str(record["taken"])] = int(taken.get(str(record["taken"]), 0)) + 1
			var board: Dictionary = record["board"]
			var owned: Array = record["owned"]
			for slot_id: String in board:
				var entry: Dictionary = board[slot_id]
				var a: int = int(entry.get("active", -1)) - 1
				var g: int = int(entry.get("augment", -1)) - 1
				if a >= 0 and a < owned.size():
					as_active[str(owned[a])] = int(as_active.get(str(owned[a]), 0)) + 1
				if g >= 0 and g < owned.size():
					as_augment[str(owned[g])] = int(as_augment.get(str(owned[g]), 0)) + 1

	var never_offered: Array[String] = []
	var never_taken: Array[String] = []
	for pid: String in catalog.parts:
		if str(catalog.parts[pid]["base_role"]) == "core":
			continue
		if not offered.has(pid):
			never_offered.append(pid)
		elif not taken.has(pid):
			never_taken.append(pid)

	_say("  %-24s %8s %8s %8s %8s" % ["파츠", "제시", "선택", "선택률", "Active"])
	for pid: String in catalog.parts:
		if not offered.has(pid):
			continue
		var o: int = int(offered[pid])
		var k: int = int(taken.get(pid, 0))
		_say("  %-24s %8d %8d %7.0f%% %8d"
			% [str(catalog.parts[pid]["name"]), o, k, 100.0 * float(k) / float(o),
				int(as_active.get(pid, 0))])
	_say("")
	_say("  한 번도 제시되지 않은 파츠: %s"
		% ("없음" if never_offered.is_empty() else str(never_offered)))
	_say("  제시됐지만 한 번도 선택되지 않은 파츠: %s"
		% ("없음" if never_taken.is_empty() else str(never_taken)))
	_say("  ※ Core는 Salvage 후보에서 제외되므로 이 표에 없다 (run_content.EXCLUDE_CORES_FROM_SALVAGE).")

# --- 전투 데이터 ---

func _report_combat(runs: Array) -> void:
	_head("전투 데이터 (플레이어 기준 평균)")
	var keys: Array[String] = [
		"elapsed", "damage", "hull_damage", "repair", "regen", "shield_gained",
		"material_gained", "material_spent", "overheat_applied", "overheat_ticks",
		"multi_fires", "accelerates", "charges", "fires", "parts_destroyed",
	]
	var totals: Dictionary = {}
	var combats: int = 0
	var by_type: Dictionary = {}
	for run: Dictionary in runs:
		for record: Dictionary in run["history"]:
			combats += 1
			var summary: Dictionary = record["summary"]
			for key: String in keys:
				totals[key] = float(totals.get(key, 0.0)) + float(summary.get(key, 0))
			for dtype: String in (summary.get("damage_by_type", {}) as Dictionary):
				by_type[dtype] = int(by_type.get(dtype, 0)) \
					+ int((summary["damage_by_type"] as Dictionary)[dtype])
	var n: float = maxf(1.0, float(combats))
	for key: String in keys:
		_say("  %-18s %8.2f" % [key, float(totals[key]) / n])
	_say("")
	_say("  피해 타입 분포 (총합):")
	for dtype: String in by_type:
		_say("    %-10s %8d" % [dtype, int(by_type[dtype])])

# --- 보조 ---

func _verdict(ok: bool) -> String:
	return "[목표 1~2]" if ok else "[목표 밖]"

func _head(title: String) -> void:
	_say("")
	_say("── %s %s" % [title, "─".repeat(maxi(2, 56 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_lines) + "\n")
	print("")
	print("리포트 저장: %s" % REPORT_PATH)
