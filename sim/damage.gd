extends RefCounted
## 타입 피해의 단일 경로. deal_damage · 과열 틱 · Corrosion 발동 · Collapse가 공유한다.
##
## 존재 이유는 **한 번의 타격이 두 배율을 지난다**는 것이다. 방어 타입 3종이
## 상성표에서 별개 열이므로, energy_shield에 걸리는 배율과 선체 재질에 걸리는 배율이
## 서로 다르다. 이 계산을 네 곳에 복사하면 반드시 어긋난다.
##
## 계산은 전부 정수다. 부동소수 배율은 드리프트를 만들고 그것이 결정론을 깬다.

const K = preload("res://sim/sim_const.gd")

## 배율 분자를 돌려준다. 알 수 없는 타입은 physical로 본다 (하한 0이 없으므로
## 저작 실수가 "피해 0"으로 조용히 나타나면 안 된다).
static func mult_num(attack_type: String, defense_type: String) -> int:
	var row: Variant = K.TYPE_MULT.get(attack_type, null)
	if not (row is Dictionary):
		row = K.TYPE_MULT[K.DEFAULT_ATTACK_TYPE]
	return int((row as Dictionary).get(defense_type, K.TYPE_MULT_DENOM))

## amount만큼의 attack_type 피해를 ship에 넣는다.
##
## 반환: {"absorbed", "hull_damage", "from", "to", "shield_mult", "material_mult"}
## ship_state.take_damage()와 같은 키를 쓴다 — 호출자가 이벤트를 그대로 만들 수 있게.
##
## 두 단계로 적용한다:
##   1) 실드 배율로 실드를 깎는다
##   2) 실드가 다 막지 못한 만큼을 **원래 단위로 환산해** 선체 재질 배율로 넣는다
##
## 2단계의 환산이 핵심이다. 환산 없이 남은 값을 그대로 넘기면 실드 배율이
## 선체에까지 새어나가 상성표가 무의미해진다.
static func apply(ship: RefCounted, amount: int, attack_type: String) -> Dictionary:
	var before: int = ship.hull
	if amount <= 0:
		return {
			"absorbed": 0, "hull_damage": 0, "from": before, "to": before,
			"shield_mult": K.TYPE_MULT_DENOM, "material_mult": K.TYPE_MULT_DENOM,
		}

	# 진단용 중립 기준(r5b 피드백 §11.1)에서는 두 배율이 모두 1.0이다.
	# 기본값에서는 이 분기가 꺼져 있어 기존 계산과 한 틱도 다르지 않다.
	var neutral: bool = bool(ship.neutral_damage_types)
	var shield_mult: int = K.TYPE_MULT_DENOM if neutral \
		else mult_num(attack_type, "energy_shield")
	var material_mult: int = K.TYPE_MULT_DENOM if neutral \
		else mult_num(attack_type, ship.hull_material)

	# 1) 실드
	var shield_effective: int = amount * shield_mult / K.TYPE_MULT_DENOM
	var absorbed: int = mini(ship.shield, shield_effective)
	ship.shield -= absorbed

	# 2) 남은 만큼을 원래 단위로 환산해 선체에
	var hull_damage: int = 0
	if absorbed < shield_effective:
		var raw_left: int = (shield_effective - absorbed) * K.TYPE_MULT_DENOM / shield_mult
		hull_damage = raw_left * material_mult / K.TYPE_MULT_DENOM
		# 하한이 0이 아니라는 계약(GDD §3.4)은 "배율이 0이 아니다"라는 뜻이다.
		# 정수 나눗셈이 1 미만을 0으로 깎는 것은 별개 문제이며, 원래 단위로 1 이상
		# 남았다면 최소 1은 들어가야 한다 — 그러지 않으면 소액 다타 빌드가
		# 상성 불리에서 완전 무력화되어 사실상 면역이 생긴다.
		if hull_damage <= 0 and raw_left > 0:
			hull_damage = 1
		ship.hull = maxi(0, ship.hull - hull_damage)
		hull_damage = before - ship.hull

	return {
		"absorbed": absorbed, "hull_damage": hull_damage,
		"from": before, "to": ship.hull,
		"shield_mult": shield_mult, "material_mult": material_mult,
	}
