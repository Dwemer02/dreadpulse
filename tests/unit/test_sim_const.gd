extends RefCounted

const K = preload("res://sim/sim_const.gd")

func run(t: RefCounted) -> void:
	# 스펙 §4.1 §4.2 §4.5 §4.6의 불변 규칙이 코드에 그대로 있는지
	t.near(K.TICK_DT, 0.05, "고정 틱 0.05초")
	t.eq(K.MIN_FIRE_TICKS, 4, "발동 상한 초당 5회 = 4틱")
	t.eq(K.MAX_CHAIN_DEPTH, 12, "체인 깊이 상한")
	t.eq(K.DEFAULT_FIRE_LIMIT, 5, "drain_fires가 무제한 파츠에 씌우는 기본 수명")
	t.eq(K.RESONANCE_PER_FIRES, 8, "발동 8회마다 공명 +1")

	# 정수 속도 유닛 — 가속은 정확히 2배, 둔화는 정확히 절반
	t.eq(K.SPEED_NORMAL, 2, "보통 속도 유닛")
	t.eq(K.SPEED_ACCEL, K.SPEED_NORMAL * 2, "가속은 보통의 2배")
	t.eq(K.SPEED_SLOW, 1, "둔화는 보통의 절반")

	# 초 → 틱 변환
	t.eq(K.secs_to_ticks(3.0), 60, "3초 = 60틱")
	t.eq(K.secs_to_ticks(0.2), 4, "0.2초 = 4틱")
	t.eq(K.secs_to_ticks(-1.0), K.PERMANENT, "음수 지속시간은 영구 센티넬")

	# 쿨타임 → 유닛 변환. 5초 파츠는 100틱 * 2유닛 = 200유닛
	t.eq(K.cooldown_to_units(5.0), 200, "쿨타임 5초 = 200유닛")
	t.eq(K.cooldown_to_units(0.2), 8, "쿨타임 0.2초 = 8유닛")

	# 틱 → 초 (이벤트의 t 필드용)
	t.near(K.ticks_to_secs(60), 3.0, "60틱 = 3.0초")
	t.done()
