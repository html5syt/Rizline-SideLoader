extends Control
# 提供选项隐藏Cancel按钮
@export var hide_cancel: bool = false
@onready var config = Config.new()

signal setup_completed

func _ready():
    # 隐藏Cancel按钮
    $BG/MarginContainer2/HBoxContainer/Cancel.visible = not hide_cancel
    # 进入节点树时播放动画
    $AnimationPlayer.play("in")

func _on_cancel_gui_input(event):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        #emit_signal("cancel_pressed")
        $AnimationPlayer.play("out")
        await $AnimationPlayer.animation_finished
        get_tree().quit()


func _on_choose_pressed() -> void:
    $FileDialog.show()

func _on_file_dialog_file_selected(path: String) -> void:
    var steam_path = DirAccess.open(path)
    if steam_path:
        config.set_general("steam_root_path",path)
        var lib_path = VDFParser.get_app_install_path(path, "2272590")
        var workshop_path = lib_path + "/steamapps/workshop/content/2272590"
        
        var err = steam_path.change_dir(workshop_path)
        if err == OK:
            config.set_general("workshop_root_path",steam_path.get_current_dir())
            config.set_general("is_inited",true)
            emit_signal("setup_completed")
            $AnimationPlayer.play("out")
            await $AnimationPlayer.animation_finished
            self.queue_free()
        else:
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "错误"
            dialog.content_text = "选择的路径有误，请重新选择。[br][b]注意：[/b]需要选择steamapps子目录包含[b]libraryfolders.vdf文件[/b]的Steam[b]安装目录[/b]!"
            dialog.hide_cancel = true
            add_child(dialog)
    else:
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "错误"
            dialog.content_text = "选择的路径有误，请重新选择。[br][b]注意：[/b]需要选择steamapps子目录包含[b]libraryfolders.vdf文件[/b]的Steam[b]安装目录[/b]!"
            dialog.hide_cancel = true
            add_child(dialog)
