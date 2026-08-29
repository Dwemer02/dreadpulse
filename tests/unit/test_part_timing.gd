extends RefCounted

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")

func _make(cooldown: float, fire_limit: int = K.UNLIMITED) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.part_id = "test_gun"
	p.part_name = "테스트 포"
	p.faction = "reclaimer"
	p.cooldown_units = K.cooldown_to_units(cooldown)
	p.fire_limit = fire_limit
	p.fires_remaining = fire_limit
	return p

func run(t: RefCounted) -> void:
	_test_cooldown(t)
	_test_accel_slow(t)
	_test_rate_cap(t)
	_test_fire_limit(t)
	t.done()

func _test_cooldown(t: RefCounted) -> void:
	var p: RefCounted = _make(1.0)  # 20틱 = 40유닛
	for i: int in 19:
		p.advance()
	t.check(not p.is_ready(), "쿨타임 1초 파츠는 19틱에 준비되지 않는다")
	p.advance()
	t.check(p.is_ready(), "20틱에 준비된다")

	# 발동 시 초과분이 이월된다
	p.advance()  # 21틱: 42유닛
	p.consume_fire(21)
	t.eq(p.progress_units, 2, "발동 후 초과분 2유닛이 이월된다")

func _test_accel_slow(t: RefCounted) -> void:
	# 가속: 쿨타임 1초 파츠가 10틱에 준비된다
	var p: RefCounted = _make(1.0)
	p.apply_accel(K.secs_to_ticks(1.0))
	for i: int in 10:
		p.advance()
	t.check(p.is_ready(), "가속 중이면 절반 시간에 준비된다")

	# 둔화: 40틱 걸린다
	var q: RefCounted = _make(1.0)
	q.apply_slow(K.secs_to_ticks(3.0))
	for i: int in 39:
		q.advance()
	t.check(not q.is_ready(), "둔화 중이면 39틱에 준비되지 않는다")
	q.advance()
	t.check(q.is_ready(), "둔화 중이면 40틱에 준비된다")

	# 같은 종류는 지속시간 합산
	var r: RefCounted = _make(10.0)
	r.apply_accel(20)
	r.apply_accel(30)
	t.eq(r.accel_ticks, 50, "가속끼리는 지속시간이 합산된다")

	# 반대 종류는 상쇄. 짧은 쪽이 사라지고 긴 쪽에 차이만 남는다
	var s: RefCounted = _make(10.0)
	s.apply_slow(30)
	s.apply_accel(50)
	t.eq(s.slow_ticks, 0, "상쇄: 둔화가 전부 지워진다")
	t.eq(s.accel_ticks, 20, "상쇄: 가속에 차이 20틱만 남는다")
	t.eq(s.speed_units(), K.SPEED_ACCEL, "상쇄 후에는 가속 상태")

	var u: RefCounted = _make(10.0)
	u.apply_accel(30)
	u.apply_slow(30)
	t.eq(u.accel_ticks, 0, "완전 상쇄: 가속 0")
	t.eq(u.slow_ticks, 0, "완전 상쇄: 둔화 0")
	t.eq(u.speed_units(), K.SPEED_NORMAL, "완전 상쇄 후에는 보통 속도")

	# 영구 지속시간은 감소하지 않는다
	var v: RefCounted = _make(10.0)
	v.apply_accel(K.PERMANENT)
	for i: int in 100:
		v.advance()
	t.eq(v.accel_ticks, K.PERMANENT, "영구 가속은 만료되지 않는다")

func _test_rate_cap(t: RefCounted) -> void:
	# 마지막 발동으로부터 4틱 미경과면 발동 불가
	var p: RefCounted = _make(0.2)
	p.consume_fire(100)
	t.eq(p.block_reason(103), "rate_cap", "3틱 뒤에는 상한에 막힌다")
	t.eq(p.block_reason(104), "", "4틱 뒤에는 발동할 수 있다")

func _test_fire_limit(t: RefCounted) -> void:
	# 유한 파츠는 발동할 때마다 1 감소, 0이면 발동 불가
	var p: RefCounted = _make(1.0, 2)
	t.eq(p.fires_remaining, 2, "초기 남은 횟수")
	p.consume_fire(0)
	t.eq(p.fires_remaining, 1, "발동하면 1 감소")
	p.consume_fire(10)
	t.eq(p.fires_remaining, 0, "두 번째 발동으로 소진")
	t.eq(p.block_reason(20), "fire_limit", "소진되면 발동 불가")

	# 무제한 파츠는 줄지 않는다
	var q: RefCounted = _make(1.0)
	q.consume_fire(0)
	t.eq(q.fires_remaining, K.UNLIMITED, "무제한 파츠는 감소하지 않는다")
	t.eq(q.block_reason(20), "", "무제한 파츠는 횟수로 막히지 않는다")

	# fires_used는 무제한 파츠에서도 누적된다 (every_nth_fire 조건용)
	t.eq(q.fires_used, 1, "무제한 파츠도 발동 이력은 센다")

	# 파손 파츠는 발동 불가
	var r: RefCounted = _make(1.0)
	r.broken = true
	t.eq(r.block_reason(100), "broken", "파손 파츠는 발동 불가")
