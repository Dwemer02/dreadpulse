extends RefCounted
## 자동 조립 리그의 규칙 검증. 리그 기획서 §14.
##
## **평가식과 같은 식을 여기 반복하지 않는다** (§14 첫 줄). 가중치 합을 다시 계산하는
## 테스트는 식을 두 번 쓴 것일 뿐 아무것도 검증하지 않는다. 대신 실제 위험을 다룬다:
## 불가능한 조립이 통과하는가, 초과 피해가 규칙대로 들어가는가, 후보 평가가 원본을
## 오염시키는가, 같은 시드가 같은 결과를 내는가.

const EXPECTED_CHECKS := 58

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const CombatSim = preload("res://sim/combat_sim.gd")
const Actions = preload("res://sim/actions.gd")

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const PartMeta = preload("res://league/part_meta.gd")
const Graph = preload("res://league/build_graph.gd")
const Generator = preload("res://league/candidate_generator.gd")
const AssemblyPolicy = preload("res://league/assembly_policy.gd")
const OfferGenerator = preload("res://league/offer_generator.gd")
const CombatAdapter = preload("res://league/combat_adapter.gd")
const Inventory = preload("res://run/inventory.gd")

var _content: RefCounted

func run(t: RefCounted) -> void:
	_content = LeagueContent.new()
	_content.load_all()
	t.check(_content.ok(), "리그 콘텐츠가 에러 없이 로드된다: %s" % str(_content.errors))

	_test_league_core(t)
	_test_meta_covers_every_op(t)
	_test_connection_direction(t)
	_test_material_gating(t)
	_test_candidate_legality(t)
	_test_candidates_do_not_mutate(t)
	_test_overtime_schedule(t)
	_test_overtime_ignores_triggers(t)
	_test_timeout_is_draw(t)
	_test_offer_pools(t)
	_test_determinism(t)
	t.done()

# --- 콘텐츠 ---

## 리그 Core는 리그에만 있어야 한다. 본편 카탈로그로 새면 Salvage 후보에 나온다.
func _test_league_core(t: RefCounted) -> void:
	var standard: RefCounted = preload("res://sim/content.gd").load_catalog()
	t.check(not standard.parts.has("league_core"),
		"리그 Core는 본편 카탈로그에 없다 — Salvage 풀로 새지 않는다")
	t.check(_content.catalog.parts.has("league_core"), "리그 카탈로그에는 있다")
	var core: Dictionary = _content.catalog.parts["league_core"]
	t.eq((core["active"] as Dictionary).size(), 0,
		"효과가 없다 — Core 효과가 조건마다 다르면 AI 비교에 교란이 섞인다")
	t.check((core["keywords"] as Array).has("plating"), "재질은 plating")

## op이 늘었는데 메타데이터 표에 안 넣으면 그 파츠를 AI가 과소평가한다.
## 조용히 0점이 되면 "약한 파츠"와 구별되지 않는다 — 그것이 §1.1의 다섯 번째 질문이다.
func _test_meta_covers_every_op(t: RefCounted) -> void:
	var missing: Array[String] = []
	for op: String in Actions.OPS:
		if not PartMeta.OP_EFFECTS.has(op):
			missing.append(op)
	t.check(missing.is_empty(), "모든 op이 메타데이터 표에 있다 — 누락: %s" % str(missing))

	var coverage: Dictionary = PartMeta.coverage_report(_content.meta_index)
	t.eq(int(coverage["covered"]), int(coverage["total"]),
		"카탈로그 전체가 자동 추정으로 덮인다 (%s)" % str(coverage["uncovered_ops"]))

# --- 연결 판정 ---

## 같은 이벤트라도 **방향이 다르면 연결이 아니다**. 적함에 나는 과열 틱을 자함
## 스코프로 듣는 파츠는 실제 전투에서 절대 반응하지 않는다.
func _test_connection_direction(t: RefCounted) -> void:
	var emitter: Dictionary = _meta({"emits": [["overheat_applied", "enemy"]]})
	var right: Dictionary = _meta({"listens": [["overheat_applied", "enemy"]], "passive": true})
	var wrong: Dictionary = _meta({"listens": [["overheat_applied", "own"]], "passive": true})

	t.eq(_links(emitter, right), 1, "방향이 맞으면 연결로 센다")
	t.eq(_links(emitter, wrong), 0, "방향이 어긋나면 연결이 아니다")

	# 태그가 같다는 이유만으로 연결이라고 부르지 않는다 (§6).
	var same_tag: Dictionary = _meta({"listens": [["overheat_ticked", "own"]], "passive": true})
	t.eq(_links(emitter, same_tag), 0, "같은 상태이상을 다뤄도 이벤트가 다르면 연결이 아니다")

## 자재를 요구하는 파츠는 생산원이 없으면 침묵한다. 그것이 "현재 병목"이고,
## 공격 수단으로도 세면 안 된다 (§4.2).
func _test_material_gating(t: RefCounted) -> void:
	var gated: Dictionary = _meta({
		"prerequisites": ["material"], "consumes": {"material": 2},
		"damage_paths": ["direct"], "burst_output": 10, "cooldown": 2.0,
	})
	var alone: Dictionary = Graph.analyze([_unit("weapon_1", gated)])
	t.eq((alone["dead"] as Array).size(), 1, "생산원이 없으면 침묵한다")
	t.check(not bool(alone["operational"]),
		"영원히 대기하는 무기는 공격 수단이 아니다")
	t.eq(int((alone["missing"] as Dictionary).get("material", 0)), 1,
		"병목 이름이 material로 남는다")

	var producer: Dictionary = _meta({"produces": {"material": 3}, "cooldown": 5.0})
	var pair: Dictionary = Graph.analyze([
		_unit("system_1", producer), _unit("weapon_1", gated)])
	t.eq((pair["dead"] as Array).size(), 0, "생산원이 생기면 둘 다 돈다")
	t.check(bool(pair["operational"]), "그제서야 공격이 성립한다")
	t.check((pair["connections"] as Array).size() > 0, "자원 연결이 잡힌다")

	# 공급이 모자라면 그 비율만큼 기여를 낮춘다 (§5.3).
	var thin: Dictionary = _meta({"produces": {"material": 1}, "cooldown": 5.0})
	var thin_pair: Dictionary = Graph.analyze([
		_unit("system_1", thin), _unit("weapon_1", gated)])
	t.check(float(thin_pair["output"]) < float(pair["output"]),
		"공급이 소비보다 적으면 출력 추정이 낮아진다 (%.2f < %.2f)"
			% [float(thin_pair["output"]), float(pair["output"])])

# --- 조립 후보 ---

## 불가능한 Base Role 배치와 증강 숙주를 실제로 막는가 (§14).
func _test_candidate_legality(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	var weapon_uid: int = inv.add("scrap_autocannon")
	var ctx: Dictionary = _ctx()

	var actions: Array = Generator.expand(inv, ctx)
	var slots: Dictionary = {}
	for action: Dictionary in actions:
		if str(action["kind"]) == "place":
			slots[str(action["slot"])] = true
	t.check(slots.has("weapon_1"), "무기는 무기 슬롯에 놓을 수 있다")
	t.check(slots.has("flex_1"), "flexible 슬롯에도 놓을 수 있다")
	t.check(not slots.has("defense_1"), "무기를 방어 슬롯에 놓는 후보는 만들지 않는다")
	t.check(not slots.has("core"), "Core 슬롯은 후보에서 제외한다")

	# Core는 증강이 될 수 없다.
	var core_uid: int = inv.add("league_core")
	inv.place("weapon_1", weapon_uid)
	t.eq(Generator.apply(inv, {"kind": "augment", "uid": core_uid, "slot": "weapon_1"}, ctx),
		null, "Core 파츠는 증강으로 쓸 수 없다")
	t.eq(Generator.apply(inv, {"kind": "augment", "uid": weapon_uid, "slot": "weapon_1"}, ctx),
		null, "자기 자신을 자기 증강으로 쓸 수 없다")

	# 숙주당 증강 슬롯은 하나다.
	var aug_uid: int = inv.add("field_welder")
	var with_aug: RefCounted = Generator.apply(inv,
		{"kind": "augment", "uid": aug_uid, "slot": "weapon_1"}, ctx)
	t.check(with_aug != null, "빈 증강 자리에는 붙는다")
	var second: int = with_aug.add("regen_sac")
	t.eq(Generator.apply(with_aug, {"kind": "augment", "uid": second, "slot": "weapon_1"}, ctx),
		null, "이미 증강이 있는 숙주에는 두 번째를 붙일 수 없다")

## 후보 평가는 원본 상태를 바꾸지 않는다 (§5.1 마지막 문단).
## 이걸 어기면 "여러 후보를 평가했다"는 이유로 파츠가 늘거나 사라진다.
func _test_candidates_do_not_mutate(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	inv.add("scrap_autocannon")
	inv.add("field_welder")
	var owned_before: int = inv.owned.size()
	var board_before: String = Generator.signature(inv)

	var actions: Array = Generator.expand(inv, _ctx())
	t.check(actions.size() > 0, "후보가 만들어진다 (%d개)" % actions.size())
	t.eq(inv.owned.size(), owned_before, "후보를 만들어도 보유 수가 변하지 않는다")
	t.eq(Generator.signature(inv), board_before, "원본 보드도 그대로다")

	# 비어 있는 본체 자리는 낭비로 센다 (§5.1의 본체 기회비용).
	# 이게 없으면 증강이 순수 이득으로 보여 AI가 본체 자리를 비워둔 채 전부 증강으로 돌린다.
	var empty: Dictionary = Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index), 5)
	t.eq(int(empty["empty_slots"]), 5, "아무것도 안 놓으면 본체 자리 5칸이 비어 있다")
	var one: RefCounted = inv.clone()
	# owned[0]은 fresh_board가 넣은 Core다. 본체를 놓아야 하므로 무기를 집는다.
	one.place("weapon_1", int((inv.owned[1] as Dictionary)["uid"]))
	var filled: Dictionary = Graph.analyze(
		Generator.placed_units(one, _content.catalog, _content.meta_index), 5)
	t.eq(int(filled["empty_slots"]), 4, "하나 놓으면 4칸")

	# 후보들끼리도 서로의 상태를 공유하지 않는다.
	var first: RefCounted = actions[0]["result"]
	first.add("regen_sac")
	t.eq(inv.owned.size(), owned_before, "후보를 고쳐도 원본은 그대로다")

# --- 초과 피해 (§9.2) ---

## 61초 첫 틱 · 양측 동시 · 누적량이 기획서 표와 일치하는가.
func _test_overtime_schedule(t: RefCounted) -> void:
	var sim: RefCounted = _idle_combat()
	var hull_at: Dictionary = {}
	while not sim.finished and sim.tick < K.MAX_COMBAT_TICKS:
		sim.step()
		var secs: float = K.ticks_to_secs(sim.tick)
		if is_equal_approx(secs, 60.0) or is_equal_approx(secs, 61.0) \
				or is_equal_approx(secs, 70.0) or is_equal_approx(secs, 80.0):
			hull_at[int(round(secs))] = [sim.player.hull, sim.enemy.hull]

	t.eq(hull_at[60], [100, 100], "60초까지는 초과 피해가 없다 (유예 구간)")
	t.eq(hull_at[61], [100, 100], "61초 첫 틱은 0.1이라 아직 정수 선체를 깎지 못한다")
	# 누적 damage(k) = 기준선체 × 0.001 × k. 70초(k=10)면 5.5%, 80초(k=20)면 21%.
	# 소수 잔여를 버리지 않고 누적하는지를 이 두 값이 확인한다.
	t.eq(hull_at[70], [95, 95], "70초 누적 5.5% → 선체 95 (기획서 §9.2 표)")
	t.eq(hull_at[80], [79, 79], "80초 누적 21% → 선체 79")
	t.eq(hull_at[70][0], hull_at[70][1], "양측에 같은 절대량이 동시에 들어간다")

	t.eq(sim.winner, "draw", "아무도 공격하지 않으면 초과 피해로 동시 사망한다")
	t.check(is_equal_approx(K.ticks_to_secs(sim.tick), 105.0),
		"105초에 누적 103.5%가 되어 양측이 함께 죽는다 (%.1f초)"
			% K.ticks_to_secs(sim.tick))

## 초과 피해는 파츠의 피해 수신 트리거를 발동시키지 않는다 (§9.2·§14).
## 발동시키면 방어형 빌드가 초과 피해로 자기 엔진을 돌리는 역전이 생긴다.
func _test_overtime_ignores_triggers(t: RefCounted) -> void:
	var sim: RefCounted = _idle_combat()
	var watcher: RefCounted = Part.new()
	watcher.slot_id = "system_1"
	watcher.role = "system"
	watcher.passive = true
	watcher.triggers = [{"on": "overtime_damage", "do": [{"op": "gain_material", "amount": 1}]}]
	# trigger_fires/trigger_accum은 타입 지정 배열이다 — 리터럴을 그대로 대입하면
	# 타입이 맞지 않아 SCRIPT ERROR가 난다. build_loader처럼 append로 채운다.
	watcher.trigger_fires.append(0)
	watcher.trigger_accum.append(0)
	sim.player.add_part(watcher)

	while not sim.finished and sim.tick < K.MAX_COMBAT_TICKS:
		sim.step()
	t.check(sim.count_events("overtime_damage") > 0, "초과 피해 이벤트 자체는 남는다")
	t.eq(watcher.trigger_fires[0], 0, "그 이벤트를 구독해도 트리거는 돌지 않는다")
	t.eq(sim.player.material, 0, "따라서 자원도 생기지 않는다")

## 리그는 시간 초과를 무승부로 처리한다 (§8.3). 본편은 잔여 선체 비율로 가른다.
func _test_timeout_is_draw(t: RefCounted) -> void:
	var sim: RefCounted = _idle_combat()
	sim.rules = {"timeout_result": "draw"}   # 초과 피해는 끄고 시간 초과만 본다
	sim.player.hull = 80
	while not sim.finished and sim.tick < K.MAX_COMBAT_TICKS:
		sim.step()
	if not sim.finished:
		sim._finish_by_timeout()
	t.eq(sim.winner, "draw", "선체가 남아 있어도 시간 초과는 무승부다")

	var vanilla: RefCounted = _idle_combat()
	vanilla.rules = {}
	vanilla.player.hull = 80
	while not vanilla.finished and vanilla.tick < K.MAX_COMBAT_TICKS:
		vanilla.step()
	if not vanilla.finished:
		vanilla._finish_by_timeout()
	t.eq(vanilla.winner, "enemy", "규칙을 주입하지 않으면 기존대로 선체 비율로 가른다")

# --- 제안 ---

## 순수 팩션 조건에 외부 팩션이 섞이지 않는가 (§4.2).
func _test_offer_pools(t: RefCounted) -> void:
	var offers: RefCounted = OfferGenerator.new()
	offers.setup(_content.catalog, _content.meta_index, _content_config())
	t.check(offers.errors.is_empty(),
		"모든 풀에 단독 공격 가능한 파츠가 있다: %s" % str(offers.errors))

	for pool_id: String in ["r100", "v100", "a100"]:
		var expected: String = {"r100": "reclaimer", "v100": "viridia",
			"a100": "aeonic"}[pool_id]
		var wrong: int = 0
		for index: int in 30:
			for part_id: String in offers.raw_offer(pool_id, 1, index, 3):
				if str((_content.catalog.parts[part_id] as Dictionary)["faction"]) != expected:
					wrong += 1
		t.eq(wrong, 0, "%s 풀에는 %s 파츠만 나온다" % [pool_id, expected])

	# 같은 제안 안에서 동일 파츠 ID 중복 금지 (§4.3).
	var dupes: int = 0
	for index2: int in 40:
		var offer: Array = offers.raw_offer("equal", 7, index2, 3)
		var seen: Dictionary = {}
		for part_id2: Variant in offer:
			if seen.has(str(part_id2)):
				dupes += 1
			seen[str(part_id2)] = true
	t.eq(dupes, 0, "한 제안 안에 같은 파츠가 두 번 나오지 않는다")

	# 같은 풀·같은 시드면 AI가 달라도 원시 후보열은 같다 (§4.4).
	t.eq(offers.raw_offer("r70_v30", 3, 5, 3), offers.raw_offer("r70_v30", 3, 5, 3),
		"원시 후보열은 (풀, 시드, 인덱스)만으로 결정된다")
	t.check(offers.raw_offer("r70_v30", 3, 5, 3) != offers.raw_offer("r70_v30", 4, 5, 3),
		"다른 반복 시드는 다른 후보열을 낸다")

## 같은 입력·시드로 선택과 전투가 재현되는가 (§14 첫 항목).
func _test_determinism(t: RefCounted) -> void:
	var first: Dictionary = _decide_once()
	var second: Dictionary = _decide_once()
	t.eq(first["signature"], second["signature"], "같은 시드는 같은 조립을 고른다")
	t.check(is_equal_approx(float(first["score"]), float(second["score"])),
		"점수도 같다")

	var config: RefCounted = _content_config()
	var build: Dictionary = first["build"]
	var a: Dictionary = CombatAdapter.fight(_content.catalog, config, build, build, 12345)
	var b: Dictionary = CombatAdapter.fight(_content.catalog, config, build, build, 12345)
	t.check(bool(a["ok"]) and bool(b["ok"]), "전투가 정상 종료한다")
	t.eq(a["winner"], b["winner"], "같은 시드는 같은 승자")
	t.check(is_equal_approx(float(a["elapsed"]), float(b["elapsed"])), "같은 경과 시간")
	t.eq(a["hulls"], b["hulls"], "같은 잔여 선체")

	# hash()에 기대지 않는다 — 엔진 버전에 따라 값이 달라져 배치 간 비교가 조용히 깨진다.
	t.eq(Config.mix(["a", 1, "b"]), Config.mix(["a", 1, "b"]), "시드 파생은 결정론적이다")
	t.check(Config.mix(["a", 1]) != Config.mix(["a", 2]), "입력이 다르면 시드도 다르다")

# --- 보조 ---

func _content_config() -> RefCounted:
	var config: RefCounted = Config.new()
	config.repeats_per_condition = 1
	return config

func _ctx() -> Dictionary:
	return {
		"catalog": _content.catalog, "meta_index": _content.meta_index,
		"slots": _content.slots_of(_content_config()),
		"allow_augment": true, "storage_limit": 6,
	}

## 최소 메타데이터. Graph가 읽는 필드만 채운다.
func _meta(overrides: Dictionary) -> Dictionary:
	var meta: Dictionary = {
		"usable": true, "passive": false, "cooldown": 3.0,
		"produces": {}, "consumes": {}, "emits": [], "listens": [],
		"prerequisites": [], "functions": [], "damage_paths": [],
		"burst_output": 0, "burst_sustain": 0,
		"trigger_output": 0, "trigger_sustain": 0, "uncovered_ops": [],
	}
	for key: String in overrides:
		meta[key] = overrides[key]
	PartMeta._freeze(meta)
	return meta

func _unit(slot: String, meta: Dictionary) -> Dictionary:
	return {"slot": slot, "part_id": slot, "body_meta": meta,
		"augment_id": "", "augment_meta": {}}

func _links(emitter: Dictionary, listener: Dictionary) -> int:
	var analysis: Dictionary = Graph.analyze([
		_unit("weapon_1", emitter), _unit("system_1", listener)])
	return (analysis["connections"] as Array).size()

## 아무도 공격하지 않는 전투. Core만 꽂힌 두 함선이라 초과 피해만이 유일한 피해원이다.
func _idle_combat() -> RefCounted:
	var config: RefCounted = _content_config()
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(config, inv)
	var build: Dictionary = inv.to_build("idle", config.frame_id)
	var prepared: Dictionary = preload("res://sim/content.gd").prepare_builds(
		_content.catalog, build, build, 1)
	var sim: RefCounted = prepared["sim"]
	sim.rules = config.combat_rules()
	sim.setup_ready()
	return sim

## 같은 조건으로 AI 결정을 한 번 돌린다. 재현성 검사에만 쓴다.
func _decide_once() -> Dictionary:
	var config: RefCounted = _content_config()
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(config, inv)
	inv.add("scrap_autocannon")
	inv.add("field_welder")
	var policy: RefCounted = AssemblyPolicy.new()
	policy.setup("immediate", config)
	var ctx: Dictionary = _ctx()
	ctx["body_slots"] = _content.body_slot_count(config)
	ctx["min_bodies"] = 2
	ctx["require_operational"] = true
	ctx["rng"] = Config.rng_for(["test", 1])
	var decision: Dictionary = policy.decide(inv, ctx)
	return {
		"signature": Generator.signature(decision["inventory"]),
		"score": decision["score"],
		"build": decision["inventory"].to_build("probe", config.frame_id),
	}
