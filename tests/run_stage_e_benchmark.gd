extends SceneTree
## 단계 E의 **외부 평가** — 각 K의 같은 획득 단계 스냅샷을 공통 고정 상대군에
## 재전투시킨다 (r5b 피드백 §8.4).
##
## 실행:
##   godot --headless --path . --script res://tests/run_stage_e_benchmark.gd -- \
##     --runs=tests/out/league/k3-...,tests/out/league/k5-...,tests/out/league/k6-... \
##     --round=4
##
## **왜 필요한가** (§8.4): 같은 K 안에서 서로 경쟁하면 모두 강해져도 전체 승패 합은
## 크게 달라지지 않는다. 리그 평균 승률이나 최종 생존 인원만으로 K를 고르면 안 된다.
##
## **같은 획득 단계**로 맞추는 것이 요점이다. K가 다르면 탈락 시점이 달라서 후반
## 스냅샷은 생존자 편향이 다르다 — 그래서 라운드를 고정하고, 그 라운드에 **도달한
## 비율**을 성과와 함께 낸다 (§8.4의 "해당 단계 도달률과 도달한 빌드의 평가 결과를
## 같이 표시").

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Benchmark = preload("res://league/benchmark.gd")

const OUT_ROOT := "res://tests/out/league"

## 대량 재전투는 시드를 하나만 쓴다. 상대군이 이미 18명이라 한 참가자당 36판이고,
## 단계 D의 레시피 검증(3시드 × 18상대 = 108판)과 목적이 다르다 — 저기서는 소수
## 보드의 강도를 정밀하게 재고, 여기서는 수백 명의 분포를 본다.
const MASS_SEEDS: Array[int] = [9001]

var _lines: Array[String] = []

func _init() -> void:
	var runs: Array[String] = _arg_list("runs")
	var target_round: int = _arg_int("round", 4)
	if runs.is_empty():
		push_error("--runs=<리그 출력 폴더 목록>이 필요하다")
		quit(1)
		return

	var content: RefCounted = LeagueContent.new()
	content.load_all()
	if not content.ok():
		for e: String in content.errors:
			print("  CONTENT  %s" % e)
		quit(1)
		return
	var config: RefCounted = Config.new()
	var opponents: Array = Archive.load_all()
	if opponents.is_empty():
		push_error("고정 상대군이 비어 있다")
		quit(1)
		return

	_head("단계 E 외부 평가 — 고정 상대군 재전투 (§8.4)")
	_say("상대군 %d명 · 시드 %s · 좌우 교환 = 참가자 1명당 %d판"
		% [opponents.size(), str(MASS_SEEDS), opponents.size() * MASS_SEEDS.size() * 2])
	_say("획득 단계 고정: **%d라운드 직전 스냅샷**" % target_round)
	_say("")

	var all: Dictionary = {}
	for run_dir: String in runs:
		var label: String = run_dir.get_file()
		var snapshots: Array = _read_jsonl("%s/snapshots.jsonl" % run_dir)
		if snapshots.is_empty():
			_say("  %s: 스냅샷을 읽지 못했다" % run_dir)
			continue
		var participants: Dictionary = _read_participants("%s/participants.csv" % run_dir)
		all[label] = _bench_run(content, config, opponents, snapshots,
			participants, target_round, label)

	_say("")
	_say("  ※ **도달률과 성과를 함께 읽는다.** 그 라운드에 도달한 빌드만 재전투하므로,")
	_say("     도달률이 낮은 조건의 높은 승률은 '살아남은 소수가 강했다'는 뜻이다 —")
	_say("     그 전략 전체의 능력이 아니다 (§8.4 마지막).")
	_say("  ※ 상대군은 r5b(구 규칙, plating Core)에서 뽑았다. 지금 배치는 중립 배율로")
	_say("     도는데 재전투도 중립으로 한다 — 상대군의 **구성**만 가져온 것이고")
	_say("     전투 조건은 현재 리그 규칙을 따른다.")

	var text: String = "\n".join(_lines)
	print(text)
	_write(text, all, target_round, runs)
	quit(0)

## 한 리그 폴더의 지정 라운드 스냅샷을 전부 재전투한다.
func _bench_run(content: RefCounted, config: RefCounted, opponents: Array,
		snapshots: Array, participants: Dictionary, target_round: int,
		label: String) -> Dictionary:
	var by_strategy: Dictionary = {}
	# Dictionary.size()는 키 개수다 — 참가자 수가 아니라 2가 나온다. 실측으로 걸렸다.
	var total_participants: int = int(participants.get("size", 0))
	var reached: int = 0

	for snap: Dictionary in snapshots:
		if int(snap["round"]) != target_round:
			continue
		reached += 1
		var strategy: String = str(snap["strategy"])
		if not by_strategy.has(strategy):
			by_strategy[strategy] = {"n": 0, "wins": 0, "decided": 0,
				"margin": 0.0, "unresolved": 0}
		var row: Dictionary = by_strategy[strategy]
		var r: Dictionary = Benchmark.run(content.catalog, config, snap["build"],
			opponents, config.combat_rules(), str(snap["snapshot_id"]), MASS_SEEDS)
		row["n"] = int(row["n"]) + 1
		row["wins"] = int(row["wins"]) + int(r["wins"])
		row["decided"] = int(row["decided"]) + int(r["decided"])
		row["margin"] = float(row["margin"]) + float(r["avg_margin"])
		row["unresolved"] = int(row["unresolved"]) + int(r["unresolved"])

	_say("  ── %s ── (참가자 %d명 중 %d명이 %d라운드에 도달, %.1f%%)"
		% [label, total_participants, reached, target_round,
			100.0 * float(reached) / float(maxi(1, total_participants))])
	_say("  %-13s %6s %8s %9s %10s" % ["전략", "도달", "도달률", "상대군 승률", "평균 격차"])
	var out: Dictionary = {"label": label, "reached": reached,
		"participants": total_participants, "round": target_round, "rows": {}}
	for strategy2: String in Config.STRATEGIES:
		var row2: Dictionary = by_strategy.get(strategy2, {})
		if row2.is_empty():
			continue
		var per_strategy: int = int(participants.get("_by_strategy", {})
			.get(strategy2, 0))
		var n: int = maxi(1, int(row2["n"]))
		var summary: Dictionary = {
			"reached": int(row2["n"]), "of": per_strategy,
			"win_rate": float(row2["wins"]) / float(maxi(1, int(row2["decided"]))),
			"avg_margin": float(row2["margin"]) / float(n),
			"unresolved": int(row2["unresolved"]),
		}
		(out["rows"] as Dictionary)[strategy2] = summary
		_say("  %-13s %6d %7.1f%% %10.1f%% %+10.1f" % [strategy2, int(row2["n"]),
			100.0 * float(row2["n"]) / float(maxi(1, per_strategy)),
			100.0 * float(summary["win_rate"]), float(summary["avg_margin"])])
	return out

# --- 입력 ---

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

## 참가자 수와 전략별 인원. 도달률의 분모다.
func _read_participants(path: String) -> Dictionary:
	var out: Dictionary = {"_by_strategy": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var header: PackedStringArray = file.get_line().split(",")
	var strategy_col: int = Array(header).find("strategy")
	var count: int = 0
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line == "":
			continue
		count += 1
		if strategy_col >= 0:
			var cells: PackedStringArray = line.split(",")
			if strategy_col < cells.size():
				var s: String = cells[strategy_col]
				(out["_by_strategy"] as Dictionary)[s] = \
					int((out["_by_strategy"] as Dictionary).get(s, 0)) + 1
	file.close()
	out["size"] = count
	return out


# --- 출력 ---

func _head(title: String) -> void:
	_lines.append("")
	_lines.append("── %s %s" % [title, "─".repeat(maxi(4, 60 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write(text: String, results: Dictionary, target_round: int,
		runs: Array[String]) -> void:
	var run_id: String = "stageE-bench-%s" \
		% Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var dir: String = "%s/%s" % [OUT_ROOT, run_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_store("%s/report.txt" % dir, text)
	_store("%s/results.json" % dir, JSON.stringify({
		"run_id": run_id, "round": target_round, "runs": runs,
		"archive": Archive.manifest(), "seeds": MASS_SEEDS,
		"results": results,
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
