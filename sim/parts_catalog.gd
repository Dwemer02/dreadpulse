extends RefCounted
# 부품 카탈로그: 정적 데이터 + 융합(graft) 치환. 수치는 전부 플레이스홀더(스펙 §4).

enum Effect {
	PRODUCE_RESOURCE,         # {resource, amount} 발동 시 자원 생산
	FIRE_PROJECTILE,          # {damage, cost} 발동 시 발사
	ADJACENT_DAMAGE_BUFF,     # {amount} 인접 무기 피해 가산 (패시브)
	ADJACENT_CHARGE_DISCOUNT, # {amount} 인접 무기 required_charge 감소 (패시브)
	EXTRA_PULSE,              # {cost} 발동 시 심장 기점 즉시 추가 펄스
	ABSORB_ADJACENT_DAMAGE,   # {ratio} 인접 부품 피격 흡수 (패시브)
	PULSE_REPLICATE,          # {chance} 펄스 통과 시 복제 (통과형)
	PERMANENT_STACK_ON_HIT,   # {amount} 적중마다 이번 전투 피해 스택
	PART_TARGETING,           # {priority} 연결 무기에 부품 조준 부여 (패시브)
	DAMAGE_TO_RESOURCE,       # {resource, ratio} 함 피격 피해 일부를 자원으로
	STORE_PULSE,              # {threshold, explode_mult} 펄스 저장, 하류 차단
	SECOND_HEART,             # {interval} 제2 펄스원
	ON_DEATH_EXPLODE,         # {self_damage} 파괴 시 자함 유폭
	INTERVAL_REDUCE_ON_HIT,   # {amount, floor, overload_self_damage} 적중 시 박동 가속
	AMMO_RESERVE,             # {amount} 전투 시작 시 ammo 가산
	ALL_FIRE_ON_THRESHOLD,    # {} 저장 임계 도달 시 연결 포탑 일제사격
	PRODUCE_PER_HIT_TAKEN,    # {resource, per_hit} 피격 횟수 비례 생산 보너스
}

const PARTS: Dictionary = {
	"heart": {"name": "심장", "kind": "core", "hull": 20, "required_charge": 0,
		"effects": []},
	"boiler": {"name": "보일러", "kind": "steel", "hull": 15, "required_charge": 2,
		"graft_slot": true,
		"effects": [{"type": Effect.PRODUCE_RESOURCE, "resource": "steam", "amount": 1}]},
	"main_turret": {"name": "주포탑", "kind": "steel", "hull": 10, "required_charge": 3,
		"graft_slot": true,
		"effects": [{"type": Effect.FIRE_PROJECTILE, "damage": 8,
			"cost": {"steam": 1, "ammo": 1}}]},
	"magazine": {"name": "탄약고", "kind": "steel", "hull": 12, "required_charge": 0,
		"graft_slot": true,
		"effects": [
			{"type": Effect.AMMO_RESERVE, "amount": 15},
			{"type": Effect.ADJACENT_DAMAGE_BUFF, "amount": 2},
			{"type": Effect.ON_DEATH_EXPLODE, "self_damage": 20}]},
	"autoloader": {"name": "자동장전기", "kind": "steel", "hull": 10, "required_charge": 0,
		"effects": [{"type": Effect.ADJACENT_CHARGE_DISCOUNT, "amount": 1}]},
	"steam_turbine": {"name": "증기터빈", "kind": "steel", "hull": 12, "required_charge": 2,
		"effects": [{"type": Effect.EXTRA_PULSE, "cost": {"steam": 3}}]},
	"armor_bulkhead": {"name": "장갑구획", "kind": "steel", "hull": 40, "required_charge": 0,
		"effects": [{"type": Effect.ABSORB_ADJACENT_DAMAGE, "ratio": 0.3}]},
	"ganglion": {"name": "신경절", "kind": "bio", "hull": 8, "required_charge": 0,
		"effects": [{"type": Effect.PULSE_REPLICATE, "chance": 0.25}]},
	"tentacle": {"name": "촉수", "kind": "bio", "hull": 10, "required_charge": 2,
		"effects": [
			{"type": Effect.FIRE_PROJECTILE, "damage": 3, "cost": {}},
			{"type": Effect.PERMANENT_STACK_ON_HIT, "amount": 1}]},
	"eye": {"name": "눈알", "kind": "bio", "hull": 6, "required_charge": 0,
		"effects": [{"type": Effect.PART_TARGETING, "priority": "magazine"}]},
	"gills": {"name": "아가미", "kind": "bio", "hull": 10, "required_charge": 0,
		"effects": [{"type": Effect.DAMAGE_TO_RESOURCE, "resource": "steam", "ratio": 0.5}]},
	"cyst": {"name": "낭포", "kind": "bio", "hull": 12, "required_charge": 0,
		"effects": [{"type": Effect.STORE_PULSE, "threshold": 10, "explode_mult": 3}]},
	"ancillary_heart": {"name": "부심장", "kind": "bio", "hull": 15, "required_charge": 0,
		"effects": [{"type": Effect.SECOND_HEART, "interval": 1.5}]},
}

const GRAFTS: Dictionary = {
	"main_turret+nerve": {"name": "아드레날린 포",
		"effects": [
			{"type": Effect.FIRE_PROJECTILE, "damage": 8, "cost": {"steam": 1, "ammo": 1}},
			{"type": Effect.INTERVAL_REDUCE_ON_HIT, "amount": 0.05, "floor": 0.5,
				"overload_self_damage": 5}]},
	"boiler+gills": {"name": "혈압 보일러",
		"effects": [
			{"type": Effect.PRODUCE_RESOURCE, "resource": "steam", "amount": 1},
			{"type": Effect.PRODUCE_PER_HIT_TAKEN, "resource": "steam", "per_hit": 0.2}]},
	"magazine+cyst": {"name": "유폭 심장",
		"effects": [
			{"type": Effect.STORE_PULSE, "threshold": 6, "explode_mult": 0},
			{"type": Effect.ALL_FIRE_ON_THRESHOLD}]},
}

static func get_def(type: String, graft: String = "") -> Dictionary:
	if not PARTS.has(type):
		return {}
	var def: Dictionary = (PARTS[type] as Dictionary).duplicate(true)
	if graft != "":
		var key := type + "+" + graft
		if not GRAFTS.has(key) or not def.get("graft_slot", false):
			return {}
		var g: Dictionary = GRAFTS[key]
		def["name"] = g["name"]
		def["effects"] = (g["effects"] as Array).duplicate(true)
	return def
