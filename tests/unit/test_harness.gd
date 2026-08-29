extends RefCounted

func run(t: RefCounted) -> void:
	t.eq(1 + 1, 2, "sanity: 덧셈")
	t.check(true, "sanity: check")
	t.eq("intentional", "intentional", "러너가 통과 시 exit 0")
