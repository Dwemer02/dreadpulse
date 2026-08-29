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

# --- 방어와 파손 ---

func is_indestructible() -> bool:
	return indestructible_ticks == K.PERMANENT or indestructible_ticks > 0

func make_indestructible(ticks: int) -> void:
	if ticks == K.PERMANENT:
		indestructible_ticks = K.PERMANENT
	elif indestructible_ticks != K.PERMANENT:
		indestructible_ticks = maxi(indestructible_ticks, ticks)

## 파손을 시도한다. 방어 우선순위: 파괴 불가 → 보강 → 파손.
## 반환값이 그대로 이벤트의 사유가 된다: "indestructible" / "reinforce" / "broken" / "already_broken"
func try_break() -> String:
	if broken:
		return "already_broken"
	if is_indestructible():
		return "indestructible"
	if reinforce_stacks > 0:
		reinforce_stacks -= 1
		return "reinforce"
	broken = true
	return "broken"

## 파손 해제 + 쿨타임 0 재시작 + 남은 횟수 초기화
func restore() -> void:
	broken = false
	progress_units = 0
	fires_remaining = fire_limit

# --- 발동 횟수 ---

## 남은 횟수를 깎고 실제로 깎인 양을 돌려준다.
## 무제한 파츠는 이 순간 DEFAULT_FIRE_LIMIT로 수명이 확정된다.
func drain_fires(amount: int) -> int:
	if amount <= 0:
		return 0
	if fires_remaining == K.UNLIMITED:
		fire_limit = K.DEFAULT_FIRE_LIMIT
		fires_remaining = K.DEFAULT_FIRE_LIMIT
	var actual: int = mini(amount, fires_remaining)
	fires_remaining -= actual
	return actual

## 남은 횟수를 회복하고 실제 회복량을 돌려준다. 초기값을 넘지 않는다.
## 무제한 파츠는 회복 대상이 아니다.
func restore_fires(amount: int) -> int:
	if amount <= 0 or fires_remaining == K.UNLIMITED:
		return 0
	var actual: int = mini(amount, fire_limit - fires_remaining)
	fires_remaining += actual
	return actual

## 발동 제한이 걸린 파츠인가 (셀렉터용)
func is_limited() -> bool:
	return fires_remaining != K.UNLIMITED
