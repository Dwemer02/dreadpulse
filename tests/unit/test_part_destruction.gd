extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너가 대조해 서브테스트 중단을 잡는다 —
## _test_* 안에서 에러가 나면 그 함수만 중단되고 run()은 정상 종료하기 때문이다.
const EXPECTED_CHECKS := 40

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")

func _make(fire_limit: int = K.UNLIMITED) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.part_id = "test_gun"
	p.cooldown_units = K.cooldown_to_units(1.0)
	p.fire_limit = fire_limit
	p.fires_remaining = fire_limit
	return p

func run(t: RefCounted) -> void:
	_test_indestructible(t)
	_test_reinforce(t)
	_test_break_and_restore(t)
	_test_fires_drain_restore(t)
	_test_defense_edge_cases(t)
	t.done()

func _test_indestructible(t: RefCounted) -> void:
	# 기간제 면제. 보강보다 먼저 적용되고 보강 스택을 소모하지 않는다.
	var p: RefCounted = _make()
	p.reinforce_stacks = 1
	p.make_indestructible(K.secs_to_ticks(1.0))
	t.eq(p.try_break(), "indestructible", "파괴 불가면 파손이 막힌다")
	t.eq(p.reinforce_stacks, 1, "파괴 불가는 보강 스택을 소모하지 않는다")
	t.check(not p.broken, "파괴 불가 파츠는 파손되지 않는다")

	# 20틱 뒤 만료
	for i: int in 20:
		p.advance()
	t.eq(p.indestructible_ticks, 0, "20틱 뒤 파괴 불가가 만료된다")
	t.eq(p.try_break(), "reinforce", "만료 후에는 보강이 막는다")

	# 영구
	var q: RefCounted = _make()
	q.make_indestructible(K.PERMANENT)
	for i: int in 500:
		q.advance()
	t.eq(q.try_break(), "indestructible", "영구 파괴 불가는 만료되지 않는다")

func _test_reinforce(t: RefCounted) -> void:
	# 횟수제 방어. 1 소모하고 파손을 막는다.
	var p: RefCounted = _make()
	p.reinforce_stacks = 2
	t.eq(p.try_break(), "reinforce", "보강이 첫 파손을 막는다")
	t.eq(p.reinforce_stacks, 1, "보강 스택 1 소모")
	t.eq(p.try_break(), "reinforce", "보강이 두 번째 파손을 막는다")
	t.eq(p.reinforce_stacks, 0, "보강 스택 소진")
	t.eq(p.try_break(), "broken", "보강이 떨어지면 파손된다")
	t.check(p.broken, "파손 플래그")

func _test_break_and_restore(t: RefCounted) -> void:
	# 파손: 효과·쿨타임 정지, 슬롯 유지. 복구: 쿨타임 0 재시작 + 횟수 초기화
	var p: RefCounted = _make(3)
	p.consume_fire(0)
	p.consume_fire(10)
	p.apply_accel(50)
	p.advance()
	var progress_before: int = p.progress_units

	t.eq(p.try_break(), "broken", "파손")
	p.advance()
	t.eq(p.progress_units, progress_before, "파손 파츠는 쿨타임이 멈춘다")
	t.eq(p.accel_ticks, 49, "파손 파츠는 지속효과도 멈춘다")

	p.restore()
	t.check(not p.broken, "복구되면 파손이 풀린다")
	t.eq(p.progress_units, 0, "복구 시 쿨타임은 0에서 재시작")
	# **채워주지 않는다** (기획서 §3.3). 복구는 "다시 켜는 것"이지 "새 파츠를 놓는 것"이
	# 아니다. 횟수를 되돌리려는 파츠(AT08)는 자기 효과로 명시한다.
	t.eq(p.fires_remaining, 1, "복구해도 남은 횟수는 그대로다")

func _test_fires_drain_restore(t: RefCounted) -> void:
	# 무제한 파츠가 처음 drain을 맞으면 DEFAULT_FIRE_LIMIT로 확정된다
	var p: RefCounted = _make()
	var drained: int = p.drain_fires(1)
	t.eq(drained, 1, "실제로 깎인 양을 돌려준다")
	t.eq(p.fire_limit, K.DEFAULT_FIRE_LIMIT, "무제한 파츠에 기본 수명이 확정된다")
	t.eq(p.fires_remaining, K.DEFAULT_FIRE_LIMIT - 1, "확정 후 깎인다")

	# 이미 유한한 파츠는 그냥 깎인다
	var q: RefCounted = _make(4)
	q.drain_fires(2)
	t.eq(q.fire_limit, 4, "유한 파츠의 초기값은 바뀌지 않는다")
	t.eq(q.fires_remaining, 2, "유한 파츠는 그대로 깎인다")

	# 0 아래로는 내려가지 않는다
	q.drain_fires(5)
	t.eq(q.fires_remaining, 0, "남은 횟수는 0 미만이 되지 않는다")

	# restore_fires는 초기값을 넘지 않는다
	q.restore_fires(10)
	t.eq(q.fires_remaining, 4, "회복은 초기값을 초과하지 않는다")

	# 무제한 파츠에 restore_fires는 아무 일도 하지 않는다
	var r: RefCounted = _make()
	t.eq(r.restore_fires(3), 0, "무제한 파츠는 회복 대상이 아니다")
	t.eq(r.fires_remaining, K.UNLIMITED, "무제한 그대로")

	# 남은 횟수 0 + 파괴 불가 = 파손 유예, 그러나 발동은 불가
	var s: RefCounted = _make(1)
	s.make_indestructible(K.secs_to_ticks(1.0))
	s.consume_fire(0)
	t.eq(s.fires_remaining, 0, "소진")
	t.eq(s.try_break(), "indestructible", "파괴 불가면 소진해도 파손이 유예된다")
	t.eq(s.block_reason(100), "fire_limit", "유예되어도 발동은 불가")

func _test_defense_edge_cases(t: RefCounted) -> void:
	# 이미 파손된 파츠는 다시 파손되지 않고 보강도 먹지 않는다
	var p: RefCounted = _make()
	p.reinforce_stacks = 2
	p.broken = true
	t.eq(p.try_break(), "already_broken", "이미 파손된 파츠는 already_broken")
	t.eq(p.reinforce_stacks, 2, "이미 파손된 파츠는 보강 스택을 소모하지 않는다")

	# 긴 파괴 불가는 짧은 것에 덮어쓰이지 않는다
	var q: RefCounted = _make()
	q.make_indestructible(100)
	q.make_indestructible(10)
	t.eq(q.indestructible_ticks, 100, "짧은 파괴 불가가 긴 것을 덮어쓰지 않는다")
	q.make_indestructible(200)
	t.eq(q.indestructible_ticks, 200, "더 긴 파괴 불가는 연장한다")

	# 영구 파괴 불가는 유한한 값에 깎이지 않는다 (센티넬이 -1이라 maxi로는 못 지킨다)
	var r: RefCounted = _make()
	r.make_indestructible(K.PERMANENT)
	r.make_indestructible(50)
	t.eq(r.indestructible_ticks, K.PERMANENT, "영구는 유한값에 깎이지 않는다")
	t.check(r.is_indestructible(), "영구 파괴 불가가 유지된다")

	# is_limited — Task 8의 셀렉터(all_own_limited)가 이 계약에 의존한다
	var s: RefCounted = _make()
	t.check(not s.is_limited(), "무제한 파츠는 제한 걸린 파츠가 아니다")
	s.drain_fires(1)
	t.check(s.is_limited(), "drain_fires를 맞으면 제한이 걸린다")
	var u: RefCounted = _make(3)
	t.check(u.is_limited(), "fire_limit을 명시한 파츠는 처음부터 제한이 걸려 있다")
	u.drain_fires(3)
	t.check(u.is_limited(), "횟수를 다 써도 제한 걸린 파츠인 것은 변하지 않는다")
