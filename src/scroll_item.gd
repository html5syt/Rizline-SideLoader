extends Control

@export var i = 0
@export var metadata: Dictionary
@export var type: int = Type.LOCAL
@export var path: String
@export var illustration: Texture2D
@export var favourite: bool = false
@export var record: Dictionary = {}

var configured = false

enum Type {
    WORKSHOP,
    LOCAL
}

enum Difficulty {
    EASY,
    HARD,
    INSANE,
    ANOTHER
}

func _ready() -> void:
    if configured:
        return
    if not metadata:
        assert(false, "Metadata is required!")
    $MarginContainer/MarginContainer/VBoxContainer/SongName.text = metadata.get("title", "标题缺失！")
    $MarginContainer/MarginContainer/VBoxContainer/SongWriter.text = metadata.get("composer", "作者缺失！")
    match int(metadata.get("difficulty", 0)):
        Difficulty.EASY:
            $MarginContainer2/HBoxContainer/VBoxContainer/LevelDifficulty.text = "EASY"
        Difficulty.HARD:
            $MarginContainer2/HBoxContainer/VBoxContainer/LevelDifficulty.text = "HARD"
        Difficulty.INSANE:
            $MarginContainer2/HBoxContainer/VBoxContainer/LevelDifficulty.text = "INSANE"
        Difficulty.ANOTHER:
            $MarginContainer2/HBoxContainer/VBoxContainer/LevelDifficulty.text = "ANOTHER"
        _:
            $MarginContainer2/HBoxContainer/VBoxContainer/LevelDifficulty.text = "?"
    $MarginContainer2/HBoxContainer/VBoxContainer/LevelNumber.text = str(int(metadata.get("level", "?")))
    # 根据type设置不同的图标
    match type:
        Type.WORKSHOP:
            var texture = await _get_steam_illustration()
            if texture:
                $HBoxContainer/MarginContainer2/BrownCircle/WhiteCircle/Illustration.texture = texture
        Type.LOCAL:
            var local_illustration_path = path+"/illustration"
            if FileAccess.file_exists(local_illustration_path):
                var file = FileAccess.open(local_illustration_path, FileAccess.READ)
                if file:
                    var data = file.get_buffer(file.get_length())
                    var image = Image.new()
                    
                    var err = Error.FAILED
                    # 修复：字节数组越界检查
                    if data.size() > 3 and data[0] == 0xFF and data[1] == 0xD8:
                        err = image.load_jpg_from_buffer(data)
                    elif data.size() > 4 and data[0] == 0x89 and data[1] == 0x50:
                        err = image.load_png_from_buffer(data)
                    
                    if err != OK: # 回退方案
                        err = image.load_jpg_from_buffer(data)
                        if err != OK: err = image.load_png_from_buffer(data)

                    if err == OK:
                        illustration = ImageTexture.create_from_image(image)
                        $HBoxContainer/MarginContainer2/BrownCircle/WhiteCircle/Illustration.texture = illustration
                    else:
                        push_error("Failed to load image from buffer for item: " + path)
            
            # Local file not found or invalid, try to fetch from Steam
            print("Illustration file may does not exist or invalid for item: ", path)
            
    # 初始化状态颜色
    var fc = bool(record.get("isFullCombo", false))
    var cl = bool(record.get("isClear", false))
    set_status_color(fc, cl)

    configured = true

func set_status_color(fc: bool, cl: bool):
    var status_rect = $MarginContainer2/HBoxContainer/Status
    if fc and cl:
        status_rect.modulate = Color(1.0, 0.831, 0.043)
    elif cl:
        status_rect.modulate = Color(0.38, 0.847, 1.0)
    else:
        status_rect.modulate = Color(0.6, 0.6, 0.6)
        
func selected(node):
    if node == self:
        #$HBoxContainer/MarginContainer2/BrownCircle/WhiteCircle/Illustration.modulate = Color.RED
        $MarginContainer/MarginContainer/VBoxContainer/SongName.add_theme_color_override(&"font_color", Color(0.275, 0.275, 0.271))
        $MarginContainer/MarginContainer/VBoxContainer/SongWriter.add_theme_color_override(&"font_color", Color(0.407, 0.407, 0.401))
        $MarginContainer/BG.add_theme_stylebox_override(&"panel", preload("uid://fwnm630fey7y"))
    else:
        #$HBoxContainer/MarginContainer2/BrownCircle/WhiteCircle/Illustration.modulate = Color.WHITE
        $MarginContainer/BG.add_theme_stylebox_override(&"panel", preload("uid://cj0gkcebpggl"))
        $MarginContainer/MarginContainer/VBoxContainer/SongName.add_theme_color_override(&"font_color", Color(0.271, 0.231, 0.714))
        $MarginContainer/MarginContainer/VBoxContainer/SongWriter.add_theme_color_override(&"font_color", Color(0.447, 0.416, 0.784))

func _get_steam_illustration() -> Texture2D:
    var steam_id = path.split("/")[-1]
    var cache_dir = OS.get_temp_dir().path_join("PigeonGames/Rizline/workshop/cache/illustrations")
    
    # 优先从备份目录读取（针对已替换的谱面显示原始曲绘）
    var illustration_local_path = path.path_join("origin_level").path_join(steam_id)
    if not FileAccess.file_exists(illustration_local_path):
        illustration_local_path = cache_dir.path_join(steam_id)
    
    if FileAccess.file_exists(illustration_local_path):
        var file = FileAccess.open(illustration_local_path, FileAccess.READ)
        if file:
            var data = file.get_buffer(file.get_length())
            var image = Image.new()
            
            var err = Error.FAILED
            # 修复：字节数组越界检查
            if data.size() > 3 and data[0] == 0xFF and data[1] == 0xD8:
                err = image.load_jpg_from_buffer(data)
            elif data.size() > 4 and data[0] == 0x89 and data[1] == 0x50:
                err = image.load_png_from_buffer(data)
            
            if err != OK: # 回退方案
                err = image.load_jpg_from_buffer(data)
                if err != OK: err = image.load_png_from_buffer(data)

            if err == OK:
                illustration = ImageTexture.create_from_image(image)
                return illustration
            else:
                push_error("Failed to load image from buffer for item: " + path)
    
    # Local file not found or invalid, try to fetch from Steam
    print("Illustration file does not exist or invalid for item: ", path, " - trying to fetch from Steam...")
    
    # Create cache directory if it doesn't exist
    if not DirAccess.dir_exists_absolute(cache_dir):
        DirAccess.make_dir_recursive_absolute(cache_dir)
        
    var http = HTTPRequest.new()
    add_child(http)
    
    # 1. Get Workshop Page
    http.request("https://steamcommunity.com/sharedfiles/filedetails/?id=" + steam_id)
    var result_page = await http.request_completed
    # result_page is [result, response_code, headers, body]
    
    if result_page[0] != HTTPRequest.RESULT_SUCCESS or result_page[1] != 200:
        http.queue_free()
        push_error("Failed to fetch workshop page for: " + steam_id)
        return null
        
    var html_content = result_page[3].get_string_from_utf8()
    var regex = RegEx.new()
    regex.compile("<link rel=\"image_src\" href=\"(.*?)\">")
    var match_result = regex.search(html_content)
    
    if not match_result:
        http.queue_free()
        push_error("Failed to find image_src in workshop page for: " + steam_id)
        return null
        
    var image_url = match_result.get_string(1)
    # Remove query parameters
    if image_url.contains("?"):
        image_url = image_url.split("?")[0]
        
    # 2. Download Image
    http.request(image_url)
    var result_image = await http.request_completed
    http.queue_free()
    
    if result_image[0] != HTTPRequest.RESULT_SUCCESS or result_image[1] != 200:
        push_error("Failed to download image from: " + image_url)
        return null
        
    var image_data = result_image[3]
    var file = FileAccess.open(illustration_local_path, FileAccess.WRITE)
    if file:
        file.store_buffer(image_data)
        file.close()
        
    var image = Image.new()
    # Workshop images are usually JPG, but verify
    # 同样应用快速检测
    var err = Error.FAILED
    if image_data.size() > 3 and image_data[0] == 0xFF and image_data[1] == 0xD8 and image_data[2] == 0xFF:
        err = image.load_jpg_from_buffer(image_data)
    elif image_data.size() > 8 and image_data[0] == 0x89 and image_data[1] == 0x50 and image_data[2] == 0x4E and image_data[3] == 0x47:
         err = image.load_png_from_buffer(image_data)
    else:
        err = image.load_jpg_from_buffer(image_data)
        if err != OK:
            err = image.load_png_from_buffer(image_data)
        
    if err == OK:
        illustration = ImageTexture.create_from_image(image)
        return illustration
    else:
        push_error("Failed to create image from downloaded data for: " + steam_id)
        return null
