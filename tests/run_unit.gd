extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

const Catalog := preload("res://sim/parts_catalog.gd")
const Ship := preload("res://sim/ship_state.gd")
const Pulse := preload("res://sim/pulse_network.gd")

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
