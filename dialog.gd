extends Control
# 提供导出变量设置BG/MarginContainer/Title和BG/Content的文本内容
@export var title_text: String = "对话框标题"
@export var content_text: String = "对话框内容"
# 提供选项隐藏Cancel按钮
@export var hide_cancel: bool = false

# 信号定义
signal check_pressed
signal cancel_pressed

func _ready():
    # 设置Title和Content文本
    var title_label = $BG/MarginContainer/Title
    var content_label = $BG/Content
    if title_label:
        title_label.text = title_text
    if content_label:
        content_label.text = content_text

    # 隐藏Cancel按钮
    $BG/MarginContainer2/HBoxContainer/Cancel.visible = not hide_cancel

    # 按钮连接
    $BG/MarginContainer2/HBoxContainer/Check.connect("gui_input", self._on_check_gui_input)
    $BG/MarginContainer2/HBoxContainer/Cancel.connect("gui_input", self._on_cancel_gui_input)

    # 进入节点树时播放动画
    $AnimationPlayer.play("in")

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


func _on_content_meta_clicked(meta: Variant) -> void:
    OS.shell_open(str(meta))
