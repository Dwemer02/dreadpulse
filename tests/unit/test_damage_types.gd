extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 68

const K = preload("res://sim/sim_const.gd")
const Damage = preload("res://sim/damage.gd")
const Ship = preload("res://sim/ship_state.gd")

func _ship(material: String = "plating", hull: int = 1000) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = hull
	s.hull = hull
	s.hull_material = material
	s.thresholds = []
	s.thresholds_crossed = []
	return s

func run(t: RefCounted) -> void:
	_test_table_shape(t)
	_test_no_immunity(t)
	_test_two_layers(t)
	_test_shield_absorbs_fully(t)
	_test_determinism(t)
	_test_neutral_flag_is_off_by_default(t)
	t.done()

## 상성표의 형태 자체를 검증한다. 표가 곧 계약이므로 오타 하나가 팩션 밸런스를 뒤집는다.
func _test_table_shape(t: RefCounted) -> void:
	t.eq(K.ATTACK_TYPES.size(), 4, "공격 타입 4종")
	t.eq(K.DEFENSE_TYPES.size(), 3, "방어 타입 3종")
	t.eq(K.HULL_MATERIALS.size(), 2, "재질은 2종 — energy_shield는 재질이 아니다")

	for atk: String in K.ATTACK_TYPES:
		t.check(K.TYPE_MULT.has(atk), "%s 행이 표에 있다" % atk)
		for def_type: String in K.DEFENSE_TYPES:
			t.check((K.TYPE_MULT[atk] as Dictionary).has(def_type),
				"%s × %s 칸이 있다" % [atk, def_type])

	# physical은 상성이 없다 — 전부 분모와 같아야 한다 (안전밸브 계약)
	for def_type: String in K.DEFENSE_TYPES:
		t.eq(Damage.mult_num("physical", def_type), K.TYPE_MULT_DENOM,
			"physical × %s는 배율 1.0이다" % def_type)

	# 각 비-physical 타입은 특효 하나(6)와 약점 하나(3)를 정확히 갖는다.
	# 이것이 "자기 특효의 다음에 약하다" 순환의 형태다.
	for atk: String in ["thermal", "caustic", "energy"]:
		var strong: int = 0
		var weak: int = 0
		for def_type: String in K.DEFENSE_TYPES:
			var m: int = Damage.mult_num(atk, def_type)
			if m > K.TYPE_MULT_DENOM:
				strong += 1
			elif m < K.TYPE_MULT_DENOM:
				weak += 1
		t.eq(strong, 1, "%s는 특효가 정확히 하나다" % atk)
		t.eq(weak, 1, "%s는 약점이 정확히 하나다" % atk)

	# 알 수 없는 타입은 physical로 폴백한다 — 피해 0으로 조용히 사라지면 안 된다
	t.eq(Damage.mult_num("nonsense", "plating"), K.TYPE_MULT_DENOM,
		"알 수 없는 공격 타입은 physical로 취급한다")

## 면역과 무효는 존재하지 않는다 (GDD §3.4).
## 이것이 타입 시스템이 "화염 빌드에 화염 면역 몬스터"가 되지 않는 유일한 근거다.
func _test_no_immunity(t: RefCounted) -> void:
	for atk: String in K.ATTACK_TYPES:
		for mat: String in K.HULL_MATERIALS:
			var s: RefCounted = _ship(mat)
			var r: Dictionary = Damage.apply(s, 100, atk)
			t.check(int(r["hull_damage"]) > 0,
				"%s → %s 피해가 0이 아니다 (면역은 존재하지 않는다)" % [atk, mat])

	# 소액 다타도 막히지 않는다. 정수 나눗셈이 1 미만을 0으로 깎으면
	# 상성 불리에서 사실상 면역이 생긴다.
	var tiny: RefCounted = _ship("plating")
	t.eq(int(Damage.apply(tiny, 1, "thermal")["hull_damage"]), 1,
		"1 피해가 불리 상성(3/4)에서도 0이 되지 않는다")

## 한 번의 타격이 실드 배율과 재질 배율을 **서로 다르게** 지난다.
## 한 배율만 쓰는 버그를 잡는 것이 이 테스트의 존재 이유다.
func _test_two_layers(t: RefCounted) -> void:
	# energy: 실드 6/4(특효), 생체 3/4(약점). 두 배율이 정반대라 섞이면 반드시 티가 난다.
	var s: RefCounted = _ship("biomass")
	s.shield = 30
	var r: Dictionary = Damage.apply(s, 100, "energy")
	t.eq(int(r["shield_mult"]), 6, "energy는 실드에 특효(6/4)")
	t.eq(int(r["material_mult"]), 3, "energy는 생체에 약점(3/4)")
	t.eq(int(r["absorbed"]), 30, "실드 30을 전부 소모한다")
	# 실드 환산: 100 * 6/4 = 150 유효. 30 흡수 → 120 유효 남음.
	# 원래 단위 환산: 120 * 4/6 = 80. 생체 배율: 80 * 3/4 = 60.
	t.eq(int(r["hull_damage"]), 60,
		"실드로 소모된 몫을 원래 단위로 환산한 뒤 재질 배율을 적용한다")

	# 실드 배율이 선체까지 새면 이 값이 달라진다. 실드가 없을 때와 비교해 검증한다.
	var bare: RefCounted = _ship("biomass")
	t.eq(int(Damage.apply(bare, 100, "energy")["hull_damage"]), 75,
		"실드가 없으면 재질 배율만 걸린다 (100 * 3/4)")

	# 같은 원리를 반대 방향으로 — caustic은 실드에 약하고 장갑에 강하다
	var s2: RefCounted = _ship("plating")
	s2.shield = 10
	var r2: Dictionary = Damage.apply(s2, 40, "caustic")
	t.eq(int(r2["shield_mult"]), 3, "caustic은 실드에 약점(3/4)")
	t.eq(int(r2["material_mult"]), 6, "caustic은 장갑에 특효(6/4)")

	# 재질이 다르면 같은 타격의 선체 피해가 다르다 — 재질이 실제로 읽히는지 확인
	var plate: RefCounted = _ship("plating")
	var bio: RefCounted = _ship("biomass")
	t.check(int(Damage.apply(plate, 100, "caustic")["hull_damage"])
			> int(Damage.apply(bio, 100, "caustic")["hull_damage"]),
		"caustic은 장갑에 더 아프다 — hull_material이 실제로 반영된다")

## 실드가 전부 막으면 선체 피해는 0이다.
func _test_shield_absorbs_fully(t: RefCounted) -> void:
	var s: RefCounted = _ship("plating")
	s.shield = 500
	var r: Dictionary = Damage.apply(s, 100, "thermal")
	t.eq(int(r["hull_damage"]), 0, "실드가 다 막으면 선체 피해 0")
	t.eq(s.hull, s.max_hull, "선체가 그대로다")
	t.check(s.shield < 500, "실드는 깎였다")

	# 0과 음수는 아무것도 바꾸지 않는다
	var z: RefCounted = _ship("plating")
	z.shield = 10
	var zr: Dictionary = Damage.apply(z, 0, "energy")
	t.eq(int(zr["hull_damage"]), 0, "0 피해는 선체를 바꾸지 않는다")
	t.eq(int(zr["absorbed"]), 0, "0 피해는 실드도 바꾸지 않는다")
	t.eq(z.shield, 10, "실드 그대로")
	Damage.apply(z, -5, "energy")
	t.eq(z.hull, z.max_hull, "음수 피해도 아무것도 바꾸지 않는다")

	# 선체 하한은 0이다
	var low: RefCounted = _ship("biomass", 10)
	Damage.apply(low, 9999, "thermal")
	t.eq(low.hull, 0, "선체는 음수가 되지 않는다")

## 정수 연산이므로 같은 입력은 항상 같은 출력을 낸다.
## 부동소수 배율이었다면 이 어서션이 플랫폼에 따라 흔들릴 수 있다.
func _test_determinism(t: RefCounted) -> void:
	for atk: String in K.ATTACK_TYPES:
		var results: Array[int] = []
		for run_index: int in 3:
			var s: RefCounted = _ship("plating")
			s.shield = 37
			results.append(int(Damage.apply(s, 83, atk)["hull_damage"]))
		t.eq(results[0], results[1], "%s: 같은 입력은 같은 출력 (1==2)" % atk)
		t.eq(results[1], results[2], "%s: 같은 입력은 같은 출력 (2==3)" % atk)


## 진단용 중립 배율 플래그 (r5b 피드백 §11.1).
##
## **기본값에서 한 틱도 달라지지 않아야 한다.** 이 플래그는 리그가 재질 축의 크기를
## 재려고 combat_sim.rules로 주입하는 진단 규칙이지 게임 규칙이 아니다.
## 켜졌을 때만 모든 배율이 1.0이 된다.
func _test_neutral_flag_is_off_by_default(t: RefCounted) -> void:
	var normal: RefCounted = _ship("plating")
	t.check(not normal.neutral_damage_types, "기본값은 꺼져 있다")
	# thermal은 plating에 3/4다. 꺼져 있으면 그대로 깎여야 한다.
	var hit: Dictionary = Damage.apply(normal, 100, "thermal")
	t.eq(int(hit["hull_damage"]), 75, "꺼진 상태에서는 상성표 그대로 (thermal→plating 0.75)")
	t.eq(int(hit["material_mult"]), 3, "배율 분자도 그대로다")

	var neutral: RefCounted = _ship("plating")
	neutral.neutral_damage_types = true
	var flat: Dictionary = Damage.apply(neutral, 100, "thermal")
	t.eq(int(flat["hull_damage"]), 100, "켜면 1.0이다")
	t.eq(int(flat["material_mult"]), K.TYPE_MULT_DENOM, "분자가 분모와 같다")

	# 불리한 쪽도 함께 1.0이 되어야 한다 — 한쪽만 중립이면 그건 중립이 아니라 너프다.
	var exposed: RefCounted = _ship("plating")
	exposed.neutral_damage_types = true
	t.eq(int(Damage.apply(exposed, 100, "caustic")["hull_damage"]), 100,
		"불리한 쪽(caustic→plating 1.5)도 1.0이 된다")
