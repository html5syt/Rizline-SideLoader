extends RefCounted
class_name SaveManager

# 存档文件枚举
enum SaveFile {
    WORKSHOP,
    CONFIG,
    RECORD,
    FAVOURITE
}

# 游戏在 Load 时硬编码回填的 GZip 头
const GZIP_HEADER = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A]

## 执行首两字节混淆/还原 (自反逻辑)
func _swap_xor_first_two_bytes(payload: PackedByteArray) -> PackedByteArray:
    if payload.size() < 3:
        push_error("Payload too short for XOR swap")
        return payload
    
    var data = payload.duplicate()
    var a = data[1] ^ data[2]
    var b = data[0] ^ data[2]
    data[0] = a
    data[1] = b
    return data

## 将 .sav 二进制还原为 JSON 文本
func decode_sav_bytes(obfuscated: PackedByteArray) -> String:
    var repaired = _swap_xor_first_two_bytes(obfuscated)
    
    var gzip_blob = PackedByteArray(GZIP_HEADER)
    gzip_blob.append_array(repaired)
    
    # 使用 GZip 动态解压
    var plain = gzip_blob.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
    return plain.get_string_from_utf8()

## 将 JSON 文本编码为 .sav 二进制
func encode_sav_bytes(json_text: String) -> PackedByteArray:
    var raw = json_text.to_utf8_buffer()
    
    # 使用 GZip 压缩
    var gz = raw.compress(FileAccess.COMPRESSION_GZIP)
    if gz.size() < 11:
        push_error("GZip compression failed")
        return PackedByteArray()
    
    # 移除前 10 字节 GZip 头并执行混淆
    var tail = gz.slice(10)
    return _swap_xor_first_two_bytes(tail)

func _get_save_path(save_file: SaveFile) -> String:
    var pfx = ""
    match save_file:
        SaveFile.WORKSHOP: pfx = "workshop"
        SaveFile.CONFIG: pfx = "config"
        SaveFile.RECORD: pfx = "record"
        SaveFile.FAVOURITE: pfx = "favourite"
        
    var save_dir = OS.get_config_dir().split("/").slice(0, -1)
    save_dir.append("LocalLow/PigeonGames/Rizline/save")
    return "/".join(save_dir).path_join(pfx + ".sav")

## 从指定的存档文件中读取键值对
func get_sav_value(save_file: SaveFile, key: String, default: Variant = null) -> Variant:
    var path = _get_save_path(save_file)
    if not FileAccess.file_exists(path):
        return default
        
    var fa = FileAccess.open(path, FileAccess.READ)
    var json_str = decode_sav_bytes(fa.get_buffer(fa.get_length()))
    var data = JSON.parse_string(json_str)
    
    if not data is Dictionary or not data.has("list"):
        return default
    
    var list_arr = data["list"]
    if not list_arr is Array:
        return default

    for item in list_arr:
        if item is Dictionary and item.get("key") == key:
            var val_str = item.get("value", "")
            if not val_str is String:
                return val_str # Should be string, but return as is if not
            
            # 尝试解析 JSON 用于复杂对象 (如 record)
            if val_str.begins_with("{") or val_str.begins_with("["):
                var parsed = JSON.parse_string(val_str)
                if parsed != null: return parsed
            
            # 处理基本类型
            if val_str == "True": return true
            if val_str == "False": return false
            if val_str.is_valid_float() and not val_str.is_valid_int(): return val_str.to_float()
            if val_str.is_valid_int(): return val_str.to_int()
            
            return val_str
            
    return default

## 获取指定存档文件中所有的键名列表
func get_sav_keys(save_file: SaveFile) -> Array:
    var path = _get_save_path(save_file)
    if not FileAccess.file_exists(path):
        return []
        
    var fa = FileAccess.open(path, FileAccess.READ)
    var json_str = decode_sav_bytes(fa.get_buffer(fa.get_length()))
    var data = JSON.parse_string(json_str)
    
    var keys = []
    if data is Dictionary and data.has("list"):
        var list_arr = data["list"]
        if list_arr is Array:
            for item in list_arr:
                if item is Dictionary and item.has("key"):
                    keys.append(item["key"])
    return keys

## 向指定的存档文件中写入键值对
func set_sav_value(save_file: SaveFile, key: String, value: Variant) -> void:
    var path = _get_save_path(save_file)
    var root_dict = {"list": []}
    
    if FileAccess.file_exists(path):
        var fa = FileAccess.open(path, FileAccess.READ)
        var json_str = decode_sav_bytes(fa.get_buffer(fa.get_length()))
        var parsed = JSON.parse_string(json_str)
        if parsed is Dictionary and parsed.has("list"):
            root_dict = parsed
    
    if not root_dict["list"] is Array:
        root_dict["list"] = []

    var data_list = root_dict["list"]
    var found = false
    
    # 转换 value 为存档所需的字符串格式
    var val_str = ""
    if typeof(value) == TYPE_STRING:
        val_str = value
    elif typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
        val_str = JSON.stringify(value)
    elif typeof(value) == TYPE_BOOL:
        val_str = "True" if value else "False"
    else:
        val_str = str(value)
    
    for item in data_list:
        if item is Dictionary and item.get("key") == key:
            item["value"] = val_str
            found = true
            break
            
    if not found:
        data_list.append({"key": key, "value": val_str})
        
    var encoded = encode_sav_bytes(JSON.stringify(root_dict))
    var fa_write = FileAccess.open(path, FileAccess.WRITE)
    if fa_write:
        fa_write.store_buffer(encoded)
        fa_write.close()
    else:
        push_error("Cannot write to save file: " + path)

func get_workshop_record(steam_id: String) -> Dictionary:
    var val = get_sav_value(SaveFile.WORKSHOP, "record:" + steam_id, {}) # default 改为 {}
    if typeof(val) == TYPE_DICTIONARY:
        return val
    # 如果返回的是字符串（未正确解析），尝试解析
    if typeof(val) == TYPE_STRING and (val.begins_with("{") or val == ""):
        if val == "": return {}
        var p = JSON.parse_string(val)
        return p if p else {}
    return {}

func backup_workshop_score(steam_path: String) -> Variant:
    var steam_id = steam_path.get_file()
    return get_sav_value(SaveFile.WORKSHOP, "record:" + steam_id, null)

func restore_workshop_score(steam_path: String, backup_data: Variant):
    if backup_data == null: return
    if typeof(backup_data) == TYPE_STRING and backup_data == "": return
    if typeof(backup_data) == TYPE_DICTIONARY and backup_data.is_empty(): return
    
    var steam_id = steam_path.get_file()
    set_sav_value(SaveFile.WORKSHOP, "record:" + steam_id, backup_data)
