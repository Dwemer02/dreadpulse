extends RefCounted
## 리그 결과를 사람이 읽는 리포트와 기계가 읽는 파일로 낸다. 기획서 §11.
##
## 읽는 규칙 셋을 리포트 안에 그대로 적는다 — 나중에 이 숫자만 떼어 인용되는 것을
## 막기 위해서다 (§11.2):
##   · 리그 승률은 빌드의 절대 강도가 아니다 (승점 매칭이 상대 분포를 바꾼다)
##   · 배치 중도 종료는 탈락이 아니라 관측 중단이다
##   · 적은 표본의 순위는 확정하지 않는다

const Config = preload("res://league/league_config.gd")

const OUT_ROOT := "res://tests/out/league"

## 실행마다 고유 폴더를 만든다. **기존 결과를 덮어쓰지 않는다** (r5 피드백 §8.2) —
## 결정론적 재생이 강점이라도 결과 보존을 생략할 이유는 아니다. 코드를 되돌리거나
## 엔진을 다시 맞추지 않고 패치 전후를 비교할 수 있어야 한다.
##
## `tests/out/`은 통째로 .gitignore 대상이다(스크래치). git은 제외된 디렉터리 안의
## 파일을 다시 포함시킬 수 없으므로 여기서 해결하지 않는다 — 분석 문서를 쓸 때
## manifest.json과 report.txt를 docs/ 쪽으로 함께 복사한다. 둘 다 작고, 무엇을
## 돌렸는지 확인하는 데 필요한 전부다.
var out_dir: String = OUT_ROOT

var lines: Array[String] = []

func report(runner: RefCounted, coverage: Dictionary) -> String:
	lines = []
	_head("자동 조립 리그 — 배치 %s" % runner.config.batch_id)
	var m: Dictionary = runner.config.manifest()
	_say("게임 %s · AI %s · 리그 %s" % [m["game_version"], m["ai_version"], m["league_version"]])
	_say("참가자 %d명 = 전략 %d × 풀 %d × 시드 %d"
		% [runner.participants.size(), Config.STRATEGIES.size(),
			Config.pool_ids().size(), runner.config.repeats_per_condition])
	_say("규칙: %d손실 탈락 · 최대 %d라운드 · 보관 %d · 초과 피해 %d초부터 · %s"
		% [m["loss_limit"], m["round_cap"], m["storage_limit"],
			int(runner.config.overtime_start_seconds), runner.config.frame_id])
	_say("Core: %s (효과 없음, 재질 plating) — **재질 편향은 알려진 조건이다**: "
		% runner.config.core_id)
	_say("  caustic을 1.5배로 맞고 thermal을 0.75배로 맞는다. 재질 축은 별도 배치다.")
	_say("커밋 %s%s · Godot %s · 시드 규칙 %s"
		% [str(m["git_commit"]).substr(0, 10),
			" (작업 트리 변경 있음 — 이 커밋으로 그대로 재현되지 않는다)" 				if bool(m["git_dirty"]) else "",
			m["godot_version"], m["seed_rule"]])

	_coverage(coverage)
	_termination(runner)
	_by_condition(runner)
	_early_failure(runner)
	_choices(runner)
	_combat(runner)
	_diversity(runner)
	_matching(runner)
	_errors(runner)

	var text: String = "\n".join(lines)
	_write(runner, text)
	return text

# --- 절 ---

func _coverage(coverage: Dictionary) -> void:
	_head("파츠 지원 범위 (§14)")
	_say("  파츠 %d종 중 %d종을 자동 추정으로 완전히 덮었다"
		% [int(coverage["total"]), int(coverage["covered"])])
	if (coverage["uncovered_ops"] as Dictionary).is_empty():
		_say("  추정에서 빠진 op 없음")
	else:
		_say("  추정에서 빠진 op (조용히 0점 처리하지 않고 그대로 노출한다):")
		for op: String in (coverage["uncovered_ops"] as Dictionary):
			_say("    %-22s %d곳" % [op, int((coverage["uncovered_ops"] as Dictionary)[op])])
		_say("  ※ 이 op을 쓰는 파츠는 AI가 과소평가한다. 선택률이 낮다면 파츠가 약한 것이")
		_say("     아니라 AI가 못 읽은 것일 수 있다 (§1.1의 다섯 번째 질문).")

func _termination(runner: RefCounted) -> void:
	_head("종료 상태")
	var by_status: Dictionary = {}
	for p: Dictionary in runner.participants:
		var s: String = str(p["status"])
		by_status[s] = int(by_status.get(s, 0)) + 1
	for status: String in ["survived", "eliminated", "invalid_start", "batch_censored"]:
		if by_status.has(status):
			_say("  %-16s %4d명" % [_status_name(status), int(by_status[status])])
	if runner.censored_round > 0:
		_say("  ※ %d라운드에서 배치가 관측 중단됐다. 탈락으로 세지 않는다 (§8.2)."
			% runner.censored_round)

	_say("")
	_say("  탈락 라운드 분포:")
	var by_round: Dictionary = {}
	for p2: Dictionary in runner.participants:
		if str(p2["status"]) != "eliminated":
			continue
		by_round[int(p2["end_round"])] = int(by_round.get(int(p2["end_round"]), 0)) + 1
	var rounds: Array = by_round.keys()
	rounds.sort()
	for r: Variant in rounds:
		_say("    %2d라운드  %s %d" % [int(r),
			"#".repeat(mini(40, int(by_round[r]))), int(by_round[r])])

func _by_condition(runner: RefCounted) -> void:
	_head("전략 × 풀 — 구간 도달과 승점")
	_say("  %-10s %-9s %5s %6s %7s %7s" % ["전략", "풀", "인원", "평균R", "평균승점", "생존"])
	var groups: Dictionary = {}
	for p: Dictionary in runner.participants:
		var key: String = "%s|%s" % [p["strategy"], p["pool"]]
		if not groups.has(key):
			groups[key] = {"n": 0, "rounds": 0, "points": 0, "survived": 0}
		var g: Dictionary = groups[key]
		g["n"] = int(g["n"]) + 1
		g["rounds"] = int(g["rounds"]) + _reached(p, runner.config)
		g["points"] = int(g["points"]) + int(p["points"])
		if str(p["status"]) == "survived":
			g["survived"] = int(g["survived"]) + 1
	for strategy: String in Config.STRATEGIES:
		for pool_id: String in Config.pool_ids():
			var g2: Dictionary = groups.get("%s|%s" % [strategy, pool_id], {})
			if g2.is_empty():
				continue
			_say("  %-10s %-9s %5d %6.1f %7.1f %6d" % [strategy, pool_id, int(g2["n"]),
				float(g2["rounds"]) / float(g2["n"]), float(g2["points"]) / float(g2["n"]),
				int(g2["survived"])])
	_say("")
	_say("  ※ 승점 매칭이 강한 상대와 싸울 확률을 바꾼다. 이 승점을 빌드의 절대 강도로")
	_say("     읽지 않는다 (§8.1).")
	_say("  ※ **도달 라운드와 승점은 독립된 증거가 아니다.** 4손실로 탈락한 참가자는")
	_say("     도달 = 승점 + 4가 항등적으로 성립한다. 두 열은 같은 사실의 두 표현이다.")

func _early_failure(runner: RefCounted) -> void:
	_head("초반 실패 (§11.2)")
	var invalid: int = 0
	var early: int = 0
	for p: Dictionary in runner.participants:
		if str(p["status"]) == "invalid_start":
			invalid += 1
		elif str(p["status"]) == "eliminated" and int(p["end_round"]) <= 3:
			early += 1
	_say("  시작 조립 실패      %d명" % invalid)
	_say("  3라운드 내 탈락     %d명" % early)
	if invalid > 0:
		_say("  ※ 시작 보장을 넣고도 공격 불능이면 그 풀의 콘텐츠 조건 문제다 (§4.2).")

func _choices(runner: RefCounted) -> void:
	_head("보상 노출 / 선택 (§11.2)")
	var offered: Dictionary = {}
	var taken: Dictionary = {}
	var by_strategy: Dictionary = {}
	var by_result: Dictionary = {}
	var guaranteed: int = 0
	for c: Dictionary in runner.choices:
		for pid: Variant in c["final"]:
			offered[str(pid)] = int(offered.get(str(pid), 0)) + 1
		taken[str(c["taken"])] = int(taken.get(str(c["taken"]), 0)) + 1
		if str(c["guarantee"]) != "":
			guaranteed += 1
		# **조작을 구조에서 읽는다.** 행동 문자열을 파싱하면 복합 행동이 가려진다.
		var ops: Array = c.get("operations", [])
		if ops.is_empty():
			var idle: String = "%s|keep" % c["strategy"]
			by_strategy[idle] = int(by_strategy.get(idle, 0)) + 1
		for op: Variant in ops:
			var key: String = "%s|%s" % [c["strategy"], str((op as Dictionary)["kind"])]
			by_strategy[key] = int(by_strategy.get(key, 0)) + 1
		var rkey: String = "%s|%s" % [c["strategy"], str(c.get("reward_result", "stored"))]
		by_result[rkey] = int(by_result.get(rkey, 0)) + 1

	_say("  총 선택 %d회 · 시작 보장이 제안을 바꾼 횟수 %d" % [runner.choices.size(), guaranteed])
	_say("")
	_say("  전략별 **조작** 분포 — 복합 행동의 각 조작을 따로 센다:")
	_say("  %-10s %8s %8s %8s %8s %8s" % ["전략", "장착", "증강", "창고", "폐기", "유지"])
	for strategy: String in Config.STRATEGIES:
		var row: Array = []
		for kind: String in ["place", "augment", "store", "discard", "keep"]:
			row.append(int(by_strategy.get("%s|%s" % [strategy, kind], 0)))
		_say("  %-10s %8d %8d %8d %8d %8d" % [strategy, row[0], row[1], row[2], row[3], row[4]])
	_say("")
	_say("  ※ 이 표는 조작 수이지 선택 수가 아니다. 한 선택이 두 조작을 할 수 있다.")
	_say("     r5 리포트는 행동 문자열로 **대표 행동 하나만** 분류해서, \"창고로 → 장착\"")
	_say("     같은 복합 행동의 창고 이동이 통째로 가려졌다.")
	_say("")
	_say("  보상이 실제로 어떻게 쓰였는가 (획득한 파츠 기준):")
	_say("  %-10s %10s %10s %10s" % ["전략", "장착", "증강", "창고 보관"])
	for strategy2: String in Config.STRATEGIES:
		var r2: Array = []
		for result: String in ["installed", "augmented", "stored"]:
			r2.append(int(by_result.get("%s|%s" % [strategy2, result], 0)))
		_say("  %-10s %10d %10d %10d" % [strategy2, r2[0], r2[1], r2[2]])
	_say("  ※ '창고 보관'은 획득 후 배치하지 않은 것이다. 패스가 아니다 — 리그에는")
	_say("     보상 패스가 없다.")

	_say("")
	_say("  한 번도 제안되지 않은 파츠: %s" % str(_never(runner, offered, true)))
	_say("  제안됐지만 한 번도 선택되지 않은 파츠: %s" % str(_never(runner, taken, false)))
	_say("  ※ 선택률이 낮다고 약한 파츠라고 단정하지 않는다. AI가 연결을 못 읽었을 수도")
	_say("     있고, 그 구분은 위의 coverage 절과 함께 읽어야 한다 (§1.1).")

func _combat(runner: RefCounted) -> void:
	_head("전투 지속과 승리 방식 (§9.4)")
	var kinds: Dictionary = {}
	var total_time: float = 0.0
	var over_60: int = 0
	var applied: int = 0
	var ok_matches: int = 0
	for m: Dictionary in runner.matches:
		if not bool(m["ok"]):
			continue
		ok_matches += 1
		kinds[str(m["victory_kind"])] = int(kinds.get(str(m["victory_kind"]), 0)) + 1
		total_time += float(m["elapsed"])
		if float(m["elapsed"]) > runner.config.overtime_start_seconds:
			over_60 += 1
		if int(m["overtime"]) > 0:
			applied += 1
	if ok_matches == 0:
		_say("  정상 종료한 매치가 없다")
		return
	_say("  매치 %d회 · 평균 %.1f초" % [ok_matches, total_time / float(ok_matches)])
	_say("  60초 이내 종료 %d회 (%.1f%%) · 60초 초과 %d회 (%.1f%%) · 초과 피해가 실제로"
		% [ok_matches - over_60, 100.0 * float(ok_matches - over_60) / float(ok_matches),
			over_60, 100.0 * float(over_60) / float(ok_matches)])
	_say("     선체를 깎은 매치 %d회 (%.1f%%)"
		% [applied, 100.0 * float(applied) / float(ok_matches)])
	for kind: String in kinds:
		_say("    %-30s %5d  (%4.1f%%)" % [_victory_name(kind), int(kinds[kind]),
			100.0 * float(int(kinds[kind])) / float(ok_matches)])
	_say("")
	_say("  ※ \"초과 피해 적용 전 승리\"는 **60초 이내 승리와 다르다.** 기준 선체 100에서")
	_say("     61~63초의 틱은 0.1·0.2·0.3이라 아직 정수 선체를 깎지 못한다 — 64초에")
	_say("     누적 1이 된다. 그 사이에 끝난 매치는 60초를 넘겼지만 초과 피해량이 0이다.")
	_say("  ※ 초과 피해로 결정된 승리는 **리그 전용 규칙**의 결과다. 본편에 이 규칙을")
	_say("     넣지 않는다면 그대로 프리셋 강도로 쓸 수 없다 (§9.4).")
	_say("")
	_say("  성장 구간별 — 초과 피해 의존은 초반에 몰려 있다:")
	_say("  %-12s %7s %8s %14s %16s" % ["구간", "매치", "평균 시간", "60초 초과", "초과 피해로 결정"])
	for band: Array in [[1, 4, "1~4라운드"], [5, 9, "5~9라운드"], [10, 99, "10라운드+"]]:
		var n: int = 0
		var secs: float = 0.0
		var over: int = 0
		var killed: int = 0
		for m2: Dictionary in runner.matches:
			if not bool(m2["ok"]) or int(m2["round"]) < int(band[0]) \
					or int(m2["round"]) > int(band[1]):
				continue
			n += 1
			secs += float(m2["elapsed"])
			if float(m2["elapsed"]) > runner.config.overtime_start_seconds:
				over += 1
			if str(m2["victory_kind"]) == "overtime_kill":
				killed += 1
		if n == 0:
			continue
		_say("  %-12s %7d %7.1f초 %8d/%4.1f%% %10d/%4.1f%%"
			% [str(band[2]), n, secs / float(n), over, 100.0 * float(over) / float(n),
				killed, 100.0 * float(killed) / float(n)])
	_say("  ※ 늦은 구간은 생존자만 남아 있다. 이를 같은 빌드의 성장 효과로 읽지 않는다.")

func _diversity(runner: RefCounted) -> void:
	_head("빌드 다양성 — 최종 보드 서명 (§11.2)")
	var signatures: Dictionary = {}
	for p: Dictionary in runner.participants:
		var build: Dictionary = p.get("build", {})
		if build.is_empty():
			continue
		var ids: Array[String] = []
		for slot_id: String in (build["slots"] as Dictionary):
			var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
			ids.append("%s+%s" % [entry["part"], entry.get("augment", "")])
		ids.sort()
		var sig: String = "|".join(ids)
		signatures[sig] = int(signatures.get(sig, 0)) + 1
	_say("  고유 보드 %d종 / 참가자 %d명" % [signatures.size(), runner.participants.size()])
	_say("  ※ 구성 중복이 없다는 뜻이다. **엔진과 승리 방식이 그만큼 다양하다는 뜻은")
	_say("     아니다** — 계열 분류는 실제 발동한 연결로 해야 한다 (§12.2).")
	var repeated: int = 0
	for sig2: String in signatures:
		if int(signatures[sig2]) > 1:
			repeated += 1
	_say("  둘 이상이 같은 보드에 도달한 서명 %d종" % repeated)
	_say("  ※ 같은 서명이라도 증강 위치가 다르면 기능이 다르다. 계열 분류는 단계 D에서")
	_say("     실제 발동한 연결로 한다 (§12.2).")

func _matching(runner: RefCounted) -> void:
	_head("매칭 특성 (§11.2)")
	var duel: int = 0
	var fill: int = 0
	for m: Dictionary in runner.matches:
		if str(m["kind"]) == "archive_fill":
			fill += 1
		else:
			duel += 1
	_say("  일반 매치 %d · 복제 매치 %d (%.1f%%)"
		% [duel, fill, 100.0 * float(fill) / float(maxi(1, duel + fill))])
	_say("  ※ 복제 매치도 생존 진행에는 반영된다. 생존 통계는 이 비중과 함께 읽는다 (§8.2).")

func _errors(runner: RefCounted) -> void:
	_head("오류")
	if runner.errors.is_empty():
		_say("  없음")
		return
	for e: String in runner.errors:
		_say("  %s" % e)
	_say("  ※ 오류 매치는 승리·무승부·0초 패배로 대체하지 않고 집계에서 제외했다 (§8.3).")

# --- 보조 ---

func _reached(p: Dictionary, config: RefCounted) -> int:
	if str(p["status"]) == "survived":
		return config.round_cap
	return int(p["end_round"])

func _never(runner: RefCounted, seen: Dictionary, offered_side: bool) -> Array[String]:
	var out: Array[String] = []
	for part_id: String in runner.content.catalog.parts:
		var def: Dictionary = runner.content.catalog.parts[part_id]
		if str(def["base_role"]) == "core":
			continue
		if offered_side:
			if not seen.has(part_id):
				out.append(part_id)
		elif not seen.has(part_id):
			out.append(part_id)
	return out

static func _status_name(status: String) -> String:
	match status:
		"survived": return "상한 생존"
		"eliminated": return "탈락"
		"invalid_start": return "시작 실패"
		"batch_censored": return "관측 중단"
	return status

static func _victory_name(kind: String) -> String:
	match kind:
		"normal": return "초과 피해가 선체를 깎기 전 승리"
		"normal_after_overtime": return "초과 피해 이후 일반 승리"
		"overtime_kill": return "초과 피해로 결정"
		"mutual_death": return "동시 사망 무승부"
		"timeout_draw": return "시간 초과 무승부"
		"simulation_error": return "시뮬레이션 오류"
	return kind

func _head(title: String) -> void:
	_say("")
	_say("── %s %s" % [title, "─".repeat(maxi(2, 56 - title.length()))])

func _say(line: String) -> void:
	lines.append(line)

# --- 파일 출력 (§11.1) ---

func _write(runner: RefCounted, text: String) -> void:
	out_dir = "%s/%s-%s" % [OUT_ROOT, runner.config.batch_id,
		Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var files: Dictionary = {
		"report.txt": text,
		"participants.csv": _participants_csv(runner),
		"matches.csv": _matches_csv(runner),
		"choices.jsonl": _choices_jsonl(runner),
		"snapshots.jsonl": _snapshots_jsonl(runner),
	}
	# manifest에 파일별 행 수를 함께 적는다 — 잘린 파일을 조용히 분석하는 것을 막는다.
	var manifest: Dictionary = runner.config.manifest()
	var rows: Dictionary = {}
	for name: String in files:
		rows[name] = str(files[name]).count("\n")
	manifest["output_rows"] = rows
	manifest["out_dir"] = out_dir
	files["manifest.json"] = JSON.stringify(manifest, "  ")

	for name2: String in files:
		_store("%s/%s" % [out_dir, name2], str(files[name2]))
	# 마지막 실행을 가리키는 포인터. 덮어써도 되는 유일한 파일이다.
	# res:// 접두어를 떼고 적는다 — 셸에서 그대로 쓸 수 있어야 한다.
	_store("%s/latest.txt" % OUT_ROOT, out_dir.replace("res://", "") + "\n")

func _participants_csv(runner: RefCounted) -> String:
	var rows: Array[String] = ["id,strategy,pool,seed,status,end_round,points,losses,"
		+ "acquisitions,start_part,end_reason"]
	for p: Dictionary in runner.participants:
		rows.append("%d,%s,%s,%d,%s,%d,%d,%d,%d,%s,%s" % [
			int(p["id"]), p["strategy"], p["pool"], int(p["seed"]), p["status"],
			int(p["end_round"]), int(p["points"]), int(p["losses"]),
			int(p["acquisitions"]), p["start_part"], str(p["end_reason"]).replace(",", ";")])
	return "\n".join(rows) + "\n"

func _matches_csv(runner: RefCounted) -> String:
	var rows: Array[String] = ["round,kind,left,right,left_strategy,right_strategy,"
		+ "left_pool,right_pool,winner,victory_kind,elapsed,overtime,seed,ok"]
	for m: Dictionary in runner.matches:
		rows.append("%d,%s,%d,%d,%s,%s,%s,%s,%s,%s,%.2f,%d,%d,%s" % [
			int(m["round"]), m["kind"], int(m["left"]), int(m["right"]),
			m["left_strategy"], m["right_strategy"], m["left_pool"], m["right_pool"],
			m["winner"], m["victory_kind"], float(m["elapsed"]), int(m["overtime"]),
			int(m["seed"]), "1" if bool(m["ok"]) else "0"])
	return "\n".join(rows) + "\n"

## 전투 직전 보드 전체. **이 파일만으로 재전투가 가능해야 한다** (§8.1).
func _snapshots_jsonl(runner: RefCounted) -> String:
	var rows: Array[String] = []
	for snap: Dictionary in runner.snapshots:
		rows.append(JSON.stringify(snap))
	return "\n".join(rows) + "\n"

func _choices_jsonl(runner: RefCounted) -> String:
	var rows: Array[String] = []
	for c: Dictionary in runner.choices:
		rows.append(JSON.stringify(c))
	return "\n".join(rows) + "\n"

func _store(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
