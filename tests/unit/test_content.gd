extends RefCounted
## 실제 콘텐츠(아키타입 9종 × 10 파츠 + Core 3종 + Relic 3종)가 어휘 안에서
## 작동하는지 검증한다.
##
## 픽스처 테스트가 엔진을 검증한다면, 이 모듈은 **콘텐츠**를 검증한다.
## 카탈로그 로드 자체가 op·조건·셀렉터 오타를 잡는 관문이므로 여기가 첫 방어선이다.
##
## 밸런스 수치는 검증하지 않는다 — 전부 잠정이고 바뀔 예정이다.
## 대신 "설계한 메커니즘이 실제 전투에서 실제로 일어나는가"를 검증한다.
## 조용히 죽는 효과(트리거가 영원히 안 도는 것)가 이 프로젝트의 주된 실패 양식이다.

const EXPECTED_CHECKS := 90

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")
const Targeting = preload("res://sim/targeting.gd")
const PartText = preload("res://debug/part_text.gd")
const BuildLoader = preload("res://sim/build_loader.gd")

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
	t.eq(c.parts.size(), 93, "파츠 93종 — 아키타입 9종 × 10 + Core 3")
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
		t.eq(int(by_faction.get(faction, 0)), 31, "%s 파츠 31종 (아키타입 3 × 10 + Core)" % faction)

	# 아키타입은 파츠의 설계상 주 용도이며 장착 제한이 아니다 (기획서 §1).
	# 각 10종이 정확히 채워져야 "이 루프가 자급 가능한가"를 아키타입 단위로 물을 수 있다.
	var by_archetype: Dictionary = {}
	for id2: String in c.parts:
		var arch: String = str((c.parts[id2] as Dictionary).get("archetype", ""))
		if arch == "":
			continue
		by_archetype[arch] = int(by_archetype.get(arch, 0)) + 1
	t.eq(by_archetype.size(), 9, "아키타입 9종이 모두 존재한다")
	for arch2: String in Catalog.VALID_ARCHETYPES:
		t.eq(int(by_archetype.get(arch2, 0)), 10, "%s 아키타입 10종" % arch2)
	t.check(not str((c.parts["foundry_core"] as Dictionary).get("archetype", "")) != "",
		"Core는 아키타입을 갖지 않는다 — 90종 풀 밖이다 (기획서 §3.1)")

	t.eq(passives, 19, "패시브(Trigger형) 파츠 19종 — 변환기 16 + Core 3")

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

## 풀의 모든 파츠가 실제로 조립되고 전투를 견디는가.
##
## 옛 판본은 "빌드에 한 번도 안 쓰인 파츠가 없다"를 봤다. 파츠가 21종일 때는 그것이
## 곧 커버리지였지만 90종에서는 성립하지 않는다 — 6슬롯 빌드 6개로 90종을 덮을 수 없다.
##
## 그래서 검사를 둘로 나눈다.
##   (1) 모든 파츠가 **Active 자리와 Augment 자리 양쪽에서** 조립된다.
##       이중용도가 이 게임의 핵심이므로 한쪽만 되는 파츠는 절반이 죽은 것이다.
##   (2) 아키타입 10종으로 짠 보드가 실제 전투에서 **자기 루프의 사건을 만든다**.
##       개별 파츠로 검사하지 않는 이유: "단독으로는 아무것도 하지 않는" 변환기가
##       17종이고, 그것들은 설계상 혼자서는 침묵하는 것이 맞다.
func _test_part_coverage(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var frame: Dictionary = c.frames["pool_frame"]

	var not_placeable: Array[String] = []
	var not_augmentable: Array[String] = []
	for id: String in c.parts:
		var def: Dictionary = c.parts[id]
		if str(def["base_role"]) == "core":
			continue
		if _build_with(c, frame, id, "") == null:
			not_placeable.append(id)
		if not def.has("augment"):
			not_augmentable.append(id)
	t.check(not_placeable.is_empty(),
		"모든 파츠가 자기 역할 슬롯에 조립된다 — 실패: %s" % str(not_placeable))
	t.check(not_augmentable.is_empty(),
		"모든 파츠가 AUGMENT 블록을 갖는다 (이중용도) — 없음: %s" % str(not_augmentable))

	# 아키타입 보드가 실제로 돈다. 사건이 하나도 안 나면 그 아키타입은 죽은 설계다.
	# 같은 실행에서 **새 메커니즘이 실제로 발화하는지**도 함께 센다 — 조용히 죽는
	# 효과가 이 프로젝트의 주된 실패 양식이므로, 어휘를 늘렸으면 그 어휘가 실물
	# 콘텐츠에서 한 번은 일어나는 것을 봐야 한다.
	var silent: Array[String] = []
	var seen: Dictionary = {}
	var destroy_causes: Dictionary = {}
	var block_reasons: Dictionary = {}
	for arch: String in Catalog.VALID_ARCHETYPES:
		var build: Dictionary = _archetype_build(c, arch)
		var prepared: Dictionary = Content.prepare_builds(c, build, build, SMOKE_SEED)
		if prepared["sim"] == null:
			silent.append("%s(조립 실패: %s)" % [arch, str(prepared["errors"])])
			continue
		var log: Array = prepared["sim"].run()
		var acted: Dictionary = {}
		for e: Dictionary in log:
			seen[str(e["type"])] = true
			if str(e.get("ship", "")) == "player" and e.has("slot"):
				acted[str(e["slot"])] = true
			if str(e["type"]) == "part_destroyed":
				destroy_causes[str(e.get("cause", "?"))] = true
			elif str(e["type"]) == "part_fire_blocked":
				block_reasons[str(e.get("reason", "?"))] = true
		if acted.size() < 2:
			silent.append("%s(움직인 슬롯 %d개)" % [arch, acted.size()])
	t.check(silent.is_empty(), "아키타입 9종의 보드가 전부 사건을 만든다 — 침묵: %s" % str(silent))

	# 90종을 위해 새로 만든 어휘. 하나라도 빠지면 그 어휘를 쓰는 파츠가 죽어 있다.
	var never: Array[String] = []
	for type: String in ["stasis_ended", "overheat_cleansed", "cooldown_shortened",
			"regen_ended", "part_restored", "charge_applied", "fires_changed"]:
		if not seen.has(type):
			never.append(type)
	t.check(never.is_empty(),
		"새 이벤트가 실제 콘텐츠에서 발화한다 — 한 번도 안 난 것: %s" % str(never))
	t.check(destroy_causes.has("self_destruct"),
		"destroy_self가 실제로 파괴를 일으킨다 (해체 순환의 전제)")
	t.check(block_reasons.has("requirement"),
		"발동 전제가 실제로 발동을 대기시킨다 (RC09·AE06·AH09의 전제)")
	t.check(block_reasons.has("fire_limit"),
		"발동 횟수 소진이 발동만 막는다 — 파손 사유에는 없다")
	t.check(not destroy_causes.has("fires_exhausted"),
		"소진은 더 이상 파손 원인이 아니다 (기획서 §3.3)")

	for faction: String in FACTIONS:
		var augments: int = 0
		for id2: String in _all_build_ids():
			var b: Dictionary = Content.read_build(id2)
			for slot_id: String in b.get("slots", {}):
				var aug: String = str((b["slots"][slot_id] as Dictionary).get("augment", ""))
				if aug != "" and str(c.parts[aug]["faction"]) == faction:
					augments += 1
		t.check(augments > 0, "%s 순수 빌드가 AUGMENT를 실제로 쓴다" % faction)

## 아키타입 하나의 파츠만으로 6슬롯을 채운 보드. 역할이 남으면 같은 팩션 Core로 메운다.
## 슬롯을 다 못 채우는 아키타입이 있으면 그 자체가 설계 결함이므로 굳이 보충하지 않는다.
func _archetype_build(c: RefCounted, archetype: String) -> Dictionary:
	var frame: Dictionary = c.frames["pool_frame"]
	var pool: Array[String] = []
	var faction: String = ""
	for id: String in c.parts:
		var def: Dictionary = c.parts[id]
		if str(def.get("archetype", "")) != archetype:
			continue
		pool.append(id)
		faction = str(def["faction"])
	var slots: Dictionary = {}
	var used: Array[String] = []
	for slot_def: Dictionary in frame["slots"]:
		var role: String = str(slot_def["role"])
		if role == "core":
			slots[str(slot_def["id"])] = {"part": _core_of(c, faction)}
			continue
		for id2: String in pool:
			if used.has(id2):
				continue
			if role != "flexible" and str(c.parts[id2]["base_role"]) != role:
				continue
			used.append(id2)
			# 남는 파츠 하나를 AUGMENT로 얹어 이중용도 경로도 함께 돌린다.
			var aug: String = ""
			for id3: String in pool:
				if not used.has(id3):
					aug = id3
					used.append(id3)
					break
			slots[str(slot_def["id"])] = {"part": id2, "augment": aug} if aug != "" \
				else {"part": id2}
			break
	return {"id": "archetype_%s" % archetype, "frame": "pool_frame", "slots": slots}

func _core_of(c: RefCounted, faction: String) -> String:
	for id: String in c.parts:
		var def: Dictionary = c.parts[id]
		if str(def["base_role"]) == "core" and str(def["faction"]) == faction:
			return id
	return ""

## 파츠 하나를 자기 역할 슬롯에 꽂은 최소 보드를 조립한다. 실패하면 null.
func _build_with(c: RefCounted, frame: Dictionary, part_id: String,
		augment_id: String) -> RefCounted:
	var role: String = str(c.parts[part_id]["base_role"])
	var faction: String = str(c.parts[part_id]["faction"])
	var slots: Dictionary = {}
	for slot_def: Dictionary in frame["slots"]:
		var slot_role: String = str(slot_def["role"])
		if slot_role == "core":
			slots[str(slot_def["id"])] = {"part": _core_of(c, faction)}
		elif slot_role == role and not slots.has(str(slot_def["id"])):
			var entry: Dictionary = {"part": part_id}
			if augment_id != "":
				entry["augment"] = augment_id
			slots[str(slot_def["id"])] = entry
			break
	var loader: RefCounted = BuildLoader.new()
	return loader.assemble({"id": "probe", "frame": str(frame["id"]), "slots": slots},
		c, "player")

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

	# 실제 콘텐츠 93종이 전부 설명 가능한가 (트리거의 on 이벤트까지)
	var c: RefCounted = Content.load_catalog()
	var broken: Array[String] = []
	for id: String in c.parts:
		var text: String = PartText.detail(c.parts[id])
		if text.contains("설명 없음") or text == "":
			broken.append(id)
	t.check(broken.is_empty(), "파츠 93종의 설명문이 온전하다 — 문제: %s" % str(broken))
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
