extends RefCounted
class_name Config

var config: ConfigFile = ConfigFile.new()

func _init() -> void:
    var err = config.load("user://rizline_sideloader.cfg")
    if err:
        config.save("user://rizline_sideloader.cfg")

func set_general(key: String, value: Variant):
    config.set_value("General", key, value)
    var err = config.save("user://rizline_sideloader.cfg")
    assert(not err, "Save failed!")

func get_general(key: String, default = null):
    return config.get_value("General", key, default)

func get_favs():
    if not config.has_section("Favourite"): return []
    return config.get_section_keys("Favourite")

func get_fav_metadata(path: String) -> Dictionary:
    return config.get_value("Favourite", path, {})

func set_fav(path: String, metadata: Dictionary):
    config.set_value("Favourite", path, metadata)
    var err = config.save("user://rizline_sideloader.cfg")
    assert(not err, "Save failed!")

func remove_fav(path: String):
    # config.set_value("Favourite", path, null) # null value acts as delete in some contexts, but erase_section_key is better
    config.erase_section_key("Favourite", path)
    var err = config.save("user://rizline_sideloader.cfg")
    assert(not err, "Save failed!")

func is_fav(path: String) -> bool:
    return config.has_section_key("Favourite", path)

func clear_configfile():
    config.clear()
    var err = config.save("user://rizline_sideloader.cfg")
    assert(not err, "Save failed!")

func set_work(key: String, value: Variant):
    config.set_value("Work", key, value)
    var err = config.save("user://rizline_sideloader.cfg")
    assert(not err, "Save failed!")

func get_work(key: String, default = null):
    return config.get_value("Work", key, default)

func remove_work(key: String):
    if config.has_section_key("Work", key):
        config.erase_section_key("Work", key)
        var err = config.save("user://rizline_sideloader.cfg")
        assert(not err, "Save failed!")
