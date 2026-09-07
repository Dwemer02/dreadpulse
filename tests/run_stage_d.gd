extends SceneTree
## 단계 D — 고정 비교 기준과 사용 가능한 레시피 확정 (r5b 피드백 §12의 D행).
##
## 실행:
##   godot --headless --path . --script res://tests/run_stage_d.gd
##
## 셋을 낸다.
##   D1  고정 상대군 점검 — 상대군 자신들끼리 붙여 기준선이 한쪽으로 기울지 않았는지
##   D2  레시피 후보 검증 — 각 레시피 완성 보드를 상대군에 붙여 강도 확인 (§7.3)
##   D3  Core·초과 피해 진단 — 재질 축과 리그 전용 규칙이 결과를 얼마나 움직이는가 (§11)
##
## **이 스크립트는 밸런스를 바꾸지 않는다.** 기준을 고정하기 위한 측정만 한다.

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Benchmark = preload("res://league/benchmark.gd")
const Recipes = preload("res://league/recipes.gd")
const Profile = preload("res://league/build_profile.gd")
const Graph = preload("res://league/build_graph.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Inventory = preload("res://run/inventory.gd")

const OUT_ROOT := "res://tests/out/league"

var _lines: Array[String] = []
var _content: RefCounted
var _config: RefCounted

func _init() -> void:
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
		push_error("고정 상대군이 비어 있다 — tests/build_opponent_archive.gd를 먼저 돌린다")
		quit(1)
		return

	var started: int = Time.get_ticks_msec()
	_head("단계 D — 고정 비교 기준과 레시피 확정")
	_say("커밋 %s%s · Godot %s" % [_config.git_commit().substr(0, 10),
		" (작업 트리 변경 있음)" if _config.git_dirty() else "",
		Engine.get_version_info()["string"]])
	var manifest: Dictionary = Archive.manifest()
	_say("고정 상대군 %s · %d명 · 출처 %s"
		% [manifest["version"], int(manifest["opponents"]), manifest["built_from"]])
	_say("전투 시드 %s · 좌우 교환 — 상대 1명당 %d판"
		% [str(Benchmark.SEEDS), Benchmark.SEEDS.size() * 2])

	var results: Dictionary = {}
	results["d1"] = _d1_archive_check(opponents)
	results["d2"] = _d2_recipes(opponents)
	results["d2b"] = _d2b_attainability()
	results["d3"] = _d3_core_and_overtime(opponents)

	var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
	_say("")
	_say("실행 시간 %.1f초" % elapsed)

	var text: String = "\n".join(_lines)
	print(text)
	_write(text, results, manifest)
	quit(0)

# --- D1. 상대군 자체 점검 ---

## 상대군이 **비교 기준**으로 쓸 만한가. 서로 붙여 본다.
##
## 한 명이 전원을 이기거나 전원에게 지면 그 상대는 기준선을 왜곡한다 — 모든 검사
## 대상이 그 한 명에게서 같은 결과를 받으므로 변별력이 없다. 그런 상대가 있는지
## **기준을 고정하기 전에** 확인해야 한다.
func _d1_archive_check(opponents: Array) -> Dictionary:
	_head("D1. 고정 상대군 점검 — 기준선이 한쪽으로 기울지 않았는가")
	var rules: Dictionary = _config.combat_rules()
	var rows: Array = []
	for i: int in opponents.size():
		var me: Dictionary = opponents[i]
		var others: Array = []
		for j: int in opponents.size():
			if j != i:
				others.append(opponents[j])
		var r: Dictionary = Benchmark.run(_content.catalog, _config,
			me["build"], others, rules, str(me["id"]))
		rows.append({"opponent": me, "result": r})

	_say("  %-18s %-42s %5s %5s %5s %7s %8s"
		% ["상대", "구조", "승", "패", "무", "승률", "선체격차"])
	for row: Dictionary in rows:
		var r2: Dictionary = row["result"]
		_say("  %-18s %-42s %5d %5d %5d %6.1f%% %+8.1f"
			% [str((row["opponent"] as Dictionary)["id"]),
				str((row["opponent"] as Dictionary)["bucket"]),
				int(r2["wins"]), int(r2["losses"]), int(r2["draws"]),
				100.0 * float(r2["win_rate"]), float(r2["avg_margin"])])

	var extremes: Array[String] = []
	for row2: Dictionary in rows:
		var rate: float = float((row2["result"] as Dictionary)["win_rate"])
		if rate >= 0.95 or rate <= 0.05:
			extremes.append("%s (%.0f%%)"
				% [str((row2["opponent"] as Dictionary)["id"]), 100.0 * rate])
	_say("")
	if extremes.is_empty():
		_say("  전원을 이기거나 전원에게 지는 상대는 없다 — 변별력이 있는 기준선이다.")
	else:
		_say("  ※ 승률 5%% 이하 / 95%% 이상: %s" % ", ".join(extremes))
		_say("     그 상대는 모든 검사 대상에게 같은 결과를 주므로 변별력이 없다.")
		_say("     **빼지는 않았다** — 상대군은 이미 고정됐고, 실험 결과를 본 뒤")
		_say("     기준을 바꾸면 그게 사후 조정이다. 읽을 때 감안한다.")
	_say("  ※ 이 표는 상대군 **내부** 결과다. 검사 대상의 강도가 아니다.")
	return {"rows": _slim(rows)}

# --- D2. 레시피 후보 검증 ---

## §7.3이 요구한 "고정 상대군에서 강도를 확인한 뒤 확정한다".
##
## 각 레시피의 **핵심 엔진만 채운 보드**와 **발견 당시의 완성 보드** 둘 다 붙인다.
## 핵심 엔진만으로 같은 강도가 나오면 "2~4개 핵심 구성만으로 같은 엔진이 작동한다"는
## §7.3의 전제가 확인되는 것이고, 크게 떨어지면 그 레시피의 핵심 정의가 틀린 것이다.
func _d2_recipes(opponents: Array) -> Dictionary:
	_head("D2. 레시피 후보 검증 — 고정 상대군 성과 (§7.3)")
	var rules: Dictionary = _config.combat_rules()
	var out: Array = []
	_say("  %-24s %-10s %5s %5s %5s %7s %9s %7s"
		% ["레시피", "보드", "승", "패", "무", "승률", "선체격차", "평균초"])
	for recipe_id: String in Recipes.RECIPES:
		for kind: String in ["core", "full"]:
			var build: Dictionary = _recipe_build(recipe_id, kind)
			if build.is_empty():
				_say("  %-24s %-10s  — 보드를 구성할 수 없다" % [recipe_id, kind])
				continue
			var r: Dictionary = Benchmark.run(_content.catalog, _config, build,
				opponents, rules, "%s/%s" % [recipe_id, kind])
			out.append({"recipe": recipe_id, "kind": kind, "result": r,
				"profile": _profile_of(build)})
			_say("  %-24s %-10s %5d %5d %5d %6.1f%% %+9.1f %7.1f"
				% [recipe_id, "핵심 엔진" if kind == "core" else "완성 보드",
					int(r["wins"]), int(r["losses"]), int(r["draws"]),
					100.0 * float(r["win_rate"]), float(r["avg_margin"]),
					float(r["avg_elapsed"])])
	_say("")
	_say("  ※ '핵심 엔진'은 core_engine 항목만 채운 보드, '완성 보드'는 r5b 상한")
	_say("     생존자의 최종 구성 전체다. 둘의 차이가 작으면 §7.3의 전제 —")
	_say("     \"2~4개 핵심 구성만으로 같은 엔진이 작동한다\" — 가 확인된 것이고,")
	_say("     크면 그 레시피의 핵심 정의가 좁게 잡힌 것이다.")
	_say("  ※ 승률의 분모는 결판난 전투다. 미해결은 따로 센다.")
	_say("  ※ **선체격차**는 (내 잔여 선체 − 상대 잔여 선체)의 평균이다.")
	_say("     승률이 100%로 포화해도 남는 해상도다 — 전원을 이기는 빌드끼리도")
	_say("     여유가 얼마나 다른지는 이 열만 말한다.")
	return {"rows": _slim_named(out)}

## 레시피의 보드를 만든다. kind: "core"(핵심 엔진만) | "full"(발견 당시 완성 보드).
## 슬롯이 모자라면 빈 Dictionary.
func _recipe_build(recipe_id: String, kind: String) -> Dictionary:
	var recipe: Dictionary = Recipes.of(recipe_id)
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_config, inv)
	var slots: Array = _content.slots_of(_config)

	var placements: Array = []
	if kind == "core":
		for entry: Variant in recipe["core_engine"]:
			var spec: Dictionary = entry
			for _i: int in int(spec["count"]):
				placements.append({"part": str(spec["part"]),
					"role": str(spec["role"]), "host": str(spec.get("host", ""))})
	else:
		# 관측된 완성 보드가 없는 레시피가 있다. 지어내지 않고 건너뛴다.
		var full: Dictionary = recipe.get("full_build", {})
		if not full.has("board"):
			return {}
		for pair: Variant in (full["board"] as Array):
			placements.append({"part": str((pair as Array)[0]), "role": "body",
				"augment": str((pair as Array)[1])})

	# 본체 먼저 놓고 증강을 얹는다. 증강은 숙주가 이미 있어야 붙는다.
	for p: Dictionary in placements:
		if str(p["role"]) != "body":
			continue
		var slot_id: String = _free_slot(inv, slots, str(p["part"]))
		if slot_id == "":
			return {}
		var uid: int = inv.add(str(p["part"]))
		var aug: int = Inventory.NONE
		if str(p.get("augment", "")) != "":
			aug = inv.add(str(p["augment"]))
		inv.place(slot_id, uid, aug)
	for p2: Dictionary in placements:
		if str(p2["role"]) != "augment":
			continue
		var host_slot: String = _slot_of_part(inv, str(p2.get("host", "")))
		if host_slot == "":
			return {}
		inv.place(host_slot, int(inv.board[host_slot]["active"]),
			inv.add(str(p2["part"])))
	return inv.to_build("recipe_%s_%s" % [recipe_id, kind], _config.frame_id)

func _free_slot(inv: RefCounted, slots: Array, part_id: String) -> String:
	var role: String = str(_content.catalog.parts[part_id]["base_role"])
	for slot_def: Dictionary in slots:
		var slot_id: String = str(slot_def["id"])
		if inv.board.has(slot_id):
			continue
		var slot_role: String = str(slot_def["role"])
		if slot_role == "core":
			continue
		if slot_role == "flexible" or slot_role == role:
			return slot_id
	return ""

func _slot_of_part(inv: RefCounted, part_id: String) -> String:
	for slot_id: String in inv.board:
		if inv.part_id_of(int(inv.board[slot_id]["active"])) == part_id:
			return slot_id
	return ""

# --- D2b. 풀별 도달성 ---

## 레시피가 **강한가**와 그 풀에서 **모을 수 있는가**는 다른 질문이다.
##
## `Recipes.reachable_in()`은 "그 팩션이 이 풀에 있는가"만 본다. 개수까지
## 감당할 수 있는지는 보지 않는다 — r5c에서 v70_r30(Reclaimer 30%)의 평균
## 진행도가 0.07이었고, 고철 기관포 3개는 사실상 도달 불가에 가까웠다.
##
## 여기서 재는 것은 **기대 노출**이다: 런 하나에서 그 파츠가 제안에 몇 번
## 나타나는가. 획득 상한(선택 17회 × 제안 3개 = 51회 추첨)에 팩션 가중치와
## 그 팩션의 파츠 종수를 곱한다. 실제 획득은 AI가 고를 때만 일어나므로 이
## 값은 **상한**이다 — 이보다 적게 모이지 더 많이 모이지 않는다.
func _d2b_attainability() -> Dictionary:
	_head("D2b. 풀별 도달성 — 강한 것과 모을 수 있는 것은 다르다")
	var draws: int = 17 * 3
	_say("  런 하나의 제안 추첨 %d회 (선택 17 × 제안 3) 기준 기대 노출." % draws)
	_say("  %-9s %-24s %-28s %8s %8s"
		% ["풀", "레시피", "가장 구하기 어려운 파츠", "필요", "기대노출"])
	var rows: Array = []
	for pool_id: String in Config.pool_ids():
		var recipe_id: String = Recipes.recipe_id_for(pool_id)
		if recipe_id == "":
			_say("  %-9s %-24s  — 배정된 레시피 없음 (주 비교 제외)" % [pool_id, "—"])
			rows.append({"pool": pool_id, "recipe": "", "excluded": true})
			continue
		var worst_part: String = ""
		var worst_need: int = 0
		var worst_expected: float = 1e9
		for entry: Variant in (Recipes.of(recipe_id)["core_engine"] as Array):
			var spec: Dictionary = entry
			var expected: float = _expected_draws(pool_id, str(spec["part"]), draws)
			if expected < worst_expected:
				worst_expected = expected
				worst_part = str(spec["part"])
				worst_need = int(spec["count"])
		rows.append({"pool": pool_id, "recipe": recipe_id, "part": worst_part,
			"need": worst_need, "expected": snappedf(worst_expected, 0.01),
			"excluded": false})
		_say("  %-9s %-24s %-28s %8d %8.1f"
			% [pool_id, recipe_id, worst_part, worst_need, worst_expected])
	_say("")
	_say("  ※ 기대노출 < 필요 이면 그 풀에서는 레시피를 모으기 어렵다.")
	_say("     r5c에서 v70_r30의 평균 진행도가 0.07이었던 것이 이 값으로 설명된다.")
	_say("  ※ 이 값은 **상한**이다. 제안에 나타나는 것과 AI가 고르는 것은 다르고,")
	_say("     같은 제안 안에서 다른 파츠와 경쟁한다.")
	_say("  ※ 도달성이 낮다고 그 풀을 빼지는 않았다. **빼는 것도 기준 변경**이고,")
	_say("     낮은 도달성 자체가 §9.3이 보려는 \"반복을 고집하는 비용\"이다.")
	_say("     다만 그 풀의 낮은 성과를 \"고정 전략이 약하다\"로 읽으면 안 된다.")
	return {"rows": rows, "draws": draws}

## 이 풀에서 그 파츠가 제안에 나타날 기대 횟수.
## 추첨은 팩션 가중치로 팩션을 고른 뒤 그 팩션 안에서 균등하다.
func _expected_draws(pool_id: String, part_id: String, draws: int) -> float:
	var weights: Dictionary = Config.POOLS[pool_id]
	var faction: String = str(_content.catalog.parts[part_id]["faction"])
	var weight: int = int(weights.get(faction, 0))
	if weight <= 0:
		return 0.0
	var total_weight: int = 0
	for f: String in weights:
		total_weight += int(weights[f])
	var siblings: int = 0
	for pid: String in _content.catalog.parts:
		var def: Dictionary = _content.catalog.parts[pid]
		if str(def["base_role"]) != "core" and str(def["faction"]) == faction:
			siblings += 1
	if siblings == 0:
		return 0.0
	return float(draws) * (float(weight) / float(total_weight)) / float(siblings)

# --- D3. Core·초과 피해 진단 ---

## §11의 두 진단. **동시에 바꾸지 않는다** — 각각 하나씩만 바꾼 대조군이다.
func _d3_core_and_overtime(opponents: Array) -> Dictionary:
	_head("D3. Core 재질과 초과 피해 진단 (§11)")

	# --- 11.1 Core: 같은 보드, 재질만 다르게 ---
	#
	# **검사 대상을 고르는 것이 이 진단의 절반이다.** 처음엔 레시피 완성 보드 셋에
	# 붙였는데 셋 다 상대군을 100%로 이겨서 재질을 바꿔도 승률이 움직이지 않았다 —
	# 포화한 표에서는 어떤 축도 0으로 보인다. 그래서 **실제로 접전하는 보드**를
	# 대상으로 쓴다: 상대군의 중반 구성 6개(D1에서 승률 11~54%)와 레시피 핵심 엔진 셋.
	_say("  11.1 Core 재질 — **같은 보드에서 재질만 바꾼다**")
	_say("  대상은 접전하는 보드다. 포화한 보드에서는 어떤 축도 0으로 보인다.")
	_say("  %-22s %-14s %5s %5s %5s %7s %9s"
		% ["대상 보드", "조건", "승", "패", "무", "승률", "선체격차"])
	var subjects: Array = []
	for o: Variant in Archive.of_stage("mid"):
		subjects.append({"name": str((o as Dictionary)["id"]),
			"build": (o as Dictionary)["build"]})
	for recipe_id: String in Recipes.RECIPES:
		var core_build: Dictionary = _recipe_build(recipe_id, "core")
		if not core_build.is_empty():
			subjects.append({"name": "%s(핵심)" % recipe_id, "build": core_build})

	var core_rows: Array = []
	var deltas: Array = []
	for subject: Dictionary in subjects:
		var baseline: float = 0.0
		for variant: Array in [
				["현재(plating)", _config.core_id, false],
				["중립(배율 1.0)", _config.core_id, true],
				["biomass", "symbiotic_core", false],
		]:
			var swapped: Dictionary = _with_core(subject["build"], str(variant[1]))
			var rules: Dictionary = _config.combat_rules()
			rules["neutral_damage_types"] = bool(variant[2])
			var others: Array = []
			for o2: Variant in opponents:
				# 자기 자신은 상대에서 뺀다. 거울전은 재질 비교를 흐린다 —
				# 같은 재질을 양쪽이 입으면 그 축이 상쇄된다.
				if str((o2 as Dictionary)["build"].get("id", "")) \
						!= str((subject["build"] as Dictionary).get("id", "")):
					others.append(o2)
			var r: Dictionary = Benchmark.run(_content.catalog, _config, swapped,
				others, rules, "%s/%s" % [subject["name"], str(variant[0])])
			core_rows.append({"subject": str(subject["name"]),
				"variant": str(variant[0]), "result": r})
			if str(variant[0]) == "현재(plating)":
				baseline = float(r["avg_margin"])
			elif str(variant[0]) == "중립(배율 1.0)":
				deltas.append(float(r["avg_margin"]) - baseline)
			_say("  %-22s %-14s %5d %5d %5d %6.1f%% %+9.1f"
				% [str(subject["name"]) if str(variant[0]) == "현재(plating)" else "",
					str(variant[0]), int(r["wins"]), int(r["losses"]),
					int(r["draws"]), 100.0 * float(r["win_rate"]),
					float(r["avg_margin"])])
	_say("")
	var worst: float = 0.0
	var total: float = 0.0
	for d: float in deltas:
		total += absf(d)
		worst = maxf(worst, absf(d))
	_say("  중립으로 바꿨을 때 선체격차 변화: 평균 %.1f · 최대 %.1f (선체 100 기준)"
		% [total / float(maxi(1, deltas.size())), worst])
	_say("  ※ 이 값이 재질 축의 **크기**다. 부호는 보드마다 다르다 — 어떤 보드는")
	_say("     중립에서 좋아지고 어떤 보드는 나빠진다. 방향이 일정하지 않다는 것")
	_say("     자체가 \"재질이 풀 순위를 정한다\"에 대한 반증이다 (§4.3).")
	_say("  ※ 상대측 Core는 그대로 두었다. 양쪽을 함께 바꾸면 재질 효과가 상쇄되어")
	_say("     0으로 보인다 — 재려는 것은 '이 빌드가 그 재질을 입었을 때'다.")
	_say("  ※ 중립 조건은 **진단 전용 규칙**이다 (combat_sim.rules의 neutral_damage_types).")
	_say("     게임 규칙이 아니고 배치에서는 항상 꺼져 있다.")
	_say("  ※ biomass Core(symbiotic_core)는 재질뿐 아니라 자체 효과(영구 재생 1)를")
	_say("     함께 갖는다. **재질만의 효과가 아니다** — §11.1의 \"Core 추가 효과는")
	_say("     고정한다\"를 지금 콘텐츠로는 만족시킬 수 없다. 중립 조건과 현재 조건의")
	_say("     차이가 재질 축의 상한이고, biomass 행은 참고값이다.")
	_say("  ※ 풀 순위만 보고 팩션 파츠를 버프·너프하지 않는다 (§11.1).")

	# --- 11.2 초과 피해 ON/OFF ---
	_say("")
	_say("  11.2 초과 피해 — **초반 대표 스냅샷에서 ON / OFF**")
	_say("  %-18s %-8s %6s %6s %6s %8s %8s %8s"
		% ["상대", "조건", "승", "패", "무", "미해결", "평균초", "초과결정"])
	var ot_rows: Array = []
	var early: Array = Archive.of_stage("early")
	for me: Dictionary in early:
		for variant2: Array in [["ON", _config.combat_rules()],
				["OFF", Benchmark.no_overtime_rules()]]:
			var others: Array = []
			for o: Variant in early:
				if str((o as Dictionary)["id"]) != str(me["id"]):
					others.append(o)
			var r2: Dictionary = Benchmark.run(_content.catalog, _config,
				me["build"], others, variant2[1] as Dictionary,
				"%s/%s" % [me["id"], str(variant2[0])])
			ot_rows.append({"opponent": str(me["id"]), "variant": str(variant2[0]),
				"result": r2})
			_say("  %-18s %-8s %6d %6d %6d %8d %8.1f %8d"
				% [str(me["id"]) if str(variant2[0]) == "ON" else "",
					str(variant2[0]), int(r2["wins"]), int(r2["losses"]),
					int(r2["draws"]), int(r2["unresolved"]),
					float(r2["avg_elapsed"]), int(r2["overtime_decided"])])
	_say("")
	_say("  ※ OFF에서 120초 상한에 닿은 전투는 **미해결**이다. 승·패·무 어디에도")
	_say("     넣지 않았다 (§11.2). 넣으면 초과 피해를 끈 조건의 승률이 규칙 때문에")
	_say("     낮아 보인다.")
	_say("  ※ 미해결 비율이 크면 그 구간의 전투가 초과 피해 **없이는 끝나지 않는다**는")
	_say("     뜻이다. 그것은 3파츠 시작의 결함일 수도, 초반 화력 부족일 수도 있다 —")
	_say("     이 표는 어느 쪽인지 말하지 않는다 (§11.2 마지막).")
	return {"core": _slim_named(core_rows), "overtime": _slim_named(ot_rows)}

## Core만 바꾼 빌드 사본.
func _with_core(build: Dictionary, core_id: String) -> Dictionary:
	var copy: Dictionary = build.duplicate(true)
	for slot_id: String in (copy["slots"] as Dictionary):
		var entry: Dictionary = (copy["slots"] as Dictionary)[slot_id]
		if str(_content.catalog.parts[str(entry["part"])]["base_role"]) == "core":
			entry["part"] = core_id
	copy["id"] = "%s_%s" % [str(copy["id"]), core_id]
	return copy

func _profile_of(build: Dictionary) -> Dictionary:
	var inv: RefCounted = Inventory.new()
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		var uid: int = inv.add(str(entry.get("part", "")))
		var aug: int = Inventory.NONE
		if str(entry.get("augment", "")) != "":
			aug = inv.add(str(entry["augment"]))
		inv.place(slot_id, uid, aug)
	return Profile.of(Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index),
		_content.body_slot_count(_config), {}))

# --- 출력 ---

func _slim(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		out.append({"id": str((row["opponent"] as Dictionary)["id"]),
			"bucket": str((row["opponent"] as Dictionary)["bucket"]),
			"result": _no_details(row["result"])})
	return out

func _slim_named(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		var copy: Dictionary = row.duplicate()
		copy["result"] = _no_details(row["result"])
		out.append(copy)
	return out

## per_opponent는 파일에만 남기고 요약에서는 뺀다 — 리포트가 읽을 수 없게 커진다.
static func _no_details(result: Dictionary) -> Dictionary:
	var copy: Dictionary = result.duplicate()
	copy.erase("per_opponent")
	return copy

func _head(title: String) -> void:
	_lines.append("")
	_lines.append("── %s %s" % [title, "─".repeat(maxi(4, 66 - title.length()))])

func _say(line: String) -> void:
	_lines.append(line)

func _write(text: String, results: Dictionary, manifest: Dictionary) -> void:
	var run_id: String = "stageD-%s" % Time.get_datetime_string_from_system(true) \
		.replace(":", "").replace("-", "")
	var dir: String = "%s/%s" % [OUT_ROOT, run_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_store("%s/report.txt" % dir, text)
	_store("%s/results.json" % dir, JSON.stringify({
		"run_id": run_id,
		"git_commit": _config.started_commit, "git_dirty": _config.started_dirty,
		"godot_version": Engine.get_version_info()["string"],
		"evaluator_version": Config.EVALUATOR_VERSION,
		"archive": manifest,
		"benchmark_seeds": Benchmark.SEEDS,
		"league_rules": _config.combat_rules(),
		"recipes": Recipes.manifest(),
		"results": results,
	}, "  "))
	print("")
	print("출력: %s" % dir)

func _store(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
