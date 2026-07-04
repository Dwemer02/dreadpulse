extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

const Catalog := preload("res://sim/parts_catalog.gd")
const Ship := preload("res://sim/ship_state.gd")
const Pulse := preload("res://sim/pulse_network.gd")
const Sim := preload("res://sim/combat_sim.gd")

const B_GUN := {"name": "gun", "parts": [
	{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
	{"id": "t1", "type": "main_turret"}],
	"wires": [["heart", "b1"], ["b1", "t1"]]}
const B_IDLE := {"name": "idle", "parts": [
	{"id": "heart", "type": "heart"}, {"id": "a1", "type": "armor_bulkhead"}],
	"wires": [["heart", "a1"]]}

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("unit result: %d passed / %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_harness()
	_test_catalog()
	_test_ship()
	_test_pulse()
	_test_combat_core()
	_test_support_effects()
	_test_growth_effects()

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)

func _test_harness() -> void:
	check(true, "harness boots")

func _test_catalog() -> void:
	var b := Catalog.get_def("boiler")
	check(not b.is_empty(), "boiler exists")
	check(b.kind == "steel" and int(b.required_charge) == 2, "boiler def fields")
	var adr := Catalog.get_def("main_turret", "nerve")
	check(adr.name == "아드레날린 포", "graft substitutes name")
	var has_adr := false
	for e in adr.effects:
		if int(e.type) == Catalog.Effect.INTERVAL_REDUCE_ON_HIT:
			has_adr = true
	check(has_adr, "adrenaline effect present")
	check(Catalog.get_def("no_such_part").is_empty(), "unknown type -> empty")
	check(Catalog.get_def("autoloader", "nerve").is_empty(), "invalid graft -> empty")
	for t in Catalog.PARTS:
		var d: Dictionary = Catalog.PARTS[t]
		check(d.has("kind") and d.has("hull") and d.has("effects"), "part %s complete" % t)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _mk_ship(parts: Array, wires: Array, extra: Dictionary = {}):
	var b := {"name": "test", "parts": parts, "wires": wires}
	b.merge(extra)
	var s = Ship.new()
	s.load_build(b)
	return s

func _test_ship() -> void:
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"},
		 {"id": "t1", "type": "main_turret"}, {"id": "al", "type": "autoloader"}],
		[["heart", "t1"], ["mag", "t1"], ["al", "t1"]])
	check(s.is_valid(), "valid build loads: %s" % [s.load_errors])
	check(int(s.resources.ammo) == 35, "ammo = 20 base + 15 reserve")
	check(s.heart_id() == "heart", "heart_id")
	check(s.effective_required_charge("t1") == 2, "autoloader discount 3->2")
	check(s.try_spend({"ammo": 30}) and int(s.resources.ammo) == 5, "spend ok")
	check(not s.try_spend({"steam": 1}), "spend fails on shortage")

	var bad = _mk_ship([{"id": "a", "type": "boiler"}], [])
	check(not bad.is_valid(), "missing heart rejected")
	var orphan = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "b", "type": "boiler"}], [])
	check(not orphan.is_valid(), "orphan part rejected")
	var dup = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "heart", "type": "boiler"}], [])
	check(not dup.is_valid(), "duplicate id rejected")
	var badgraft = _mk_ship(
		[{"id": "heart", "type": "heart"},
		 {"id": "x", "type": "autoloader", "graft": "nerve"}], [["heart", "x"]])
	check(not badgraft.is_valid(), "invalid graft rejected")

func _test_pulse() -> void:
	# 체인 전파: heart-a-b 모두 charge 1
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "a", "type": "boiler"},
		 {"id": "b", "type": "main_turret"}],
		[["heart", "a"], ["a", "b"]])
	var evs: Array = []
	Pulse.propagate(s, "heart", 1, _rng(1), evs, 1, 0)
	check(s.parts.a.charge == 1 and s.parts.b.charge == 1, "chain propagation")
	check(s.parts.heart.charge == 0, "origin gets no charge")

	# 낭포: 흡수하고 하류 차단
	var c = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "cy", "type": "cyst"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "cy"], ["cy", "t"]])
	Pulse.propagate(c, "heart", 1, _rng(1), [], 1, 0)
	check(c.parts.cy.stored_pulses == 1 and c.parts.cy.charge == 0, "cyst stores")
	check(c.parts.t.charge == 0, "cyst blocks downstream")

	# 파괴 부품은 전도하지 않음
	var d = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "m", "type": "boiler"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "m"], ["m", "t"]])
	d.parts.m.hull = 0
	Pulse.propagate(d, "heart", 1, _rng(1), [], 1, 0)
	check(d.parts.t.charge == 0, "destroyed part does not conduct")

	# 신경절: 결정론적 복제, 200회에서 25% 근방
	var g = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "g1", "type": "ganglion"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "g1"], ["g1", "t"]])
	var rng_a := _rng(7)
	for i in 200:
		Pulse.propagate(g, "heart", 1, rng_a, [], i, 0)
	var extra: int = g.parts.t.charge - 200
	check(extra >= 25 and extra <= 80, "ganglion ~25%% replication (got +%d)" % extra)
	# 같은 시드로 재실행 = 같은 결과
	var g2 = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "g1", "type": "ganglion"},
		 {"id": "t", "type": "main_turret"}],
		[["heart", "g1"], ["g1", "t"]])
	var rng_b := _rng(7)
	for i in 200:
		Pulse.propagate(g2, "heart", 1, rng_b, [], i, 0)
	check(g2.parts.t.charge == g.parts.t.charge, "replication deterministic")

func _test_combat_core() -> void:
	var sim = Sim.new()
	check(sim.setup(B_GUN, B_IDLE, 42), "setup with valid builds")
	# 2.1초(42틱): 보일러(rc2)가 최소 1회 발동해 steam 생산
	var evs: Array = []
	for i in 42:
		evs.append_array(sim.step())
	var produced := false
	var fired := false
	for e in evs:
		if e.type == "part_fired" and e.side == 0 and e.part == "b1":
			produced = true
		if e.type == "part_fired" and e.side == 0 and e.part == "t1":
			fired = true
	check(produced, "boiler produced steam")
	# 주포: rc3 = 3펄스 = 3초 시점. 42틱(2.1s)에는 미발동, steam1+ammo1 필요.
	check(not fired, "turret not yet at 2.1s")
	# 끝까지: gun이 idle을 격침
	var r = sim.run_to_end()
	check(r.winner == 0, "gun defeats idle (winner=%s reason=%s)" % [r.winner, r.reason])
	check(sim.ships[1].hull <= 0 or r.reason == "timeout", "defender dead or timeout")

	# 불발: 보일러 없는 포탑, steam 없음 → misfire 이벤트, charge 유지
	var starving := {"name": "starve", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "t1"]]}
	var sim2 = Sim.new()
	sim2.setup(starving, B_IDLE, 42)
	var evs2: Array = []
	for i in 70:
		evs2.append_array(sim2.step())
	var misfired := false
	for e in evs2:
		if e.type == "misfire" and e.side == 0:
			misfired = true
	check(misfired, "misfire on steam shortage")
	check(sim2.ships[0].parts.t1.charge >= 3, "misfire keeps charge")

	# 결정론: 같은 시드 = 같은 결과
	var ra = Sim.new(); ra.setup(B_GUN, B_GUN, 7)
	var rb = Sim.new(); rb.setup(B_GUN, B_GUN, 7)
	var res_a = ra.run_to_end()
	var res_b = rb.run_to_end()
	check(res_a.ticks == res_b.ticks and res_a.hull_a == res_b.hull_a
		and res_a.hull_b == res_b.hull_b and res_a.winner == res_b.winner,
		"determinism: same seed same outcome")

	# ichor: 함체 피격 시 양측 +1
	check(int(sim.ships[0].resources.ichor) > 0 or int(sim.ships[1].resources.ichor) > 0,
		"ichor accumulates on hits")

func _test_support_effects() -> void:
	# 탄약고 버프: 8+2=10 피해
	var gunner := {"name": "g", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "mag", "type": "magazine"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["mag", "t1"]]}
	var sim = Sim.new()
	sim.setup(gunner, B_IDLE, 42)
	var evs: Array = []
	for i in 200:
		evs.append_array(sim.step())
	var buffed := false
	for e in evs:
		if e.type == "damage_dealt" and e.side == 0 and int(e.amount) == 10:
			buffed = true
	check(buffed, "magazine adjacency buff +2")

	# 눈알 조준: 적 탄약고 저격 → 파괴 → 유폭 explosion(kind=magazine)
	var sniper := {"name": "s", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "ey", "type": "eye"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["heart", "ey"], ["ey", "t1"]]}
	var victim := {"name": "v", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"}],
		"wires": [["heart", "mag"]]}
	var sim2 = Sim.new()
	sim2.setup(sniper, victim, 42)
	var evs2: Array = []
	for i in 400:
		if sim2.ended:
			break
		evs2.append_array(sim2.step())
	var sniped := false
	var detonated := false
	for e in evs2:
		if e.type == "damage_dealt" and e.side == 0 and e.get("target_part", "") == "mag":
			sniped = true
		if e.type == "explosion" and e.get("kind", "") == "magazine" and e.side == 1:
			detonated = true
	check(sniped, "eye targets enemy magazine")
	check(detonated, "magazine destruction detonates own ship")

	# 장갑 흡수: 부품 조준 피해 30% 흡수
	var armored := {"name": "a", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"},
		{"id": "ar", "type": "armor_bulkhead"}],
		"wires": [["heart", "mag"], ["ar", "mag"]]}
	var sim3 = Sim.new()
	sim3.setup(sniper, armored, 42)
	var evs3: Array = []
	for i in 200:
		if sim3.ended:
			break
		evs3.append_array(sim3.step())
	var absorbed := false
	for e in evs3:
		if e.type == "damage_dealt" and e.get("absorbed", false):
			absorbed = true
	check(absorbed, "armor absorbs part-target damage")

	# 아가미: 함 피격 피해 절반이 steam으로
	var gilled := {"name": "gl", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "gl", "type": "gills"}],
		"wires": [["heart", "gl"]]}
	var sim4 = Sim.new()
	sim4.setup(gunner, gilled, 42)
	for i in 200:
		if sim4.ended:
			break
		sim4.step()
	check(int(sim4.ships[1].resources.steam) > 0, "gills convert damage to steam")

	# 자동장전기: rc3-1=2 → 2펄스(약 2초) 시점에 첫 발사 가능
	var fastgun := {"name": "f", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "al", "type": "autoloader"}, {"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["b1", "t1"], ["al", "t1"]]}
	var sim5 = Sim.new()
	sim5.setup(fastgun, B_IDLE, 42)
	var first_fire_tick := -1
	for i in 200:
		for e in sim5.step():
			if e.type == "part_fired" and e.side == 0 and e.part == "t1" and first_fire_tick < 0:
				first_fire_tick = e.tick
	check(first_fire_tick > 0 and first_fire_tick * Sim.TICK_DT <= 2.5,
		"autoloader accelerates first shot (%.2fs)" % (first_fire_tick * Sim.TICK_DT))

func _test_growth_effects() -> void:
	# 촉수: 스택으로 피해 증가 (3, 4, 5, ...)
	var biter := {"name": "bt", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "tc", "type": "tentacle"}],
		"wires": [["heart", "tc"]]}
	var sim = Sim.new()
	sim.setup(biter, B_IDLE, 42)
	var dmgs: Array = []
	for i in 200:
		if sim.ended:
			break
		for e in sim.step():
			if e.type == "damage_dealt" and e.side == 0:
				dmgs.append(int(e.amount))
	check(dmgs.size() >= 3 and dmgs[0] == 3 and dmgs[1] == 4 and dmgs[2] == 5,
		"tentacle permanent stacks (%s)" % [dmgs.slice(0, 3)])

	# 아드레날린 포: interval 감소, 하한 0.5, 하한 이후 과부하 자해
	var adren := {"name": "ad", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"}, {"id": "mag", "type": "magazine"},
		{"id": "t1", "type": "main_turret", "graft": "nerve"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["b1", "t1"], ["mag", "t1"]]}
	var big_idle := {"name": "bi", "ship_hull": 3000, "parts": [
		{"id": "heart", "type": "heart"}, {"id": "a1", "type": "armor_bulkhead"}],
		"wires": [["heart", "a1"]]}
	var sim2 = Sim.new()
	sim2.setup(adren, big_idle, 42)
	var overloaded := false
	var min_interval := 1.0
	for i in 6000:
		if sim2.ended:
			break
		for e in sim2.step():
			if e.type == "interval_changed":
				min_interval = minf(min_interval, float(e.interval))
			if e.type == "explosion" and e.get("kind", "") == "overload":
				overloaded = true
	check(min_interval <= 0.55, "adrenaline reduces interval (min %.2f)" % min_interval)
	check(sim2.ships[0].pulse_interval >= 0.5, "interval floor respected")
	check(overloaded, "overload self-damage past floor")

	# 증기터빈: steam 3 소모 → 추가 펄스 (pulse_emitted origin=heart 증가)
	var turbo := {"name": "tb", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"}, {"id": "b3", "type": "boiler"},
		{"id": "st", "type": "steam_turbine"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["heart", "b3"], ["heart", "st"]]}
	var sim3 = Sim.new()
	sim3.setup(turbo, B_IDLE, 42)
	var turbine_fired := false
	for i in 600:
		if sim3.ended:
			break
		for e in sim3.step():
			if e.type == "part_fired" and e.side == 0 and e.part == "st":
				turbine_fired = true
	check(turbine_fired, "steam turbine fires extra pulse")

	# 낭포: threshold 10 도달 시 폭발 → 적 hull 30 감소 (10*3)
	var cystic := {"name": "cy", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "cy", "type": "cyst"}],
		"wires": [["heart", "cy"]]}
	var sim4 = Sim.new()
	sim4.setup(cystic, B_IDLE, 42)
	var cyst_boom := false
	for i in 300:
		if sim4.ended:
			break
		for e in sim4.step():
			if e.type == "explosion" and e.get("kind", "") == "cyst" and int(e.amount) == 30:
				cyst_boom = true
	check(cyst_boom, "cyst explodes at threshold for stored*3")

	# 유폭 심장(magazine+cyst): 임계 6 도달 시 연결 포탑 강제 일제사격
	var alpha := {"name": "al", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"},
		{"id": "b2", "type": "boiler"},
		{"id": "dh", "type": "magazine", "graft": "cyst"},
		{"id": "t1", "type": "main_turret"}],
		"wires": [["heart", "b1"], ["heart", "b2"], ["heart", "dh"], ["dh", "t1"]]}
	var sim5 = Sim.new()
	sim5.setup(alpha, B_IDLE, 42)
	var all_fire := false
	for i in 600:
		if sim5.ended:
			break
		for e in sim5.step():
			if e.type == "explosion" and e.get("kind", "") == "all_fire":
				all_fire = true
	check(all_fire, "detonation heart triggers all-fire")

	# 부심장 공명: resonance 이벤트 + power 2 pulse_emitted
	var twin := {"name": "tw", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "ah", "type": "ancillary_heart"},
		{"id": "b1", "type": "boiler"}],
		"wires": [["heart", "ah"], ["heart", "b1"]]}
	var sim6 = Sim.new()
	sim6.setup(twin, B_IDLE, 42)
	var resonance := false
	var power2 := false
	for i in 1200:
		if sim6.ended:
			break
		for e in sim6.step():
			if e.type == "resonance" and e.side == 0:
				resonance = true
			if e.type == "pulse_emitted" and e.side == 0 and int(e.power) == 2:
				power2 = true
	check(resonance and power2, "ancillary heart resonance (res=%s p2=%s)" % [resonance, power2])
