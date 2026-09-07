extends SceneTree
## 고정 상대군을 r5b 스냅샷에서 뽑아 **얼려 파일로 남긴다** (r5b 피드백 §8.4).
##
## 실행:
##   godot --headless --path . --script res://tests/build_opponent_archive.gd \
##     -- --from=tests/out/league/r5-20260907T111238/snapshots.jsonl
##
## 왜 파일로 얼리는가: `tests/out/`은 gitignore 대상이라 원본 스냅샷이 리포지토리에
## 남지 않는다. 상대군이 실행할 때마다 다시 뽑히면 "실험 전에 고정"(§8.4)이 아니고,
## 배치 간 비교의 기준선이 조용히 움직인다.
##
## **이 스크립트는 상대군을 만들 때 한 번만 돌린다.** 결과 파일
## `league/data/opponent_archive.json`이 기준이고, 그 파일을 바꾸는 것은
## 기준을 바꾸는 것이므로 사유를 커밋에 남겨야 한다.

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const Graph = preload("res://league/build_graph.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Profile = preload("res://league/build_profile.gd")
const Inventory = preload("res://run/inventory.gd")

const OUT_PATH := "res://league/data/opponent_archive.json"

## 버킷(구조) 하나당 최대 몇 명. §8.4의 "상대 수를 많이 늘리기보다 서로 다른
## 구조를 포함"이라 작게 잡는다.
const PER_BUCKET: int = 1
## 획득 단계 구간당 최대 인원. 세 구간이므로 상한은 3 × 이 값이다.
const PER_STAGE: int = 6

func _init() -> void:
	var source: String = _arg("from", "")
	if source == "":
		push_error("--from=<snapshots.jsonl 경로>가 필요하다")
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

	var rows: Array = _read_jsonl(source)
	if rows.is_empty():
		push_error("스냅샷을 읽지 못했다: %s" % source)
		quit(1)
		return
	print("스냅샷 %d개를 읽었다: %s" % [rows.size(), source])

	# 참가자 id → 그 참가자의 마지막 라운드. "상한 생존 빌드만으로 구성하지 않음"을
	# 확인하려면 각 후보가 그 참가자의 끝이었는지 아닌지를 알아야 한다.
	var last_round: Dictionary = {}
	for row: Dictionary in rows:
		var pid: int = int(row["participant"])
		last_round[pid] = maxi(int(last_round.get(pid, 0)), int(row["round"]))

	# 후보를 먼저 전부 모은다. 파일 순서대로 그냥 채우면 참가자 id 오름차순이라
	# **한 전략·앞쪽 풀에만 몰린다** — 실제로 첫 판본이 18명 전부 즉시 전력형에
	# r100/v100/a100뿐이었다. 그건 "서로 다른 구조"가 아니라 "먼저 나온 구조"다.
	var candidates: Array = []
	var bucket_census: Dictionary = {}   # 전체 분포 (선정과 무관하게 기록)
	var seen_board: Dictionary = {}
	for row2: Dictionary in rows:
		var analysis: Dictionary = _analyze(content, config, row2["build"])
		var profile: Dictionary = Profile.of(analysis)
		var bucket: String = Profile.bucket_of(profile)
		bucket_census[bucket] = int(bucket_census.get(bucket, 0)) + 1

		# 공격 수단이 없는 빌드는 상대군에 넣지 않는다. 그런 상대는 모든 빌드가
		# 시간 초과로만 이기므로 강도를 재지 못한다.
		if not bool(profile["operational"]):
			continue
		var signature: String = _signature(row2["build"])
		if seen_board.has(signature):
			continue
		seen_board[signature] = true
		candidates.append({
			"row": row2, "profile": profile, "bucket": bucket,
			"stage": Profile.stage_of(int(row2["round"])), "signature": signature,
		})

	# 탐욕 선택: 매번 **새로운 면을 가장 많이 더하는** 후보를 고른다.
	# 면은 셋이다 — 구조 버킷, 출처 전략, 출처 풀. 동점이면 참가자 id가 작은 쪽.
	# 무작위가 아니므로 같은 입력에서 같은 상대군이 나온다.
	var by_stage: Dictionary = {"early": [], "mid": [], "late": []}
	var used_bucket: Dictionary = {}
	var used_strategy: Dictionary = {}
	var used_pool: Dictionary = {}
	var taken: Dictionary = {}
	for _slot: int in PER_STAGE * 3:
		var best: Dictionary = {}
		var best_score: int = -1
		var best_id: int = 0
		for i: int in candidates.size():
			if taken.has(i):
				continue
			var c: Dictionary = candidates[i]
			var stage: String = str(c["stage"])
			if (by_stage[stage] as Array).size() >= PER_STAGE:
				continue
			var key: String = "%s|%s" % [stage, c["bucket"]]
			if int(used_bucket.get(key, 0)) >= PER_BUCKET:
				continue
			var row3: Dictionary = c["row"]
			var score: int = 0
			if not used_bucket.has(key):
				score += 4
			if not used_strategy.has(str(row3["strategy"])):
				score += 2
			if not used_pool.has(str(row3["pool"])):
				score += 1
			var pid: int = int(row3["participant"])
			if score > best_score or (score == best_score and pid < best_id):
				best_score = score
				best = c
				best_id = pid
		if best.is_empty():
			break
		taken[candidates.find(best)] = true
		var chosen: Dictionary = best["row"]
		var stage2: String = str(best["stage"])
		used_bucket["%s|%s" % [stage2, best["bucket"]]] = \
			int(used_bucket.get("%s|%s" % [stage2, best["bucket"]], 0)) + 1
		used_strategy[str(chosen["strategy"])] = true
		used_pool[str(chosen["pool"])] = true
		(by_stage[stage2] as Array).append({
			"id": "%s_%s" % [stage2, str(chosen["snapshot_id"])],
			"source": {
				"run_id": source.get_file().get_basename(),
				"snapshot_id": str(chosen["snapshot_id"]),
				"participant": int(chosen["participant"]),
				"strategy": str(chosen["strategy"]), "pool": str(chosen["pool"]),
				"seed": int(chosen["seed"]), "round": int(chosen["round"]),
				# 이 참가자가 여기서 끝났는가. 상한 생존자만 모으지 않았다는 것을
				# 파일에서 확인할 수 있어야 한다.
				"was_final_round":
					int(chosen["round"]) == int(last_round[int(chosen["participant"])]),
				"points_at_snapshot": int(chosen["points"]),
				"losses_at_snapshot": int(chosen["losses"]),
			},
			"stage": stage2, "bucket": str(best["bucket"]), "profile": best["profile"],
			"signature": str(best["signature"]),
			"build": chosen["build"],
		})

	var opponents: Array = []
	for stage2: String in ["early", "mid", "late"]:
		opponents.append_array(by_stage[stage2] as Array)

	var archive: Dictionary = {
		"_comment": "고정 상대군. r5b 피드백 §8.4 — 실험 전에 고정하고 배치마다 "
			+ "다시 뽑지 않는다. 바꾸는 것은 비교 기준을 바꾸는 것이다.",
		"version": "archive-1",
		"built_from": source,
		"built_commit": config.git_commit(),
		"selection_rule": {
			"stages": {"early": "round<=2", "mid": "round 3~6", "late": "round>=7"},
			"per_bucket": PER_BUCKET, "per_stage": PER_STAGE,
			"bucket": "공격 경로 + 방어 기능 + 시동 구조 (league/build_profile.gd)",
			"order": "새로운 면(구조 버킷 4점 · 전략 2점 · 풀 1점)을 가장 많이 "
				+ "더하는 후보를 매번 고른다. 동점이면 참가자 id가 작은 쪽.",
			"excluded": "공격 불능 빌드, 보드 서명 중복",
			"note": "출력 크기를 기준에 넣지 않는다 — 강한 것을 고르는 것이 아니라 "
				+ "작동 방식이 다른 것을 고르는 것이다 (§8.4).",
		},
		"census": bucket_census,
		"opponents": opponents,
	}

	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("쓸 수 없다: %s" % OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(archive, "  "))
	file.close()

	print("")
	print("고정 상대군 %d명을 %s에 썼다" % [opponents.size(), OUT_PATH])
	print("  %-8s %-46s %-6s %s" % ["구간", "구조 (공격|방어|시동)", "라운드", "출처"])
	for o: Dictionary in opponents:
		print("  %-8s %-46s %6d %s (%s·%s·시드%d)%s"
			% [o["stage"], o["bucket"], int((o["source"] as Dictionary)["round"]),
				str((o["source"] as Dictionary)["snapshot_id"]),
				str((o["source"] as Dictionary)["strategy"]),
				str((o["source"] as Dictionary)["pool"]),
				int((o["source"] as Dictionary)["seed"]),
				"  ※최종 라운드" if bool((o["source"] as Dictionary)["was_final_round"]) else ""])
	var finals: int = 0
	for o2: Dictionary in opponents:
		if bool((o2["source"] as Dictionary)["was_final_round"]):
			finals += 1
	print("")
	print("  최종 라운드 스냅샷 %d / %d — 상한 생존 빌드만으로 구성하지 않았다 (§8.4)"
		% [finals, opponents.size()])
	print("  전체 스냅샷의 구조 버킷 %d종 중 %d종을 담았다"
		% [bucket_census.size(), _bucket_count(opponents)])
	quit(0)

func _bucket_count(opponents: Array) -> int:
	var seen: Dictionary = {}
	for o: Dictionary in opponents:
		seen[str(o["bucket"])] = true
	return seen.size()

## 슬롯 이름을 뺀 보드 서명. candidate_generator.signature()와 같은 규약이다 —
## 여기서 인벤토리를 만들지 않고 build에서 바로 읽는다.
static func _signature(build: Dictionary) -> String:
	var rows: Array[String] = []
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		rows.append("%s+%s" % [str(entry.get("part", "")), str(entry.get("augment", ""))])
	rows.sort()
	return "|".join(rows)

func _analyze(content: RefCounted, config: RefCounted, build: Dictionary) -> Dictionary:
	var inv: RefCounted = Inventory.new()
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		var active: int = inv.add(str(entry.get("part", "")))
		var augment: int = Inventory.NONE
		if str(entry.get("augment", "")) != "":
			augment = inv.add(str(entry["augment"]))
		inv.place(slot_id, active, augment)
	return Graph.analyze(
		Generator.placed_units(inv, content.catalog, content.meta_index),
		content.body_slot_count(config), {})

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

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.split("=", true, 1)[1]
	return fallback
