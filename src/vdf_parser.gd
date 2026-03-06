class_name VDFParser
extends RefCounted

static func get_app_install_path(steam_root_path: String, app_id: String) -> String:
	var vdf_path = steam_root_path + "/steamapps/libraryfolders.vdf"
	if not FileAccess.file_exists(vdf_path):
		return steam_root_path
	
	var file = FileAccess.open(vdf_path, FileAccess.READ)
	if not file:
		return steam_root_path
		
	var content = file.get_as_text()
	file.close()
	
	var lines = content.split("\n")
	var current_path = ""
	var in_apps = false
	var braces_level = 0
	var current_library_level = 0
	
	for line in lines:
		var stripped = line.strip_edges()
		if stripped == "":
			continue
			
		if stripped == "{":
			braces_level += 1
			continue
		elif stripped == "}":
			braces_level -= 1
			if braces_level < current_library_level:
				current_path = ""
			if braces_level < current_library_level + 1:
				in_apps = false
			continue
			
		if stripped.begins_with("\"path\""):
			var parts = stripped.split("\"", false)
			if parts.size() >= 3:
				current_path = parts[parts.size() - 1].replace("\\\\", "/")
				current_library_level = braces_level
				
		elif stripped == "\"apps\"":
			in_apps = true
			
		elif in_apps and stripped.begins_with("\"" + app_id + "\""):
			return current_path
			
	return steam_root_path
