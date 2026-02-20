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
    var data_list = JSON.parse_string(json_str)
    
    if not data_list is Array:
        return default
        
    for item in data_list:
        if item.get("key") == key:
            return str_to_var(item.get("value", ""))
    return default

## 获取指定存档文件中所有的键名列表
func get_sav_keys(save_file: SaveFile) -> Array:
    var path = _get_save_path(save_file)
    if not FileAccess.file_exists(path):
        return []
        
    var fa = FileAccess.open(path, FileAccess.READ)
    var json_str = decode_sav_bytes(fa.get_buffer(fa.get_length()))
    var data_list = JSON.parse_string(json_str)
    
    var keys = []
    if data_list is Array:
        for item in data_list:
            if item is Dictionary and item.has("key"):
                keys.append(item["key"])
    return keys

## 向指定的存档文件中写入键值对
func set_sav_value(save_file: SaveFile, key: String, value: Variant) -> void:
    var path = _get_save_path(save_file)
    var data_list: Array = []
    
    if FileAccess.file_exists(path):
        var fa = FileAccess.open(path, FileAccess.READ)
        var json_str = decode_sav_bytes(fa.get_buffer(fa.get_length()))
        var parsed = JSON.parse_string(json_str)
        if parsed is Array:
            data_list = parsed

    var found = false
    var string_val = var_to_str(value)
    
    for item in data_list:
        if item.get("key") == key:
            item["value"] = string_val
            found = true
            break
            
    if not found:
        data_list.append({"key": key, "value": string_val})
        
    var new_json = JSON.stringify(data_list)
    var encoded = encode_sav_bytes(new_json)
    
    var fa_write = FileAccess.open(path, FileAccess.WRITE)
    if fa_write:
        fa_write.store_buffer(encoded)
    else:
        push_error("Cannot write to save file: " + path)
