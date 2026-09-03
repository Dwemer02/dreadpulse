extends RefCounted
## 실제 콘텐츠(파츠 21종 + Relic 3종 + 빌드 6종)가 어휘 안에서 작동하는지 검증한다.
##
## 픽스처 테스트가 엔진을 검증한다면, 이 모듈은 **콘텐츠**를 검증한다.
## 카탈로그 로드 자체가 op·조건·셀렉터 오타를 잡는 관문이므로 여기가 첫 방어선이다.
##
## 밸런스 수치는 검증하지 않는다 — 전부 잠정이고 바뀔 예정이다.
## 대신 "설계한 메커니즘이 실제 전투에서 실제로 일어나는가"를 검증한다.
## 조용히 죽는 효과(트리거가 영원히 안 도는 것)가 이 프로젝트의 주된 실패 양식이다.

const EXPECTED_CHECKS := 72

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")
const Targeting = preload("res://sim/targeting.gd")
const PartText = preload("res://debug/part_text.gd")

const SMOKE_SEED := 7
const FACTIONS: Array[String] = ["reclaimer", "viridia", "aeonic"]

func run(t: RefCounted) -> void:
	_test_catalog_loads(t)
	_test_relic_validation(t)
	_test_builds_assemble(t)
	_test_part_coverage(t)
	_test_core_sets_hull_material(t)
	_test_smoke_combat(t)
	_test_new_mechanics_actually_fire(t)
	_test_chain_grouping(t)
	_test_display_order(t)
	_test_every_event_describes(t)
	_test_part_text_covers_vocabulary(t)
	_test_part_breakdown(t)
	_test_overheat_attribution(t)
	_test_determinism(t)
	t.done()

func _test_catalog_loads(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	t.check(c.ok(), "실제 카탈로그가 에러 없이 로드된다: %s" % str(c.errors))
	t.eq(c.parts.size(), 24, "파츠 24종 (팩션당 8종 — 7종 + Core)")
	t.eq(c.relics.size(), 3, "Relic 3종")
	t.eq(c.frames.size(), 4, "Frame 4종 (픽스처용 · 테스트 풀 · 초반 적 · Boss)")

	var by_faction: Dictionary = {}
	var passives: int = 0
	for id: String in c.parts:
		var def: Dictionary = c.parts[id]
		var f: String = str(def["faction"])
		by_faction[f] = int(by_faction.get(f, 0)) + 1
		if not (def["active"] as Dictionary).has("cooldown"):
			passives += 1
	for faction: String in FACTIONS:
		t.eq(int(by_faction.get(faction, 0)), 8, "%s 파츠 8종" % faction)
	t.eq(passives, 6, "패시브 파츠 6종 — 변환기 3 + Core 3 (Core는 트리거만 갖는다)")

	# 선체 재질은 Core가 정한다 (Frame이 아니다). Core가 재질 키워드를 갖지 않으면
	# 조용히 기본값(plating)이 되어 상성표의 절반이 잠든다.
	var materials: Dictionary = {}
	for id: String in c.parts:
		var def2: Dictionary = c.parts[id]
		if str(def2["base_role"]) != "core":
			continue
		for mat: String in K.HULL_MATERIALS:
			if (def2.get("keywords", []) as Array).has(mat):
				materials[str(def2["faction"])] = mat
	t.eq(materials.size(), 3, "Core 3종이 모두 선체 재질 키워드를 갖는다")
	t.check(materials.values().has("biomass"),
		"재질이 최소 두 종류로 갈린다 — 전부 plating이면 상성표가 잠든다")

func _test_relic_validation(t: RefCounted) -> void:
	# Relic 트리거의 어휘도 검증되어야 한다 — 안 그러면 오타 난 Relic이 조용히 죽는다.
	var c: RefCounted = Catalog.new()
	c.load_relics("res://sim/data/test_relics/broken_relic.json")
	t.check(not c.ok(), "op 오타가 있는 Relic은 로드 에러를 낸다")
	t.eq(c.relics.size(), 0, "검증에 실패한 Relic은 등록되지 않는다")

func _test_builds_assemble(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	t.eq(Content.build_ids().size(), 3, "플레이어 빌드 3종 (팩션당 순수 하나)")
	t.eq(Content.enemy_ids().size(), 3, "적 빌드 3종 (거울짝)")

	for id: String in _all_build_ids():
		var prepared: Dictionary = Content.prepare(c, id, id, 1)
		t.check(prepared["sim"] != null, "%s 조립 성공: %s" % [id, str(prepared["errors"])])
		if prepared["sim"] == null:
			continue
		t.eq(prepared["sim"].player.parts.size(), 6, "%s는 슬롯 6칸을 모두 채운다" % id)

## 풀의 모든 파츠가 어딘가에 쓰이는가, 그리고 각 팩션이 AUGMENT를 실제로 쓰는가.
## 쓰이지 않는 파츠는 전투에서 한 번도 검증되지 않는다.
func _test_part_coverage(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var used: Dictionary = {}
	var augment_by_faction: Dictionary = {}
	for id: String in _all_build_ids():
		var build: Dictionary = Content.read_build(id)
		for slot_id: String in build.get("slots", {}):
			var entry: Dictionary = build["slots"][slot_id]
			used[str(entry["part"])] = true
			var aug: String = str(entry.get("augment", ""))
			if aug == "":
				continue
			used[aug] = true
			var f: String = str(c.parts[aug]["faction"])
			augment_by_faction[f] = int(augment_by_faction.get(f, 0)) + 1

	var unused: Array[String] = []
	for id: String in c.parts:
		if not used.has(id):
			unused.append(id)
	t.check(unused.is_empty(), "빌드에 한 번도 안 쓰인 파츠가 없다 — 미사용: %s" % str(unused))
	for faction: String in FACTIONS:
		t.check(int(augment_by_faction.get(faction, 0)) > 0,
			"%s 순수 빌드가 AUGMENT를 실제로 쓴다" % faction)

## Core가 실제로 선체 재질을 정하는가. 조립된 함선에서 확인한다 —
## JSON에 키워드를 적어도 build_loader가 읽지 않으면 조용히 기본값이 된다.
func _test_core_sets_hull_material(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var by_build: Dictionary = {}
	for id: String in Content.build_ids():
		by_build[id] = str(Content.prepare(c, id, id, 1)["sim"].player.hull_material)
	t.eq(str(by_build.get("viridia_pure", "")), "biomass", "Viridia는 biomass 선체다")
	t.eq(str(by_build.get("reclaimer_pure", "")), "plating", "Reclaimer는 plating 선체다")
	t.eq(str(by_build.get("aeonic_pure", "")), "plating", "Aeonic은 plating 선체다")

func _test_smoke_combat(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var capped: int = 0
	var unfinished: int = 0
	var bad_winner: int = 0
	var thin: int = 0
	for build_id: String in Content.build_ids():
		for enemy_id: String in Content.enemy_ids():
			var sim: RefCounted = Content.prepare(c, build_id, enemy_id, SMOKE_SEED)["sim"]
			var log: Array = sim.run()
			if not sim.finished:
				unfinished += 1
			if not ["player", "enemy", "draw"].has(sim.winner):
				bad_winner += 1
			if log.size() < 100:
				thin += 1
			capped += sim.count_events("chain_capped")
	# 9판을 판마다 어서션하지 않고 모아서 판정한다 — 빌드 수가 바뀌어도
	# EXPECTED_CHECKS가 흔들리지 않게 하기 위함이다.
	t.eq(unfinished, 0, "9개 대진이 모두 끝난다")
	t.eq(bad_winner, 0, "9개 대진의 승자가 모두 유효하다")
	t.eq(thin, 0, "9개 대진 모두 이벤트가 충분히 나온다")
	t.eq(capped, 0, "chain_capped가 하나도 없다 — 있으면 설계 결함이다")

## 새로 넣은 메커니즘 네 가지가 **실제 콘텐츠에서 실제로 일어나는가**.
## 이 프로젝트의 주된 실패 양식은 크래시가 아니라 "트리거가 조용히 한 번도 안 도는 것"이다.
## 파츠 JSON은 로드를 통과해도 조건이 영원히 거짓이면 아무 일도 하지 않는다.
func _test_new_mechanics_actually_fire(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var seen: Dictionary = {}
	var multi_fires: int = 0
	var passive_fires: int = 0
	for build_id: String in Content.build_ids():
		for enemy_id: String in Content.enemy_ids():
			var sim: RefCounted = Content.prepare(c, build_id, enemy_id, SMOKE_SEED)["sim"]
			for e: Dictionary in sim.run():
				seen[str(e["type"])] = true
				if str(e["type"]) != "part_fired":
					continue
				if str(e.get("cause", "")) == "multi_fire":
					multi_fires += 1
				if _is_passive_slot(c, build_id, enemy_id, e):
					passive_fires += 1

	t.check(multi_fires > 0, "Multi-fire 재발동이 실제로 일어난다 (%d회)" % multi_fires)
	t.check(seen.has("multi_fire_queued"), "multi_fire_queued가 방출된다")
	t.check(seen.has("charge_applied"), "Charge가 실제로 걸린다 — Aeonic 루프의 전제")
	t.check(seen.has("growth_changed"), "성장이 실제로 누적된다")
	t.check(seen.has("stasis_applied"), "Stasis가 실제로 걸린다")
	t.check(seen.has("overheat_ticked"), "과열 피해가 실제로 발생한다")
	t.check(seen.has("regen_ticked"), "Viridia Core의 초당 재생이 실제로 돈다")
	t.eq(passive_fires, 0, "패시브 변환기는 한 번도 스스로 발동하지 않는다")

## 이벤트의 슬롯이 패시브 파츠의 슬롯인가. 빌드 정의(정적)로만 판정한다.
func _is_passive_slot(c: RefCounted, player_id: String, enemy_id: String,
		e: Dictionary) -> bool:
	var build: Dictionary = Content.read_build(
		player_id if str(e.get("ship", "")) == "player" else enemy_id)
	var entry: Variant = build.get("slots", {}).get(str(e.get("slot", "")), null)
	if not (entry is Dictionary):
		return false
	var def: Dictionary = c.parts[str((entry as Dictionary)["part"])]
	return not (def["active"] as Dictionary).has("cooldown")

func _test_chain_grouping(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var sim: RefCounted = Content.prepare(c, "aeonic_pure", "viridia_mirror", SMOKE_SEED)["sim"]
	var log: Array = sim.run()
	var chains: Array = Analysis.chains(log)

	# 연쇄마다 어서션을 걸면 어서션 수가 콘텐츠 수치에 따라 흔들려
	# EXPECTED_CHECKS가 무의미해진다. 모아서 한 번만 판정한다.
	var counted: int = 0
	var ids: Dictionary = {}
	var duplicated: int = 0
	for chain: Dictionary in chains:
		counted += (chain["events"] as Array).size()
		if ids.has(chain["id"]):
			duplicated += 1
		ids[chain["id"]] = true
	t.eq(duplicated, 0, "각 chain_id가 정확히 한 묶음으로 모인다")
	t.eq(counted, log.size(), "모든 이벤트가 정확히 한 연쇄에 속한다")

	# 연쇄의 뿌리는 하나뿐이어야 한다. chain_id가 상수가 되는 회귀(모든 이벤트가 한
	# 묶음)는 위의 개수 검사만으로는 잡히지 않는다 — 뿌리 수를 세야 잡힌다.
	# 쿨타임·Multi-fire 발동은 depth 0, 체인이 부른 강제 발동은 depth ≥ 1이므로
	# 한 연쇄 안의 depth 0 part_fired는 정확히 최대 하나다.
	var multi_root: int = 0
	var deep: int = 0
	for chain: Dictionary in chains:
		if int(chain["depth"]) >= 2:
			deep += 1
		var roots: int = 0
		for event: Dictionary in chain["events"]:
			if str(event["type"]) == "part_fired" and int(event["chain_depth"]) == 0:
				roots += 1
		if roots > 1:
			multi_root += 1
	t.eq(multi_root, 0, "한 연쇄에 뿌리 발동은 하나뿐이다")
	t.check(chains.size() > 1, "연쇄가 여러 개로 갈라진다 (%d개)" % chains.size())
	t.check(deep > 0, "2단계 이상 연쇄가 실제로 발생한다 (%d건)" % deep)

	var ranking: Array = Analysis.signature_ranking(log)
	t.check(not ranking.is_empty(), "대표 연쇄 서명을 뽑을 수 있다")

## 표시용 재배열은 이벤트를 잃지도 만들지도 않고, 같은 틱 안에서 한 연쇄를
## 두 조각으로 쪼개지 않아야 한다. 쪼개지면 화면에서 캐스케이드가 끊겨 보인다.
func _test_display_order(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var sim: RefCounted = Content.prepare(c, "viridia_pure", "viridia_mirror", SMOKE_SEED)["sim"]
	var log: Array = sim.run()
	var ordered: Array = Analysis.grouped_by_chain(log)
	t.eq(ordered.size(), log.size(), "재배열이 이벤트를 잃거나 만들지 않는다")

	var out_of_order: int = 0
	var split_chains: int = 0
	var last_t: float = -1.0
	var seen_here: Dictionary = {}
	var prev_key: String = ""
	var tick_t: float = -1.0
	for event: Dictionary in ordered:
		var now: float = float(event["t"])
		if now < last_t:
			out_of_order += 1
		last_t = now
		if not is_equal_approx(now, tick_t):
			tick_t = now
			seen_here = {}
			prev_key = ""
		var key: String = str(event.get("chain_id", 0))
		if key != prev_key and seen_here.has(key):
			split_chains += 1
		seen_here[key] = true
		prev_key = key
	t.eq(out_of_order, 0, "재배열해도 시간 순서는 뒤집히지 않는다")
	t.eq(split_chains, 0, "한 틱 안에서 연쇄가 두 조각으로 쪼개지지 않는다")

## §6.1의 "이벤트는 자기서술적이어야 한다"를 실물로 검증한다 —
## 어떤 이벤트든 sim을 조회하지 않고 한 줄로 읽을 수 있어야 한다.
func _test_every_event_describes(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var bare: Array[String] = []
	var seen: Dictionary = {}
	for build_id: String in Content.build_ids():
		for enemy_id: String in Content.enemy_ids():
			var sim: RefCounted = Content.prepare(c, build_id, enemy_id, SMOKE_SEED)["sim"]
			for event: Dictionary in sim.run():
				var type: String = str(event["type"])
				if seen.has(type):
					continue
				seen[type] = true
				# describe가 타입 이름만 돌려줬다면 그 타입에 서술문이 없다는 뜻이다.
				if Analysis.describe(event) == type:
					bare.append(type)
	t.check(bare.is_empty(), "모든 이벤트 타입에 서술문이 있다 — 누락: %s" % str(bare))
	t.check(seen.size() >= 15, "전투가 이벤트 타입 15종 이상을 낸다 (%d)" % seen.size())

## 게임 안 파츠 설명은 액션 블록에서 만들어진다 — 별도 설명 문구를 두면 파츠를
## 고칠 때 두 곳을 고쳐야 하고 반드시 어긋나기 때문이다. 그 대가로 **어휘가 늘 때마다
## part_text에 한 줄을 추가해야 하고**, 잊으면 파츠 설명에 구멍이 뚫린다.
## 어휘 전체를 훑어 설명이 빠진 항목을 찾는다.
func _test_part_text_covers_vocabulary(t: RefCounted) -> void:
	var missing: Array[String] = []
	for op: String in Actions.OPS:
		if PartText.action_line({"op": op}).contains("설명 없음"):
			missing.append("op:" + op)
	for selector: String in Targeting.SELECTORS:
		if PartText.action_line({"op": "accelerate", "target": selector}).contains("설명 없음"):
			missing.append("selector:" + selector)
	for cond: String in Conditions.CONDITIONS:
		if PartText.condition_text({cond: 1}).contains("설명 없음"):
			missing.append("condition:" + cond)
	t.check(missing.is_empty(), "모든 어휘에 한국어 설명이 있다 — 누락: %s" % str(missing))

	# 실제 콘텐츠 24종이 전부 설명 가능한가 (트리거의 on 이벤트까지)
	var c: RefCounted = Content.load_catalog()
	var broken: Array[String] = []
	for id: String in c.parts:
		var text: String = PartText.detail(c.parts[id])
		if text.contains("설명 없음") or text == "":
			broken.append(id)
	t.check(broken.is_empty(), "파츠 24종의 설명문이 온전하다 — 문제: %s" % str(broken))
	t.check(PartText.summary(c.parts["rotary_incinerator"]).contains("열 피해"),
		"요약에 실제 효과가 들어간다")
	t.check(PartText.detail(c.parts["scrap_autocannon"]).contains("AUGMENT"),
		"전문에 AUGMENT 쪽도 들어간다 — 이중용도가 핵심이므로 한쪽만 보이면 선택을 못 한다")

## 슬롯별 전투 기여 집계. 화면의 전투 결과표가 이 값을 쓴다.
func _test_part_breakdown(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var sim: RefCounted = Content.prepare(c, "reclaimer_pure", "viridia_mirror", SMOKE_SEED)["sim"]
	var log: Array = sim.run()
	var rows: Dictionary = Analysis.part_breakdown(log, "player")
	t.check(not rows.is_empty(), "슬롯별 집계가 나온다")

	var total_fires: int = 0
	var total_damage: int = 0
	var named: int = 0
	for slot: String in rows:
		total_fires += int((rows[slot] as Dictionary)["fires"])
		total_damage += int((rows[slot] as Dictionary)["damage"])
		if str((rows[slot] as Dictionary)["name"]) != "":
			named += 1
	var summary: Dictionary = Analysis.combat_summary(log, "player")
	t.eq(total_fires, int(summary["fires"]), "슬롯별 발동 수의 합이 전체 발동 수와 같다")
	t.eq(total_damage, int(summary["damage"]), "슬롯별 피해의 합이 전체 피해와 같다")
	t.check(named > 0, "슬롯에 파츠 이름이 붙는다")

## 상태이상 부여는 **맞는 쪽** 진영으로 방출된다. ship으로 세면 부호가 뒤집혀
## "내가 받은 과열"이 "내가 부여한 과열"로 표시된다 — 실제로 화면에서 발견된 버그다.
func _test_overheat_attribution(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	# Reclaimer는 과열을 부여하고 Viridia는 이 풀에서 과열 파츠가 없다.
	var sim: RefCounted = Content.prepare(c, "reclaimer_pure", "viridia_mirror", SMOKE_SEED)["sim"]
	var log: Array = sim.run()
	var mine: Dictionary = Analysis.combat_summary(log, "player")
	var theirs: Dictionary = Analysis.combat_summary(log, "enemy")

	t.check(int(mine["overheat_applied"]) > 0, "Reclaimer는 과열을 부여한다 (%d)"
		% int(mine["overheat_applied"]))
	t.eq(int(theirs["overheat_applied"]), 0,
		"과열 파츠가 없는 Viridia의 부여량은 0이다 — ship으로 세면 여기가 뒤집힌다")
	t.check(int(mine["overheat_damage"]) > 0, "부여한 과열이 실제 피해로 이어진다")
	t.eq(int(theirs["overheat_damage"]), 0, "상대는 과열 피해를 내지 않았다")

	# 파츠별 집계도 같은 규칙을 쓴다
	var rows: Dictionary = Analysis.part_breakdown(log, "player")
	var applied: int = 0
	for slot: String in rows:
		applied += int((rows[slot] as Dictionary)["overheat"])
	t.eq(applied, int(mine["overheat_applied"]),
		"슬롯별 과열 부여량의 합이 전체 부여량과 같다")

func _test_determinism(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var first: Array = Content.prepare(c, "aeonic_pure", "reclaimer_mirror", 42)["sim"].run()
	var second: Array = Content.prepare(c, "aeonic_pure", "reclaimer_mirror", 42)["sim"].run()
	t.eq(second.size(), first.size(), "같은 시드는 같은 이벤트 수를 낸다")
	var mismatch: int = -1
	for i: int in mini(first.size(), second.size()):
		if str(first[i]) != str(second[i]):
			mismatch = i
			break
	t.eq(mismatch, -1, "같은 시드는 필드 단위로 동일한 스트림을 낸다")

	var other: Array = Content.prepare(c, "aeonic_pure", "reclaimer_mirror", 43)["sim"].run()
	t.check(str(other) != str(first), "다른 시드는 다른 스트림을 낸다")

func _all_build_ids() -> Array[String]:
	var out: Array[String] = Content.build_ids()
	out.append_array(Content.enemy_ids())
	return out
