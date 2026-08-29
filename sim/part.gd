extends RefCounted
## 파츠 하나의 런타임 상태.
## 정의(JSON)는 catalog가 병합해서 넣어준다 — 이 클래스는 상태만 갖는다.

const K = preload("res://sim/sim_const.gd")

# --- 정체 (catalog가 채움) ---
var slot_id: String = ""
var role: String = ""
var part_id: String = ""
var part_name: String = ""
var faction: String = ""
var keywords: Array[String] = []
var augment_id: String = ""

# --- 발동 규칙 (catalog가 채움) ---
var cooldown_units: int = 0
var cost: Dictionary = {}
var on_fire: Array = []
var triggers: Array = []
## triggers와 같은 길이. max_fires 계산용 — 트리거별 전투당 발동 횟수.
var trigger_fires: Array[int] = []
## triggers와 같은 길이. every_nth_accumulated 조건이 쓰는 트리거별 누적값.
var trigger_accum: Array[int] = []

# --- 런타임 상태 ---
var progress_units: int = 0
var accel_ticks: int = 0
var slow_ticks: int = 0
var fire_limit: int = K.UNLIMITED
var fires_remaining: int = K.UNLIMITED
var fires_used: int = 0
var last_fire_tick: int = -99999
var reinforce_stacks: int = 0
## 0 = 없음, K.PERMANENT = 영구, 그 외 = 남은 틱
var indestructible_ticks: int = 0
## empower 스택. 각 원소가 damage_mult 하나. 발동 시 앞에서부터 소모한다.
var empower_stacks: Array[float] = []
var broken: bool = false

# --- 쿨타임 ---

func speed_units() -> int:
	if accel_ticks != 0:
		return K.SPEED_ACCEL
	if slow_ticks != 0:
		return K.SPEED_SLOW
	return K.SPEED_NORMAL

## 한 틱 진행. 파손 상태면 쿨타임도 지속효과도 멈춘다.
func advance() -> void:
	if broken:
		return
	progress_units += speed_units()
	if accel_ticks > 0:
		accel_ticks -= 1
	if slow_ticks > 0:
		slow_ticks -= 1
	if indestructible_ticks > 0:
		indestructible_ticks -= 1

func is_ready() -> bool:
	return not broken and progress_units >= cooldown_units

# --- 가속 / 둔화 ---

func apply_accel(ticks: int) -> void:
	_apply_speed_effect(ticks, true)

func apply_slow(ticks: int) -> void:
	_apply_speed_effect(ticks, false)

## 가속과 둔화는 서로 배타적이다 — 상쇄 규칙상 둘 중 하나는 항상 0이다.
## 이 불변식을 유지하는 것이 이 함수의 유일한 책임이다.
## 영구(K.PERMANENT = -1)는 무한한 지속시간이므로 유한한 양으로 깎을 수 없고,
## 유한한 양을 아무리 쌓아도 영구를 넘어설 수 없다.
func _apply_speed_effect(ticks: int, accelerating: bool) -> void:
	var same: int = accel_ticks if accelerating else slow_ticks
	var opposite: int = slow_ticks if accelerating else accel_ticks

	if ticks == K.PERMANENT:
		if opposite == K.PERMANENT:
			# 영구끼리 맞부딪히면 서로를 지운다
			same = 0
			opposite = 0
		else:
			# 영구는 유한한 반대 효과를 전부 덮는다
			same = K.PERMANENT
			opposite = 0
	elif opposite == K.PERMANENT:
		# 영구인 반대 효과는 유한한 양에 깎이지 않는다 — 들어온 양이 전부 흡수된다
		pass
	elif same == K.PERMANENT:
		# 이미 영구다. 더 쌓을 것이 없다
		pass
	else:
		var remaining: int = ticks
		var cancel: int = mini(opposite, remaining)
		opposite -= cancel
		remaining -= cancel
		same += remaining

	if accelerating:
		accel_ticks = same
		slow_ticks = opposite
	else:
		slow_ticks = same
		accel_ticks = opposite

# --- 발동 ---

## 발동을 막는 이유. 빈 문자열이면 발동 가능.
## 자재 비용은 함선 상태가 필요하므로 ShipState가 따로 검사한다.
func block_reason(tick: int) -> String:
	if broken:
		return "broken"
	if tick - last_fire_tick < K.MIN_FIRE_TICKS:
		return "rate_cap"
	if fires_remaining == 0:
		return "fire_limit"
	return ""

## 발동 확정. 쿨타임 초과분은 이월한다.
func consume_fire(tick: int) -> void:
	fires_used += 1
	last_fire_tick = tick
	if progress_units >= cooldown_units:
		progress_units -= cooldown_units
	if fires_remaining != K.UNLIMITED:
		fires_remaining = maxi(0, fires_remaining - 1)

## 이번 발동에 적용할 피해 배율. empower 스택을 하나 소모한다.
func take_empower() -> float:
	if empower_stacks.is_empty():
		return 1.0
	return empower_stacks.pop_front()

func has_keyword(kw: String) -> bool:
	return keywords.has(kw)
