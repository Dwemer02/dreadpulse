extends RefCounted
# 빌드 JSON 파일 로더.

static func load_build(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("build file missing: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("build file is not a JSON object: " + path)
		return {}
	return data

static func list_builds(dir_path := "res://sim/builds") -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".json"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out

static func load_hull(hull_name := "standard") -> Dictionary:
	var path := "res://sim/hulls/%s_hull.json" % hull_name
	if not FileAccess.file_exists(path):
		push_error("hull file missing: " + path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("hull file is not a JSON object: " + path)
		return {}
	if not data.has("slots") or not data.has("silhouette") or not data.has("canvas"):
		push_error("hull file missing required keys (slots/silhouette/canvas): " + path)
		return {}
	return data
