# -*- coding: utf-8 -*-
"""
一键补验：把待验证清单跑成可复现的结论。

为什么需要这个脚本：这轮有 6 项改动只过了编译、没在设备上跑过。
模拟器恢复后手工点一遍既慢又容易漏，所以固化成脚本 —— 每次恢复后
直接跑一遍，输出明确的通过/失败，而不是靠人回忆「刚才好像点过了」。

用法：
    python -u verify_all.py            # 全跑
    python -u verify_all.py --keep     # 跑完不清理截图

判据说明：
    · 定位靠 UI 树文本，不靠坐标（滚动后会漂）
    · 「页面渲染出来了」的判据 = 该页关键文本出现在 UI 树里
    · 设备桥接连不上时直接退出，不假装跑过
"""
import os
import re
import hashlib
import subprocess
import sys
import time

from harmony_paths import hdc_path, repo_path, shots_dir, entry_dir

# 路径全部从仓库位置反推 —— 原先写死的 C:\Users\... 迁到 Mac 就失效了
HDC = hdc_path()
TREE = repo_path('tools', '_t.json')
SHOTS = shots_dir()
BUNDLE = "com.rinne.caloriefit"
ABILITY = "EntryAbility"
HAP = os.path.join(entry_dir(), 'build', 'default', 'outputs', 'default', 'entry-default-unsigned.hap')

# `uitest uiInput swipe` 的第 5 个参数是**速度**（200~40000，默认 600），不是时长。
# 原脚本传 250（最慢档），1200px 的一次滚动要约 4.8 秒，一轮回归里几十次滚动
# 会把整轮拖成十几分钟，表现为"脚本卡住不动"。本机实测：250 → 5.9s，4000 → 0.45s。
SWIPE_VELOCITY = 4000
# 轮播条是横向定点滑动，需要在截图前滑完，速度同样调快，避免拍到动画中途。
CAROUSEL_VELOCITY = 2000
#
# 扫描用的滑动必须**慢**，与 scroll_top 不同：
#   scroll_top 只求滚到页面顶部，甩过头无妨，所以用最快的 4000；
#   扫描是"边滚边找目标"，速度一快，惯性 fling 会把目标直接带过采样窗口 ——
#   表现为"滑了 N 次仍未找到「X」"，而且加长等待也救不回来（见下方实测）。
# 本机模拟器实测（每种配置各跑 3 次，记录是否命中「全部餐食」）：
#   4000 + 等 0.5s → 命中 1/3     4000 + 等 1.2s → 命中 2/3
#   1500 + 等 0.8s → 命中 3/3     1500 + 等 1.2s → 命中 3/3
# 1500 单次 1.0s，比 4000 的 0.45s 慢，但换来的是确定性。
SCAN_VELOCITY = 1500
SCAN_SETTLE = 0.8


def sh(*args, timeout=120):
    return subprocess.run([HDC] + list(args), capture_output=True, text=True, timeout=timeout)


def connected():
    """只接受目标在线；`-v` 可能同时列出 TCP Offline 的残留 target。"""
    try:
        r = sh('list', 'targets', '-v')
        if r.returncode != 0:
            return False
        return any(
            '127.0.0.1:5555' in line and
            not re.search(r'\b(offline|disconnected)\b', line, re.IGNORECASE)
            for line in (r.stdout or '').splitlines()
        )
    except Exception:
        return False


def fetch_tree(retries=5):
    """取回 UI 树的原始 JSON（含所有节点，不做 text 过滤）。

    底栏只留图标后，Tab 本身没有文字可查，只能靠 TabBar 下的可点击子项定位，
    所以需要能看到「没有 text 但可点击」的节点。
    """
    last = None
    for _ in range(retries):
        # 屏幕熄灭时 dumpLayout 会报 "Get window nodes failed"，
        # 重试前先唤醒屏幕 —— 否则只是在黑屏上空转 5 次。
        # 这轮踩过：模拟器息屏后连续三次在第一步就失败，唤醒后同一步立刻通过。
        sh('shell', 'power-shell', 'wakeup')
        layout = sh('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/t.json')
        layout_output = '\n'.join(part.strip() for part in (layout.stdout, layout.stderr) if part).strip()
        if layout.returncode != 0 or re.search(r'DumpLayout failed', layout_output, re.IGNORECASE):
            last = RuntimeError(layout_output or f'dumpLayout exit={layout.returncode}')
            time.sleep(1.5)
            continue
        receive = sh('file', 'recv', '/data/local/tmp/t.json', TREE)
        if receive.returncode != 0:
            last = RuntimeError((receive.stdout or receive.stderr or f'file recv exit={receive.returncode}').strip())
            time.sleep(1.2)
            continue
        try:
            import json
            with open(TREE, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:
            last = e
            time.sleep(1.2)
            continue
        return data
    raise RuntimeError(f'dumpLayout failed: {last}')


def dump(retries=5):
    """只返回**有文字**的节点（外加空 TextInput，填表要用）。"""
    data = fetch_tree(retries)
    out = []

    def walk(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or {}
        # 空输入框的 text 是空串，会被 `if a.get('text')` 滤掉 —— 但填写
        # 表单时正需要按位置找到空框，所以 TextInput 一律收进来。
        if a.get('text') or a.get('type') == 'TextInput':
            out.append({'text': a['text'], 'bounds': a.get('bounds', ''),
                        'type': a.get('type', '')})
        for c in (n.get('children') or []):
            walk(c)

    walk(data)
    return out


def dump_all(retries=5):
    """返回 UI 树里的**全部**节点（连空 text 的也要）。

    底栏只留图标后，Tab 本身没有文字可查，只能靠 TabBar 下的可点击子项定位，
    所以需要能看到「没有 text 但可点击」的节点。
    """
    data = fetch_tree(retries)
    out = []

    def walk(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or {}
        out.append({'type': a.get('type', ''), 'bounds': a.get('bounds', ''),
                    'clickable': a.get('clickable', ''), 'text': a.get('text', '')})
        for c in (n.get('children') or []):
            walk(c)

    walk(data)
    return out


def center(bounds):
    n = [int(x) for x in re.findall(r'\d+', bounds or '')]
    return ((n[0] + n[2]) // 2, (n[1] + n[3]) // 2) if len(n) >= 4 else None


def texts(nodes):
    return [n['text'] for n in nodes]


def has(nodes, kw):
    return any(kw == t or kw in t for t in texts(nodes))


def tap(kw, settle=2.2):
    nodes = dump()
    hit = next((n for n in nodes if n['text'] == kw), None) or \
          next((n for n in nodes if kw in n['text']), None)
    if not hit:
        return False
    c = center(hit['bounds'])
    if not c:
        return False
    sh('shell', 'uitest', 'uiInput', 'click', str(c[0]), str(c[1]))
    time.sleep(settle)
    return True


def back():
    sh('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
    time.sleep(2.0)


# 底栏 Tab 与名称的顺序对应。
# 2026-10-21 起底栏**只保留图标按钮**，文字标签已从可见层去掉 ——
# UI 树里再也查不到「今日/进度/我的」这几个字，按文本点的老写法全部失效。
TAB_ORDER = ['今日', '进度', '我的']


def _bounds(bounds):
    n = [int(x) for x in re.findall(r'\d+', bounds or '')]
    return (n[0], n[1], n[2], n[3]) if len(n) >= 4 else (0, 0, 0, 0)


def tab_centers():
    """底栏各 Tab 的中心坐标（按从左到右）。

    底栏没有文字可查，只能取 TabBar 下的**可点击**子项 ——
    比写死坐标稳：底栏高度变了、Tab 数量变了都不会点空。
    """
    nodes = dump_all()
    bar = next((n for n in nodes if n['type'] == 'TabBar'), None)
    if bar is None:
        return []
    bx0, by0, bx1, by1 = _bounds(bar['bounds'])
    if bx1 <= bx0:
        return []
    pts = []
    for n in nodes:
        if n['clickable'] != 'true':
            continue
        x0, y0, x1, y1 = _bounds(n['bounds'])
        if x0 >= bx0 and x1 <= bx1 and y0 >= by0 and y1 <= by1:
            pts.append(((x0 + x1) // 2, (y0 + y1) // 2))
    return sorted(set(pts))


def tap_tab(label, settle=2.2):
    """按名称点底栏 Tab。名字只用来查顺序，坐标从 UI 树实测。"""
    pts = tab_centers()
    if len(pts) == 0:
        # App 冷启动会恢复上次的路由栈，停在二级页时根本没有底栏。
        # 先退回主界面再找，别直接判失败。
        for _ in range(6):
            back()
            time.sleep(1.2)
            pts = tab_centers()
            if len(pts) > 0:
                break
    if label not in TAB_ORDER:
        print(f'unknown tab: {label}')
        return False
    idx = TAB_ORDER.index(label)
    if idx >= len(pts):
        print(f'tab {label} not found (bar has {len(pts)} items)')
        return False
    x, y = pts[idx]
    sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
    time.sleep(settle)
    return True


def scroll_top(times=8):
    """把页面滚回顶部。

    速度参数说明：`uitest uiInput swipe <x1> <y1> <x2> <y2> [velocity]` 的
    第 5 个参数是**速度**（200~40000，默认 600），不是时长。
    写 250 等于最慢速滑动，1200px 要走约 4.8 秒，一次滚动就拖垮整轮回归
    （本机实测：velocity 250 → 5.9s/次，4000 → 0.45s/次）。
    """
    for _ in range(times):
        sh('shell', 'uitest', 'uiInput', 'swipe', '640', '900', '640', '2100', str(SWIPE_VELOCITY))
        time.sleep(0.35)
    # 末次滑动是带惯性的 fling，手指抬起后内容还在继续往顶部滚。
    # 不等它停稳就取树，采到的是动画中途的帧 —— 下一轮扫描的第一次取树就会失准。
    time.sleep(1.2)


def home_top():
    """返回今日首页并把纵向列表复位，避免复用旧滚动位置。

    底栏只有图标、没有文字，所以「当前在不在今日页」不能再靠查「今日」两个字，
    改成查今日页特有的文案（今日摄入）。
    """
    for _ in range(4):
        nodes = dump()
        if has(nodes, '今日摄入'):
            scroll_top()
            return True
        if not tap_tab('今日', settle=2.5):
            return False
        scroll_top()
        if has(dump(), '今日摄入'):
            return True
        back()
    return False


def read_toggles():
    """只返回开关的 bounds/checked，不把设置页其他控件内容输出到日志。"""
    import json
    remote = '/data/local/tmp/verify_layout.json'
    local = repo_path('tools', '_t.json')
    sh('shell', 'uitest', 'dumpLayout', '-p', remote)
    sh('file', 'recv', remote, local)
    with open(local, 'r', encoding='utf-8') as f:
        root = json.load(f)
    out = []

    def walk(node):
        if not isinstance(node, dict):
            return
        attrs = node.get('attributes') or {}
        if attrs.get('type') == 'Toggle':
            out.append({'bounds': attrs.get('bounds', ''),
                        'checked': str(attrs.get('checked', 'false')).lower()})
        for child in node.get('children') or []:
            walk(child)

    walk(root)
    return out


def enable_demo_mode():
    """在本次验证会话开启本地 AI 模拟，避免把示例图发往已配置服务。"""
    if not tap_tab('我的', settle=2.5):
        return False
    scroll_top()
    if not find_and_tap('AI 食物识别设置', max_scroll=20, settle=3.0):
        return False
    toggles = read_toggles()
    if len(toggles) < 2:
        return False
    demo = toggles[1]
    if demo['checked'] != 'true':
        point = center(demo['bounds'])
        if point is None:
            return False
        sh('shell', 'uitest', 'uiInput', 'click', str(point[0]), str(point[1]))
        time.sleep(1.0)
        toggles = read_toggles()
        if len(toggles) < 2 or toggles[1]['checked'] != 'true':
            return False
    back()
    if not tap_tab('今日', settle=2.5):
        return False
    scroll_top()
    return has(dump(), '今日摄入')


def accept_privacy_for_test():
    """验证首次告知/政策可达；只在测试设备上显式同意健康数据处理。"""
    nodes = dump()
    if not has(nodes, '请先阅读隐私说明'):
        print('    当前已存在本版本的隐私同意记录')
        return True

    shot('v_00_privacy_consent')
    if not tap('阅读完整隐私政策', settle=1.0):
        print('    隐私政策入口不可达')
        return False
    policy = dump()
    if not has(policy, '运营主体') or not has(policy, '待填写运营主体法定全称'):
        print('    完整隐私政策内容未渲染')
        return False
    shot('v_00_privacy_policy')
    if not tap('‹', settle=0.5) or not has(dump(), '请先阅读隐私说明'):
        print('    无法返回隐私同意页')
        return False
    if not tap('我已阅读并同意', settle=0.4):
        print('    通用隐私同意项不可操作')
        return False
    if not tap('我单独同意处理身体档案', settle=0.4):
        print('    健康信息单独同意项不可操作')
        return False
    if not tap('同意并继续', settle=3.0):
        print('    同意按钮不可操作')
        return False
    return not has(dump(), '请先阅读隐私说明')


def _set_field(idx, value):
    """把第 idx 个输入框设为 value。

    uitest 的 inputText 是**追加**而不是替换，所以必须先清空。
    清空不能只按固定次数的 DEL —— 实测会残留字符（21.5 → 21.55），
    因此这里「按 DEL → 确认该框已空 → 才输入 → 确认等于目标值」，
    每一步都读回 UI 树核对。
    """
    for _ in range(3):
        nodes = [n for n in dump() if n.get('type') == 'TextInput']
        if idx >= len(nodes):
            return False
        if nodes[idx]['text'] == value:
            return True
        c = center(nodes[idx]['bounds'])
        if c is None:
            return False
        sh('shell', 'uitest', 'uiInput', 'click', str(c[0]), str(c[1]))
        time.sleep(0.8)
        for _ in range(20):
            sh('shell', 'uitest', 'uiInput', 'keyEvent', '2055')
        time.sleep(0.6)
        nodes = [n for n in dump() if n.get('type') == 'TextInput']
        if idx >= len(nodes) or nodes[idx]['text'] != '':
            continue  # 没清干净，重来
        sh('shell', 'uitest', 'uiInput', 'inputText', str(c[0]), str(c[1]), value)
        time.sleep(1.0)
        nodes = [n for n in dump() if n.get('type') == 'TextInput']
        if idx < len(nodes) and nodes[idx]['text'] == value:
            return True
    return False


def fill_body_data(values):
    """往引导第 3 步「你的身体数据」表单里填值并选性别。"""
    for _ in range(3):
        if not all(_set_field(i, v) for i, v in enumerate(values)):
            continue
        # 收键盘：键盘开着时页面下半部分被挡住，滑动起点会落在键盘上 ——
        # 实测滑一次就把键盘上的数字敲进了体脂率框（21.5 → 21.55）。
        # 焦点在输入框上时返回键只会收键盘，不会退出页面。
        sh('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
        time.sleep(1.2)
        if not has(dump(), '你的身体数据'):
            return False
        # 性别：选「男」。若仍落在折叠线以下就往下滚（手指上滑 2000→900）。
        for _ in range(5):
            if tap('男', settle=1.2):
                return True
            sh('shell', 'uitest', 'uiInput', 'swipe', '640', '2000', '640', '900',
               str(SCAN_VELOCITY))
            time.sleep(SCAN_SETTLE)
        return False
    return False


def complete_onboarding_for_test():
    """全新同意/数据删除后的首启会进入六步引导，完成它再测主页面。"""
    if has(dump(), '今日摄入'):
        print('    模拟器已有完成引导的用户，保留现有数据并跳过首启引导')
        return True

    # 第 3 步是身体数据表单，必填项不填就点不动「继续」
    body_values = ['70.5', '178', '33', '21.5']
    sequence = [
        ('你想达成什么', '继续'),
        ('平时的活动量', '继续'),
        ('你的身体数据', '继续'),
        ('随时掌握进度', '继续'),
        ('你会吃补剂吗', '继续'),
        ('你的生活方式', '开始使用'),
    ]
    for title, cta in sequence:
        nodes = dump()
        if has(nodes, '今日摄入'):
            return True
        if not has(nodes, title):
            print(f'    引导步骤未到预期页面：{title}')
            return False
        if title == '你的身体数据':
            if not fill_body_data(body_values):
                print('    身体数据填写失败')
                return False
        if not tap(cta, settle=3.0 if cta == '开始使用' else 1.0):
            print(f'    引导 CTA 不可用：{cta}（{title}）')
            return False
    if not has(dump(), '今日摄入'):
        return False

    # 引导应当把用户填的体征写进档案，且**不出现旧版伪造的默认值**。
    if not tap_tab('我的', settle=2.5):
        return False
    scroll_top()
    profile_nodes = dump()
    if any(n['text'] in ('65', '170') for n in profile_nodes):
        print('    首次引导后仍出现旧版体征默认值')
        return False
    entered = [n['text'] for n in profile_nodes if n.get('type') == 'TextInput']
    if not all(v in entered for v in body_values):
        print(f'    引导填写的体征未落到档案：{entered}')
        return False
    print(f'    PASS  引导填写的体征已落到档案：{body_values}')
    if not tap_tab('今日', settle=2.5):
        return False
    scroll_top()
    return has(dump(), '今日摄入')


def find_and_tap(kw, max_scroll=12, settle=2.5):
    """边下滑边找目标文本，找到就点。

    固定滑动次数找长页面里的入口是不可靠的：滚少了够不着，
    滚多了又滑过头。前面两次「全部餐食」FAIL 都是这个原因 ——
    属于脚本定位问题，不是应用问题（条目卡本身渲染是正常的）。
    """
    for i in range(max_scroll):
        nodes = dump()
        hit = next((n for n in nodes if n['text'] == kw), None) or \
              next((n for n in nodes if kw in n['text']), None)
        if hit:
            c = center(hit['bounds'])
            if c:
                sh('shell', 'uitest', 'uiInput', 'click', str(c[0]), str(c[1]))
                time.sleep(settle)
                return True
        sh('shell', 'uitest', 'uiInput', 'swipe', '640', '2000', '640', '900', str(SCAN_VELOCITY))
        time.sleep(SCAN_SETTLE)
    print(f'    (scroll_and_tap: 滑了 {max_scroll} 次仍未找到「{kw}」)')
    return False


def shot(name):
    sh('shell', 'snapshot_display', '-f', '/data/local/tmp/s.jpeg')
    sh('file', 'recv', '/data/local/tmp/s.jpeg', os.path.join(SHOTS, name + '.jpeg'))
    print(f'    shot -> {name}.jpeg')


RESULTS = []


def check(name, fn):
    print(f'\n[CHECK] {name}')
    try:
        ok, detail = fn()
    except Exception as e:
        ok, detail = False, f'exception: {e}'
    if detail.startswith('SKIP:'):
        result = None
        detail = detail[len('SKIP:'):].strip()
        status = 'SKIP'
    else:
        result = ok
        status = 'PASS' if ok else 'FAIL'
    RESULTS.append((name, result, detail))
    print(f'    => {status}  {detail}')
    return result is True


# ---------------- 各项检查 ----------------

def c_home():
    """今日页主体是黑板：板面概览 + nosh 式日期胶囊条。

    2026-10-20 起，当日黑板成为今日页第一屏主体，原版复刻的「今日热量」
    半环卡已从首页移除（其数据在进度页仍在），所以这里验的是黑板。
    """
    ok = home_top()
    nodes = dump()
    required = ('今日摄入', '还可以吃', 'kcal', '蛋白', '碳水', '脂肪')
    rendered = all(has(nodes, text) for text in required)
    return ok and rendered, '黑板表头显示摄入/剩余与宏量摘要'


def c_date_strip():
    """nosh 式横排日期胶囊条：显示本周日期，当日高亮。"""
    if not home_top():
        return False, '无法回到今日首页'
    nodes = dump()
    # 胶囊上写的是**独立**的星期单字文本节点；用包含匹配会被别的文案误命中
    exact = [n for n in nodes if n['text'] in ('一', '二', '三', '四', '五', '六', '日')]
    return len(exact) >= 3, f'日期胶囊条渲染（{len(exact)} 个星期单字）'


def c_ai_entry():
    if not home_top():
        return False, '无法回到今日首页顶部'
    # 2026-10-21：黑板占满首屏后，「今日餐食」标题右侧的拍照入口
    # 正好落在右下角悬浮「+」按钮的下方 —— 点它会先命中 FAB、跳到记��页。
    # 所以这里改点黑板操作排里的常驻「拍照」入口（一拍即贴的主入口）。
    ok = tap('拍照', settle=4.0)
    return ok and has(dump(), 'AI 食物识别'), 'AI 入口进入识别页'


def c_meal_cards():
    if not home_top():
        return False, '无法回到今日首页顶部'
    # 早餐卡片通常在首屏以下；HomePage 的 Scroll 只把可见项挂进 UI 树，
    # 所以先滚动到它出现，再按可见 bounds 点击。
    # 2026-10-21：黑板上的示例贴纸也写着「早餐/午餐/晚餐」，
    # 按「早餐」找会命中黑板而不是餐食卡片 ——
    # 改用餐食卡片独有的 emoji 定位（黑板上没有这个符号）。
    ok = find_and_tap('🍳', max_scroll=12, settle=4.0)
    return ok and has(dump(), '餐食详情'), '早餐卡片进入餐食详情'


def c_meal_detail():
    """餐食详情页渲染。

    两种状态都要认：当天这一餐**没有记录**时显示空态，有记录时显示明细。
    之前只认空态，于是当天一旦有记录就误判 FAIL —— 而 verify_blackboard.py
    会往当天写一条记录，两者连着跑时必然踩到。回归脚本不该依赖数据状态。
    """
    nodes = dump()
    empty = has(nodes, '这一餐还没有记录')
    filled = has(nodes, '蛋白') and has(nodes, '碳水') and has(nodes, '脂肪')
    ok = has(nodes, '餐食详情') and (empty or filled)
    return ok, '餐食详情页渲染（空态或已有记录）'


def _shot_bytes():
    sh('shell', 'snapshot_display', '-f', '/data/local/tmp/c.jpeg')
    local = repo_path('tools', '_c.jpeg')
    sh('file', 'recv', '/data/local/tmp/c.jpeg', local)
    with open(local, 'rb') as f:
        return f.read()


def _pixels(img):
    """取灰度图的像素序列。

    Pillow 13 起 `getdata()` 被标记弃用（2027-10-15 移除），改用
    `get_flattened_data()`；老版本 Pillow 没有这个方法，回退到 getdata()。
    """
    getter = getattr(img, 'get_flattened_data', None)
    if getter is not None:
        return getter()
    return img.getdata()


def c_carousel():
    """轮播条横向滚动 —— 用**像素**判据，不看 UI 树。

    为什么不用树：dumpLayout 会把 Scroll 里屏外的兄弟节点一并列出来，
    所以「第一条提示还在树上」根本不能证明它在屏内。除比较轮播带像素外，
    还比较主卡标题锚点；若竖向页面位置变化，测试直接失败。
    """
    from PIL import Image, ImageChops
    import io

    tip1 = '拍照识别后可核对'
    if not home_top():
        return False, '无法复位到今日首页顶部'
    nodes = dump()
    hit = next((n for n in nodes if tip1 in n['text']), None)
    if not hit:
        return False, f'首条提示「{tip1}」不在 UI 树上，无法定位轮播条'
    y = center(hit['bounds'])[1]
    print(f'    轮播条 y={y}（按 UI 树定位，非写死坐标）')

    hero = next((n for n in nodes if n['text'] == '今日摄入'), None)
    if hero is None:
        return False, '主卡标题不在当前视口，无法确认页面滚动位置'
    hero_y = center(hero['bounds'])[1]

    before = Image.open(io.BytesIO(_shot_bytes())).convert('RGB')

    # 起点选 700 而不是 1000：轮播条在首屏底部时，
    # 右边正好压着右下角的悬浮「+」按钮，从那里起手会变成点 FAB。
    sh('shell', 'uitest', 'uiInput', 'swipe', '700', str(y), '200', str(y), str(CAROUSEL_VELOCITY))
    time.sleep(1.8)

    after = Image.open(io.BytesIO(_shot_bytes())).convert('RGB')
    if before.size != after.size:
        return False, '前后截图尺寸不一致，无法比较'

    # 主卡标题与其背景保持静止，用它识别滑动是否误触发了外层纵向 Scroll。
    anchor = (0, max(0, hero_y - 60), before.size[0], min(before.size[1], hero_y + 60))
    anchor_diff = ImageChops.difference(before.crop(anchor), after.crop(anchor)).convert('L')
    anchor_changed = sum(1 for px in _pixels(anchor_diff) if px > 12)
    anchor_ratio = anchor_changed / max(1, (anchor[2] - anchor[0]) * (anchor[3] - anchor[1]))
    print(f'    主卡锚点变化率 {anchor_ratio*100:.2f}%')
    if anchor_ratio > 0.02:
        return False, f'主卡锚点变化 {anchor_ratio*100:.2f}%，页面发生了竖向位移'

    # 只取轮播条所在横带：避开上下会变的日期/数字
    band = (0, max(0, y - 45), before.size[0], min(before.size[1], y + 45))
    diff = ImageChops.difference(before.crop(band), after.crop(band))
    changed = sum(1 for px in _pixels(diff.convert('L')) if px > 12)
    total = band[3] - band[1]
    ratio = changed / max(1, (band[2] - band[0]) * total)
    print(f'    横带像素变化率 {ratio*100:.1f}%')
    if ratio < 0.10:
        return False, f'横带几乎没变（{ratio*100:.1f}%），轮播条未响应滑动'
    return True, f'轮播条横带变化 {ratio*100:.1f}%，确已横向滚动'


def c_sample_ai():
    if not home_top():
        return False, '无法回到今日首页顶部'
    # 点黑板操作排里的「拍照」入口：
    # 「今日餐食」标题右侧那个拍照入口正好落在右下角悬浮「+」按钮下方，
    # 点它会先命中 FAB、跳到记录页。
    if not tap('拍照', settle=4.0):
        return False, 'AI 入口无法打开'
    ok = tap('没有照片？用内置示例图试一下', settle=3.5)
    nodes = dump()
    return ok and has(nodes, '更换图片') and has(nodes, '开始 AI 识别'), '示例图载入并启用识别按钮'


def c_foodlog():
    if not home_top():
        return False, '无法回到今日首页顶部'
    tap_tab('我的', settle=3.0)
    scroll_top()
    ok = find_and_tap('全部餐食', settle=3.0)
    nodes = dump()
    return ok and has(nodes, '饮食记录'), 'NavDestination 包裹后的饮食列表渲染'


def count_exact(nodes, value):
    return sum(1 for n in nodes if n['text'] == value)


def relaunch_app():
    sh('shell', 'aa', 'force-stop', BUNDLE)
    start = sh('shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY)
    time.sleep(5.0)
    return start.returncode == 0


def c_blackboard_page():
    """今日黑板就在今日页第一屏（不再是二级页面）。

    只做只读检查 —— 不写入任何饮食记录，避免污染回归流程的数据状态。
    需要写入记录的完整链路（抠图 → 保存 → 便签墙）在 verify_blackboard.py 里验。
    """
    if not home_top():
        return False, '无法回到今日首页'
    nodes = dump()
    # 超预算时右侧文案会变成「已超出」，两种都要认
    ok = has(nodes, '今日摄入') and (has(nodes, '还可以吃') or has(nodes, '已超出'))
    return ok, '今日页第一屏即黑板（摄入 + 剩余额度）'

def ensure_today_tab():
    """从个人页或子路由回到今日主 Tab，避免误把不可见子页当成产品故障。"""
    for _ in range(5):
        nodes = dump()
        if has(nodes, '今日摄入'):
            return True
        if tap_tab('今日', settle=2.5):
            scroll_top()
            if has(dump(), '今日摄入'):
                return True
        back()
    return has(dump(), '今日摄入')


def c_privacy_collected_inventory():
    """个人信息保护「已收集个人信息清单」必须可达且有实质内容。

    工信部 292 号文要求双清单在二级菜单展示，应用市场把它列为上架要求。
    入口若被后续改动删掉，审核会被直接驳回，所以固化成回归项。
    """
    if not tap_tab('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('已收集个人信息清单', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「已收集个人信息清单」入口不可达'
    nodes = dump()
    required = ('已收集个人信息清单', '身体档案', '使用目的', '使用场景', '存储位置')
    if not all(has(nodes, t) for t in required):
        return False, '清单页缺少必备字段'
    return True, '入口可达，采集项逐条标注用途/场景/存储位置'


def c_privacy_shared_inventory():
    """个人信息保护「第三方共享个人信息清单」必须可达且写明接收方。"""
    if not tap_tab('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('第三方共享个人信息清单', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「第三方共享个人信息清单」入口不可达'
    nodes = dump()
    # 接收方必须同时写出默认服务方（OpenCSG）与备用服务方（百炼），
    # 否则清单与实际默认配置对不上，属于披露不实。
    required = ('第三方共享个人信息清单', 'OpenCSG', '阿里云百炼', '接收方', '使用目的', '共享方式')
    if not all(has(nodes, t) for t in required):
        return False, '共享清单页缺少接收方或共享方式'
    return True, '入口可达，共享项写明接收方与共享方式'


def c_privacy_policy():
    """隐私政策正文必须含免责条款与待补齐提示。"""
    if not tap_tab('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('查看隐私政策', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「查看隐私政策」入口不可达'
    nodes = dump()
    if not has(nodes, 'CalorieFit 隐私政策'):
        return False, '隐私政策正文未渲染'
    # 免责条款在第三节。政策正文很长，第三节可能落在首屏之外；
    # 往**下**滚找它，找不到再往回滚 —— 只朝一个方向找会漏。
    def found_disclaimer() -> bool:
        return any('医疗建议' in t for t in texts(dump()))

    if found_disclaimer():
        return True, '政策可达，含免责条款'
    for _ in range(8):
        sh('shell', 'uitest', 'uiInput', 'swipe', '640', '2000', '640', '900', str(SCAN_VELOCITY))
        time.sleep(SCAN_SETTLE)
        if found_disclaimer():
            return True, '政策可达，含免责条款'
    for _ in range(8):
        sh('shell', 'uitest', 'uiInput', 'swipe', '640', '900', '640', '2100', str(SCAN_VELOCITY))
        time.sleep(SCAN_SETTLE)
        if found_disclaimer():
            return True, '政策可达，含免责条款'
    return False, '隐私政策缺少「不构成医疗建议」的免责条款'


def c_account_login():
    """华为账号入口可达，且页面处于「未配置」或「已配置」两种合法态之一。

    真正的登录链路需要 AGC 的 client_id + 已签名的包，CI/模拟器上跑不通，
    所以这里只验**入口与状态机**：入口能进、页面渲染、且要么明确提示
    client_id 未配置，要么给出登录界面（协议勾选 + 官方按钮）。
    """
    if not tap_tab('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('华为账号', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「华为账号」入口不可达'
    nodes = dump()
    if has(nodes, '尚未配置 client_id'):
        return True, '入口可达，未配置 client_id 时给出明确提示'
    required = ('登录华为账号', '我已阅读并同意', '华为账号登录')
    if not all(has(nodes, t) for t in required):
        return False, '账号页缺少协议勾选或官方登录按钮'
    return True, '入口可达，协议勾选与官方登录按钮均已渲染'


def c_ai_sample_flow():
    """示例图完整链路：选图 → 本地演示识别 → 出结果，不发起网络请求。"""
    # 按钮实际文案是「开始 AI 识别」，不是「开始识别」——
    # 上一轮写成后者导致点空，FAIL 是脚本的锅。
    ok = tap('开始 AI 识别', settle=8.0)
    nodes = dump()
    return ok and has(nodes, '识别结果') and has(nodes, '演示食物（模拟识别）'), '演示模式返回本地识别结果'


def main():
    if not connected():
        print('设备桥接不可用，无法补验。')
        print('请先在 DevEco 图形界面重启模拟器，再跑本脚本。')
        return 2

    if not os.path.isfile(HAP):
        print(f'当前 HAP 不存在，无法补验：{HAP}')
        return 3
    with open(HAP, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    stat = os.stat(HAP)
    print(f'HAP: {HAP}')
    print(f'HAP bytes: {stat.st_size}; modified: {time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(stat.st_mtime))}')
    print(f'HAP SHA-256: {digest}')

    print('=== 安装 ===')
    r = sh('install', '-r', HAP)
    install_output = '\n'.join(part.strip() for part in (r.stdout, r.stderr) if part).strip()
    print(install_output[-200:])
    if r.returncode != 0 or re.search(r'\b(failed|failure|error)\b', install_output, re.IGNORECASE):
        print('安装未确认成功，已停止；不会把旧版本的回归结果记为当前 HAP。')
        return 4
    sh('shell', 'aa', 'force-stop', BUNDLE)
    start = sh('shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY)
    if start.returncode != 0:
        print((start.stdout or '').strip() or (start.stderr or '').strip())
        print('应用启动失败，已停止回归。')
        return 5
    time.sleep(6)

    print('=== 首次隐私告知与健康信息单独同意 ===')
    if not accept_privacy_for_test():
        print('首次隐私同意流程未通过，已停止后续测试。')
        return 6
    print('    PASS  政策可打开，分项同意后进入应用')

    print('=== 首次使用六步引导（含体征手填） ===')
    if not complete_onboarding_for_test():
        print('首次使用引导未完成，已停止后续测试。')
        return 7
    print('    PASS  六步引导完成并进入今日页')

    print('=== 本次验证启用本地 AI 演示模式 ===')
    if not enable_demo_mode():
        print('无法启用本地 AI 演示模式，已停止后续 AI 调用。')
        return 3

    check('综合页主视觉', c_home); shot('v_01_home')
    check('AI 拍照识别入口(综合页顶部)', c_ai_entry); shot('v_02_ai_entry')
    back()
    check('轮播条横向滚动', c_carousel); shot('v_03_carousel')
    check('餐食卡片流', c_meal_cards); shot('v_04_meal_card')
    check('餐食详情页', c_meal_detail); shot('v_05_meal_detail')
    # 仅当详情页实际打开时返回，避免前一项失败后误退到桌面并污染后续结论。
    if has(dump(), '餐食详情'):
        back()
    check('AI 示例图入口', c_sample_ai); shot('v_06_sample')
    check('AI 示例图完整识别链路', c_ai_sample_flow); shot('v_07_ai_result')
    back()
    foodlog_ok = check('全部餐食(NavDestination 包裹)', c_foodlog)
    shot('v_08_foodlog')
    if foodlog_ok:
        # FoodLog 是全屏 NavDestination，不含底部 Tab；先返回到「我的」，
        # 再让后续 V4 检查通过可见的「今日」Tab 进入个人记录子页。
        back()

    print('\n=== 个人信息保护双清单与隐私政策 ===')
    check('已收集个人信息清单', c_privacy_collected_inventory); shot('v_12_inv_collected')
    back()
    check('第三方共享个人信息清单', c_privacy_shared_inventory); shot('v_13_inv_shared')
    back()
    check('隐私政策免责条款', c_privacy_policy); shot('v_14_privacy_policy')
    back()
    check('华为账号登录入口', c_account_login); shot('v_15_account')
    back()

    check('今日黑板即今日页主体', c_blackboard_page); shot('v_16_blackboard')
    check('nosh 式日期胶囊条', c_date_strip); shot('v_17_date_strip')


    print('\n================ 汇总 ================')
    passed = sum(1 for _, state, _ in RESULTS if state is True)
    skipped = sum(1 for _, state, _ in RESULTS if state is None)
    failed = sum(1 for _, state, _ in RESULTS if state is False)
    for name, ok, detail in RESULTS:
        status = 'PASS' if ok is True else ('SKIP' if ok is None else 'FAIL')
        print(f'{status}  {name:<28} {detail}')
    print(f'\n{passed} passed, {skipped} skipped, {failed} failed ({len(RESULTS)} checks)')
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    raise SystemExit(main())
