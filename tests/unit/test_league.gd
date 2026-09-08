extends RefCounted
## 자동 조립 리그의 규칙 검증. 리그 기획서 §14.
##
## **평가식과 같은 식을 여기 반복하지 않는다** (§14 첫 줄). 가중치 합을 다시 계산하는
## 테스트는 식을 두 번 쓴 것일 뿐 아무것도 검증하지 않는다. 대신 실제 위험을 다룬다:
## 불가능한 조립이 통과하는가, 초과 피해가 규칙대로 들어가는가, 후보 평가가 원본을
## 오염시키는가, 같은 시드가 같은 결과를 내는가.

const EXPECTED_CHECKS := 227

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const CombatSim = preload("res://sim/combat_sim.gd")
const Actions = preload("res://sim/actions.gd")

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const PartMeta = preload("res://league/part_meta.gd")
const Recipes = preload("res://league/recipes.gd")
const InvestmentLog = preload("res://league/investment_log.gd")
const Archive = preload("res://league/opponent_archive.gd")
const Benchmark = preload("res://league/benchmark.gd")
const EngineTrace = preload("res://league/engine_trace.gd")
const Profile = preload("res://league/build_profile.gd")
const Graph = preload("res://league/build_graph.gd")
const Evaluator = preload("res://league/build_evaluator.gd")
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
	_test_inert_units_are_not_bottlenecks(t)
	_test_potential_needs_real_supply(t)
	_test_relief_names_the_bottleneck(t)
	_test_one_shot_is_not_sustained(t)
	_test_augment_scales_with_host_speed(t)
	_test_action_condition_does_not_kill_part(t)
	_test_time_horizons_split(t)
	_test_recipe_counts_role_and_host(t)
	_test_recipe_unreachable_is_not_failure(t)
	_test_recipe_progress_is_a_level(t)
	_test_offer_stage_does_not_saturate(t)
	_test_investment_unresolved_is_not_failure(t)
	_test_reward_uses_split_by_disposition(t)
	_test_archive_is_fixed_and_diverse(t)
	_test_benchmark_separates_unresolved(t)
	_test_benchmark_margin_is_side_aware(t)
	_test_overtime_pairs_by_match(t)
	_test_inert_core_is_not_silent(t)
	_test_trigger_only_contribution_is_visible(t)
	_test_foreign_slots_are_not_ours(t)
	_test_link_root_must_be_a_fire(t)
	_test_merge_keeps_best_observation(t)
	_test_rejected_recipe_is_not_assigned(t)
	_test_candidate_legality(t)
	_test_candidates_do_not_mutate(t)
	_test_overtime_schedule(t)
	_test_overtime_ignores_triggers(t)
	_test_timeout_is_draw(t)
	_test_offer_pools(t)
	_test_result_accounting(t)
	_test_invalid_is_not_a_score(t)
	_test_errors_are_isolated(t)
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

	# 숙주 한정 트리거(is_host)는 **자기 슬롯의 본체**하고만 연결된다.
	# 이걸 무시하면 증강 하나가 보드의 모든 본체와 연결된 것으로 세어져
	# 연결 특징이 상한에 붙어버리고, 전략 사이의 차이를 못 만든다.
	var host_only: Dictionary = _meta({
		"listens": [["part_fired", "own"]], "passive": true, "host_only": true})
	var body_a: Dictionary = _meta({"emits": [["part_fired", "own"]]})
	var body_b: Dictionary = _meta({"emits": [["part_fired", "own"]]})
	var board: Dictionary = Graph.analyze([
		{"slot": "weapon_1", "part_id": "a", "body_meta": body_a,
			"augment_id": "aug", "augment_meta": host_only},
		{"slot": "weapon_2", "part_id": "b", "body_meta": body_b,
			"augment_id": "", "augment_meta": {}}])
	t.eq((board["connections"] as Array).size(), 1,
		"숙주 한정 증강은 숙주 하나와만 연결된다 (보드의 모든 본체가 아니다)")

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

# --- r5 피드백의 고정 판단 사례 (§2.4·§7.1) ---

## 효과 없는 단위는 병목이 아니다.
##
## r5에서 리그 Core(효과 없음)가 늘 "침묵 파츠"로 잡혀 dead가 1,777개 기록 전부에서
## 1 이상이었다. 그 결과 potential에 상수가 깔렸다 (피드백 §2.3.1).
func _test_inert_units_are_not_bottlenecks(t: RefCounted) -> void:
	var config: RefCounted = _content_config()
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(config, inv)   # Core만 꽂힌 보드
	var core_meta: Dictionary = (_content.meta_index["league_core"] as Dictionary)["body"]
	t.check(bool(core_meta["inert"]), "효과 없는 Core는 inert로 표시된다")

	var alone: Dictionary = Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index), 5)
	t.eq((alone["units"] as Array).size(), 0, "평가 단위에 들어가지 않는다")
	t.eq((alone["dead"] as Array).size(), 0, "따라서 침묵 파츠로도 세지 않는다")

	inv.place("weapon_1", inv.add("scrap_autocannon"))
	var working: Dictionary = Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index), 5)
	t.eq((working["dead"] as Array).size(), 0,
		"자족 무기 하나만 있는 보드의 dead는 0이다 — r5에서는 1이었다")

## potential은 **작동하지 않는 상태 자체**가 아니라, 실제로 열릴 수 있는 연결을 센다.
##
## r5에서는 potential = min(dead/4, 1)이 1,769/1,777 기록에서 성립했다. 즉 침묵
## 파츠를 늘리는 것만으로 미래 가치가 올랐다 (피드백 §2.2).
func _test_potential_needs_real_supply(t: RefCounted) -> void:
	# 가압 산성포는 자재를 요구한다. 보드는 그대로 두고 **공급 정보만** 바꾼다.
	var board: RefCounted = _pair_board("acid_jet_cutter", "pressurized_acid_cannon")
	var none: float = _potential(board, {})
	var pool: float = _potential(board, {"material": 0.15})
	var stored: float = _potential(board, {"material": 1.0})
	t.check(is_zero_approx(none),
		"이 풀에서 구할 수 없는 병목은 미래 가치가 0이다 (%.3f)" % none)
	t.check(pool > none and stored > pool,
		"근접도가 오르면 미래 가치도 오른다 — 없음 %.3f < 풀 %.3f < 창고 %.3f"
			% [none, pool, stored])

	# **침묵 장치를 추가하는 것만으로 자동 상승하지 않는다** (§2.4).
	# 두 조건으로 갈라 본다 — 공급이 없을 때와, 풀에 있을 때.
	var base: RefCounted = _pair_board("scrap_autocannon", "")
	var with_idle: RefCounted = _pair_board("scrap_autocannon", "acid_extractor")

	# (1) 그 병목을 이 풀에서 구할 수 없으면 상승이 **전혀** 없다.
	var no_corrosion: Dictionary = {"material": 0.5}
	t.check(is_equal_approx(_potential(with_idle, no_corrosion),
			_potential(base, no_corrosion)),
		"부식을 구할 수 없는 풀에서는 부식 소비기를 넣어도 미래 가치가 그대로다")

	# (2) 풀에서 구할 수 있으면 오르지만, **옛 판본의 dead/4 = 0.25보다 훨씬 작다.**
	# 근접도(풀 비중)와 열렸을 때의 가치를 함께 곱하기 때문이다.
	var realistic: Dictionary = {"corrosion": 0.15, "material": 0.15}
	var rise: float = _potential(with_idle, realistic) - _potential(base, realistic)
	t.check(rise > 0.0 and rise < 0.1,
		"풀에 공급이 있으면 조금 오른다 — 옛 판본의 0.25와 달리 %.3f" % rise)

## relief는 **어떤 병목이 사라졌는지** 이름으로 남아야 한다.
##
## r5에서는 침묵 파츠 개수의 감소를 셌다. 그러면 침묵 파츠를 그냥 빼도 병목이 풀린
## 것으로 세어지고, 병목을 풀면서 다른 침묵 장치를 넣으면 상쇄되어 0이 된다 (§2.3.4).
func _test_relief_names_the_bottleneck(t: RefCounted) -> void:
	var supply: Dictionary = {"material": 0.5, "corrosion": 0.5}
	var before: RefCounted = _pair_board("acid_jet_cutter", "pressurized_acid_cannon")
	var a: Dictionary = _analyze_with(before, supply)
	t.eq(int((a["missing"] as Dictionary).get("material", 0)), 1, "자재 병목이 하나 있다")

	# 공급기를 넣으면 그 이름이 해소 목록에 남는다.
	var fixed: RefCounted = _pair_board("acid_jet_cutter", "pressurized_acid_cannon")
	fixed.place("flex_2", fixed.add("scrap_compactor"))
	var f: Dictionary = Evaluator.features(a, _analyze_with(fixed, supply), 0.4, "")
	t.check((f["resolved"] as Array).has("material"),
		"해소된 병목이 이름으로 남는다: %s" % str(f["resolved"]))
	t.check(float(f["relief"]) > 0.0, "relief가 오른다")

	# 다른 침묵 장치를 넣는 것만으로는 아무 병목도 해소되지 않는다.
	var noise: RefCounted = _pair_board("acid_jet_cutter", "pressurized_acid_cannon")
	noise.place("flex_2", noise.add("acid_extractor"))
	var f2: Dictionary = Evaluator.features(a, _analyze_with(noise, supply), 0.4, "")
	t.eq((f2["resolved"] as Array).size(), 0,
		"침묵 장치를 하나 더 넣는 것은 병목 해소가 아니다")
	t.check(is_zero_approx(float(f2["relief"])), "relief도 오르지 않는다")

	# **두 공식이 갈라지는 자리다.** 병목을 풀면서 동시에 다른 침묵 장치를 넣으면
	# 침묵 파츠 **개수**는 그대로다 — 개수 차이로 재면 해소가 0으로 상쇄된다.
	# 이름으로 재야 "자재는 실제로 풀렸다"가 남는다.
	var both: RefCounted = _pair_board("acid_jet_cutter", "pressurized_acid_cannon")
	both.place("flex_2", both.add("scrap_compactor"))    # 자재 병목 해소
	# 야전 재조립기는 **파손된 아군**을 요구한다. 이 보드에는 파츠를 파괴하는 것이
	# 없으므로 계속 침묵한다 — 산성 추출기를 쓰면 안 된다(가압 산성포가 자재를 받아
	# 돌기 시작하면서 부식을 공급해 함께 살아난다).
	both.place("flex_3", both.add("field_reassembler"))
	var after_both: Dictionary = _analyze_with(both, supply)
	t.eq((after_both["dead"] as Array).size(), (a["dead"] as Array).size(),
		"침묵 파츠 개수는 변하지 않았다")
	var f3: Dictionary = Evaluator.features(a, after_both, 0.4, "")
	t.check((f3["resolved"] as Array).has("material"),
		"그래도 자재 병목은 실제로 해소됐다: %s" % str(f3["resolved"]))
	t.check(float(f3["relief"]) > 0.0,
		"개수가 같아도 relief가 오른다 — 개수 차이로 재면 0이 된다 (%.2f)"
			% float(f3["relief"]))

## 한 발 쏘고 죽는 파츠를 영구 무기보다 높게 평가하면 안 된다.
##
## r5에서 일회용 파쇄탄(물리 12/3초, 발동 뒤 자폭)의 초당 추정이 4.00이었고
## 고철 기관포(물리 6/3초, 영구)가 2.00이었다 — 선택률 1위(75%)의 이유다 (§7.1).
func _test_one_shot_is_not_sustained(t: RefCounted) -> void:
	var shredder: float = _output_of("disposable_shredder")
	var autocannon: float = _output_of("scrap_autocannon")
	t.check(bool((_content.meta_index["disposable_shredder"] as Dictionary)["body"]["one_shot"]),
		"자기 파괴가 메타데이터에 표시된다")
	t.check(shredder < autocannon,
		"일회용 고피해가 반복 공격보다 낮게 추정된다 (%.2f < %.2f)"
			% [shredder, autocannon])

	# 발동 제한도 같은 방향으로 깎인다.
	var limited: float = _output_of("forward_loan_beam")   # Energy 10 / 3초 / Fire Limit 3
	var unlimited: float = _output_of("photon_lance")      # Energy 8 / 5초 / 무제한
	t.check(limited < unlimited,
		"발동 제한 3회는 영구 무기보다 낮게 추정된다 (%.2f < %.2f)" % [limited, unlimited])

## 증강 기여는 **숙주 속도에 반비례**해야 한다 (r5b 피드백 §6.1).
##
## r5b까지는 모든 트리거 기여를 명목 4초 주기로 뭉갰다. 그래서 같은 증강을 2초 숙주와
## 7초 숙주에 붙여도 추정이 같았고, "본체를 증강으로 전환"하는 선택이 대량 발생하는데
## 그것이 유효한 전환인지 판정할 근거가 없었다.
##
## 숙주 단독 출력과 **분리해서** 재야 한다 — 합산해 보면 느린 숙주가 자기 본체 출력
## 때문에 더 높게 나와 방향이 거꾸로 보인다.
func _test_augment_scales_with_host_speed(t: RefCounted) -> void:
	# 고철 기관포의 증강은 "숙주 발동 시 물리 피해 1"이다. 숙주만 바꾼다.
	var fast: float = _augment_contribution("bone_spike_organ", "scrap_autocannon")
	var mid: float = _augment_contribution("photon_lance", "scrap_autocannon")
	var slow: float = _augment_contribution("severance_beam", "scrap_autocannon")

	t.check(fast > mid and mid > slow,
		"빠른 숙주의 증강 기여가 크다 — 3초 %.3f > 5초 %.3f > 10초 %.3f"
			% [fast, mid, slow])
	# 피해 1을 숙주 쿨타임마다 낸다 = 1/쿨타임. 정확히 그 값이어야 한다.
	t.check(is_equal_approx(snappedf(fast, 0.001), 0.333),
		"3초 숙주면 초당 1/3 (%.3f)" % fast)
	t.check(is_equal_approx(snappedf(slow, 0.001), 0.100),
		"10초 숙주면 초당 1/10 (%.3f)" % slow)

## 액션 하나에 붙은 조건이 **파츠 전체를 죽이면 안 된다**.
##
## "가속 중이면 재사용" 파츠 3종이 보드에 가속원이 없으면 통째로 침묵 처리됐다.
## 셋 다 가속 없이도 기본 효과는 정상 작동한다 — 가속은 보너스다.
## 파츠 전제는 `active.require`와 트리거 자신의 `where`뿐이다.
func _test_action_condition_does_not_kill_part(t: RefCounted) -> void:
	for part_id: String in ["layered_regen_membrane", "solar_reflector",
			"resonant_fiber_cluster"]:
		var meta: Dictionary = (_content.meta_index[part_id] as Dictionary)["body"]
		t.check((meta["conditional_ops"] as Array).has("multi_fire"),
			"%s의 조건부 재사용이 표시된다" % part_id)
		t.check(not (meta["prerequisites"] as Array).has("is_accelerated"),
			"%s의 가속 조건이 파츠 전제로 세어지지 않는다" % part_id)

		var inv: RefCounted = Inventory.new()
		_content.fresh_board(_content_config(), inv)
		var role: String = str(_content.catalog.parts[part_id]["base_role"])
		inv.place("weapon_1" if role == "weapon" else "defense_1", inv.add(part_id))
		var a: Dictionary = _analyze_with(inv, {})
		t.eq((a["dead"] as Array).size(), 0,
			"%s는 가속원이 없어도 침묵하지 않는다" % part_id)
		t.check(float(a["output"]) + float(a["sustain"]) > 0.0,
			"%s의 기본 효과가 추정에 잡힌다" % part_id)

## 초반 출력과 지속 출력을 구분해야 한다 (§6.1).
func _test_time_horizons_split(t: RefCounted) -> void:
	# 일회용: 15초 안에서는 온전하지만 60초로 보면 희석된다.
	var burst_early: float = _output_at("disposable_shredder", "output_early")
	var burst_late: float = _output_at("disposable_shredder", "output")
	t.check(burst_early > burst_late * 2.0,
		"일회용은 초반 추정이 지속 추정보다 훨씬 크다 (%.2f vs %.2f)"
			% [burst_early, burst_late])

	# 발동 제한도 같은 방향이다.
	var limited_early: float = _output_at("forward_loan_beam", "output_early")
	var limited_late: float = _output_at("forward_loan_beam", "output")
	t.check(limited_early > limited_late,
		"발동 제한 파츠도 초반이 크다 (%.2f vs %.2f)" % [limited_early, limited_late])

	# 진짜 지속 무기는 두 지평선에서 같다.
	var steady_early: float = _output_at("scrap_autocannon", "output_early")
	var steady_late: float = _output_at("scrap_autocannon", "output")
	t.check(is_equal_approx(steady_early, steady_late),
		"무제한 무기는 두 지평선이 같다 (%.2f = %.2f)" % [steady_early, steady_late])

## 고정 레시피의 완성 판정은 **역할과 숙주 관계까지** 본다 (r5b §7.3).
##
## "증강이 핵심이면 본체로 소유한 것만으로 완성 판정하지 않는다"가 그 문장이다.
## 이걸 빼면 photon_lance+fracture_engraver 엔진을 두 파츠를 각각 본체로 놓은
## 보드가 완성으로 세어지고, "반복 성공 조합"의 위험을 실제보다 낮게 본다.
func _test_recipe_counts_role_and_host(t: RefCounted) -> void:
	var rid: String = "a70_r30_photon_engine"
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	# 핵심 본체 4종을 다 놓는다. 증강 2종은 아직 없다.
	var photon: int = 0
	for pair: Array in [["weapon_1", "helios_lance"], ["flex_1", "photon_lance"],
			["flex_2", "returning_photon_shell"], ["flex_3", "scrap_autocannon"]]:
		var uid: int = inv.add(str(pair[1]))
		inv.place(str(pair[0]), uid)
		if str(pair[1]) == "photon_lance":
			photon = uid
	var body_only: Dictionary = Recipes.progress(rid, inv)
	t.eq(int(body_only["have"]), 4, "본체 4종은 세어진다")
	t.check(not bool(body_only["complete"]), "증강 2종이 없으면 완성이 아니다")

	# fracture_engraver를 **엉뚱한 숙주**에 붙인다. 개수는 맞지만 관계가 틀렸다.
	var wrong: RefCounted = inv.clone()
	wrong.place("weapon_1", int(wrong.board["weapon_1"]["active"]),
		wrong.add("fracture_engraver"))
	t.eq(int(Recipes.progress(rid, wrong)["have"]), 4,
		"숙주가 다른 증강은 세지 않는다")

	# 지정된 숙주(photon_lance)에 붙이면 센다.
	var right: RefCounted = inv.clone()
	right.place("flex_1", photon, right.add("fracture_engraver"))
	t.eq(int(Recipes.progress(rid, right)["have"]), 5,
		"지정 숙주에 붙은 증강은 세어진다")

## 도달 불가한 풀에서의 실패를 **약함의 근거로 쓰지 않는다** (§7.3).
## 그 판정이 코드에 있어야 리포트가 그 참가자를 표에서 뺄 수 있다.
func _test_recipe_unreachable_is_not_failure(t: RefCounted) -> void:
	# 세 레시피의 핵심 파츠에 Viridia가 없다 — v100은 어느 것도 못 만든다.
	t.eq(Recipes.recipe_id_for("v100"), "",
		"도달 불가한 풀에는 레시피를 배정하지 않는다")
	for pool_id: String in Config.pool_ids():
		var rid: String = Recipes.recipe_id_for(pool_id)
		if rid == "":
			continue
		t.check(Recipes.reachable_in(rid, Config.POOLS[pool_id], _content.catalog),
			"%s에 배정된 %s는 그 풀에서 전부 구할 수 있다" % [pool_id, rid])

## 진행도는 **수준**이지 증분이 아니다.
##
## 증분으로 두면 완성한 엔진을 그대로 유지하는 선택이 0점이 되어, 완성 직후
## 목표를 허무는 쪽이 이긴다. 그리고 창고 보유는 장착보다 낮아야 한다 —
## 같으면 영원히 쟁여두는 것이 최적이 된다.
func _test_recipe_progress_is_a_level(t: RefCounted) -> void:
	var rid: String = "equal_helios_pair"
	var placed: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), placed)
	placed.place("weapon_1", placed.add("helios_lance"))
	var second: int = placed.add("helios_lance")
	placed.place("flex_1", second)
	var done: Dictionary = Recipes.progress(rid, placed)
	t.check(bool(done["complete"]), "본체 2개면 완성이다")
	t.check(is_equal_approx(float(done["progress"]), 1.0),
		"완성 진행도는 1.0 (%.2f)" % float(done["progress"]))

	# 창고에 둔 것은 부분 점수만.
	var stored: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), stored)
	stored.add("helios_lance")
	stored.add("helios_lance")
	var waiting: Dictionary = Recipes.progress(rid, stored)
	t.check(not bool(waiting["complete"]), "창고에 있으면 완성이 아니다")
	t.check(float(waiting["progress"]) < float(done["progress"]),
		"보관(%.2f)은 장착(%.2f)보다 낮다"
			% [float(waiting["progress"]), float(done["progress"])])
	t.check(float(waiting["progress"]) > 0.0, "그래도 0은 아니다 — 보관은 합법이다")

	# 완성한 엔진을 그대로 유지하는 것이 허무는 것보다 높아야 한다.
	var broken: RefCounted = placed.clone()
	broken._detach(second)
	t.check(float(Recipes.progress(rid, broken)["progress"])
		< float(done["progress"]), "엔진을 허물면 진행도가 내려간다")

## 1단계 지표가 **포화하지 않는가**.
##
## 처음 판본은 "제안 파츠와 보드의 이벤트 키가 겹치는가"로 쟀고, 그것은 거의 항상
## 참이었다 — part_fired@own을 거의 모든 파츠가 내고 거의 모든 증강이 듣는다.
## 항상 참인 신호는 §5.1이 요구한 1·2·3단계의 분리를 만들어 주지 못한다.
## connection 특징이 네 전략 모두 1.00으로 포화했던 것과 같은 결함이다.
func _test_offer_stage_does_not_saturate(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	inv.place("weapon_1", inv.add("scrap_autocannon"))
	var before: Dictionary = _analyze_with(inv, {})

	var future: int = 0
	var total: int = 0
	for part_id: String in _content.catalog.parts:
		if str(_content.catalog.parts[part_id]["base_role"]) == "core":
			continue
		total += 1
		if bool(InvestmentLog.offer_stage(part_id, _content.meta_index,
				before)["future"]):
			future += 1
	t.check(total > 50, "카탈로그 전체를 훑었다 (%d종)" % total)
	t.check(future < total, "모든 파츠가 미래 연결로 잡히지는 않는다 (%d/%d)"
		% [future, total])
	t.check(float(future) / float(total) < 0.9,
		"1단계가 포화하지 않는다 (%d/%d)" % [future, total])

## **미해결을 실패로 적지 않는다** (§5.2).
## "런이 끝나 관측이 없는 보관을 투자 실패로 처리해서도 안 된다"가 그 문장이다.
func _test_investment_unresolved_is_not_failure(t: RefCounted) -> void:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	inv.place("weapon_1", inv.add("scrap_autocannon"))
	var stored_uid: int = inv.add("photon_lance")
	var analysis: Dictionary = _analyze_with(inv, {})

	var log: RefCounted = InvestmentLog.new()
	log.open(3, 2, inv, stored_uid, "storage", analysis, ["material"])
	t.eq(log.pending.size(), 1, "보관은 투자로 등록된다")
	log.finish(9)
	t.eq(log.closed.size(), 1, "런이 끝나면 결론이 난다")
	t.eq(str((log.closed[0] as Dictionary)["outcome"]), "unresolved",
		"관측이 끝난 보관은 미해결이다 — 실패가 아니다")

	# 즉시 도는 파츠를 장착한 것은 투자가 아니다. 회수율이 희석되면 안 된다.
	var immediate: RefCounted = InvestmentLog.new()
	immediate.open(1, 1, inv, int(inv.board["weapon_1"]["active"]), "body",
		analysis, [])
	t.eq(immediate.pending.size(), 0, "이미 도는 장착은 투자로 세지 않는다")

	# 실제 발동이 관측되면 미해결이 아니라 기여로 닫는다.
	var paid: RefCounted = InvestmentLog.new()
	var fired: RefCounted = inv.clone()
	fired.place("flex_1", stored_uid)
	paid.open(3, 2, fired, stored_uid, "storage", _analyze_with(fired, {}),
		["material"])
	t.eq(paid.pending.size(), 1, "투자가 등록됐다")
	paid.observe_combat(4, fired,
		[{"type": "part_fired", "ship": "player", "slot": "flex_1"},
			{"type": "part_fired", "ship": "enemy", "slot": "flex_1"}], "player")
	t.eq(paid.closed.size(), 1, "발동이 관측되면 닫힌다")
	t.eq(str((paid.closed[0] as Dictionary)["outcome"]), "contributed",
		"슬롯이 실제로 발동하면 기여로 닫는다")
	t.eq(int((paid.closed[0] as Dictionary)["fires"]), 1,
		"상대 진영의 같은 슬롯 발동은 세지 않는다")

## 보상 처분을 **본체·증강·보관으로 나눠** 세는가 (§5.1의 2단계).
## 합계만 남기면 "본체 후보가 아예 없었다"와 "있었지만 낮게 평가됐다"를
## 구별할 수 없다 — r5b가 정확히 그 상태였다.
func _test_reward_uses_split_by_disposition(t: RefCounted) -> void:
	var config: RefCounted = _content_config()
	var policy: RefCounted = AssemblyPolicy.new()
	policy.setup("immediate", config)

	var inv: RefCounted = Inventory.new()
	_content.fresh_board(config, inv)
	inv.place("weapon_1", inv.add("scrap_autocannon"))
	inv.place("flex_1", inv.add("photon_lance"))
	var reward: int = inv.add("field_welder")

	var ctx: Dictionary = _ctx()
	ctx["body_slots"] = _content.body_slot_count(config)
	ctx["reward_uid"] = reward
	ctx["rng"] = Config.rng_for(["test", 1])
	var decision: Dictionary = policy.decide(inv, ctx)
	t.check(bool(decision["valid"]), "조립 가능한 상태다")
	var counts: Dictionary = decision["candidate_counts"]
	var uses: Dictionary = counts["reward_uses"]
	t.check(int(uses["body"]) > 0, "본체 후보가 세어진다 (%d)" % int(uses["body"]))
	t.check(int(uses["augment"]) > 0, "증강 후보가 세어진다 (%d)" % int(uses["augment"]))
	t.check(int(uses["storage"]) > 0, "보관 후보가 세어진다 (%d)" % int(uses["storage"]))
	t.eq(int(uses["body"]) + int(uses["augment"]) + int(uses["storage"])
		+ int(uses["gone"]), int(counts["accepted"]),
		"처분 합계가 합법 후보 수와 같다")
	t.check(["body", "augment", "storage"].has(str(decision["chosen_use"])),
		"고른 후보의 처분이 기록된다 (%s)" % str(decision["chosen_use"]))


## 고정 상대군은 **파일에 얼려져 있고 다양해야** 한다 (r5b 피드백 §8.4).
##
## 첫 판본은 스냅샷 파일 순서대로 채웠는데, 그 순서가 참가자 id 오름차순이라
## 18명 전부 즉시 전력형에 r100/v100/a100뿐이었다. 그건 "서로 다른 구조"가 아니라
## "먼저 나온 구조"다.
func _test_archive_is_fixed_and_diverse(t: RefCounted) -> void:
	var opponents: Array = Archive.load_all()
	t.check(opponents.size() >= 12, "상대군이 파일에 있다 (%d명)" % opponents.size())

	var strategies: Dictionary = {}
	var pools: Dictionary = {}
	var buckets: Dictionary = {}
	var stages: Dictionary = {}
	var finals: int = 0
	for o: Variant in opponents:
		var row: Dictionary = o
		var src: Dictionary = row["source"]
		strategies[str(src["strategy"])] = true
		pools[str(src["pool"])] = true
		buckets[str(row["bucket"])] = true
		stages[str(row["stage"])] = true
		if bool(src["was_final_round"]):
			finals += 1
	t.check(strategies.size() >= 3,
		"한 전략에서만 뽑히지 않았다 (%d종)" % strategies.size())
	t.check(pools.size() >= 5, "한 풀에서만 뽑히지 않았다 (%d종)" % pools.size())
	t.check(buckets.size() >= 10, "구조가 다양하다 (%d종)" % buckets.size())
	t.eq(stages.size(), 3, "초·중·후반이 모두 있다")
	# **상한 생존 빌드만으로 구성하지 않음** (§8.4).
	t.check(finals < opponents.size(),
		"최종 라운드 스냅샷만으로 채우지 않았다 (%d/%d)" % [finals, opponents.size()])

	# 모든 상대는 공격 수단이 있어야 한다 — 없으면 모든 검사 대상이 시간 초과로만
	# 이기므로 강도를 재지 못한다.
	for o2: Variant in opponents:
		t.check(bool(((o2 as Dictionary)["profile"] as Dictionary)["operational"]),
			"%s는 공격 수단이 있다" % str((o2 as Dictionary)["id"]))

## 시간 상한에 닿은 전투는 **미해결**이지 무승부가 아니다 (§11.2).
##
## 이걸 무승부나 패배로 세면 초과 피해를 끈 진단 조건의 승률이 규칙 때문에 낮아
## 보이고, "초과 피해가 없으면 약하다"는 거짓 결론이 나온다.
func _test_benchmark_separates_unresolved(t: RefCounted) -> void:
	var opponents: Array = Archive.load_all()
	if opponents.size() < 2:
		t.check(false, "상대군이 없어 검증할 수 없다")
		return
	# 공격이 아주 느린 보드를 만든다. 초과 피해가 없으면 120초 안에 못 끝낸다.
	var slow: Dictionary = _lone_board("regen_sac")
	var subset: Array = [opponents[0]]
	var off: Dictionary = Benchmark.run(_content.catalog, _content_config(),
		slow, subset, Benchmark.no_overtime_rules(), "off")
	t.eq(int(off["matches"]),
		int(off["wins"]) + int(off["losses"]) + int(off["draws"])
			+ int(off["unresolved"]) + int(off["errors"]),
		"모든 전투가 정확히 한 칸에 들어간다")
	t.check(int(off["unresolved"]) > 0,
		"초과 피해 없이 안 끝나는 전투가 미해결로 잡힌다 (%d판)" % int(off["unresolved"]))
	t.eq(int(off["draws"]), 0, "미해결을 무승부 칸에 넣지 않는다")
	# 승률의 분모는 결판난 전투다.
	t.eq(int(off["decided"]),
		int(off["wins"]) + int(off["losses"]) + int(off["draws"]),
		"승률 분모에 미해결이 들어가지 않는다")

## 선체 격차는 **좌우 교환을 안다** (§8.4의 "필요 시 좌우 교환").
##
## 우리가 오른쪽에 섰을 때 hulls.left를 우리 것으로 읽으면 잔여 선체가 뒤바뀐다.
##
## 첫 판본은 "강한 쪽 격차 > 0, 약한 쪽 격차 < 0"만 봤는데 **그 어서션은 버그를
## 통과시켰다.** 좌우를 무시해도 절반의 판은 우연히 맞고 나머지 절반은 0이 되어
## 부호는 그대로였기 때문이다. 부호가 아니라 **불변식**을 봐야 한다:
## 같은 대진을 양쪽에서 본 것이므로 A가 본 "내 선체"는 B가 본 "상대 선체"와 같다.
func _test_benchmark_margin_is_side_aware(t: RefCounted) -> void:
	# regen_sac은 공격 수단이 없다 — 결과가 결정적이라 시드 차이가 값을 흔들지 않는다.
	var strong: Dictionary = _lone_board("photon_lance")
	var weak: Dictionary = _lone_board("regen_sac")
	var config: RefCounted = _content_config()
	var a: Dictionary = Benchmark.run(_content.catalog, config, strong,
		[{"id": "weak", "stage": "early", "bucket": "test", "build": weak}],
		config.combat_rules(), "strong")
	var b: Dictionary = Benchmark.run(_content.catalog, config, weak,
		[{"id": "strong", "stage": "early", "bucket": "test", "build": strong}],
		config.combat_rules(), "weak")

	t.check(float(a["avg_margin"]) > 0.0,
		"강한 쪽의 격차는 양수다 (%+.1f)" % float(a["avg_margin"]))
	t.check(float(b["avg_margin"]) < 0.0,
		"약한 쪽의 격차는 음수다 (%+.1f)" % float(b["avg_margin"]))
	# 불변식 — 같은 대진을 뒤집어 본 것이다.
	t.check(absf(float(a["avg_our_hull"]) - float(b["avg_their_hull"])) < 10.0,
		"A가 본 내 선체(%.1f) = B가 본 상대 선체(%.1f)"
			% [float(a["avg_our_hull"]), float(b["avg_their_hull"])])
	t.check(absf(float(a["avg_their_hull"]) - float(b["avg_our_hull"])) < 10.0,
		"A가 본 상대 선체(%.1f) = B가 본 내 선체(%.1f)"
			% [float(a["avg_their_hull"]), float(b["avg_our_hull"])])
	t.check(float(b["avg_our_hull"]) < 10.0,
		"공격 수단이 없는 쪽의 잔여 선체는 0에 가깝다 (%.1f)" % float(b["avg_our_hull"]))
	t.check(float(a["win_rate"]) > float(b["win_rate"]), "승률도 같은 방향이다")

## 기각된 레시피는 어느 풀에도 배정되지 않는다 (§7.3).
##
## 지우지 않고 기각 표시만 남기므로, 표에서 빼는 것을 잊으면 조용히 다시 쓰인다.
func _test_rejected_recipe_is_not_assigned(t: RefCounted) -> void:
	var rejected: Array[String] = []
	for recipe_id: String in Recipes.RECIPES:
		if (Recipes.RECIPES[recipe_id] as Dictionary).has("rejected"):
			rejected.append(recipe_id)
	t.check(not rejected.is_empty(),
		"기각 기록이 남아 있다 (%s)" % str(rejected))
	for pool_id: String in Config.pool_ids():
		var assigned: String = Recipes.recipe_id_for(pool_id)
		t.check(not rejected.has(assigned),
			"%s에 기각된 레시피가 배정되지 않았다 (%s)" % [pool_id, assigned])

## 파츠 하나만 놓은 최소 보드. 벤치마크 판정을 재는 데 쓴다.
func _lone_board(part_id: String) -> Dictionary:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	var role: String = str(_content.catalog.parts[part_id]["base_role"])
	inv.place("weapon_1" if role == "weapon" else "defense_1", inv.add(part_id))
	return inv.to_build("test_%s" % part_id, _content_config().frame_id)

# --- 기여 판정과 짝별 비교 (A~G 검토 §6.2·§6.3) ---

## ON/OFF는 **짝**으로 봐야 한다. 승률만 빼면 분모가 서로 달라 "규칙과 무관하다"를
## 증명하지 못한다 — OFF에서 시간 안에 끝나지 않은 판은 OFF 승률의 분모에서 빠진다.
func _test_overtime_pairs_by_match(t: RefCounted) -> void:
	var on: Array = [
		{"opponent": "a", "seed": 1, "side": "L", "outcome": "win"},
		{"opponent": "a", "seed": 1, "side": "R", "outcome": "win"},
		{"opponent": "b", "seed": 1, "side": "L", "outcome": "win"},
		{"opponent": "c", "seed": 1, "side": "L", "outcome": "loss"},
	]
	var off: Array = [
		{"opponent": "a", "seed": 1, "side": "L", "outcome": "win"},
		{"opponent": "a", "seed": 1, "side": "R", "outcome": "loss"},
		{"opponent": "b", "seed": 1, "side": "L", "outcome": "unresolved"},
		{"opponent": "c", "seed": 2, "side": "L", "outcome": "loss"},
	]
	var paired: Dictionary = Benchmark.pair(on, off)
	t.eq(int(paired["pairs"]), 3, "짝이 맞는 판만 센다 — 시드가 다른 c는 짝이 없다")
	t.eq(int(paired["same"]), 1, "둘 다 결판나고 승패가 같은 짝")
	t.eq(int(paired["flipped"]), 1, "둘 다 결판났지만 승패가 바뀐 짝")
	t.eq(int(paired["a_only"]), 1,
		"ON에서만 결판난 짝 — **미해결을 패배로 바꾸지 않는다**")

	# 키에 좌우가 빠지면 같은 상대·시드의 두 판이 한 칸에 겹쳐 짝이 어긋난다.
	t.check(Benchmark.match_key(on[0]) != Benchmark.match_key(on[1]),
		"좌우가 다른 두 판은 다른 키다")

## 효과가 없는 리그 테스트 Core를 "침묵"으로 세면 안 된다 (검토 §6.2). 단계 G의
## 첫 판본이 후보 24개 전부를 침묵 1칸 이상으로 적은 원인이 이것이다.
##
## 그리고 **주기 발동이 없는 파츠가 안 돌았다는 것은 무기여가 아니다** — 조건을
## 못 만난 것이다. 두 사실을 같은 칸에 넣으면 "이 빌드에 죽은 자리가 있다"로 읽힌다.
func _test_inert_core_is_not_silent(t: RefCounted) -> void:
	var config: RefCounted = _content_config()
	var inv: RefCounted = _pair_board("scrap_autocannon", "waste_heat_recovery")
	var build: Dictionary = inv.to_build("trace", config.frame_id)
	var result: Dictionary = CombatAdapter.fight(_content.catalog, config,
		build, build, 4242)
	t.check(bool(result["ok"]), "추적용 전투가 돈다: %s" % str(result.get("error", "")))

	var trace: Dictionary = EngineTrace.of_combat(result["log"], "player", build,
		_content.catalog)
	var kinds: Dictionary = {}
	for slot: String in (trace["contribution"] as Dictionary):
		kinds[slot] = str(((trace["contribution"] as Dictionary)[slot]
			as Dictionary)["kind"])
	t.eq(str(kinds.get("core", "")), "inert",
		"효과가 없는 Core는 기여 판정에서 제외한다")
	t.eq(str(kinds.get("weapon_1", "")), "fired", "주기 발동이 있는 무기는 발동으로 잡힌다")
	t.eq(str(kinds.get("flex_1", "")), "waiting",
		"주기 발동이 없는 파츠는 조건 미충족이지 무기여가 아니다")
	t.check((trace["silent"] as Array).is_empty(),
		"셋 중 어느 것도 '기여 없음'이 아니다: %s" % str(trace["silent"]))

	# 카탈로그를 주지 않으면 Core도 침묵으로 떨어진다 — 그것이 옛 동작이다.
	var blind: Dictionary = EngineTrace.of_combat(result["log"], "player", build)
	t.check((blind["silent"] as Array).has("core"),
		"카탈로그 없이는 구별할 수 없다 — 그래서 단계 G가 카탈로그를 넘긴다")

## Active 발동이 없어도 트리거로 기여한 슬롯이 있다. 실측에서
## `acid_tentacle→waste_heat_recovery` 연결이 기록된 후보의 그 회수기가 같은 표의
## 침묵 칸에 들어 있었다.
func _test_trigger_only_contribution_is_visible(t: RefCounted) -> void:
	var build: Dictionary = {"id": "synthetic", "frame": "pool_frame", "slots": {
		"weapon_1": {"part": "scrap_autocannon"},
		"flex_1": {"part": "waste_heat_recovery"},
	}}
	# 발동은 무기에서만 나고, 회수기는 자원 획득 사건만 낸다.
	var log: Array = [
		{"type": "part_fired", "ship": "player", "slot": "weapon_1",
			"part_id": "scrap_autocannon", "chain_depth": 0, "chain_id": 1},
		{"type": "material_gained", "ship": "player", "slot": "flex_1",
			"amount": 1, "chain_depth": 1, "chain_id": 1},
	]
	var trace: Dictionary = EngineTrace.of_combat(log, "player", build,
		_content.catalog)
	var cells: Dictionary = trace["contribution"]
	t.eq(str((cells["flex_1"] as Dictionary)["kind"]), "reacted",
		"발동이 없어도 사건을 냈으면 반응으로 잡는다")
	t.eq(int((cells["flex_1"] as Dictionary)["outputs"]), 1,
		"자원 획득은 실제 출력으로 센다")
	t.check((trace["silent"] as Array).is_empty(), "침묵 칸은 없다")
	t.eq(int((trace["links"] as Dictionary).get("weapon_1→flex_1", 0)), 1,
		"연결은 뿌리 발동 뒤에 다른 슬롯이 한 일로 센다")

## 우리 진영으로 방출되지만 **상대의 슬롯 id**를 담는 사건이 있다
## (`overheat_cleansed`의 source_slot). 그것을 우리 기여로 세면 우리 보드에 없는
## 자리가 연결 표에 나타난다 — 실측 로그에서 "league_core → flex_2"가 찍혔다.
func _test_foreign_slots_are_not_ours(t: RefCounted) -> void:
	var build: Dictionary = {"id": "synthetic", "frame": "pool_frame", "slots": {
		"weapon_1": {"part": "scrap_autocannon"},
	}}
	var log: Array = [
		{"type": "part_fired", "ship": "player", "slot": "weapon_1",
			"part_id": "scrap_autocannon", "chain_depth": 0, "chain_id": 1},
		# 상대가 우리 과열을 제거했다. 우리 진영으로 나오지만 slot은 상대 것이다.
		{"type": "overheat_cleansed", "ship": "player", "source_slot": "flex_2",
			"stacks": 1, "chain_depth": 1, "chain_id": 1},
	]
	var trace: Dictionary = EngineTrace.of_combat(log, "player", build,
		_content.catalog)
	t.check(not (trace["contribution"] as Dictionary).has("flex_2"),
		"우리 보드에 없는 슬롯은 기여 표에 넣지 않는다")
	t.eq((trace["links"] as Dictionary).size(), 0,
		"그 사건으로 연결도 만들지 않는다")

## **뿌리는 발동이어야 한다.** 아무 depth-0 사건이나 뿌리로 삼으면 효과가 없는 Core의
## `part_fire_blocked`가 뿌리가 되어 그 뒤의 모든 사건이 "Core가 불렀다"로 세어진다.
func _test_link_root_must_be_a_fire(t: RefCounted) -> void:
	var build: Dictionary = {"id": "synthetic", "frame": "pool_frame", "slots": {
		"core": {"part": "league_core"},
		"weapon_1": {"part": "scrap_autocannon"},
		"flex_1": {"part": "regen_sac"},
	}}
	var log: Array = [
		{"type": "part_fire_blocked", "ship": "player", "slot": "core",
			"reason": "requirement", "chain_depth": 0, "chain_id": 1},
		{"type": "repaired", "ship": "player", "source_slot": "flex_1",
			"amount": 3, "chain_depth": 1, "chain_id": 1},
	]
	var trace: Dictionary = EngineTrace.of_combat(log, "player", build,
		_content.catalog)
	t.eq((trace["links"] as Dictionary).size(), 0,
		"발동이 아닌 사건은 연쇄의 뿌리가 되지 않는다")
	t.eq(str(((trace["contribution"] as Dictionary)["core"]
		as Dictionary)["kind"]), "inert",
		"막힌 기록이 있어도 효과 없는 Core는 판정 제외다")
	t.eq(str(((trace["contribution"] as Dictionary)["flex_1"]
		as Dictionary)["kind"]), "reacted",
		"실제 회복을 낸 자리는 반응으로 잡힌다")

	# 그렇다고 **발동만** 뿌리로 두면 재생 틱이 부른 연쇄를 놓친다 — 재생은
	# 발동이 아니라 지속 효과이고 자기 연쇄를 연다.
	var regen_log: Array = [
		{"type": "repaired", "ship": "player", "source_slot": "flex_1",
			"amount": 3, "chain_depth": 0, "chain_id": 2},
		{"type": "damage_dealt", "ship": "player", "source_slot": "weapon_1",
			"hull_damage": 6, "chain_depth": 1, "chain_id": 2},
	]
	var regen_trace: Dictionary = EngineTrace.of_combat(regen_log, "player",
		build, _content.catalog)
	t.eq(int((regen_trace["links"] as Dictionary).get("flex_1→weapon_1", 0)), 1,
		"실제 출력을 낸 사건은 연쇄의 뿌리가 된다")

## 한 판에서 안 돌았다고 죽은 파츠가 아니다 — 상대에 따라 조건이 안 맞았을 수 있다.
func _test_merge_keeps_best_observation(t: RefCounted) -> void:
	var quiet: Dictionary = {"fires": {}, "links": {}, "damage": {},
		"contribution": {"flex_1": {"part": "x", "kind": "silent",
			"fires": 0, "reactions": 0, "outputs": 0}}, "silent": ["flex_1"]}
	var busy: Dictionary = {"fires": {}, "links": {}, "damage": {},
		"contribution": {"flex_1": {"part": "x", "kind": "fired",
			"fires": 7, "reactions": 2, "outputs": 3}}, "silent": []}
	# **순서가 결과를 바꾸면 안 된다.** 마지막 관측을 그대로 덮어쓰는 구현은
	# [침묵, 발동] 순서에서만 맞고 [발동, 침묵]에서 틀린다 — 돌연변이 점검에서
	# 첫 판본의 이 테스트가 한 순서만 봐서 그 결함을 놓쳤다.
	for order: Array in [[quiet, busy], [busy, quiet]]:
		var merged: Dictionary = EngineTrace.merge(order)
		var cell: Dictionary = (merged["contribution"] as Dictionary)["flex_1"]
		t.eq(str(cell["kind"]), "fired",
			"어느 한 판에서라도 돌았으면 돈 것으로 센다 (순서 무관)")
		t.eq(int(cell["combats_active"]), 1, "몇 판에서 돌았는지는 따로 남는다")
		t.check((merged["silent"] as Array).is_empty(),
			"침묵은 **모든 전투에서** 아무것도 안 했을 때만 남는다")

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
	# 빈 슬롯이 여럿이어도 후보는 하나다 — 서명에 슬롯 이름이 없으므로 같은 빌드로
	# 접힌다. 남는 자리가 weapon_1 · flex ×3인데 후보가 넷이면 탐색만 네 배가 된다.
	t.eq(slots.size(), 1, "역할이 맞는 빈 자리가 여럿이어도 배치 후보는 하나로 접힌다")
	var chosen: String = slots.keys()[0]
	t.check(chosen == "weapon_1" or chosen.begins_with("flex"),
		"그 자리는 실제로 무기를 받을 수 있는 슬롯이다 (%s)" % chosen)
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

	# 서명에 슬롯 이름이 없다 — flex_2와 flex_3은 같은 빌드다.
	var here: RefCounted = inv.clone()
	var there: RefCounted = inv.clone()
	var uid: int = int((inv.owned[1] as Dictionary)["uid"])
	here.place("flex_1", uid)
	there.place("flex_2", uid)
	t.eq(Generator.signature(here), Generator.signature(there),
		"자리만 다른 같은 조립은 같은 서명이다 — 상위 3개가 같은 빌드로 채워지지 않는다")

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
		"105초에 누적 103.5%%가 되어 양측이 함께 죽는다 (%.1f초)"
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

## 승점·손실·탈락 회계 (§8.3·§14).
##
## 무승부를 통계에서 패배와 합치지 않으면서 탈락 계산에는 같은 비용을 매기는 것,
## 그리고 탈락한 참가자에게 보상이 더 가지 않는 것이 여기서 갈린다.
func _test_result_accounting(t: RefCounted) -> void:
	var runner: RefCounted = _runner()

	var winner: Dictionary = _participant()
	runner._apply_result(winner, true, false, 1)
	t.eq(int(winner["points"]), 1, "승리는 승점 +1")
	t.eq(int(winner["losses"]), 0, "승리는 손실을 늘리지 않는다")

	var drawer: Dictionary = _participant()
	runner._apply_result(drawer, false, true, 1)
	t.eq(int(drawer["points"]), 0, "무승부는 승점을 주지 않는다")
	t.eq(int(drawer["losses"]), 1, "탈락 계산에는 패배와 같은 비용이다")

	# 손실이 상한에 닿으면 그 자리에서 탈락한다. 상태가 바뀌어야 다음 라운드의
	# 보상 지급 루프가 이 참가자를 건너뛴다 (§3.2의 "종료한 참가자에게 지급하지 않는다").
	var doomed: Dictionary = _participant()
	for i: int in runner.config.loss_limit:
		runner._apply_result(doomed, false, false, 1)
	t.eq(str(doomed["status"]), "eliminated", "손실 %d회면 탈락" % runner.config.loss_limit)
	t.eq(int(doomed["end_round"]), 1, "탈락 라운드가 기록된다")

	var acquired_before: int = int(doomed["acquisitions"])
	# 탈락자는 active가 아니므로 보상 루프가 건너뛴다. 그 조건을 그대로 확인한다.
	t.check(str(doomed["status"]) != "active", "탈락자는 더 이상 active가 아니다")
	t.eq(int(doomed["acquisitions"]), acquired_before, "탈락 처리 자체가 보상을 주지 않는다")

	# 마지막 라운드에서 손실이 차면 상한 생존이 아니라 탈락이 우선한다 (§3.2 마지막).
	var last: Dictionary = _participant()
	for j: int in runner.config.loss_limit:
		runner._apply_result(last, false, false, runner.config.round_cap)
	t.eq(str(last["status"]), "eliminated", "15라운드의 4번째 손실도 탈락이 우선한다")

## 조립할 수 없는 상황을 **낮은 점수가 아니라 무효로** 표현하는가.
##
## 이것이 시작 조립 실패의 진짜 원인이었다. 초반 점수는 흔히 음수인데(빈 본체 자리·
## 공격 불능 페널티) 실패를 0점으로 돌려주면 그것이 정상 후보를 이겨서,
## 조립할 수 있는 파츠를 두고 "아무것도 안 함"을 고른다.
func _test_invalid_is_not_a_score(t: RefCounted) -> void:
	var config: RefCounted = _content_config()
	var policy: RefCounted = AssemblyPolicy.new()
	policy.setup("immediate", config)

	# 본체 3개를 요구하는데 파츠가 하나뿐이다 — 깊이 2로도 도달할 수 없다.
	var starved: RefCounted = Inventory.new()
	_content.fresh_board(config, starved)
	starved.add("scrap_autocannon")
	var ctx: Dictionary = _ctx()
	ctx["body_slots"] = _content.body_slot_count(config)
	ctx["min_bodies"] = 3
	ctx["require_operational"] = true
	ctx["rng"] = Config.rng_for(["test", 2])
	var impossible: Dictionary = policy.decide(starved, ctx)
	t.check(not bool(impossible.get("valid", false)), "조립 불가는 valid: false로 표시된다")
	t.check(float(impossible["score"]) < -1000.0,
		"점수는 정상 후보와 겨룰 수 없는 값이어야 한다 (%.1f)" % float(impossible["score"]))

	# 같은 요구를 **한 단계 안에** 채울 수 있으면 유효한 결정이 나온다.
	# (탐색 깊이가 2이므로 실제 리그처럼 매 획득마다 요구가 하나씩 늘어야 도달한다.)
	var enough: RefCounted = Inventory.new()
	_content.fresh_board(config, enough)
	enough.place("weapon_1", enough.add("scrap_autocannon"))
	enough.place("defense_1", enough.add("field_welder"))
	enough.add("regen_sac")
	var ctx2: Dictionary = ctx.duplicate()
	ctx2["rng"] = Config.rng_for(["test", 3])
	var possible: Dictionary = policy.decide(enough, ctx2)
	t.check(bool(possible.get("valid", false)), "조립할 수 있으면 valid: true다")
	t.check(float(possible["score"]) > float(impossible["score"]),
		"유효한 후보가 무효 신호를 이긴다 — 음수 점수여도 그렇다 (%.2f > %.1f)"
			% [float(possible["score"]), float(impossible["score"])])

## 오류 매치를 승리·무승부·0초 패배로 대체하지 않는다 (§8.3).
## 조용히 결과로 바꾸면 그 배치의 승률이 조용히 거짓이 된다.
func _test_errors_are_isolated(t: RefCounted) -> void:
	var config: RefCounted = _content_config()
	# Core가 빠진 빌드는 조립되지 않는다 — 실제 실행에서 났던 오류를 그대로 재현한다.
	var broken: Dictionary = {"id": "broken", "frame": config.frame_id, "slots": {}}
	var result: Dictionary = CombatAdapter.fight(_content.catalog, config, broken, broken, 1)
	t.check(not bool(result["ok"]), "조립할 수 없는 빌드는 오류로 돌아온다")
	t.eq(str(result["victory_kind"]), "simulation_error", "승리 방식이 오류로 분류된다")
	t.eq(str(result["winner"]), "", "승자를 지어내지 않는다")
	t.eq(float(result["elapsed"]), 0.0, "0초 패배로 바꾸지도 않는다")

	# 오류는 승점에도 손실에도 반영되지 않는다.
	var runner: RefCounted = _runner()
	runner.participants = [_participant(), _participant()]
	runner.participants[0]["build"] = broken
	runner.participants[1]["build"] = broken
	runner._fight(0, 1, 1, "duel")
	t.eq(int(runner.participants[0]["losses"]), 0, "오류 매치는 손실을 만들지 않는다")
	t.eq(int(runner.participants[0]["points"]), 0, "승점도 만들지 않는다")
	t.eq(runner.matches.size(), 1, "그래도 매치 기록에는 남는다 — 재현할 수 있어야 한다")
	t.check(not runner.errors.is_empty(), "오류 목록에도 남는다")

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

## 라운드 회계만 쓰는 최소 러너. 배치를 돌리지 않는다.
func _runner() -> RefCounted:
	var runner: RefCounted = preload("res://league/league_runner.gd").new()
	runner.setup(_content_config(), _content)
	return runner

func _participant() -> Dictionary:
	return {"id": 0, "strategy": "immediate", "pool": "r100", "seed": 1,
		"points": 0, "losses": 0, "status": "active", "acquisitions": 0,
		"end_round": 0, "end_reason": "", "recent_opponents": [],
		"build": {}, "history": [],
		"recipe_id": "", "recipe_reachable": false, "recipe_progress": 0.0,
		"recipe_complete_round": 0, "investments": InvestmentLog.new()}

## 파츠 하나 또는 둘을 놓은 보드. 두 번째가 빈 문자열이면 하나만 놓는다.
func _pair_board(first: String, second: String) -> RefCounted:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	for pair: Array in [["weapon_1", first], ["flex_1", second]]:
		if str(pair[1]) == "":
			continue
		inv.place(str(pair[0]), inv.add(str(pair[1])))
	return inv

func _analyze_with(inv: RefCounted, supply: Dictionary) -> Dictionary:
	return Graph.analyze(
		Generator.placed_units(inv, _content.catalog, _content.meta_index),
		_content.body_slot_count(_content_config()), supply)

func _potential(inv: RefCounted, supply: Dictionary) -> float:
	var a: Dictionary = _analyze_with(inv, supply)
	return float(Evaluator.features(a, a, 0.4, "")["potential"])

## 증강 기여만 분리한 값. 숙주 단독 출력을 빼서 구한다.
func _augment_contribution(host: String, augment: String) -> float:
	return _host_output(host, augment) - _host_output(host, "")

func _host_output(host: String, augment: String) -> float:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	var role: String = str(_content.catalog.parts[host]["base_role"])
	var slot: String = "weapon_1" if role == "weapon" else "defense_1"
	var host_uid: int = inv.add(host)
	if augment == "":
		inv.place(slot, host_uid)
	else:
		inv.place(slot, host_uid, inv.add(augment))
	return float(_analyze_with(inv, {})["output"])

## 지정한 지평선 키의 출력 추정.
func _output_at(part_id: String, key: String) -> float:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	var role: String = str(_content.catalog.parts[part_id]["base_role"])
	inv.place("weapon_1" if role == "weapon" else "defense_1", inv.add(part_id))
	return float(_analyze_with(inv, {})[key])

## 파츠 하나만 놓은 보드의 초당 출력 추정.
func _output_of(part_id: String) -> float:
	var inv: RefCounted = Inventory.new()
	_content.fresh_board(_content_config(), inv)
	var role: String = str(_content.catalog.parts[part_id]["base_role"])
	inv.place("weapon_1" if role == "weapon" else "flex_1", inv.add(part_id))
	return float(_analyze_with(inv, {})["output"])

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
		"trigger_specs": [], "one_shot": false, "fire_limit": -1,
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
