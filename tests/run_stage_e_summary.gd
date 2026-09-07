extends SceneTree
## 단계 E 종합 — K=3/5/6을 나란히 놓고 §9의 지표로 읽는다.
##
## 실행:
##   godot --headless --path . --script res://tests/run_stage_e_summary.gd -- \
##     --runs=tests/out/league/k3-n5-...,tests/out/league/k5-n5-...,tests/out/league/k6-n5-...
##
## 각 리그의 report.txt는 그 리그 안의 이야기만 한다. K를 **고르려면** 셋을 같은
## 표에 놓아야 하고, §9.4의 판단 기준이 요구하는 것도 그 비교다.
##
## **이 스크립트는 K를 고르지 않는다.** 판단 기준의 각 항목에 해당하는 수치를 낼 뿐이고,
## 허용할 재현율의 수치 기준은 아직 없다 (§9.4 마지막).

const Config = preload("res://league/league_config.gd")

const OUT_ROOT := "res://tests/out/league"

var _lines: Array[String] = []

func _init() -> void:
	var runs: Array[String] = _arg_list("runs")
	if runs.is_empty():
		push_error("--runs=<리그 출력 폴더 목록>이 필요하다")
		quit(1)
		return

	var data: Array = []
	for run_dir: String in runs:
		var loaded: Dictionary = _load(run_dir)
		if loaded.is_empty():
			_say("  %s: 읽지 못했다" % run_dir)
			continue
		data.append(loaded)
	if data.is_empty():
		quit(1)
		return

	_head("단계 E 종합 — K=3/5/6")
	_say("리그 %d개를 나란히 읽는다. 각 리그는 전략 5 × 풀 10 × 시드 5 = 250명." % data.size())
	_say("**K별 리그는 분리돼 있다** — 같은 상대를 만난 짝 비교가 아니다 (§8.2 마지막).")

	_progress(data)
	_offer_quality(data)
	_investment(data)
	_repetition_risk(data)
	_fixed_vs_flexible(data)
	_reading_guide()

	var text: String = "\n".join(_lines)
	print(text)
	_write(text, data, runs)
	quit(0)

# --- 1. 진행 ---

func _progress(data: Array) -> void:
	_head("K별 진행 — 도달·승점·생존")
	_say("  %-10s %6s %8s %9s %8s %10s" % ["배치", "K", "평균 도달", "평균 승점",
		"상한 생존", "시작 실패"])
	for run: Dictionary in data:
		var rows: Array = run["participants"]
		var reach: float = 0.0
		var points: float = 0.0
		var survived: int = 0
		var invalid: int = 0
		for p: Dictionary in rows:
			reach += float(p["end_round"])
			points += float(p["points"])
			if str(p["status"]) == "survived":
				survived += 1
			elif str(p["status"]) == "invalid_start":
				invalid += 1
		var n: int = maxi(1, rows.size())
		_say("  %-10s %6d %8.2f %9.2f %8d %10d" % [str(run["label"]).get_slice("-", 0),
			int(run["k"]), reach / float(n), points / float(n), survived, invalid])
	_say("")
	_say("  ※ 도달 라운드와 승점은 독립된 증거가 아니다 — 4손실 탈락자는")
	_say("     도달 = 승점 + 4가 항등적으로 성립한다.")

# --- 2. §9.1 제안의 질 ---

func _offer_quality(data: Array) -> void:
	_head("제안의 질 (§9.1) — K를 늘리면 유효한 대안이 늘어나는가")
	_say("  %-10s %6s %9s %11s %8s %9s" % ["배치", "K", "즉시 유효", "근거리 투자",
		"대안 수", "후보 부재"])
	for run: Dictionary in data:
		var choices: Array = run["choices"]
		var keepable_offers: int = 0
		var immediate: int = 0
		var future: int = 0
		var none: int = 0
		var lanes: int = 0
		for c: Dictionary in choices:
			# 유지 후보가 없는 제안은 즉시 유효의 분모에서도 뺀다.
			var keepable: bool = false
			var any_i: bool = false
			var any_f: bool = false
			var seen: Dictionary = {}
			for entry: Variant in c.get("offer_candidates", []):
				var offer: Dictionary = entry
				if bool(offer.get("keep_available", false)):
					keepable = true
				if bool(offer.get("improves", false)):
					any_i = true
				if bool((offer.get("future", {}) as Dictionary).get("future", false)):
					any_f = true
				var uses: Dictionary = offer.get("uses", {})
				for lane: String in ["body", "augment", "storage"]:
					if int(uses.get(lane, 0)) > 0:
						seen["%s/%s" % [str(offer["part_id"]), lane]] = true
			if keepable:
				keepable_offers += 1
			if any_i:
				immediate += 1
			if any_f:
				future += 1
			if not any_i and not any_f:
				none += 1
			lanes += seen.size()
		var n: int = maxi(1, choices.size())
		_say("  %-10s %6d %8.1f%% %10.1f%% %8.2f %8.1f%%"
			% [str(run["label"]).get_slice("-", 0), int(run["k"]),
				100.0 * float(immediate) / float(maxi(1, keepable_offers)),
				100.0 * float(future) / float(n),
				float(lanes) / float(n),
				100.0 * float(none) / float(n)])
	_say("")
	_say("  ※ **대안 수가 K에 비례해 늘지 않으면** 제안을 늘려도 유효한 선택지가")
	_say("     늘지 않는 것이다 (§9.4의 마지막 행). 그때는 평가기·콘텐츠 기능 중복·")
	_say("     합법적 사용법을 재검토해야 한다.")

# --- 3. §5.1 근거리 투자 ---

func _investment(data: Array) -> void:
	_head("근거리 투자의 실현 (§5.1의 4단계)")
	_say("  %-10s %6s %10s %10s %10s %10s" % ["배치", "K", "투자 건수", "기여",
		"열림·무기여", "미개방"])
	for run: Dictionary in data:
		var contributed: int = 0
		var idle: int = 0
		var never: int = 0
		for p: Dictionary in (run["participants"] as Array):
			contributed += int(p.get("inv_contributed", 0))
			idle += int(p.get("inv_opened_idle", 0))
			never += int(p.get("inv_never_opened", 0))
		var total: int = contributed + idle + never
		_say("  %-10s %6d %10d %9d %10d %10d"
			% [str(run["label"]).get_slice("-", 0), int(run["k"]),
				total, contributed, idle, never])
	_say("")
	_say("  ※ **미개방은 실패가 아니다.** 대부분은 런이 4손실로 끝나 결말을 못 본")
	_say("     것이다 — 회수 실패와 합치면 §5.2가 경고한 오독이 된다.")

# --- 4. §9.3 반복 위험 ---

func _repetition_risk(data: Array) -> void:
	_head("고정 전략 반복의 위험 (§9.3)")
	_say("  %-10s %5s %9s %8s %10s %11s %10s" % ["배치", "K", "레시피 완성",
		"완성 R", "보드 재현", "최다 중복", "본체+증강"])
	for run: Dictionary in data:
		var complete: int = 0
		var complete_rounds: int = 0
		var eligible: int = 0
		for p: Dictionary in (run["participants"] as Array):
			if str(p["strategy"]) != "fixed_recipe":
				continue
			if str(p.get("recipe_reachable", "0")) != "1":
				continue
			eligible += 1
			if int(p.get("recipe_complete_round", 0)) > 0:
				complete += 1
				complete_rounds += int(p["recipe_complete_round"])

		# 최종 보드 서명의 재현. 같은 서명이 둘 이상에게 나타난 횟수.
		var finals: Dictionary = _final_boards(run)
		var repeated: int = 0
		var signatures: Dictionary = {}
		for pid: int in finals:
			var sig: String = str(finals[pid])
			signatures[sig] = int(signatures.get(sig, 0)) + 1
		for sig2: String in signatures:
			if int(signatures[sig2]) > 1:
				repeated += int(signatures[sig2])

		# 같은 파츠를 본체로 몇 개까지 쌓았는가 (§9.3의 "중복 파츠 개수").
		var max_dup: int = 0
		var pairs: Dictionary = {}
		for pid2: int in finals:
			var counts: Dictionary = {}
			for row: String in str(finals[pid2]).split("|"):
				var body: String = row.get_slice("+", 0)
				var augment: String = row.get_slice("+", 1)
				if body == "" or body == "league_core":
					continue
				counts[body] = int(counts.get(body, 0)) + 1
				if augment != "":
					pairs["%s+%s" % [body, augment]] = \
						int(pairs.get("%s+%s" % [body, augment], 0)) + 1
			for part: String in counts:
				max_dup = maxi(max_dup, int(counts[part]))
		# 가장 많이 나온 본체+증강 조합의 점유율.
		var top_pair: int = 0
		var total_pairs: int = 0
		for pair: String in pairs:
			top_pair = maxi(top_pair, int(pairs[pair]))
			total_pairs += int(pairs[pair])

		_say("  %-10s %5d %6d/%-2d %8s %9.1f%% %11d %9.1f%%"
			% [str(run["label"]).get_slice("-", 0), int(run["k"]),
				complete, eligible,
				("%.1f" % (float(complete_rounds) / float(complete))) if complete > 0 else "-",
				100.0 * float(repeated) / float(maxi(1, finals.size())),
				max_dup,
				100.0 * float(top_pair) / float(maxi(1, total_pairs))])
	_say("")
	_say("  ※ '보드 재현'은 최종 보드 서명이 **둘 이상에게** 나타난 참가자의 비율이다.")
	_say("     0%가 목표가 아니다 — 목표는 반복을 고집하는 비용이 평균과 하위 성과에")
	_say("     나타나면서 운이 맞은 성공 경험은 남는 것이다 (§9.3 마지막).")
	_say("  ※ '최다 중복'은 한 보드에 같은 본체 파츠를 몇 개까지 쌓았는가다.")
	_say("  ※ '본체+증강'은 가장 많이 나온 숙주-증강 조합의 점유율이다. 이 값이 K와")
	_say("     함께 오르면 제안을 늘린 것이 **집중**을 낳은 것이다.")

# --- 5. 고정형 대 유연형 ---

func _fixed_vs_flexible(data: Array) -> void:
	_head("고정 레시피형 대 유연형 — 같은 풀에서 (§9.3)")
	_say("  도달 가능한 레시피가 배정된 풀만 본다. 하위 성과는 하위 25%의 평균이다.")
	_say("  %-10s %5s %11s %11s %10s %10s" % ["배치", "K", "고정형 평균",
		"유연형 평균", "고정 하위", "유연 하위"])
	for run: Dictionary in data:
		# 고정형에게 레시피가 없는 풀은 양쪽 모두에서 뺀다 — 비교가 성립하지 않는다.
		var usable: Dictionary = {}
		for p2: Dictionary in (run["participants"] as Array):
			if str(p2["strategy"]) == "fixed_recipe" \
					and str(p2.get("recipe_reachable", "0")) == "1":
				usable[str(p2["pool"])] = true

		var fixed: Array[float] = []
		var flexible: Array[float] = []
		for p3: Dictionary in (run["participants"] as Array):
			if not usable.has(str(p3["pool"])):
				continue
			if str(p3["strategy"]) == "fixed_recipe":
				fixed.append(float(p3["end_round"]))
			else:
				flexible.append(float(p3["end_round"]))
		_say("  %-10s %5d %11.2f %11.2f %10.2f %10.2f"
			% [str(run["label"]).get_slice("-", 0), int(run["k"]),
				_mean(fixed), _mean(flexible), _bottom_quartile(fixed),
				_bottom_quartile(flexible)])
	_say("")
	_say("  ※ **AI 승률을 맞추는 것이 목표가 아니다.** 보려는 것은 '반복을 고집하는")
	_say("     비용이 평균과 하위 성과에 나타나는가'다 — 고정형의 하위가 유연형의")
	_say("     하위보다 낮으면 나쁜 보상 흐름에서 더 크게 무너진다는 뜻이다.")
	_say("  ※ 유연형 넷을 한 칸에 합쳤다. 넷의 차이는 각 리그 report.txt에 있다.")

func _reading_guide() -> void:
	_head("§9.4의 판단 기준 — 이 표들을 어떻게 읽는가")
	_say("  5개 채택 후보  5가 3보다 의미 있는 선택과 고정 상대군 성과를 개선하고,")
	_say("                 레시피 재현·계열 집중은 과도하게 늘지 않을 때")
	_say("  6개 추가 검토  6이 5보다 새로운 판단과 유연형 성과를 더 개선하고,")
	_say("                 반복 전략 우위가 나타나지 않을 때")
	_say("  5개 유지       6에서 이득이 작고 강한 파츠·레시피 반복만 늘 때")
	_say("  원인 조사      5개부터 고정형이 안정적으로 우세해질 때")
	_say("  평가기 재검토  제안 수를 늘려도 유효한 대안이 늘지 않을 때")
	_say("")
	_say("  **지금 데이터에는 제품적으로 허용할 재현율의 수치 기준이 없다** (§9.4 마지막).")
	_say("  이 스크립트는 K를 고르지 않는다. 효과 크기를 낸 뒤 허용 범위와 실질적인")
	_say("  개선 폭을 정하는 것은 본실험 전의 결정이다.")

# --- 입력 ---

func _load(run_dir: String) -> Dictionary:
	var manifest: Variant = _read_json("%s/manifest.json" % run_dir)
	if not (manifest is Dictionary):
		return {}
	return {
		"label": run_dir.get_file(),
		"dir": run_dir,
		"k": int((manifest as Dictionary).get("resolved_config", {})
			.get("offers_per_choice", 0)),
		"manifest": manifest,
		"participants": _read_csv("%s/participants.csv" % run_dir),
		"choices": _read_jsonl("%s/choices.jsonl" % run_dir),
	}

## 참가자 id -> 최종 보드 서명. 선택 로그의 마지막 after_signature다.
func _final_boards(run: Dictionary) -> Dictionary:
	var last_index: Dictionary = {}
	var out: Dictionary = {}
	for c: Dictionary in (run["choices"] as Array):
		var pid: int = int(c["participant"])
		if int(c["index"]) >= int(last_index.get(pid, -1)):
			last_index[pid] = int(c["index"])
			out[pid] = str(c["after_signature"])
	return out

func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed

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

func _read_csv(path: String) -> Array:
	var out: Array = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var header: PackedStringArray = file.get_line().strip_edges().split(",")
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line == "":
			continue
		var cells: PackedStringArray = line.split(",")
		var row: Dictionary = {}
		for i: int in header.size():
			row[header[i]] = cells[i] if i < cells.size() else ""
		out.append(row)
	file.close()
	return out

# --- 통계 ---

static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(values.size())

## 하위 25%의 평균. **나쁜 보상 흐름에서 어떻게 되는가**를 보는 값이다 (§9.3).
static func _bottom_quartile(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var cut: int = maxi(1, int(float(sorted.size()) * 0.25))
	var total: float = 0.0
	for i: int in cut:
		total += sorted[i]
	return total / float(cut)

# --- 출력 ---

func _head(title: String) -> void:
	_lines.append("")
	_lines.append("── %s %s" % [title, "─".repeat(maxi(4, 62 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write(text: String, data: Array, runs: Array[String]) -> void:
	var run_id: String = "stageE-summary-%s" \
		% Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var dir: String = "%s/%s" % [OUT_ROOT, run_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file: FileAccess = FileAccess.open("%s/report.txt" % dir, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
	var manifests: Dictionary = {}
	for run: Dictionary in data:
		manifests[str(run["label"])] = run["manifest"]
	var meta: FileAccess = FileAccess.open("%s/inputs.json" % dir, FileAccess.WRITE)
	if meta != null:
		meta.store_string(JSON.stringify({"runs": runs, "manifests": manifests}, "  "))
	print("")
	print("출력: %s" % dir)

func _arg_list(name: String) -> Array[String]:
	var out: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			for piece: String in arg.split("=", true, 1)[1].split(","):
				if piece.strip_edges() != "":
					out.append(piece.strip_edges())
	return out
