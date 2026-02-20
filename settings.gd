extends Control
# 信号定义
signal check_pressed
signal cancel_pressed
@onready var config = Config.new()

func _ready():
    # 按钮连接
    $BG/MarginContainer2/HBoxContainer/Check.connect("gui_input", self._on_check_gui_input)
    $BG/MarginContainer2/HBoxContainer/Cancel.connect("gui_input", self._on_cancel_gui_input)
    # 进入节点树时播放动画
    $AnimationPlayer.play("in")
    # 加载配置并设置输入框文本
    var local_root_path = config.get_general("local_root_path", "")
    var workshop_root_path = config.get_general("workshop_root_path", "")
    $BG/Control/VBoxContainer/HBoxContainer/LocalPath.text = local_root_path if local_root_path else $BG/Control/VBoxContainer/HBoxContainer/LocalPath.text
    $BG/Control/VBoxContainer/HBoxContainer2/SteamPath.text = workshop_root_path

func _on_check_gui_input(event):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        emit_signal("check_pressed")
        $AnimationPlayer.play("out")
        await $AnimationPlayer.animation_finished
        self.queue_free()

func _on_cancel_gui_input(event):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        emit_signal("cancel_pressed")
        $AnimationPlayer.play("out")
        await $AnimationPlayer.animation_finished
        self.queue_free()


func _on_local_path_text_changed(new_text: String) -> void:
    config.set_general("local_root_path", new_text)


func _on_steam_path_text_changed(new_text: String) -> void:
    config.set_general("workshop_root_path", new_text)

func _on_localpath_choose_pressed() -> void:
    $PickFolder.dir_selected.connect(_on_pick_localpath_folder_dir_selected)
    $PickFolder.show()

func _on_steam_path_choose_pressed() -> void:
    $PickFolder.dir_selected.connect(_on_pick_steampath_folder_dir_selected)
    $PickFolder.show()

func _on_open_local_path_pressed() -> void:
    OS.shell_open(config.get_general("local_root_path", ProjectSettings.globalize_path("user://custom_local_levels")))


func _on_open_steam_path_pressed() -> void:
    OS.shell_open(config.get_general("workshop_root_path", ""))


func _on_open_config_path_pressed() -> void:
    OS.shell_open(ProjectSettings.globalize_path("user://"))


func _on_open_save_path_pressed() -> void:
    var save_dir = OS.get_config_dir().split("/").slice(0, -1)
    save_dir.append("LocalLow/PigeonGames/Rizline/save")
    save_dir = "/".join(save_dir)
    OS.shell_open(save_dir)


func _on_open_rizline_pressed() -> void:
    var steam_root_path = config.get_general("steam_root_path")
    if steam_root_path:
        var rizline_path = DirAccess.open(steam_root_path)
        if rizline_path:
            rizline_path.change_dir("./steamapps/common/Rizline")
            OS.shell_open(rizline_path.get_current_dir().path_join("Rizline.exe"))
        else:
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "错误"
            dialog.content_text = "Rizline路径无效，请检查Steam路径设置是否正确！"
            dialog.hide_cancel = true
            add_child(dialog)
    else:
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "错误"
        dialog.content_text = "Steam路径未设置或无效，请先进行初始设置！"
        dialog.hide_cancel = true
        add_child(dialog)


func _on_open_rizline_editor_pressed() -> void:
    var steam_root_path = config.get_general("steam_root_path")
    if steam_root_path:
        var rizline_path = DirAccess.open(steam_root_path)
        if rizline_path:
            rizline_path.change_dir("./steamapps/common/Rizline/Editor")
            OS.shell_open(rizline_path.get_current_dir().path_join("Rizline Editor.exe"))
        else:
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "错误"
            dialog.content_text = "Rizline Editor路径无效，请检查Steam路径设置是否正确！"
            dialog.hide_cancel = true
            add_child(dialog)
    else:
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "错误"
        dialog.content_text = "Steam路径未设置或无效，请先进行初始设置！"
        dialog.hide_cancel = true
        add_child(dialog)


func _on_open_rizline_editor_manual_pressed() -> void:
    var steam_root_path = config.get_general("steam_root_path")
    if steam_root_path:
        var rizline_path = DirAccess.open(steam_root_path)
        if rizline_path:
            rizline_path.change_dir("./steamapps/common/Rizline/Editor")
            OS.shell_open(rizline_path.get_current_dir().path_join("Rizline Editor Manual.exe"))
        else:
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "错误"
            dialog.content_text = "Rizline Editor Manual路径无效，请检查Steam路径设置是否正确！"
            dialog.hide_cancel = true
            add_child(dialog)
    else:
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "错误"
        dialog.content_text = "Steam路径未设置或无效，请先进行初始设置！"
        dialog.hide_cancel = true
        add_child(dialog)


func _on_about_pressed() -> void:
    var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    dialog.title_text = "关于"
    dialog.content_text = "[center][b]Rizline Sideloader v%s[/b][/center][br]©2026，Tim & Pigeon Games[br]本工具用于为Rizline游戏侧载本地谱面。[br][url=https://github.com/html5syt/Rizline-SideLoader]GitHub仓库[/url][br][left][b]注意：请勿滥用本工具进行加载任何官方内置谱面等违规行为！[/b][/left]" % ProjectSettings.get_setting("application/config/version")
    dialog.hide_cancel = true
    add_child(dialog)


func _on_init_pressed() -> void:
    var first_setup = preload("uid://baakbpgxj617d").instantiate()
    add_child(first_setup)
    await first_setup.setup_completed
    config._init() # 重新加载配置，确保路径等信息被正确读取


func _on_reset_pressed() -> void:
    var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    dialog.title_text = "警告"
    dialog.content_text = "[color=red]确定要清除所有配置信息吗？这将重置所有设置并清除所有收藏！（不清除成绩和本地谱面文件）[/color][br][b]此操作不可逆！清除后程序将自动退出。[/b]"
    dialog.check_pressed.connect(func(): config.clear_configfile();$AnimationPlayer.play("out");await $AnimationPlayer.animation_finished;get_tree().quit())
    add_child(dialog)

func _on_pick_localpath_folder_dir_selected(dir: String) -> void:
    config.set_general("local_root_path", dir)
    $BG/Control/VBoxContainer/HBoxContainer/LocalPath.text = dir

func _on_pick_steampath_folder_dir_selected(dir: String) -> void:
    config.set_general("workshop_root_path", dir)
    $BG/Control/VBoxContainer/HBoxContainer2/SteamPath.text = dir
