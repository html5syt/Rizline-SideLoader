## 垂直循环滚动列表控件。
##
## 该控件提供了一个垂直方向的“跑步机”式循环列表，支持无限滚动，并始终将选中项对齐至中心。[br]
## 当列表项目不足以填满视图时，会自动循环填充以保持视觉上的满溢状态。
@tool
extends Control
class_name CyclicList

## 当选中项发生改变时发出。包含新选中的节点实例及其逻辑索引。
signal selection_changed(item_node: Node, index: int)

## 列表项固定的显示高度（根据 Prefab 自动计算）。
var item_height: float = 100.0

## 列表项之间的垂直间距。
@export var item_spacing: float = 10.0:
    set(v):
        item_spacing = v
        _layout_items()

## 在可视区域之外多渲染的缓冲区项数量（上下各增加）。
@export var items_buffer_extra: int = 2

## 切换选中项时的动画持续时间（秒）。
@export var scroll_duration: float = 0.3

var _templates: Array[Control] = []
var _active_items: Array[Control] = []
# 对象池：Key=模板的对象ID, Value=Array[Control] (回收的实例)
var _pool: Dictionary = {}
var _current_index: int = 0
var _current_scroll_y: float = 0.0
var _tween: Tween

func _ready():
    focus_mode = FOCUS_ALL
    clip_contents = true
    _layout_items()

func _exit_tree():
    # 清理所有池中的对象
    for key in _pool:
        for item in _pool[key]:
            if is_instance_valid(item):
                item.queue_free()
    _pool.clear()
    
    # 清理手动管理的模板
    for t in _templates:
        if is_instance_valid(t) and t.get_parent() == null:
            t.queue_free()

func _gui_input(event):
    if _templates.is_empty():
        return

    # 变更：allow_echo = true (第二个参数) 允许按住连发
    if event.is_action_pressed("ui_down", true) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed):
        _move_selection(1)
        accept_event()
    elif event.is_action_pressed("ui_up", true) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed):
        _move_selection(-1)
        accept_event()

func _get_stride() -> float:
    return item_height + item_spacing

## 原地排序列表项，避免重新实例化
func sort_items(comparator: Callable):
    if _templates.is_empty():
        return
    
    var current_node = null
    if _current_index >= 0 and _current_index < _templates.size():
        current_node = _templates[_current_index]

    _templates.sort_custom(comparator)

    if current_node:
        var new_index = _templates.find(current_node)
        if new_index != -1:
            _current_index = new_index
        else:
            _current_index = 0
    
    # 排序仅改变映射关系，直接更新位置即可
    _update_positions()
    _snap_to_current()

##  添加一个Control作为列表的 Item。
func add_item(node: Control):
    if node == null: return
    _templates.append(node)
    if _templates.size() == 1:
        item_height = node.custom_minimum_size.y if node.custom_minimum_size.y > 0 else node.size.y
        if item_height <= 1.0: item_height = 100.0
    _layout_items()

## 兼容函数：实例化 PackedScene 并将其作为 Item 添加。
func add_prefab(scene: PackedScene):
    if scene:
        var instance = scene.instantiate()
        if instance is Control:
            add_item(instance)
        else:
            instance.free()

## 移除指定索引位置的模板。
func remove_item_at(index: int):
    if index >= 0 and index < _templates.size():
        var t = _templates[index]
        _templates.remove_at(index)
        # 如果模板没有父节点，移除时销毁它
        if is_instance_valid(t) and t.get_parent() == null:
            t.queue_free()
            
        if _current_index >= _templates.size():
            _current_index = max(0, _templates.size() - 1)
        _layout_items()
        _snap_to_current()

## 清空列表所有项。
func clear_list():
    for t in _templates:
        if is_instance_valid(t) and t.get_parent() == null:
            t.queue_free()
    _templates.clear()
    
    # 清空并销毁当前活跃的 item
    for item in _active_items:
        if is_instance_valid(item):
            item.queue_free()
    _active_items.clear()
            
    # 清空对象池
    for key in _pool:
        for p_item in _pool[key]:
            if is_instance_valid(p_item):
                p_item.queue_free()
    _pool.clear()
    
    _current_index = 0
    _layout_items()
    
## 获取当前选中的逻辑索引。
func get_selected_index() -> int:
    return _current_index

## 获取当前视口中心对齐的节点实例。
func get_selected_node() -> Node:
    if _active_items.is_empty(): return null
    
    # 寻找当前选中的节点。
    # 使用 "最小距离中心" 策略，比单纯检查阈值更稳健
    var target_index = _current_index
    var best_node = null
    var min_dist = INF
    var screen_center = size.y / 2.0
    
    for item in _active_items:
        if !is_instance_valid(item): continue
        
        # 检查 items meta 数据是否匹配当前选择的 index
        if item.has_meta("data_index") and item.get_meta("data_index") == target_index:
            var item_center = item.position.y + item_height / 2.0
            var dist = abs(item_center - screen_center)
            
            if dist < min_dist:
                min_dist = dist
                best_node = item
                
    return best_node

## 获取列表总长度。
func get_list_size() -> int:
    return _templates.size()

## 手动跳转到指定的索引项。[br]
## [param index]: 目标项的索引。[br]
## [param animated]: 是否播放三次方平滑滚动动画。[br]
## [b]注意[/b]：该函数会忽略切换的速率限制，直接切换，常常和滚动条搭配。
func set_selected_index(index: int, animated: bool = true):
    if _templates.is_empty():
        return

    var target = posmod(index, _templates.size())
    if target == _current_index and not (_tween and _tween.is_running()):
        return

    _current_index = target
    
    # 计算目标的绝对 Scroll Y 位置，而不是相对位移
    # 这能防止在动画过程中再次触发移动时产生的累积误差
    var target_y = _solve_target_scroll_y(_current_index)

    if animated:
        if _tween and _tween.is_running():
            _tween.kill()
        _animate_to_scroll_y(target_y)
        # 动画结束后信号由动画流程发射
    else:
        _current_scroll_y = target_y
        queue_redraw()
        _update_positions() # 立即刷新布局和meta，确保get_selected_node有效
        selection_changed.emit(get_selected_node(), _current_index)

# 计算离当前 scroll_y 最近的、对应 target_index 的绝对 Y 值
func _solve_target_scroll_y(target_index: int) -> float:
    var stride = _get_stride()
    var total_h = stride * _templates.size()
    if total_h == 0: return _current_scroll_y
    
    var base_target = target_index * stride
    
    # 我们寻找一个 k，使得 base_target + k * total_h 最接近 _current_scroll_y
    # 公式推导: Minimize |(base + k*total) - current|
    # => k * total ~ current - base
    # => k ~ (current - base) / total
    var k = round((_current_scroll_y - base_target) / total_h)
    
    return base_target + k * total_h

func _move_selection(direction: int):
    if _active_items.is_empty(): return
    if _tween and _tween.is_running(): return

    # 修复：直接在当前滚动位置累加方向偏移，确保滚动方向与输入一致
    var target_y = _current_scroll_y + (direction * _get_stride())
    _current_index = posmod(_current_index + direction, _templates.size())
    
    _animate_to_scroll_y(target_y)

func _animate_to_scroll_y(target_y: float):
    var start_val = _current_scroll_y
    var end_val = target_y
    
    if _tween:
        _tween.kill()
    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_IN_OUT)
    _tween.tween_method(func(val):
        _current_scroll_y = val
        _update_positions()
    , start_val, end_val, scroll_duration)
    
    # 动画结束后确保信号发出且节点有效
    _tween.tween_callback(func():
        _update_positions()
        selection_changed.emit(get_selected_node(), _current_index)
    )

# 保留旧函数名以兼容内部其他调用，但重定向逻辑（虽然上面代码已替换了调用）
func _animate_to_selection(steps: int):
    # 计算相对目标的绝对位置
    var stride = _get_stride()
    var end_val = _current_scroll_y + (steps * stride)
    # 注意：这种相对计算仅在静止时准确，建议尽量使用 _animate_to_scroll_y
    _animate_to_scroll_y(end_val)

func _snap_to_current():
    # 注意：对于无限滚动，_current_scroll_y 可能很大，不应该简单重置为 index * stride
    # 除非是在 layout 重置时。这里为了简单，仅在添加/删除时调用。
    _current_scroll_y = _current_index * _get_stride()
    queue_redraw()

func _process(_delta):
    if Engine.is_editor_hint():
        if _active_items.size() == 0 and _templates.size() > 0:
            _layout_items()
        return
    
    _update_positions()

func _layout_items():
    var old_items = _active_items.duplicate()
    _active_items.clear()
    
    if _templates.is_empty():
        # 如果模板为空，清理所有现有项
        for item in old_items:
            item.queue_free()
        return
    
    var stride = _get_stride()
    if stride <= 0.1: stride = 100.0

    # 修复：防止 size.y 为 0 时导致计算出的项过少，设置最小可见数
    var display_height = size.y if size.y > 0 else 1080.0
    var visible_count = ceil(display_height / stride)
    var total_needed = max(visible_count + (items_buffer_extra * 2), 5) # 保证至少有一定数量的实例
    
    for i in range(total_needed):
        var prefab_idx = i % _templates.size()
        var item: Control = null
        if i < old_items.size():
            item = old_items[i]
        else:
            item = _acquire_instance(prefab_idx)
            # 健壮性检查：只有在没有父级或父级不符时操作
            if item.get_parent() == null:
                add_child(item)
            elif item.get_parent() != self:
                item.reparent(self )
            
        _active_items.append(item)
        
        if item is Control:
            item.mouse_filter = MOUSE_FILTER_PASS
            item.custom_minimum_size.y = item_height
            item.size.y = item_height
            
    # 如果 old_items 有多余的，回收到池里
    if old_items.size() > total_needed:
        for j in range(total_needed, old_items.size()):
            _recycle_instance(old_items[j])
            
    _update_positions()

# 从池或新建获取一个实例
func _acquire_instance(template_idx: int) -> Control:
    var template = _templates[template_idx]
    var tid = template.get_instance_id()
    
    if _pool.has(tid) and not _pool[tid].is_empty():
        var instance = _pool[tid].pop_back()
        instance.visible = true
        return instance
    
    # 真正的新建 only here
    var instance = template.duplicate(7)
    # 记录来源模板的 ID
    instance.set_meta("template_id", tid)
    return instance

# 回收实例
func _recycle_instance(item: Control):
    var tid = item.get_meta("template_id", 0)
    if tid == 0:
        item.queue_free()
        return
        
    if not _pool.has(tid):
        _pool[tid] = []
        
    item.visible = false
    # 移出树可能会有一些副作用，这里仅隐藏并保留在树上，或者 remove_child
    # 为了避免 _layout_items 时 add_child 报错，如果还在树上就不用 add
    # 这里根据 Godot 建议，对象池对象通常保留在树上只是隐藏，或者 remove_child
    # 考虑到 list item 位置会变，隐藏比较简单。但 _update_positions 会重排 y
    # 只要不在 _active_items 里，就不会被 _update_positions 处理
    _pool[tid].append(item)

func _update_positions():
    if _templates.is_empty() or _active_items.is_empty():
        return

    var stride = _get_stride()
    var center_offset = (size.y / 2.0) - (item_height / 2.0)
    var item_count = _active_items.size()
    
    var center_logical_idx = int(floor(_current_scroll_y / stride))
    var start_offset_idx = center_logical_idx - int(floor(item_count / 2.0))
    
    for i in range(item_count):
        var item = _active_items[i]
        if !is_instance_valid(item): continue

        var logical_index = start_offset_idx + i
        var prefab_data_index = int(logical_index) % _templates.size()
        if prefab_data_index < 0:
            prefab_data_index += _templates.size()

        # 检查是否需要替换内容 - 提前检查，避免修改可能即将被替换的 item 的 meta/pos
        var expected_template = _templates[prefab_data_index]
        var current_tid = item.get_meta("template_id", 0)
        
        var pos_y = (logical_index * stride) - _current_scroll_y + center_offset

        if current_tid != expected_template.get_instance_id():
            var idx = item.get_index()
            _recycle_instance(item)
            
            var new_item = _acquire_instance(prefab_data_index)
            
            if new_item.get_parent() == null:
                add_child(new_item)
            elif new_item.get_parent() != self:
                new_item.reparent(self )
                
            move_child(new_item, idx)
            
            _active_items[i] = new_item
            item = new_item
            
            item.set_meta("template_id", expected_template.get_instance_id())
            if item is Control:
                item.mouse_filter = MOUSE_FILTER_PASS
                item.custom_minimum_size.y = item_height

        # 修复：同步自定义变量状态（由于克隆不拷贝脚本变量）
        if "favourite" in expected_template and "favourite" in item:
            item.favourite = expected_template.favourite

        # 更新位置和数据索引
        item.set_meta("logical_index", logical_index)
        item.set_meta("data_index", prefab_data_index)
        
        if item.position.y != pos_y:
            item.position = Vector2(0, pos_y)
        item.size = Vector2(size.x, item_height)

func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_items()
