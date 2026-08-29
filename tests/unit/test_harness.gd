extends RefCounted

func run(t: RefCounted) -> void:
	t.eq(1 + 1, 2, "sanity: 덧셈")
	t.check(true, "sanity: check")
	t.eq("intentional", "intentional", "러너가 통과 시 exit 0")
	t.near(1.0, 1.00001, "sanity: near — 기본 허용오차 안")
	t.done()
