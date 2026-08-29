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
	_test_broken_stops_everything(t)
	_test_empower(t)
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

	# 쿨타임에 미달한 상태에서 강제 발동하면 진행도를 빼지 않는다
	# (체인이 fire_part로 준비되지 않은 파츠를 발동시킬 수 있다)
	var early: RefCounted = _make(1.0)   # 40유닛 필요
	early.advance()                      # 2유닛
	early.consume_fire(1)
	t.eq(early.progress_units, 2, "쿨타임 미달 시 발동해도 진행도가 깎이지 않는다")

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

	# 영구를 걸면 반대 효과는 지워진다
	var w: RefCounted = _make(10.0)
	w.apply_slow(30)
	w.apply_accel(K.PERMANENT)
	t.eq(w.slow_ticks, 0, "영구 가속은 남아 있던 둔화를 지운다")
	t.eq(w.accel_ticks, K.PERMANENT, "영구 가속이 걸린다")

	# 영구인 반대 효과는 유한한 양에 깎이지 않는다 (이것이 상쇄 가드가 놓쳤던 경우다)
	var x: RefCounted = _make(10.0)
	x.apply_slow(K.PERMANENT)
	x.apply_accel(20)
	t.eq(x.slow_ticks, K.PERMANENT, "영구 둔화는 유한 가속에 지워지지 않는다")
	t.eq(x.accel_ticks, 0, "유한 가속은 영구 둔화에 전부 흡수된다")
	t.eq(x.speed_units(), K.SPEED_SLOW, "영구 둔화가 계속 유효하다")

	# 영구끼리는 서로를 지운다
	var y: RefCounted = _make(10.0)
	y.apply_slow(K.PERMANENT)
	y.apply_accel(K.PERMANENT)
	t.eq(y.accel_ticks, 0, "영구끼리 맞부딪히면 가속이 0")
	t.eq(y.slow_ticks, 0, "영구끼리 맞부딪히면 둔화도 0")
	t.eq(y.speed_units(), K.SPEED_NORMAL, "상쇄되어 보통 속도")

	# 불변식: 가속과 둔화가 동시에 0이 아닌 상태는 존재하지 않는다
	for pair: Array in [[20, 50], [50, 20], [30, 30], [K.PERMANENT, 10], [10, K.PERMANENT]]:
		var z: RefCounted = _make(10.0)
		z.apply_slow(pair[0])
		z.apply_accel(pair[1])
		t.check(z.accel_ticks == 0 or z.slow_ticks == 0,
			"불변식: 가속(%d)과 둔화(%d)가 동시에 0이 아닐 수 없다" % [z.accel_ticks, z.slow_ticks])

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

func _test_broken_stops_everything(t: RefCounted) -> void:
	# 파손 파츠는 쿨타임도 지속효과도 멈춘다
	var p: RefCounted = _make(10.0)
	p.apply_accel(50)
	p.advance()
	var progress: int = p.progress_units
	var accel: int = p.accel_ticks

	p.broken = true
	for i: int in 10:
		p.advance()
	t.eq(p.progress_units, progress, "파손 파츠는 쿨타임이 멈춘다")
	t.eq(p.accel_ticks, accel, "파손 파츠는 가속 지속시간도 멈춘다")
	t.check(not p.is_ready(), "파손 파츠는 준비 상태가 될 수 없다")

func _test_empower(t: RefCounted) -> void:
	# empower 스택은 넣은 순서대로 하나씩 소모된다
	var p: RefCounted = _make(1.0)
	t.near(p.take_empower(), 1.0, "스택이 없으면 1.0배")

	p.empower_stacks.append(1.5)
	p.empower_stacks.append(2.0)
	t.near(p.take_empower(), 1.5, "먼저 넣은 스택이 먼저 나온다")
	t.eq(p.empower_stacks.size(), 1, "한 스택 소모")
	t.near(p.take_empower(), 2.0, "다음 스택")
	t.eq(p.empower_stacks.size(), 0, "전부 소모")
	t.near(p.take_empower(), 1.0, "소진 후에는 다시 1.0배")

