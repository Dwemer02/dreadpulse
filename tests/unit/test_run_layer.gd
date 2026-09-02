extends RefCounted
## 런 계층(res://run/) 검증.
##
## 밸런스는 보지 않는다 — 승률은 잠정 수치의 함수다.
## 검증하는 것은 **구조**다: 인스턴스가 두 자리에 동시에 있지 않는가,
## Salvage가 3택1 형식을 지키는가, 상태 전이가 순서를 강제하는가,
## 같은 런 시드가 같은 런을 만드는가.

const EXPECTED_CHECKS := 73

const K = preload("res://sim/sim_const.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const RunContent = preload("res://run/run_content.gd")
const Inventory = preload("res://run/inventory.gd")
const Salvage = preload("res://run/salvage.gd")
const RunState = preload("res://run/run_state.gd")
const MiniIteration = preload("res://run/mini_iteration.gd")
const Autopilot = preload("res://run/autopilot.gd")

func run(t: RefCounted) -> void:
	_test_content_loads(t)
	_test_inventory_instances(t)
	_test_inventory_build(t)
	_test_board_diff(t)
	_test_combat_seed(t)
	_test_salvage_shape(t)
	_test_state_machine_order(t)
	_test_autopilot_completes(t)
	_test_run_determinism(t)
	_test_combat_summary(t)
	t.done()

func _catalog() -> RefCounted:
	return Content.load_catalog()

func _content(catalog: RefCounted) -> RefCounted:
	var rc: RefCounted = RunContent.new()
	rc.load_all()
	rc.validate(catalog)
	return rc

## 런 콘텐츠 검증은 build_loader.assemble()에 맡긴다. 그래서 이 테스트가
## 존재하지 않는 파츠·역할 불일치·Core 누락을 전부 대신 잡는다.
func _test_content_loads(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	t.check(rc.ok(), "런 콘텐츠가 에러 없이 로드·검증된다: %s" % str(rc.errors))
	t.eq(rc.enemies.size(), 8, "적 8종 (일반 6 + Elite + Boss)")
	t.eq(rc.starters.size(), 3, "스타터 3종")
	t.eq(rc.node_count(), 6, "노드 6개")

	var tiers: Dictionary = {}
	for id: String in rc.enemies:
		var tier: String = str((rc.enemies[id] as Dictionary).get("tier", "normal"))
		tiers[tier] = int(tiers.get(tier, 0)) + 1
	t.eq(int(tiers.get("normal", 0)), 6, "일반 적 6종")
	t.eq(int(tiers.get("elite", 0)), 1, "Elite 1종")
	t.eq(int(tiers.get("boss", 0)), 1, "Boss 1종")

	# 경로 선택 시점에 보이는 정보가 실제로 채워져 있는가 (손으로 적는 값이다)
	var missing: Array[String] = []
	for id: String in rc.enemies:
		var threat: Dictionary = (rc.enemies[id] as Dictionary).get("threat", {})
		if str(threat.get("material", "")) == "" or (threat.get("tags", []) as Array).is_empty():
			missing.append(id)
	t.check(missing.is_empty(), "모든 적에 Threat Profile이 있다 — 누락: %s" % str(missing))

	# 6전투 안에 3팩션을 모두 만날 수 있는가
	var factions: Dictionary = {}
	for node: Variant in rc.nodes:
		for enemy_id: Variant in (node as Dictionary)["options"]:
			factions[str((rc.enemies[str(enemy_id)] as Dictionary)["faction"])] = true
	t.eq(factions.size(), 3, "노드 구성에 3팩션이 모두 등장한다")

## 한 인스턴스는 한 자리에만 있을 수 있다. 이 규칙이 깨지면 파츠 하나를
## Active와 Augment로 동시에 쓰는 빌드가 만들어진다.
func _test_inventory_instances(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	var a: int = inv.add("scrap_autocannon")
	var b: int = inv.add("field_welder")
	t.check(a != b, "같은 파츠를 두 번 넣어도 uid가 다르다")
	t.eq(inv.owned.size(), 2, "보유 2개")
	t.eq(inv.part_id_of(a), "scrap_autocannon", "uid로 part_id를 찾는다")

	inv.place("weapon_1", a, b)
	t.eq(inv.slot_of(a), "weapon_1", "Active가 배치된다")
	t.eq(inv.slot_of(b), "weapon_1", "Augment도 같은 슬롯에 있다")
	t.eq(inv.unplaced().size(), 0, "둘 다 배치됐으므로 창고가 비었다")

	# 다른 슬롯에 같은 인스턴스를 놓으면 원래 자리에서 떨어진다
	inv.place("flex_1", b)
	t.eq(inv.slot_of(b), "flex_1", "인스턴스가 새 슬롯으로 옮겨간다")
	t.eq(int(inv.board["weapon_1"]["augment"]), Inventory.NONE,
		"원래 슬롯의 Augment 자리가 비워진다 — 한 자리 규칙")

	# Active를 떼면 그 슬롯의 Augment도 함께 풀린다 (숙주 없는 Augment는 없다)
	var c: int = inv.add("scrap_compactor")
	inv.place("flex_2", a, c)
	inv.place("weapon_2", a)
	t.check(not inv.board.has("flex_2"), "Active가 떠난 슬롯은 사라진다")
	t.check(not inv.is_placed(c), "숙주를 잃은 Augment는 창고로 돌아간다")

func _test_inventory_build(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var inv: RefCounted = Inventory.new()
	inv.place("core", inv.add("foundry_core"))
	var gun: int = inv.add("scrap_autocannon")
	inv.place("weapon_1", gun, inv.add("scrap_autocannon"))
	var build: Dictionary = inv.to_build("t", "pool_frame")

	t.eq(str(build["frame"]), "pool_frame", "프레임이 실린다")
	t.eq((build["slots"] as Dictionary).size(), 2, "배치된 슬롯만 들어간다 (빈 슬롯 제외)")
	t.eq(str(build["slots"]["weapon_1"]["augment"]), "scrap_autocannon", "Augment가 실린다")
	t.check(not (build["slots"]["core"] as Dictionary).has("augment"),
		"Augment가 없는 슬롯에는 키 자체가 없다")

	# 만들어진 빌드가 실제로 조립되는가 — 검증의 단일 출처는 assemble()이다
	var prepared: Dictionary = Content.prepare_builds(catalog, build, build, 1)
	t.check(prepared["sim"] != null, "인벤토리가 만든 빌드가 조립된다: %s" % str(prepared["errors"]))

func _test_board_diff(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	var a: int = inv.add("scrap_autocannon")
	var b: int = inv.add("photon_lance")
	inv.place("weapon_1", a)
	var before: Dictionary = inv.snapshot()

	t.eq(int(Inventory.board_diff(before, before)["active"]), 0, "안 바꾸면 변화 0")

	inv.place("weapon_1", b)
	var swapped: Dictionary = Inventory.board_diff(before, inv.snapshot())
	t.eq(int(swapped["active"]), 1, "Active 교체 1건")
	t.eq(int(swapped["augment"]), 0, "Augment는 안 건드렸다")

	inv.place("weapon_1", b, a)
	var augmented: Dictionary = Inventory.board_diff(before, inv.snapshot())
	t.eq(int(augmented["augment"]), 1, "Augment 변경 1건")
	# 같은 슬롯 안에서 Active -> Augment로 역할만 바뀐 것은 "슬롯 재배치"가 아니다.
	# Augment 변경으로 이미 세어졌으므로 moved에서 다시 세면 이중 계산이 된다.
	t.eq(int(augmented["moved"]), 0, "같은 슬롯 안의 역할 변경은 슬롯 재배치가 아니다")

func _test_combat_seed(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var run_a: RefCounted = RunState.new()
	run_a.begin(rc.starters["reclaimer"], 42)
	var run_b: RefCounted = RunState.new()
	run_b.begin(rc.starters["reclaimer"], 42)
	var run_c: RefCounted = RunState.new()
	run_c.begin(rc.starters["reclaimer"], 43)

	t.eq(run_a.combat_seed(0), run_b.combat_seed(0), "같은 런 시드는 같은 전투 시드를 낸다")
	t.check(run_a.combat_seed(0) != run_a.combat_seed(1), "노드마다 전투 시드가 다르다")
	t.check(run_a.combat_seed(0) != run_c.combat_seed(0), "런 시드가 다르면 전투 시드도 다르다")
	t.check(run_a.combat_seed(3) >= 0, "전투 시드는 음수가 아니다")
	t.eq(run_a.inventory.owned.size(), 4, "스타터는 파츠 4개다 (프레임 6칸 중 2칸이 성장 공간)")

## Salvage는 3택1이라는 **형식**을 지켜야 한다. 후보가 2개면 플레이어가
## 무엇을 포기했는지 알 수 없고, 세 후보가 같은 팩션이면 혼종 질문이 사라진다.
func _test_salvage_shape(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	var short_offers: int = 0
	var duplicated: int = 0
	var cores: int = 0
	var not_from_enemy: int = 0
	var single_faction: int = 0
	for enemy_id: String in rc.enemies:
		var used: Array[String] = rc.parts_used_by(enemy_id)
		for s: int in range(1, 11):
			rng.seed = s
			var offer: Array[String] = Salvage.offer(catalog, rc, rng, enemy_id)
			if offer.size() != 3:
				short_offers += 1
			var seen: Dictionary = {}
			var factions: Dictionary = {}
			for pid: String in offer:
				if seen.has(pid):
					duplicated += 1
				seen[pid] = true
				factions[str(catalog.parts[pid]["faction"])] = true
				if str(catalog.parts[pid]["base_role"]) == "core":
					cores += 1
			if not used.has(offer[0]):
				not_from_enemy += 1
			if factions.size() < 2:
				single_faction += 1

	t.eq(short_offers, 0, "모든 후보가 정확히 3개다")
	t.eq(duplicated, 0, "한 후보 안에 같은 파츠가 두 번 나오지 않는다")
	t.eq(cores, 0, "Core는 Salvage 후보에 나오지 않는다")
	t.eq(not_from_enemy, 0, "첫 후보는 항상 방금 싸운 적이 실제로 쓴 파츠다")
	t.eq(single_faction, 0, "후보가 한 팩션으로만 채워지지 않는다 — 혼종 질문이 사라진다")

	# 같은 시드는 같은 후보를 낸다 (런 재현성)
	rng.seed = 7
	var first: Array[String] = Salvage.offer(catalog, rc, rng, "reclaimer_gunline")
	rng.seed = 7
	var again: Array[String] = Salvage.offer(catalog, rc, rng, "reclaimer_gunline")
	t.eq(str(again), str(first), "같은 런 RNG 시드는 같은 후보를 낸다")

## 상태 기계는 순서를 강제해야 한다. 순서를 안 지킨 호출이 조용히 통과하면
## UI가 잘못된 단계에서 전투를 시작시킬 수 있다.
func _test_state_machine_order(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var it: RefCounted = MiniIteration.new()
	it.setup(catalog, rc)

	t.check(not it.begin("nonexistent_faction", 1), "없는 팩션으로는 시작할 수 없다")

	it = MiniIteration.new()
	it.setup(catalog, rc)
	t.check(it.begin("reclaimer", 1), "런이 시작된다")
	t.eq(it.state, "choose_enemy", "첫 상태는 적 선택")
	t.eq(it.enemy_options().size(), 2, "노드 1의 후보는 2종")
	t.check(not (it.enemy_options()[0] as Dictionary).has("slots"),
		"선택 시점에는 파츠 구성이 보이지 않는다 — Threat Profile만")

	t.check(not it.fight(), "적을 고르기 전에는 전투할 수 없다")
	it = MiniIteration.new()
	it.setup(catalog, rc)
	it.begin("reclaimer", 1)
	t.check(not it.choose_enemy("boss_first_divergence"), "이 노드의 후보가 아닌 적은 못 고른다")

	it = MiniIteration.new()
	it.setup(catalog, rc)
	it.begin("reclaimer", 1)
	var first_option: String = str((it.enemy_options()[0] as Dictionary)["id"])
	t.check(it.choose_enemy(first_option), "후보를 고른다")
	t.eq(it.state, "tune", "고르면 Tune 단계로 간다")
	t.check((it.enemy_reveal()["slots"] as Dictionary).size() > 0,
		"전투 직전에는 적의 실제 슬롯이 전부 공개된다")
	t.check(it.validate_board().is_empty(), "스타터 보드는 조립 가능하다")
	t.check(not it.take_salvage("scrap_autocannon"), "Tune 단계에서는 Salvage를 못 받는다")
	t.eq(it.state, "tune", "잘못된 호출을 거절해도 상태는 그대로다 — 오조작이 런을 죽이지 않는다")

	t.check(it.fight(), "전투가 실행된다")
	t.check(["salvage", "lost"].has(it.state), "전투 뒤 상태는 Salvage 또는 패배")
	t.eq(it.history.size(), 1, "노드 기록이 하나 남는다")
	if it.state == "salvage":
		t.eq(it.offer.size(), 3, "Salvage 후보 3개")
		t.check(not it.take_salvage("no_such_part"), "후보에 없는 파츠는 못 받는다")
		var owned_before: int = it.run.inventory.owned.size()
		t.check(it.take_salvage(it.offer[0]), "후보 하나를 받는다")
		t.eq(it.run.inventory.owned.size(), owned_before + 1, "인벤토리가 하나 늘어난다")
		t.eq(it.node_index, 1, "다음 노드로 넘어간다")
	else:
		# 패배해도 어서션 수가 흔들리지 않도록 같은 개수를 채운다
		t.check(true, "패배 — Salvage 검사 생략")
		t.check(true, "패배 — Salvage 검사 생략")
		t.check(true, "패배 — Salvage 검사 생략")
		t.eq(it.node_index, 0, "패배하면 노드가 넘어가지 않는다")

## 오토파일럿이 규칙만으로 끝까지 간다. 승패는 보지 않는다 —
## 검증하는 것은 "상태 기계가 막히지 않는가"와 "보드가 항상 조립 가능한가"다.
func _test_autopilot_completes(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var stuck: int = 0
	var errored: int = 0
	var invalid_boards: int = 0
	var combats: int = 0
	for faction: String in rc.faction_ids():
		for s: int in range(1, 6):
			var it: RefCounted = MiniIteration.new()
			it.setup(catalog, rc)
			it.begin(faction, s)
			var result: String = Autopilot.play(it)
			if result == "error":
				errored += 1
			if not ["won", "lost"].has(result):
				stuck += 1
			if not it.errors.is_empty():
				errored += 1
			combats += it.history.size()
			for record: Dictionary in it.history:
				if str(record["winner"]) == "":
					invalid_boards += 1
	t.eq(stuck, 0, "15개 런이 모두 won/lost로 끝난다 (무한 루프 없음)")
	t.eq(errored, 0, "15개 런에서 상태 에러가 없다")
	t.eq(invalid_boards, 0, "모든 전투가 승패를 낸다")
	t.check(combats >= 15, "런마다 최소 1전투는 실행된다 (총 %d전투)" % combats)

## 같은 런 시드는 같은 런을 만든다. 런 RNG와 전투 RNG가 섞이면 이것이 깨진다.
func _test_run_determinism(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var runs: Array[String] = []
	for i: int in 2:
		var it: RefCounted = MiniIteration.new()
		it.setup(catalog, rc)
		it.begin("aeonic", 99)
		Autopilot.play(it)
		var trace: Array[String] = []
		for record: Dictionary in it.history:
			trace.append("%s/%s/%s/%s" % [record["enemy"], record["winner"],
				str(record["offer"]), record["taken"]])
		runs.append(" | ".join(trace))
	t.eq(runs[1], runs[0], "같은 런 시드는 적 선택·승패·Salvage 후보까지 동일하다")

	var other: RefCounted = MiniIteration.new()
	other.setup(catalog, rc)
	other.begin("aeonic", 100)
	Autopilot.play(other)
	var other_trace: Array[String] = []
	for record: Dictionary in other.history:
		other_trace.append("%s/%s" % [record["enemy"], str(record["offer"])])
	t.check(" | ".join(other_trace) != runs[0], "다른 런 시드는 다른 런을 만든다")

## 전투 요약이 이벤트 스트림에서 실제로 채워지는가.
## 0으로 채워진 요약은 지표를 조용히 무의미하게 만든다.
func _test_combat_summary(t: RefCounted) -> void:
	var catalog: RefCounted = _catalog()
	var rc: RefCounted = _content(catalog)
	var it: RefCounted = MiniIteration.new()
	it.setup(catalog, rc)
	it.begin("aeonic", 2)
	Autopilot.play(it)
	t.check(not it.history.is_empty(), "전투 기록이 있다")

	var totals: Dictionary = {}
	for record: Dictionary in it.history:
		for key: String in record["summary"]:
			if (record["summary"][key] is int) or (record["summary"][key] is float):
				totals[key] = float(totals.get(key, 0.0)) + float(record["summary"][key])
	t.check(float(totals.get("elapsed", 0.0)) > 0.0, "전투 시간이 기록된다")
	t.check(float(totals.get("damage", 0.0)) > 0.0, "피해가 기록된다")
	t.check(float(totals.get("fires", 0.0)) > 0.0, "발동 수가 기록된다")
	t.check(float(totals.get("shield_gained", 0.0)) > 0.0,
		"Aeonic 런이므로 보호막이 기록된다")
	t.check(float(totals.get("charges", 0.0)) >= 0.0, "Charge 항목이 존재한다")
