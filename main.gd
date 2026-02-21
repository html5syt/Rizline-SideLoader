extends Control

@onready var cycle_list = $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/CyclicList
@onready var config = Config.new()

enum SortOption {
    NAME,
    LEVEL,
    ACHIEVEMENT
}

enum SortDirection {
    ASCENDING,
    DESCENDING
}

enum GroupType {
    ALL,
    LOCAL,
    WORKSHOP,
    FAVOURITE
}

enum SFXType {
    COMMON,
    SETUP
}

var current_sort_option: SortOption = SortOption.NAME:
    set(value):
        current_sort_option = value
        config.set_general("last_sort_option", value)
var current_sort_direction: SortDirection = SortDirection.ASCENDING:
    set(value):
        current_sort_direction = value
        config.set_general("last_sort_direction", value)
var current_group: GroupType = GroupType.ALL

var _master_items: Array[Control] = [] # 缓存所有项实例
var _last_selected_node: Node = null
var _active_dialog: Node = null # 追踪当前打开的对话框
var _preview_start_marker: float = 0.0 # 当前预览音乐的起始秒数
var _preview_tween: Tween # 追踪淡入淡出动画
var _is_splashed: bool = false # 标记是否完成了开场动画
var _save_manager = SaveManager.new()

# 标签路径
const GROUP_LABEL_PATHS = [
    "MarginContainer/UIContainer/RightPannel/Head/BG/MarginContainer/HBoxContainer/HBoxTabsContainer/All",
    "MarginContainer/UIContainer/RightPannel/Head/BG/MarginContainer/HBoxContainer/HBoxTabsContainer/Local",
    "MarginContainer/UIContainer/RightPannel/Head/BG/MarginContainer/HBoxContainer/HBoxTabsContainer/WorkShop",
    "MarginContainer/UIContainer/RightPannel/Head/BG/MarginContainer/HBoxContainer/HBoxTabsContainer/Favourite"
]

func _on_selected(node, idx):
    print("Current Selection:", node, idx)
    play_sound_effect(SFXType.COMMON)
    # 重置上一个选中项的视觉状态
    if _last_selected_node and is_instance_valid(_last_selected_node) and _last_selected_node != node:
        _last_selected_node.selected(node)
    
    if node:
        node.selected(node)
        _last_selected_node = node
    else:
        _last_selected_node = null

    # 获取选中项的metadata
    var selected_metadata = node.metadata if node else null
    
    # ——设置相关信息——
    # 曲绘
    $MarginContainer/UIContainer/LeftPannel/BrownCircle/WhiteCircle/Illustration.texture = node.illustration if node and node.illustration else preload("uid://dxgna62048eux")
    # 曲目标题，作者
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer3/Title/SongName.text = selected_metadata.get("title", "标题缺失！") if selected_metadata else "标题缺失！"
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer3/Title/SongWriter.text = selected_metadata.get("composer", "请检查是否导入/下载过谱面，文件是否损坏") if selected_metadata else "请检查是否导入/下载过谱面，文件是否损坏"
    
    # 难度及相关信息显示逻辑
    var diff_label = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer/HBoxContainer/HBoxContainer/VBoxContainer/LevelDifficulty
    var level_label = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer/HBoxContainer/HBoxContainer/VBoxContainer/LevelNumber
    
    if node and selected_metadata:
        match int(selected_metadata.get("difficulty", 0)):
            node.Difficulty.EASY: diff_label.text = "EASY"
            node.Difficulty.HARD: diff_label.text = "HARD"
            node.Difficulty.INSANE: diff_label.text = "INSANE"
            node.Difficulty.ANOTHER: diff_label.text = "ANOTHER"
            _: diff_label.text = "?"
        level_label.text = str(int(selected_metadata.get("level", 0)))
    else:
        diff_label.text = "?"
        level_label.text = "?"

    # 谱面类型与按钮
    var chart_type_label = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer/HBoxContainer/VBoxContainer/ChartType
    var load_btn = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer2/Load
    
    if node:
        chart_type_label.text = "创意工坊" if node.type == node.Type.WORKSHOP else "本地谱面"
        
        # 3. 追加状态文字 (支持多对替换关系)
        var replace_pairs = _get_synced_replace_pairs()
        
        if node.type == node.Type.WORKSHOP:
            for i in range(replace_pairs.size()):
                if replace_pairs[i].get("steam_path") == node.path:
                    if replace_pairs[i].get("local_path", "") != "":
                         chart_type_label.text += "【已替换%d】" % (i + 1)
                    else:
                         chart_type_label.text += "【已选中%d】" % (i + 1)
                    break
        elif node.type == node.Type.LOCAL:
            for i in range(replace_pairs.size()):
                if replace_pairs[i].get("local_path") == node.path:
                    chart_type_label.text += "【源文件%d】" % (i + 1)
                    break
                
        load_btn.text = " SET" if node.type == node.Type.WORKSHOP else "LOAD"
        load_btn.icon = preload("uid://cy1knjjngl56f") if node.type == node.Type.WORKSHOP else preload("uid://0pdxj8y8hgih")
    else:
        chart_type_label.text = "未知来源"
        load_btn.text = "WTF?"
        load_btn.icon = null

    # 读取并显示成绩信息
    var record = _get_record_for_node(node)
    
    # ① score
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer2/HBoxContainer/Control/MarginContainer/Score/Current.text = "%07d" % int(record.get("score", 0))
    
    # ② completeRate
    var acc = float(record.get("completeRate", 0.0))
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/Control/MarginContainer/HBoxContainer/Acc/Big.text = str(int(acc))
    var decimal_part = acc - int(acc)
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/Control/MarginContainer/HBoxContainer/Acc/Small.text = "." + ("%.4f" % decimal_part).substr(2) + "%"

    # ③ isFullCombo, isClear - Status Color
    var fc = bool(record.get("isFullCombo", false))
    var cl = bool(record.get("isClear", false))
    var status_color = Color(0.6, 0.6, 0.6)
    if fc and cl:
        status_color = Color(1.0, 0.831, 0.043)
    elif cl:
        status_color = Color(0.38, 0.847, 1.0)
    
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer/HBoxContainer/HBoxContainer/Status.modulate = status_color
    # 列表项自身的颜色设置现在由 scroll_item._ready 自动处理，且数据已在 refresh 时注入
    # if node: node.set_status_color(fc, cl) 

    # ④ hit
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/Control/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/Hit/Current.text = str(int(record.get("hit", 0)))
    # ⑤ bad
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/VBoxContainer/Bad.text = str(int(record.get("bad", 0)))
    # ⑥ miss
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/VBoxContainer2/Miss.text = str(int(record.get("miss", 0)))
    # ⑦ maxHit
    var display_max_hit = int(record.get("maxHit", selected_metadata.get("maxHit", 0) if selected_metadata else 0))
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer/HBoxContainer/Control/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/Hit/All.text = "/" + str(display_max_hit)
    # ⑧ maxScore
    var display_max_score = int(record.get("maxScore", selected_metadata.get("maxScore", 0) if selected_metadata else 0))
    $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/MarginContainer2/HBoxContainer/Control/MarginContainer/Score/All.text = "/" + "%07d" % display_max_score
    
    # 刷新收藏图标状态
    _update_favourite_icon_visual(node)

    # 预览音乐处理
    _update_music_preview(node)

    # 同步滚动条和当前页数显示
    if idx >= 0:
        $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/ListVScrollBar.page = 1.0
        $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/ListVScrollBar.set_value_no_signal(idx)
        $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/BG/Current.text = str(idx + 1)
    else:
        $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/BG/Current.text = "0"

func _ready() -> void:
    # 初始化预览循环定时器
    var preview_timer = Timer.new()
    preview_timer.name = "PreviewTimer"
    preview_timer.timeout.connect(_on_preview_timeout)
    add_child(preview_timer)
        
    # 进行一次数据同步检查
    _check_data_sync()
    
    # 连接收藏按钮点击事件
    var fav_rect = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer2/Love/Icon
    if not fav_rect.gui_input.is_connected(_on_fav_icon_gui_input):
        fav_rect.gui_input.connect(_on_fav_icon_gui_input)
        
    # 连接删除按钮点击事件
    var delete_btn = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer/Delete
    if not delete_btn.gui_input.is_connected(_on_delete_gui_input):
        delete_btn.gui_input.connect(_on_delete_gui_input)
        
    # 信号连接
    cycle_list.selection_changed.connect(_on_selected)
    # 获取上次的排序选项和排序方向
    current_sort_option = config.get_general("last_sort_option", SortOption.NAME)
    current_sort_direction = config.get_general("last_sort_direction", SortDirection.ASCENDING)
    _update_sort_ui_text()
    _update_group_ui()
    refresh(true)
    
    var splash = preload("uid://dky81dd77rcs2").instantiate()
    splash.splash_played.connect(func(): _is_splashed = true)
    add_child(splash)
    await splash.splash_played
    # 检查是否初始化
    if not config.get_general("is_inited"):
        var first_setup = preload("uid://baakbpgxj617d").instantiate()
        add_child(first_setup)
        await first_setup.setup_completed
        config._init() # 重新加载配置，确保路径等信息被正确读取
    
# 分组筛选逻辑：始终从 master 列表进行筛选
func _filter_items_by_group(items: Array) -> Array:
    match current_group:
        GroupType.ALL:
            return items.duplicate()
        GroupType.LOCAL:
            return items.filter(func(n): return n.type == n.Type.LOCAL)
        GroupType.WORKSHOP:
            return items.filter(func(n): return n.type == n.Type.WORKSHOP)
        GroupType.FAVOURITE:
            return items.filter(func(n): return n.favourite)
    return items.duplicate()

func _on_list_v_scroll_bar_value_changed(value: float) -> void:
    cycle_list.set_selected_index(int(value))

# 音乐预览相关逻辑
func _update_music_preview(node):
    var player = $SongPreview
    var timer = $PreviewTimer
    
    player.stop()
    timer.stop()
    if _preview_tween: _preview_tween.kill()
    _preview_start_marker = 0.0
    
    if not node or not node.path:
        return
        
    var stream = _load_audio_stream(node.path)
    if not stream:
        return
        
    var metadata = node.metadata
    var ratio = float(metadata.get("previewTime", 0.0))
    var total_dur = stream.get_length()
    
    # 规则：时长小于20s或比例>1.1，从头开始
    if total_dur >= 20.0 and ratio <= 1.1:
        _preview_start_marker = (total_dur - 20.0) * ratio
    else:
        _preview_start_marker = 0.0
        
    player.stream = stream
    
    # 循环片段长度为 播放时间(max 20s) + 1.5s 间隔
    timer.start(min(20.0, total_dur) + 1.5)
    _start_preview_playback()

func _start_preview_playback():
    var player = $SongPreview
    if not player.stream: return
    if _preview_tween: _preview_tween.kill()
    
    var total_dur = player.stream.get_length()
    var play_dur = min(20.0, total_dur)
    
    player.volume_db = -80.0
    player.play(_preview_start_marker)
    
    _preview_tween = create_tween()
    if play_dur > 1.0:
        # 渐入 0.5s
        _preview_tween.tween_property(player, "volume_db", -2.0, 0.5)
        # 维持预览时长（扣除渐入渐出）
        _preview_tween.tween_interval(play_dur - 1.0)
        # 渐出 0.5s
        _preview_tween.tween_property(player, "volume_db", -80.0, 0.5)
    else:
        # 音频太短，平分渐入渐出时间
        var half = play_dur / 2.0
        _preview_tween.tween_property(player, "volume_db", -2.0, half)
        _preview_tween.tween_property(player, "volume_db", -80.0, half)
    
    _preview_tween.tween_callback(player.stop)

func _load_audio_stream(dir_path: String) -> AudioStream:
    var song_p = ""
    # 优先检查 origin_level 目录（针对已替换的 Steam 谱面音频预览）
    var check_dirs = [dir_path.path_join("origin_level"), dir_path]
    for d in check_dirs:
        for ext in [".mp3", ".ogg"]:
            var p = d.path_join("song" + ext)
            if FileAccess.file_exists(p):
                song_p = p
                break
        if song_p != "": break
    
    if song_p == "": return null
    
    var file = FileAccess.open(song_p, FileAccess.READ)
    var buffer = file.get_buffer(file.get_length())
    
    if song_p.ends_with(".mp3"):
        var stream = AudioStreamMP3.new()
        stream.data = buffer
        return stream
    else:
        return AudioStreamOggVorbis.load_from_buffer(buffer)

func _on_preview_timeout():
    _start_preview_playback()

# 获取达成率的函数
func _get_achievement_rate(node: Node) -> float:
    var record = _get_record_for_node(node)
    return float(record.get("completeRate", 0.0))

# 排序比较函数，用于 scroll_item 节点
func _sort_items_nodes(a: Node, b: Node) -> bool:
    var ret = false
    # 注意：此时 a 和 b 是 scroll_item 实例，直接访问其属性
    match current_sort_option:
        SortOption.NAME:
            var title_a = a.metadata.get("title", "")
            var title_b = b.metadata.get("title", "")
            ret = title_a.naturalnocasecmp_to(title_b) < 0
        SortOption.LEVEL:
            var diff_a = int(a.metadata.get("difficulty", 0))
            var diff_b = int(b.metadata.get("difficulty", 0))
            if diff_a != diff_b:
                ret = diff_a < diff_b
            else:
                var lvl_a = int(a.metadata.get("level", 0))
                var lvl_b = int(b.metadata.get("level", 0))
                ret = lvl_a < lvl_b
        SortOption.ACHIEVEMENT:
            # 由于 scroll_item 可能没有缓存 achievement，这里可能需要实时计算或先存入 metadata
            # 简单起见，假设 Node 上可以动态挂载数据或 metadata 中有
            var ach_a = _get_achievement_rate(a)
            var ach_b = _get_achievement_rate(b)
            ret = ach_a < ach_b
    
    if current_sort_direction == SortDirection.DESCENDING:
        return not ret
    return ret

func refresh(rescan: bool = true) -> void:
    if rescan:
        # 重新扫描时停止音乐，防止指向已失效的路径
        if has_node("SongPreview"): $SongPreview.stop()
        if has_node("PreviewTimer"): $PreviewTimer.stop()
        if _preview_tween: _preview_tween.kill()
        
        print("Refreshing list with rescan...")
        _last_selected_node = null
        # 释放 master 中的实例
        for item in _master_items:
            if is_instance_valid(item): item.queue_free()
        _master_items.clear()
        
        var raw_result = _refresh()
        
        # 1. 加载普通列表
        for type in range(raw_result.size()):
            for item_path in raw_result[type]:
                var metadata = _load_metadata(item_path)
                if metadata:
                    var scroll_item = preload("uid://d2rre1cg65hg1").instantiate()
                    scroll_item.metadata = metadata
                    scroll_item.type = type
                    scroll_item.path = item_path
                    # 初始化收藏状态
                    scroll_item.favourite = config.is_fav(item_path)
                    
                    # 初始化成绩记录 (用于列表显示FC/Clear状态)
                    # 统一使用 _get_record_for_node 从而支持替换后的成绩显示逻辑
                    scroll_item.record = _get_record_for_node(scroll_item)
                            
                    _master_items.append(scroll_item)
        
        # 2. 检查收藏夹中的内容是否都在列表中，如果不在（例如移动了位置或者仅有记录），可能需要补充
        # 题目要求“当切换到的时候使用保存的path和metadata构建列表”，但为了统一管理，
        # 我们这里假设所有有效的item都在 _refresh 扫描结果中。
        # 如果需要支持仅仅存于配置文件的“离线收藏”，逻辑会复杂很多。
        # 这里仅同步状态：如果在配置文件里有，设置 favourite=true (上面已做)

    # 更新收藏标签可见性
    var fav_keys = config.get_favs()
    var fav_tab = get_node(GROUP_LABEL_PATHS[GroupType.FAVOURITE])
    fav_tab.visible = not fav_keys.is_empty()
    
    # 如果当前在收藏分组但没收藏了，切回 ALL
    if current_group == GroupType.FAVOURITE and fav_keys.is_empty():
        current_group = GroupType.ALL
        _update_group_ui()

    # 1. 设置当前显示的 Templates
    var current_display_list = _filter_items_by_group(_master_items)
    
    # 2. 排序
    current_display_list.sort_custom(_sort_items_nodes)
    
    # 3. 更新列表内容
    # 先清空当前 active 实例的显示，但不销毁 master 里的模板
    for child in cycle_list.get_children():
        if child.has_meta("template_id"):
            cycle_list._recycle_instance(child)
            
    cycle_list._templates = current_display_list
    
    if current_display_list.is_empty():
        _on_selected(null, -1)
    else:
        cycle_list._current_index = clamp(cycle_list._current_index, 0, current_display_list.size() - 1)
        cycle_list._active_items.clear() # 强制布局系统重置
        cycle_list._layout_items()
        
        # 修复：当模板列表发生变化（尤其是长度变化）时，重置滚动位置防止错位
        cycle_list._snap_to_current()
        
        var current_node = cycle_list.get_selected_node()
        if current_node:
            _on_selected(current_node, cycle_list.get_selected_index())

    # 更新 UI
    $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/ListVScrollBar.max_value = cycle_list.get_list_size()
    $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/BG/All.text = str(cycle_list.get_list_size())
    $MarginContainer/UIContainer/RightPannel/MarginContainer/HBoxContainer/MarginContainer/VBoxContainer/BG/Current.text = str(cycle_list.get_selected_index() + 1)

func _load_metadata(item_path: String) -> Dictionary:
    # 7. 如果是已替换的Steam谱面，尝试读取原始元数据以便在列表中显示正确信息
    var origin_meta_path = item_path.path_join("origin_level/metadata.json")
    if FileAccess.file_exists(origin_meta_path):
        var file = FileAccess.open(origin_meta_path, FileAccess.READ)
        if file:
            var json_str = file.get_as_text()
            var data = JSON.parse_string(json_str)
            if data: return data
            
    var metadata_path = item_path.path_join("metadata.json")
    if FileAccess.file_exists(metadata_path):
        var file = FileAccess.open(metadata_path, FileAccess.READ)
        if file:
            var json_str = file.get_as_text()
            var data = JSON.parse_string(json_str)
            if data: return data
    return {}

func _refresh() -> Array:
    var workshop_root = config.get_general("workshop_root_path", "")
    var local_root = config.get_general("local_root_path", "user://custom_local_levels")
    var result = [[], []]
    
    var roots = [workshop_root, local_root]
    for i in range(roots.size()):
        var root = roots[i]
        if root == null or root == "" or not DirAccess.dir_exists_absolute(root):
            continue
        
        var folders = DirAccess.get_directories_at(root)
        for folder in folders:
            var full_path = root.path_join(folder)
            var has_chart = FileAccess.file_exists(full_path.path_join("chart.json"))
            var has_metadata = FileAccess.file_exists(full_path.path_join("metadata.json"))
            var has_audio = FileAccess.file_exists(full_path.path_join("song.mp3")) or FileAccess.file_exists(full_path.path_join("song.ogg"))
            
            if has_chart and has_metadata and has_audio:
                result[i].append(full_path)
    
    return result

func _update_sort_ui_text():
    var text_label = $MarginContainer/UIContainer/RightPannel/Head/BG/MarginContainer2/HBoxContainer/Sort
    match current_sort_option:
        SortOption.NAME:
            text_label.text = "名称"
        SortOption.LEVEL:
            text_label.text = "等级"
        SortOption.ACHIEVEMENT:
            text_label.text = "达成率" # 或 ACHIEVEMENT

func _update_group_ui():
    for i in range(GROUP_LABEL_PATHS.size()):
        var label = get_node(GROUP_LABEL_PATHS[i])
        if i == int(current_group):
            label.add_theme_color_override("font_color", Color(0.416, 0.38, 0.812))
        else:
            label.add_theme_color_override("font_color", Color(0.655, 0.639, 1.0))

func _handle_input_event(event):
    if event.is_action_pressed("rs_enter"):
        _on_load_pressed()
    elif event.is_action_pressed("rs_change_sort"):
        current_sort_option = SortOption.values()[(current_sort_option + 1) % SortOption.values().size()]
        _update_sort_ui_text()
        refresh(false) # 仅排序
    elif event.is_action_pressed("rs_left_shift"):
        _switch_group(-1)
    elif event.is_action_pressed("rs_right_shift"):
        _switch_group(1)
    elif event.is_action_pressed("rs_favourite"):
        _toggle_favourite()
    elif event.is_action_pressed("rs_refresh"):
        refresh(true)
    elif event.is_action_pressed("rs_delete"):
        _confirm_delete()
        play_sound_effect(SFXType.COMMON)
    elif event.is_action_pressed("rs_quit"):
        get_tree().quit()
        play_sound_effect(SFXType.COMMON)
    elif event.is_action_pressed("rs_settings"):
        _on_settings_pressed()

# 删除图标点击事件
func _on_delete_gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        play_sound_effect(SFXType.COMMON)
        _confirm_delete()

# 弹出删除确认对话框
func _confirm_delete():
    if is_instance_valid(_active_dialog): return # 如果对话框已弹出，则忽略请求
    
    var node = cycle_list.get_selected_node()
    if not node: return
    
    # 6. 删除检查 (支持多对替换关系)
    var replace_pairs = _get_synced_replace_pairs()
    var is_involved = false
    var warn_msg = ""
    
    for pair in replace_pairs:
        if node.path == pair.get("steam_path"):
            is_involved = true
            warn_msg = "该谱面正在参与替换（作为目标），删除将导致需要重新复原或数据丢失。"
            break
        elif node.path == pair.get("local_path"):
            is_involved = true
            warn_msg = "该谱面正在参与替换（作为源），删除可能影响替换状态。"
            break
        
    if is_involved:
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "替换冲突警告"
        dialog.content_text = warn_msg + "[br]建议先[b]复原替换[/b]再进行删除操作。[br]是否仍要强制删除？"
        # 这里简化逻辑，如果用户确认强制删除，则直接走原删除逻辑（可能会留下残留配置，需refresh清理）
        # 更好的做法是在删除确认回调里清理配置
        dialog.check_pressed.connect(_on_delete_confirmed.bind(node.path))
        add_child(dialog)
        _active_dialog = dialog
        return

    _active_dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    _active_dialog.title_text = "警告"
    _active_dialog.content_text = "是否从本地[color=RED]删除谱面文件[/color]？[br][b]※注意：[/b][u]从Steam下载的[/u]创意工坊谱面在此处删除后会[color=BLUE]使Rizline报“谱面文件损坏”错误[/color]。如需彻底删除/恢复请关闭Rizline，在Steam中[b]取消该谱面的订阅[/b]并[b]在Steam的“属性-创意工坊”中手动删除文件[/b]。收藏信息也会一并移除。[br]您[u]或许[/u]可以在系统回收站中找到被删除的谱面文件夹。"
    _active_dialog.check_pressed.connect(_on_delete_confirmed.bind(node.path))
    add_child(_active_dialog)

# 执行删除操作
func _on_delete_confirmed(path: String):
    # 删除时清理相关配置防止野指针
    var replace_pairs = _get_synced_replace_pairs()
    var modified = false
    for i in range(replace_pairs.size() - 1, -1, -1):
        var pair = replace_pairs[i]
        if path == pair.get("steam_path"):
            replace_pairs.remove_at(i)
            modified = true
        elif path == pair.get("local_path"):
            pair["local_path"] = ""
            pair["local_metadata"] = {}
            modified = true
            
    if modified:
        _save_synced_replace_pairs(replace_pairs)

    # 尝试移动到回收站
    var global_path = ProjectSettings.globalize_path(path)
    var err = OS.move_to_trash(global_path)
    
    if err != OK:
        push_error("Failed to move folder to trash: " + path + ". Error code: " + str(err))
    
    # 无论删除是否成功（有时文件夹不存在也会报错），强制移除收藏信息并刷新
    config.remove_fav(path)
    refresh(true)

# 导入功能
func import_levels(zip_paths: Array):
    if zip_paths.is_empty(): return
    
    var workshop_root = config.get_general("workshop_root_path", "")
    var illustration_cache_dir = OS.get_temp_dir().path_join("PigeonGames/Rizline/workshop/cache/illustrations")
    var local_root = config.get_general("local_root_path", "user://custom_local_levels")
    
    # 确保目录存在
    if not DirAccess.dir_exists_absolute(illustration_cache_dir):
        DirAccess.make_dir_recursive_absolute(illustration_cache_dir)
    if not DirAccess.dir_exists_absolute(local_root):
        DirAccess.make_dir_recursive_absolute(local_root)
        
    for zip_path in zip_paths:
        var reader = ZIPReader.new()
        var err = reader.open(zip_path)
        if err != OK:
            push_error("Failed to open zip: " + zip_path)
            continue
            
        var files = reader.get_files()
        var steam_id_file = ""
        var is_steam = false
        var regex = RegEx.new()
        regex.compile("^\\d{10}$") # 匹配10位纯数字文件名
        
        for f in files:
            # 排除文件夹（以/结尾）
            if f.ends_with("/"): continue
            var file_name = f.get_file()
            if regex.search(file_name):
                steam_id_file = f
                is_steam = true
                break
        
        if is_steam and workshop_root != "":
            # Steam Workshop 导入逻辑
            var steam_id = steam_id_file.get_file()
            var target_level_dir = workshop_root.path_join(steam_id)
            
            if not DirAccess.dir_exists_absolute(target_level_dir):
                DirAccess.make_dir_recursive_absolute(target_level_dir)
                
            # 解压所有文件
            for f in files:
                if f.ends_with("/"): continue
                var buffer = reader.read_file(f)
                var file_name = f.get_file()
                
                if file_name == steam_id:
                    # 曲绘解压到缓存目录
                    var img_file = FileAccess.open(illustration_cache_dir.path_join(steam_id), FileAccess.WRITE)
                    if img_file: img_file.store_buffer(buffer)
                else:
                    # 其他文件解压到工坊目录
                    var level_file = FileAccess.open(target_level_dir.path_join(file_name), FileAccess.WRITE)
                    if level_file: level_file.store_buffer(buffer)
        else:
            # 本地导入逻辑
            # 计算chart.json哈希作为文件夹名
            var chart_hash = 0
            var metadata_hash = 0
            for f in files:
                if f.get_file().to_lower() == "chart.json":
                    var chart_buf = reader.read_file(f)
                    chart_hash = hash(chart_buf)
                elif f.get_file().to_lower() == "metadata.json":
                    var metadata_buf = reader.read_file(f)
                    metadata_hash = hash(metadata_buf)
            if not chart_hash and not metadata_hash:
                # 没有chart.json，回退为uuid
                push_error("No chart.json or metadata.json found in zip: " + zip_path + ".")
                break
            var target_dir = local_root.path_join(str(chart_hash) + str(metadata_hash))
            DirAccess.make_dir_recursive_absolute(target_dir)
            
            for f in files:
                if f.ends_with("/"): continue
                var buffer = reader.read_file(f)
                var file_name = f.get_file()
                # 无论是illustration还是其他，都解压到这里
                var out_file = FileAccess.open(target_dir.path_join(file_name), FileAccess.WRITE)
                if out_file: out_file.store_buffer(buffer)
                
        reader.close()
        
    refresh(true)
    _show_import_export_dialog("导入", zip_paths[0] + ("等" if zip_paths.size() > 1 else ""))

# 导出功能
func export_levels(items: Array, target_dir: String):
    if items.is_empty(): return
    
    var illustration_cache_dir = OS.get_temp_dir().path_join("PigeonGames/Rizline/workshop/cache/illustrations")
    
    for item in items:
        # 获取文件名所需信息
        var meta = item.metadata
        var title = meta.get("title", "Unknown")
        var composer = meta.get("composer", "Unknown")
        var diff_idx = int(meta.get("difficulty", 0))
        var diff_str = ["EZ", "HD", "IN", "AT"][diff_idx] if diff_idx >= 0 and diff_idx < 4 else "UNK"
        var level = str(int(meta.get("level", 0)))
        
        # 简单清理文件名非法字符
        var safe_name = "%s-%s-%s.%s.zip" % [title, composer, diff_str, level]
        var regex = RegEx.new()
        regex.compile("[\\\\/:*?\"<>|]")
        safe_name = regex.sub(safe_name, "_", true)
        
        var zip_path = target_dir.path_join(safe_name)
        var packer = ZIPPacker.new()
        var err = packer.open(zip_path)
        if err != OK:
            push_error("Failed to create zip: " + zip_path)
            continue
            
        # 1. 打包 path 下所有文件
        var source_dir = item.path
        if DirAccess.dir_exists_absolute(source_dir):
            var files = DirAccess.get_files_at(source_dir)
            for file_name in files:
                var file_path = source_dir.path_join(file_name)
                var file_access = FileAccess.open(file_path, FileAccess.READ)
                if file_access:
                    var buffer = file_access.get_buffer(file_access.get_length())
                    packer.start_file(file_name)
                    packer.write_file(buffer)
                    packer.close_file()
        
        # 2. 如果是 Workshop，还需要打包缓存中的曲绘
        if item.type == 0: # Type.WORKSHOP is 0 based on scroll_item.gd enum, but main.gd doesn't see inner enum directly easily unless using const
            # Workshop logic relies on path ending with steam_id
            var steam_id = item.path.get_file() # folder name is steam_id
            var cached_img_path = illustration_cache_dir.path_join(steam_id)
            if FileAccess.file_exists(cached_img_path):
                var img_file = FileAccess.open(cached_img_path, FileAccess.READ)
                if img_file:
                    var buffer = img_file.get_buffer(img_file.get_length())
                    packer.start_file(steam_id) # No extension as per requirement
                    packer.write_file(buffer)
                    packer.close_file()
        
        packer.close()
        
    _show_import_export_dialog("导出", target_dir)

func _show_import_export_dialog(action: String, path_info: String):
    if is_instance_valid(_active_dialog): return
    
    var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    dialog.title_text = "提示"
    if action == "导入":
        dialog.content_text = "已从 " + path_info + " 导入谱面"
    else:
        dialog.content_text = "已导出到 " + path_info
    
    dialog.hide_cancel = true
    _active_dialog = dialog
    add_child(dialog)

# 分组切换辅助
func _switch_group(direction: int):
    # 如果收藏不可见（没收藏），需要跳过 FAVOURITE
    var fav_visible = get_node(GROUP_LABEL_PATHS[GroupType.FAVOURITE]).visible
    var max_idx = GroupType.values().size() if fav_visible else GroupType.values().size() - 1
    
    # 计算新索引
    var next = (int(current_group) + direction) % max_idx
    if next < 0: next += max_idx
    
    current_group = GroupType.values()[next]
    _update_group_ui()
    refresh(false) # 仅筛选

# 收藏图标点击事件
func _on_fav_icon_gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        play_sound_effect(SFXType.COMMON)
        _toggle_favourite()

# 切换收藏状态
func _toggle_favourite():
    var node = cycle_list.get_selected_node()
    if not node: return
    
    # 查找原始模板数据索引
    var data_idx = node.get_meta("data_index", -1)
    if data_idx == -1: return
    
    # 获取模板引用并修改状态
    var template = cycle_list._templates[data_idx]
    template.favourite = !template.favourite
    # 立即同步当前结点的视觉数据
    node.favourite = template.favourite
    
    _update_favourite_icon_visual(node)
    
    if template.favourite:
        config.set_fav(template.path, template.metadata)
    else:
        config.remove_fav(template.path)
        
        # 修复：如果在收藏分组中取消收藏，应立即刷新列表以移除该项
        if current_group == GroupType.FAVOURITE:
            # 标记：由于 _templates 已经变了，需要从 master 重新构建筛选
            refresh(false)
            
    # 实时更新标签可见性
    var fav_tab = get_node(GROUP_LABEL_PATHS[GroupType.FAVOURITE])
    fav_tab.visible = not config.get_favs().is_empty()

# 更新图标颜色
func _update_favourite_icon_visual(node):
    # 此处 node 可能为 null
    var icon = $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer2/Love/Icon
    if node and node.get("favourite"): # 使用 get 安全访问
        icon.modulate = Color(1.0, 0.494, 0.451)
    else:
        icon.modulate = Color(0.89, 0.89, 0.89)

func _input(event):
    _handle_input_event(event)

func _on_refresh_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        refresh(true)


func _on_import_pressed() -> void:
    play_sound_effect(SFXType.COMMON)
    $Import.show()

func _on_export_pressed() -> void:
    play_sound_effect(SFXType.COMMON)
    var node = cycle_list.get_selected_node()
    if not node or $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer2/Load.text == "WTF?":
        # 7. 如果加载按钮不可用，说明当前选中项不合法，弹出提示
        if is_instance_valid(_active_dialog): return
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "错误"
        dialog.content_text = "当前选中的谱面不合法，无法进行导出操作。请检查该谱面文件[b]是否完整，包含chart.json、metadata.json和音频文件。[/b][br]并检查[b]是否下载/导入过谱面[/b]。"
        dialog.hide_cancel = true
        add_child(dialog)
        _active_dialog = dialog
        return
    $ExportThis.show()

func _on_import_files_selected(paths: PackedStringArray) -> void:
    import_levels(paths)
    
func _on_export_this_dir_selected(dir: String) -> void:
    export_levels([cycle_list.get_selected_node()], dir)


func _on_exit_pressed() -> void:
    play_sound_effect(SFXType.COMMON)
    await $SFXPlayer.finished
    get_tree().quit()

func _on_settings_pressed() -> void:
    play_sound_effect(SFXType.COMMON)
    if is_instance_valid(_active_dialog): return # 如果对话框已弹出，则忽略请求
    _active_dialog = preload("uid://bcxmdc3up2wat").instantiate()
    add_child(_active_dialog)

func play_sound_effect(type: SFXType):
    if not _is_splashed: return # 未完成开场动画时禁止播放音效
    var player = $SFXPlayer
    match type:
        SFXType.COMMON:
            player.stream = preload("uid://brl0c8l7xal7g")
        SFXType.SETUP:
            player.stream = preload("uid://dschilpvwk0no")
    player.play()


func _on_load_pressed() -> void:
    play_sound_effect(SFXType.SETUP)
    
    var node = cycle_list.get_selected_node()
    if not node or $MarginContainer/UIContainer/LeftPannel/MarginContainer/BG/MarginContainer4/VBoxContainer/BG/MarginContainer2/Load.text == "WTF?":
        # 7. 如果加载按钮不可用，说明当前选中项不合法，弹出提示
        if is_instance_valid(_active_dialog): return
        var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
        dialog.title_text = "错误"
        dialog.content_text = "当前选中的谱面不合法，无法进行替换操作。请检查该谱面文件[b]是否完整，包含chart.json、metadata.json和音频文件。[/b][br]并检查[b]是否下载/导入过谱面[/b]。"
        dialog.hide_cancel = true
        add_child(dialog)
        _active_dialog = dialog
        return
    
    var replace_pairs = _get_synced_replace_pairs()
    
    if node.type == 0: # Type.WORKSHOP
        # 1. & 4. Steam 谱面逻辑
        var found_idx = -1
        for i in range(replace_pairs.size()):
            if replace_pairs[i].get("steam_path") == node.path:
                found_idx = i
                break
                
        if found_idx != -1:
            var pair = replace_pairs[found_idx]
            if pair.get("local_path", "") != "":
                # 4. 已进行过替换，提示复原
                if is_instance_valid(_active_dialog): return
                var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
                dialog.title_text = "提示"
                dialog.content_text = "该Steam谱面已进行过替换操作，若继续将[b]复原谱面文件并取消选中[/b]"
                dialog.check_pressed.connect(_revert_level.bind(node.path))
                add_child(dialog)
                _active_dialog = dialog
            else:
                # 仅选中，提示取消选中
                if is_instance_valid(_active_dialog): return
                var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
                dialog.title_text = "提示"
                dialog.content_text = "该Steam谱面已处于选中状态，是否取消选中？"
                dialog.check_pressed.connect(_cancel_selection.bind(node.path))
                add_child(dialog)
                _active_dialog = dialog
        else:
            # 1. 设置为待替换
            replace_pairs.append({
                "steam_path": node.path,
                "steam_metadata": node.metadata,
                "local_path": "",
                "local_metadata": {}
            })
            _save_synced_replace_pairs(replace_pairs)
            
            if is_instance_valid(_active_dialog): return
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "提示"
            dialog.content_text = "已设置 " + node.metadata.get("title", "未命名") + " 为待替换的Steam谱面 (标号: %d)" % replace_pairs.size()
            dialog.hide_cancel = true
            add_child(dialog)
            _active_dialog = dialog
            
            # 刷新UI显示“已选中”
            refresh(false)

    elif node.type == 1: # Type.LOCAL
        # 2. 本地谱面逻辑
        # 检查是否已作为源，如果是，则取消替换（复原文件但保留选中状态）
        var pair_idx = -1
        for i in range(replace_pairs.size()):
            if replace_pairs[i].get("local_path") == node.path:
                pair_idx = i
                break
        
        if pair_idx != -1:
            var steam_path = replace_pairs[pair_idx].get("steam_path")
            
            # 在复原文件前，保存当前成绩到本地谱面独立存档
            _save_current_score_as_local(steam_path, replace_pairs[pair_idx].get("local_path", ""))
            
            _revert_files_only(steam_path)
            
            # 修复：保存当前成绩到 local_score (作为冗余备份或旧逻辑兼容)
            var steam_id = steam_path.get_file()
            var current_score_json = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, "")
            replace_pairs[pair_idx]["local_score"] = current_score_json
            
            # 恢复 Steam 原谱面分数
            var backup = replace_pairs[pair_idx].get("backup_score", "")
            _save_manager.restore_workshop_score(steam_path, backup)
            
            # 修改配置
            replace_pairs[pair_idx]["local_path"] = ""
            replace_pairs[pair_idx]["local_metadata"] = {}
            # 清除备份的分数记录 (因为 Steam 分数已恢复)
            if replace_pairs[pair_idx].has("backup_score"):
                replace_pairs[pair_idx].erase("backup_score")
                
            _save_synced_replace_pairs(replace_pairs)
            
            if is_instance_valid(_active_dialog): return
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "提示"
            dialog.content_text = "已取消 [color=BLUE]" + node.metadata.get("title", "未知") + "[/color] 的替换状态。[br]目标创意工坊谱面仍处于[b]选中待替换[/b]状态。[br]原谱面成绩已恢复。"
            dialog.hide_cancel = true
            add_child(dialog)
            _active_dialog = dialog
            
            refresh(true)
            return
            
        # 寻找空余的 target
        var target_idx = -1
        for i in range(replace_pairs.size()):
            if replace_pairs[i].get("local_path", "") == "":
                target_idx = i
                break
                
        if target_idx == -1:
            if is_instance_valid(_active_dialog): return
            var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
            dialog.title_text = "提示"
            dialog.content_text = "当前没有空余的待替换目标创意工坊谱面可用，请先选择一个Steam谱面点击SET。"
            dialog.hide_cancel = true
            add_child(dialog)
            _active_dialog = dialog
            return
            
        var target_path = replace_pairs[target_idx].get("steam_path")
        if not DirAccess.dir_exists_absolute(target_path):
            replace_pairs.remove_at(target_idx)
            _save_synced_replace_pairs(replace_pairs)
            push_error("Target steam level not found")
            return
            
        _perform_replace(target_path, node.path, node.metadata, target_idx)

func _cancel_selection(path: String):
    var replace_pairs = _get_synced_replace_pairs()
    for i in range(replace_pairs.size() - 1, -1, -1):
        if replace_pairs[i].get("steam_path") == path:
            replace_pairs.remove_at(i)
    _save_synced_replace_pairs(replace_pairs)
    refresh(false)

func _perform_replace(target_path: String, source_path: String, source_metadata: Dictionary, pair_idx: int):
    # 备份 Steam 谱面的分数
    var replace_pairs = _get_synced_replace_pairs()
    if pair_idx >= 0 and pair_idx < replace_pairs.size():
        _backup_steam_score(target_path, replace_pairs[pair_idx])
        
        var steam_id = target_path.get_file()
        var local_folder_name = source_path.get_file()
        
        # 修复：尝试读取该本地谱面独立保存的成绩
        var saved_local_score = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, "record:local:" + local_folder_name, null)
        
        if saved_local_score != null:
             # 如果有历史成绩，恢复到当前 Steam ID 位置供游戏读取
             _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, saved_local_score)
        elif replace_pairs[pair_idx].has("local_score") and str(replace_pairs[pair_idx]["local_score"]) != "":
             # 兼容旧逻辑：如果配置里有暂存的，也尝试恢复
             _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, replace_pairs[pair_idx]["local_score"])
        else:
             # 首次游玩或无成绩，重置为空
             var empty_record = {"score":0,"completeRate":0.0,"isFullCombo":false,"isClear":false,"hit":0,"bad":0,"miss":0,"maxHit":0,"maxScore":0}
             _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, JSON.stringify(empty_record))
        
    var dir = DirAccess.open(target_path)
    if not dir: return
    
    var steam_id = target_path.get_file()
    var illustration_cache_dir = OS.get_temp_dir().path_join("PigeonGames/Rizline/workshop/cache/illustrations")
    
    # 2.① 处理文件移动/清理
    var origin_dir = target_path.path_join("origin_level")
    if not dir.dir_exists("origin_level"):
        # 第一次替换：将原有文件移动到 origin_level 备份
        dir.make_dir("origin_level")
        var files = dir.get_files()
        for f in files:
            dir.rename(target_path.path_join(f), origin_dir.path_join(f))
            
        # 备份原始曲绘
        var cached_img = illustration_cache_dir.path_join(steam_id)
        if FileAccess.file_exists(cached_img):
            DirAccess.copy_absolute(cached_img, origin_dir.path_join(steam_id))
    else:
        # 已替换过：仅清理根目录下现有的（上一次替换的）文件
        var files = dir.get_files()
        for f in files:
            dir.remove(target_path.path_join(f))
        
    # 2.② 拷贝本地文件到目标
    _copy_dir_contents(source_path, target_path)
    
    # 替换缓存中的曲绘
    var local_img = source_path.path_join("illustration")
    if FileAccess.file_exists(local_img):
        DirAccess.copy_absolute(local_img, illustration_cache_dir.path_join(steam_id))
    
    # 2.③ 保存记录
    # var replace_pairs = config.get_work("replace_pairs", []) # Update to use synced
    if pair_idx >= 0 and pair_idx < replace_pairs.size():
        replace_pairs[pair_idx]["local_path"] = source_path
        replace_pairs[pair_idx]["local_metadata"] = source_metadata
        _save_synced_replace_pairs(replace_pairs)
    
    if is_instance_valid(_active_dialog): return
    var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    dialog.title_text = "成功"
    dialog.content_text = "替换完成！(标号: %d)[br]注：1. Rizline中曲绘刷新需要[b]重新进入“工坊”页[/b][br]2. 成绩刷新[b]需要重启Rizline并同步云存档[/b][br]3. 本地谱面成绩取[b]最近一次的成绩[/b]保留[br]4. Rizline中“关卡设计”项为原有Steam谱面的设计者" % (pair_idx + 1)
    dialog.hide_cancel = true
    add_child(dialog)
    _active_dialog = dialog
    
    refresh(true)

func _revert_level(path: String):
    var replace_pairs = _get_synced_replace_pairs()
    var found_idx = -1
    for i in range(replace_pairs.size()):
        if replace_pairs[i].get("steam_path") == path:
            found_idx = i
            break
            
    if found_idx == -1: return
    
    # 在复原文件前，先保存当前成绩（这是本地谱面的成绩）
    _save_current_score_as_local(path, replace_pairs[found_idx].get("local_path", ""))
    
    _revert_files_only(path)
    
    # 恢复 Steam 分数
    var backup = replace_pairs[found_idx].get("backup_score", "")
    _save_manager.restore_workshop_score(path, backup)
    
    # 清除配置 (此函数被 Steam 谱面触发，意为彻底取消该对关系)
    # 也可以选择不删除，而是保留配置但标记为未激活，以便下次替换时恢复分数?
    # 根据题意 "取消替换...保存a的成绩"，这里确实应该保存下来。
    # 但由于 _revert_level 逻辑是 "复原并取消选中"，意味着关系断裂。
    # 如果要保留成绩供下次使用，逻辑会比较复杂（因为本地谱面是作为 Source 存在的）。
    # 这里我们假设用户可能想保留这个 replace_pair 条目但清空 local。
    
    # 这里我们仅移除配置
    replace_pairs.remove_at(found_idx)
    _save_synced_replace_pairs(replace_pairs)
    
    refresh(true)

# 新增：仅处理文件复原的逻辑（不处理配置）
func _revert_files_only(path: String):
    var dir = DirAccess.open(path)
    if not dir: return
    
    var steam_id = path.get_file()
    var illustration_cache_dir = OS.get_temp_dir().path_join("PigeonGames/Rizline/workshop/cache/illustrations")
    
    # 1. 删除当前根目录下的所有文件 (替换后的文件)
    var files = dir.get_files()
    for f in files:
        dir.remove(f)
        
    # 2. 将 origin_level 下的文件移回
    var origin_dir_path = path.path_join("origin_level")
    var origin_dir = DirAccess.open(origin_dir_path)
    if origin_dir:
        var origin_files = origin_dir.get_files()
        for f in origin_files:
            if f == steam_id:
                # 恢复曲绘到缓存
                DirAccess.copy_absolute(origin_dir_path.path_join(f), illustration_cache_dir.path_join(steam_id))
            else:
                origin_dir.rename(origin_dir_path.path_join(f), path.path_join(f))
        
        # 3. 删除 origin_level 文件夹
        # 注意：DirAccess.remove对于非空文件夹会失败，需要先清理里面的文件
        for f in origin_dir.get_files():
            origin_dir.remove(f)
        dir.remove("origin_level")

func _copy_dir_contents(from_dir: String, to_dir: String):
    var dir = DirAccess.open(from_dir)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if !dir.current_is_dir():
                dir.copy(from_dir.path_join(file_name), to_dir.path_join(file_name))
            file_name = dir.get_next()

# -------------------------------------------------------------------------
# 数据同步与分数管理逻辑
# -------------------------------------------------------------------------

const SYNC_KEY = "rizline-sideloader"

# 获取记录信息（优先从 workshop.sav 读，如果没有则 fallback 到 defaults）
func _get_record_for_node(node: Node) -> Dictionary:
    if not node: return {}
    
    var replace_pairs = _get_synced_replace_pairs()
    
    # CASE 1: 创意工坊谱面 (Workshop Item)
    if node.type == 0: # Type.WORKSHOP
        var steam_id = node.path.get_file()
        if not steam_id.is_valid_int() or steam_id.length() != 10: return {}
        
        # 检查是否被替换
        for pair in replace_pairs:
            if pair.get("steam_path") == node.path:
                # 如果被替换了且有本地路径，说明当前该位置运行的是本地谱面
                # 用户希望此处显示“原成绩”，即备份的成绩
                if pair.get("local_path", "") != "":
                    if pair.has("backup_score"):
                        var backup = pair["backup_score"]
                        if typeof(backup) == TYPE_STRING and backup != "":
                            var parsed = JSON.parse_string(backup)
                            if parsed: return parsed
                        elif typeof(backup) == TYPE_DICTIONARY:
                            return backup
                    # 如果没有备份成绩，返回空或者尝试读取实时（但这可能不符合预期），这里返回空以示区别
                    return {}
                break
        
        # 如果没被替换，显示真实存档
        return _save_manager.get_workshop_record(steam_id)

    # CASE 2: 本地谱面 (Local Item)
    elif node.type == 1: # Type.LOCAL
        # 检查是否作为源替换了某个 Steam 谱面
        for pair in replace_pairs:
            if pair.get("local_path") == node.path:
                var target_steam_path = pair.get("steam_path", "")
                var steam_id = target_steam_path.get_file()
                
                # 如果正在生效，显示该 Steam ID 下的实时存档（即当前游玩该本地谱面的成绩）
                if steam_id.is_valid_int() and steam_id.length() == 10:
                    return _save_manager.get_workshop_record(steam_id)
                break
        
        # 如果未绑定，尝试读取独立保存的本地成绩
        var local_folder_name = node.path.get_file()
        var saved_local_score = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, "record:local:" + local_folder_name, {})
        if typeof(saved_local_score) == TYPE_DICTIONARY:
            return saved_local_score
        elif typeof(saved_local_score) == TYPE_STRING and saved_local_score != "":
             var p = JSON.parse_string(saved_local_score)
             return p if p else {}
                
    return {}

# 检查 Local Config 与 Workshop Save 的同步状态
func _check_data_sync():
    var local_data = config.get_work("replace_pairs", [])
    var sav_data = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, SYNC_KEY, [])
    
    if JSON.stringify(local_data) != JSON.stringify(sav_data):
        if local_data.is_empty() and not sav_data.is_empty():
            # Local 空，Sav 有 -> 信任 Sav
            print("Sync: Local emtpy, trusting Save.")
            config.set_work("replace_pairs", sav_data)
        elif not local_data.is_empty() and sav_data.is_empty():
            # Local 有，Sav 空 -> 信任 Local
            print("Sync: Save empty, trusting Local.")
            _save_to_workshop_sav(local_data)
        else:
            # 冲突
            _show_conflict_dialog(local_data, sav_data)

func _show_conflict_dialog(local_data: Array, sav_data: Array):
    if is_instance_valid(_active_dialog): return
    var dialog = preload("uid://bjwhxckwh2wyu").instantiate()
    dialog.title_text = "数据冲突"
    dialog.content_text = "检测到配置文件与存档文件(workshop.sav)中的替换记录不一致。[br]本地配置记录数: %d，存档文件记录数: %d[br]点击 [b]√[/b] 保留本地配置覆盖存档；[br]点击 [b]x[/b] 保留存档配置覆盖本地。[color=RED]*建议选择，否则会导致Steam谱面成绩丢失[/color]" % [local_data.size(), sav_data.size()]
    
    dialog.hide_cancel = false
    
    # 绑定确认 (√) -> 使用本地配置覆盖存档
    dialog.check_pressed.connect(func(): 
        _save_to_workshop_sav(local_data)
        refresh(true)
    )
    
    # 绑定取消 (x) -> 使用存档配置覆盖本地
    if dialog.has_signal("cancel_pressed"):
         dialog.cancel_pressed.connect(func():
             config.set_work("replace_pairs", sav_data)
             refresh(true)
         )

    add_child(dialog)
    _active_dialog = dialog

func _get_synced_replace_pairs() -> Array:
    # 始终以 config 为准，但在 ready 时我们做了同步
    return config.get_work("replace_pairs", [])

func _save_synced_replace_pairs(data: Array):
    config.set_work("replace_pairs", data)
    _save_to_workshop_sav(data)

func _save_to_workshop_sav(data: Array):
    _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, SYNC_KEY, JSON.stringify(data))

# 备份 Steam 分数到 pair data 中
func _backup_steam_score(steam_path: String, pair_data: Dictionary):
    var steam_id = steam_path.get_file()
    var score_data = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, null)
    if score_data != null:
        pair_data["backup_score"] = score_data
    # 随后记得保存 pair_data 到 config/sav (由调用者 _perform_replace 触发 _save_synced_replace_pairs)

# 恢复 Steam 分数
func _restore_steam_score(steam_path: String, pair_data: Dictionary):
    if pair_data.has("backup_score"):
        var steam_id = steam_path.get_file()
        var backup_json = pair_data["backup_score"]
        _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, backup_json)

# 辅助函数：将当前Steam槽位的成绩保存为本地谱面的独立成绩
func _save_current_score_as_local(steam_path: String, local_path: String):
    if local_path == "": return
    
    var steam_id = steam_path.get_file()
    var local_folder_name = local_path.get_file()
    
    # 获取当前 Steam ID 下的成绩（即刚才玩出来的本地谱面成绩）
    var current_score = _save_manager.get_sav_value(SaveManager.SaveFile.WORKSHOP, "record:" + steam_id, null)
    
    if current_score != null:
        # 保存到独立 Key
        _save_manager.set_sav_value(SaveManager.SaveFile.WORKSHOP, "record:local:" + local_folder_name, current_score)
