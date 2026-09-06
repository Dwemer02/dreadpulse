extends RefCounted
## 파츠 하나의 런타임 상태.
## 정의(JSON)는 catalog가 병합해서 넣어준다 — 이 클래스는 상태만 갖는다.

const K = preload("res://sim/sim_const.gd")

# --- 정체 (catalog가 채움) ---
var slot_id: String = ""
## 이 파츠가 꽂힌 **슬롯**의 role. `flexible`일 수 있다.
var role: String = ""
## **파츠 자신**의 Base Role. 파츠당 하나 고정이며 AUGMENT가 바꾸지 못한다.
## 슬롯 role과 다를 수 있다 — flexible 슬롯에 꽂힌 경우가 그렇다.
var base_role: String = ""
var part_id: String = ""
var part_name: String = ""
var faction: String = ""
var keywords: Array[String] = []
var augment_id: String = ""

# --- 발동 규칙 (catalog가 채움) ---
## 쿨타임을 갖지 않는 파츠. 스스로 발동하지 않고 트리거로만 작동한다 —
## "단독으로는 아무것도 하지 않는" 변환기 계열이 이것이다.
## 슬롯은 차지하며 파괴선·상태이상의 대상도 된다.
var passive: bool = false
var cooldown_units: int = 0
## 저작된 원래 쿨타임. shorten_cooldown이 cooldown_units를 줄여도 이 값은 그대로다 —
## RD08 「해체용 기폭기」가 "**기본 쿨타임**이 가장 긴 파츠"를 희생양으로 고르므로
## 현재 값과 원래 값을 구별해야 한다.
var base_cooldown_units: int = 0
var cost: Dictionary = {}
## 발동 전제. where와 같은 조건 사전이며 거짓이면 발동하지 않고 쿨타임도 소모하지 않는다.
## "조건이 안 되면 다음 주기까지 기다림"(기획서 §3.2.10)이 이것이다.
var require: Variant = null
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
## 부식 중첩. 이 파츠가 발동할 때 중첩만큼 Caustic 피해를 **소유 함선**에 준다.
## 발동해도 줄지 않고 자연 감소도 없다. 파손되면 사라진다.
var corrosion_stacks: int = 0
## 정지 남은 틱. 0보다 크면 쿨타임 진행과 발동이 멈춘다.
## 파손과 달리 **트리거는 계속 돈다** — 그러지 않으면 숙주에 걸린 AUGMENT가
## 조용히 침묵한다 (CLAUDE.md의 "조용히 죽는 효과").
var stasis_ticks: int = 0
## 0 = 없음, K.PERMANENT = 영구, 그 외 = 남은 틱
var indestructible_ticks: int = 0
## 이번 전투 동안 누적된 수치 성장. stat 이름 -> 누적값.
## 옛 empower(런타임 배율 스택)를 대신한다 — 배율이 아니라 **파츠 수치 자체**가 커진다.
## 전투마다 파츠를 새로 만들므로 초기화 지점이 따로 없다.
var growth: Dictionary = {}
## Multi-fire가 예약한 추가 발동 수. 발동 상한(초당 5회)이 간격을 벌린다.
var pending_fires: int = 0
var broken: bool = false
## 파손된 틱. oldest_broken_own이 "가장 오래 파괴되어 있던 파츠"를 고르는 데 쓴다.
var broken_at_tick: int = 0
## destroy_self가 세운 깃발. **이번 발동 묶음이 끝난 뒤** 파괴된다 —
## 즉시 파괴하면 자기 파괴 파츠의 나머지 효과와 AUGMENT가 실행되지 못한다.
var destroy_pending: bool = false
## 마지막으로 방출한 불발 사유. 같은 사유가 매 틱 반복될 때 이벤트 스팸을 막는다.
## 발동에 성공하거나 복구되면 비운다 — 다시 막히면 새 사건으로 보고해야 하기 때문이다.
var last_block_reason: String = ""

# --- 쿨타임 ---

func speed_units() -> int:
	if accel_ticks != 0:
		return K.SPEED_ACCEL
	if slow_ticks != 0:
		return K.SPEED_SLOW
	return K.SPEED_NORMAL

func is_stasised() -> bool:
	return stasis_ticks > 0

## 한 틱 진행. 파손 상태면 쿨타임도 지속효과도 멈춘다.
##
## 정지 상태도 같다 — 다만 정지 자체의 남은 시간은 흘러야 하므로 그것만 먼저 깎는다.
## 가속/둔화/파괴 불가 타이머는 함께 멈춘다: 정지가 "시간이 멈춘 상태"인데
## 그 안에서 가속이 소모되면 정지가 오히려 이득이 된다.
## 반환: 이번 틱에 정지가 풀렸으면 true. combat_sim이 stasis_ended를 방출한다 —
## 「Stasis에서 풀릴 때」를 구독하는 파츠가 다섯 종 있고, 해제는 시간이 흘러서
## 일어나는 일이라 액션 쪽에서는 관측할 수 없다.
func advance() -> bool:
	if broken:
		return false
	if stasis_ticks > 0:
		stasis_ticks -= 1
		return stasis_ticks == 0
	progress_units += speed_units()
	if accel_ticks > 0:
		accel_ticks -= 1
	if slow_ticks > 0:
		slow_ticks -= 1
	if indestructible_ticks > 0:
		indestructible_ticks -= 1
	return false

## 정지를 건다. 반환: **최초 진입**이면 true.
##
## 이미 정지한 대상에 재부여하면 지속시간만 갱신하고 진입 사건은 만들지 않는다
## (기획서 §3.2.7). 재부여를 진입으로 세면 "Stasis에 들어갈 때 Charge" 계열이
## 스스로를 되먹여 증식한다.
##
## 갱신 규칙은 가속/둔화와 같다 — 남은 시간과 새 지속시간 중 큰 값 (§3.2.8).
func apply_stasis(ticks: int) -> bool:
	if ticks <= 0:
		return false
	var was_free: bool = stasis_ticks == 0
	stasis_ticks = maxi(stasis_ticks, ticks)
	return was_free

## 쿨타임이 찼는가. **정지는 여기서 보지 않는다** — 일부러다.
##
## 정지된 파츠를 후보에서 빼버리면 _fire()에 도달하지 못해
## part_fire_blocked가 방출되지 않고, 정지가 아무 보고 없이 조용히 발동을 막는다.
## 후보로 올린 뒤 block_reason()이 "stasis"로 거절해야 이벤트 스트림에 남는다.
##
## 쿨타임 중간에 얼어붙은 파츠는 진행도가 멈추므로 애초에 준비되지 않는다.
## 그것은 "막힌" 것이 아니라 "느린" 것이므로 보고할 사건이 없다 — 의미가 맞는다.
func is_ready() -> bool:
	return not broken and not passive and progress_units >= cooldown_units

## Multi-fire가 예약한 추가 발동을 지금 쏠 수 있는가.
## 막힌 사유는 보고하지 않는다 — 큐가 시간에 걸쳐 빠지는 것은 "막힌" 상태가 아니라
## 설계된 간격이다. 불발 이벤트로 보고하면 Multi-fire 한 번에 로그가 뒤덮인다.
func has_pending_fire(tick: int) -> bool:
	return pending_fires > 0 and block_reason(tick) == ""

# --- 가속 / 둔화 ---

func apply_accel(ticks: int) -> void:
	_apply_speed_effect(ticks, true)

func apply_slow(ticks: int) -> void:
	_apply_speed_effect(ticks, false)

## 가속과 둔화는 서로 배타적이다 — 상쇄 규칙상 둘 중 하나는 항상 0이다.
## 이 불변식을 유지하는 것이 이 함수의 유일한 책임이다.
##
## **같은 종류는 합산하지 않고 큰 쪽으로 갱신한다** (기획서 §3.2.8).
## 반대 종류를 먼저 상쇄하고, 남은 양과 기존 남은 시간 중 큰 값을 쓴다.
## 합산이면 1초짜리 작은 가속을 여러 개 붙이는 것만으로 영구 가속이 되고,
## 그것을 전제로 설계된 파츠가 없다.
##
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
		same = maxi(same, remaining)

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
	# 정지는 강제 발동(fire_part)까지 막는다. 파손보다 먼저 볼 이유는 없지만
	# 발동 상한보다는 먼저 봐야 한다 — 정지가 사유로 보고되지 않으면
	# 왜 안 쏘는지 이벤트 스트림으로 알 수 없다.
	if is_stasised():
		return "stasis"
	if tick - last_fire_tick < K.MIN_FIRE_TICKS:
		return "rate_cap"
	if fires_remaining == 0:
		return "fire_limit"
	return ""

## 발동 횟수를 다 쓴 파츠인가. 파손과 다르다 — 슬롯에 살아 있고 트리거도 돈다.
## AT09 「잔여 시간 교환기」의 대상 조건이며, 시간 조작 대상에서는 제외된다.
func is_exhausted() -> bool:
	return fires_remaining == 0

## 가속·충전 같은 시간 조작을 걸 의미가 있는 파츠인가 (기획서 §3.2.6).
## 주기가 없는 패시브와 소진된 파츠는 대상에서 뺀다 — 걸어도 아무 일이 없어서
## 조용히 낭비되기 때문이다.
func accepts_time_effects() -> bool:
	return not broken and not passive and not is_exhausted()

## 발동 확정. 쿨타임 초과분은 이월한다.
func consume_fire(tick: int) -> void:
	fires_used += 1
	last_fire_tick = tick
	if progress_units >= cooldown_units:
		progress_units -= cooldown_units
	if fires_remaining != K.UNLIMITED:
		fires_remaining = maxi(0, fires_remaining - 1)

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
	destroy_pending = false
	# 예약된 추가 발동도 함께 사라진다. 남겨두면 복구 직후 옛 Multi-fire가 되살아난다.
	pending_fires = 0
	# 파손되면 부식 중첩이 사라진다 — 부식은 "발동할 때" 아픈 상태이고
	# 파손된 파츠는 발동하지 않으므로, 남겨두면 복구했을 때 부활한다.
	# 이것이 부식의 세 번째 제거 경로다 (수리 · 파손 · 실드 완화).
	corrosion_stacks = 0
	return "broken"

## 파손 해제 + 쿨타임 0 재시작.
##
## **잔여 발동 횟수는 채우지 않는다** (기획서 §3.3). 성장(growth)도 그대로 둔다 —
## 복구는 "다시 켜는 것"이지 "새 파츠를 놓는 것"이 아니다. 횟수를 되돌리고 싶은
## 파츠는 AT08처럼 자기 효과로 명시한다.
func restore() -> void:
	broken = false
	destroy_pending = false
	pending_fires = 0
	progress_units = 0
	last_block_reason = ""
	# 정지는 파손이 풀릴 때 함께 풀린다. 파손 중에는 advance()가 통째로 멈춰
	# stasis_ticks가 흐르지 않으므로, 남겨두면 복구 직후 다시 얼어 있다.
	stasis_ticks = 0

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

## 기본 쿨타임 자체를 줄인다 (VG09). 실제로 줄어든 유닛 수를 돌려준다.
## `min_units` 아래로는 내려가지 않는다 — 하한 없는 감소는 0초 주기를 만든다.
func shorten_cooldown(units: int, min_units: int) -> int:
	if units <= 0:
		return 0
	var target: int = maxi(min_units, cooldown_units - units)
	var actual: int = cooldown_units - target
	cooldown_units = target
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
