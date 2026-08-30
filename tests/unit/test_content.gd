extends RefCounted
## 실제 콘텐츠(Reclaimer 6종 + Relic 3종 + 빌드 3종)가 어휘 안에서 작동하는지 검증한다.
##
## 픽스처 테스트가 엔진을 검증한다면, 이 모듈은 **콘텐츠**를 검증한다.
## 카탈로그 로드 자체가 op·조건·셀렉터 오타를 잡는 관문이므로 여기가 첫 방어선이다.

const EXPECTED_CHECKS := 62

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")

## 이 빌드들에는 파손이 반드시 일어나야 한다 — 발동 제한이 걸린 파츠가 있고
## 파괴선도 있기 때문이다. 하나도 안 나오면 콘텐츠가 축을 안 쓰고 있다는 뜻이다.
const SMOKE_SEED := 7

func run(t: RefCounted) -> void:
	_test_catalog_loads(t)
	_test_relic_validation(t)
	_test_builds_assemble(t)
	_test_dual_use_coverage(t)
	_test_smoke_combat(t)
	_test_chain_grouping(t)
	_test_every_event_describes(t)
	_test_determinism(t)
	t.done()

func _test_catalog_loads(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	t.check(c.ok(), "실제 카탈로그가 에러 없이 로드된다: %s" % str(c.errors))
	t.eq(c.parts.size(), 6, "Reclaimer 파츠 6종")
	t.eq(c.relics.size(), 3, "Relic 3종")
	t.eq(c.frames.size(), 1, "Frame 1종")
	for pid: String in ["supercharged_turbine", "breaker", "rivet_railgun",
			"weld_plating", "venting_manifold", "scrap_reactor"]:
		t.check(c.parts.has(pid), "파츠 %s 존재" % pid)
	for id: String in c.parts:
		t.eq(str(c.parts[id]["faction"]), "reclaimer", "%s는 reclaimer다" % id)

func _test_relic_validation(t: RefCounted) -> void:
	# Relic 트리거의 어휘도 검증되어야 한다 — 안 그러면 오타 난 Relic이 조용히 죽는다.
	var c: RefCounted = Catalog.new()
	c.load_relics("res://sim/data/test_relics/broken_relic.json")
	t.check(not c.ok(), "op 오타가 있는 Relic은 로드 에러를 낸다")
	t.eq(c.relics.size(), 0, "검증에 실패한 Relic은 등록되지 않는다")

func _test_builds_assemble(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var all_ids: Array[String] = Content.build_ids()
	all_ids.append_array(Content.enemy_ids())
	t.eq(all_ids.size(), 3, "빌드 3종 (플레이어 1 + 적 2)")
	for id: String in all_ids:
		var prepared: Dictionary = Content.prepare(c, id, id, 1)
		t.check(prepared["sim"] != null, "%s 조립 성공: %s" % [id, str(prepared["errors"])])
		if prepared["sim"] == null:
			continue
		t.check(prepared["sim"].player.parts.size() >= 5, "%s에 파츠가 5개 이상" % id)
		t.check(prepared["sim"].player.get_part("core") != null, "%s에 Core가 있다" % id)

## 이중용도 최소 조건: Core가 아닌 모든 파츠가 배포된 빌드 안에서
## ACTIVE로도 AUGMENT로도 최소 한 번씩 등장해야 한다.
## 한쪽으로만 쓰이는 파츠는 §61.A가 묻는 "고민"을 만들지 못한다.
func _test_dual_use_coverage(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var as_active: Dictionary = {}
	var as_augment: Dictionary = {}
	var all_ids: Array[String] = Content.build_ids()
	all_ids.append_array(Content.enemy_ids())
	for id: String in all_ids:
		var build: Dictionary = Content.read_build(id)
		for slot_id: String in build.get("slots", {}):
			var entry: Dictionary = build["slots"][slot_id]
			as_active[str(entry.get("part", ""))] = true
			var aug: String = str(entry.get("augment", ""))
			if aug != "":
				as_augment[aug] = true
	for pid: String in c.parts:
		var is_core: bool = (c.parts[pid]["roles"] as Array).has("core")
		t.check(as_active.has(pid), "%s가 어떤 빌드에서든 ACTIVE로 쓰인다" % pid)
		if is_core:
			continue
		t.check(as_augment.has(pid), "%s가 어떤 빌드에서든 AUGMENT로 쓰인다" % pid)

func _test_smoke_combat(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	for enemy_id: String in Content.enemy_ids():
		var sim: RefCounted = Content.prepare(c, "reclaimer_pure", enemy_id, SMOKE_SEED)["sim"]
		var log: Array = sim.run()
		t.check(sim.finished, "%s전이 끝났다" % enemy_id)
		t.check(["player", "enemy", "draw"].has(sim.winner), "%s전 승자가 유효하다" % enemy_id)
		t.check(log.size() > 50, "%s전 이벤트가 충분히 나온다 (%d)" % [enemy_id, log.size()])
		t.eq(sim.count_events("chain_capped"), 0, "%s전에 chain_capped가 없다" % enemy_id)
		t.check(sim.count_events("part_destroyed") > 0, "%s전에 파손이 일어난다" % enemy_id)
		t.check(sim.count_events("fires_changed") > 0, "%s전에 발동 횟수가 움직인다" % enemy_id)

func _test_chain_grouping(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var sim: RefCounted = Content.prepare(c, "reclaimer_pure", "hulk_breaker", SMOKE_SEED)["sim"]
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
	# 쿨타임 발동은 depth 0, 체인이 부른 강제 발동은 depth ≥ 1이므로
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
	t.eq(multi_root, 0, "한 연쇄에 쿨타임 발동 뿌리는 하나뿐이다")
	t.check(chains.size() > 1, "연쇄가 여러 개로 갈라진다 (%d개)" % chains.size())
	t.check(deep > 0, "2단계 이상 연쇄가 실제로 발생한다 (%d건)" % deep)

	var ranking: Array = Analysis.signature_ranking(log)
	t.check(not ranking.is_empty(), "대표 연쇄 서명을 뽑을 수 있다")

## §6.1의 "이벤트는 자기서술적이어야 한다"를 실물로 검증한다 —
## 어떤 이벤트든 sim을 조회하지 않고 한 줄로 읽을 수 있어야 한다.
func _test_every_event_describes(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var sim: RefCounted = Content.prepare(c, "reclaimer_pure", "scrap_raider", SMOKE_SEED)["sim"]
	var log: Array = sim.run()
	var bare: Array[String] = []
	var seen: Dictionary = {}
	for event: Dictionary in log:
		var type: String = str(event["type"])
		if seen.has(type):
			continue
		seen[type] = true
		var line: String = Analysis.describe(event)
		# describe가 타입 이름만 돌려줬다면 그 타입에 서술문이 없다는 뜻이다.
		if line == type:
			bare.append(type)
	t.check(bare.is_empty(), "모든 이벤트 타입에 서술문이 있다 — 누락: %s" % str(bare))
	t.check(seen.size() >= 10, "전투가 이벤트 타입 10종 이상을 낸다 (%d)" % seen.size())

func _test_determinism(t: RefCounted) -> void:
	var c: RefCounted = Content.load_catalog()
	var first: Array = Content.prepare(c, "reclaimer_pure", "hulk_breaker", 42)["sim"].run()
	var second: Array = Content.prepare(c, "reclaimer_pure", "hulk_breaker", 42)["sim"].run()
	t.eq(second.size(), first.size(), "같은 시드는 같은 이벤트 수를 낸다")
	var mismatch: int = -1
	for i: int in mini(first.size(), second.size()):
		if str(first[i]) != str(second[i]):
			mismatch = i
			break
	t.eq(mismatch, -1, "같은 시드는 필드 단위로 동일한 스트림을 낸다")

	var other: Array = Content.prepare(c, "reclaimer_pure", "hulk_breaker", 43)["sim"].run()
	t.check(str(other) != str(first), "다른 시드는 다른 스트림을 낸다")
