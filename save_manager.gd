extends RefCounted
class_name SaveManager

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
