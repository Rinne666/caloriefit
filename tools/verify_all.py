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


def dump(retries=5):
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
        out = []

        def walk(n):
            if not isinstance(n, dict):
                return
            a = n.get('attributes') or {}
            if a.get('text'):
                out.append({'text': a['text'], 'bounds': a.get('bounds', '')})
            for c in (n.get('children') or []):
                walk(c)

        walk(data)
        return out
    raise RuntimeError(f'dumpLayout failed: {last}')


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
    """返回今日首页并把纵向列表复位，避免复用旧滚动位置。"""
    for _ in range(4):
        nodes = dump()
        if any(n['text'] == '今日' for n in nodes):
            if not tap('今日', settle=2.5):
                return False
            scroll_top()
            return has(dump(), '今日热量')
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
    if not tap('我的', settle=2.5):
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
    if not tap('今日', settle=2.5):
        return False
    scroll_top()
    return has(dump(), '今日热量')


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


def complete_onboarding_for_test():
    """全新同意/数据删除后的首启会进入五步引导，完成它再测主页面。"""
    if has(dump(), '今日热量'):
        print('    模拟器已有完成引导的用户，保留现有数据并跳过首启引导')
        return True

    sequence = [
        ('你想达成什么', '继续'),
        ('平时的活动量', '继续'),
        ('随时掌握进度', '继续'),
        ('你会吃补剂吗', '继续'),
        ('你的生活方式', '开始使用'),
    ]
    for title, cta in sequence:
        nodes = dump()
        if has(nodes, '今日热量'):
            return True
        if not has(nodes, title):
            print(f'    引导步骤未到预期页面：{title}')
            return False
        if not tap(cta, settle=3.0 if cta == '开始使用' else 1.0):
            print(f'    引导 CTA 不可用：{cta}（{title}）')
            return False
    if not has(dump(), '今日热量'):
        return False

    # 首次完成引导只写目标/活动量；不得重新引入旧版伪造体征默认值。
    if not tap('我的', settle=2.5):
        return False
    scroll_top()
    profile_nodes = dump()
    if any(n['text'] in ('65', '170') for n in profile_nodes):
        print('    首次引导后仍出现旧版体征默认值')
        return False
    print('    PASS  新用户体重/身高未被预填')
    if not tap('今日', settle=2.5):
        return False
    scroll_top()
    return has(dump(), '今日热量')


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
    ok = home_top()
    nodes = dump()
    required = ('今日热量', '剩余 kcal', '已摄入 kcal', '目标 kcal', '蛋白质', '碳水', '脂肪')
    rendered = all(has(nodes, text) for text in required)
    return ok and rendered, '主卡显示热量半环三项数据与宏量条'


def c_ai_entry():
    if not home_top():
        return False, '无法回到今日首页顶部'
    ok = tap('拍照识别食物', settle=4.0)
    return ok and has(dump(), 'AI 食物识别'), 'AI 入口进入识别页'


def c_meal_cards():
    if not home_top():
        return False, '无法回到今日首页顶部'
    # 早餐卡片通常在首屏以下；HomePage 的 Scroll 只把可见项挂进 UI 树，
    # 所以先滚动到它出现，再按可见 bounds 点击。
    ok = find_and_tap('早餐', max_scroll=12, settle=4.0)
    return ok and has(dump(), '餐食详情'), '早餐卡片进入餐食详情'


def c_meal_detail():
    nodes = dump()
    return has(nodes, '餐食详情') and has(nodes, '这一餐还没有记录'), '空餐食详情页标题与空态渲染'


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

    hero = next((n for n in nodes if n['text'] == '今日热量'), None)
    if hero is None:
        return False, '主卡标题不在当前视口，无法确认页面滚动位置'
    hero_y = center(hero['bounds'])[1]

    before = Image.open(io.BytesIO(_shot_bytes())).convert('RGB')

    sh('shell', 'uitest', 'uiInput', 'swipe', '1000', str(y), '200', str(y), str(CAROUSEL_VELOCITY))
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
    if not tap('拍照识别食物', settle=4.0):
        return False, 'AI 入口无法打开'
    ok = tap('没有照片？用内置示例图试一下', settle=3.5)
    nodes = dump()
    return ok and has(nodes, '更换图片') and has(nodes, '开始 AI 识别'), '示例图载入并启用识别按钮'


def c_foodlog():
    if not home_top():
        return False, '无法回到今日首页顶部'
    tap('我的', settle=3.0)
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


def ensure_today_tab():
    """从个人页或子路由回到今日主 Tab，避免误把不可见子页当成产品故障。"""
    for _ in range(5):
        nodes = dump()
        if has(nodes, '今日热量'):
            return True
        if any(n['text'] == '今日' for n in nodes) and tap('今日', settle=2.5):
            scroll_top()
            if has(dump(), '今日热量'):
                return True
        back()
    return has(dump(), '今日热量')


def c_privacy_collected_inventory():
    """个人信息保护「已收集个人信息清单」必须可达且有实质内容。

    工信部 292 号文要求双清单在二级菜单展示，应用市场把它列为上架要求。
    入口若被后续改动删掉，审核会被直接驳回，所以固化成回归项。
    """
    if not tap('我的', settle=3.0):
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
    if not tap('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('第三方共享个人信息清单', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「第三方共享个人信息清单」入口不可达'
    nodes = dump()
    required = ('第三方共享个人信息清单', '阿里云百炼', '接收方', '使用目的', '共享方式')
    if not all(has(nodes, t) for t in required):
        return False, '共享清单页缺少接收方或共享方式'
    return True, '入口可达，共享项写明接收方与共享方式'


def c_privacy_policy():
    """隐私政策正文必须含免责条款与待补齐提示。"""
    if not tap('我的', settle=3.0):
        return False, '无法进入我的页'
    scroll_top()
    ok = find_and_tap('查看隐私政策', max_scroll=25, settle=3.0)
    if not ok:
        return False, '「查看隐私政策」入口不可达'
    nodes = dump()
    if not has(nodes, 'CalorieFit 隐私政策'):
        return False, '隐私政策正文未渲染'
    # 免责条款在第三节，位于页面上部。Scroll 里视口外的内容不保证进 UI 树，
    # 所以先在当前位置找，找不到就**往回滚**到顶部再找 —— 往下滚是背离目标的。
    found = any('医疗建议' in t for t in texts(nodes))
    for _ in range(6):
        if found:
            break
        sh('shell', 'uitest', 'uiInput', 'swipe', '640', '900', '640', '2100', str(SCAN_VELOCITY))
        time.sleep(SCAN_SETTLE)
        nodes = dump()
        found = any('医疗建议' in t for t in texts(nodes))
    if not found:
        return False, '隐私政策缺少「不构成医疗建议」的免责条款'
    return True, '政策可达，含免责条款'


def c_water_v4_persistence():
    if not ensure_today_tab() or not tap('饮水', settle=3.0):
        return False, '饮水子页不可达'
    nodes = dump()
    if not has(nodes, 'ml consumed'):
        return False, '饮水页没有显示累计用量'
    if not has(nodes, '还没有饮水记录'):
        return False, 'SKIP: 模拟器已有饮水记录，为避免覆盖或撤销现有记录，跳过空数据持久化测试'
    before = count_exact(nodes, '250')
    if before < 1 or not tap('250', settle=2.5):
        return False, '250 ml 快捷记录不可操作'
    after_add = dump()
    if not has(after_add, 'ml consumed') or count_exact(after_add, '250') < before + 1:
        return False, '新增 250 ml 后总量未更新'
    if not relaunch_app() or not ensure_today_tab() or not tap('饮水', settle=3.0):
        return False, '重启后无法返回饮水页'
    after_restart = dump()
    if count_exact(after_restart, '250') < before + 1:
        return False, '重启后没有读回 250 ml 记录'
    shot('v_09_water_v4_persisted')
    if not tap('撤销', settle=2.5):
        return False, '重启后已读回 250 ml，但撤销入口不可操作'
    after_undo = dump()
    if not has(after_undo, '还没有饮水记录') or count_exact(after_undo, '250') > before:
        return False, '撤销本次测试记录后，页面未恢复原始空态'
    return True, '新装水表可写；重启后读回 250 ml，并成功撤销本次测试记录'


def c_fasting_intro():
    if not tap('断食', settle=3.0):
        return False, '断食子页不可达'
    nodes = dump()
    return (has(nodes, '断食，让每一餐更有节奏') and has(nodes, '选择方案') and
            not has(nodes, '选择断食方案')), '首屏显示介绍、环形视觉和选择方案入口'


def c_fasting_v4_persistence():
    if not tap('断食', settle=3.0):
        return False, '断食子页不可达'
    nodes = dump()
    if has(nodes, '已坚持'):
        return False, 'SKIP: 模拟器已有进行中的断食，为避免更改现有计划，跳过持久化写入测试'
    if not has(nodes, '选择方案') or not tap('选择方案', settle=2.0):
        return False, '断食介绍页的方案入口不可操作'
    nodes = dump()
    if not has(nodes, '选择断食方案') or not has(nodes, '16:8'):
        return False, '新装状态未渲染断食方案'
    if not tap('开始', settle=3.0):
        return False, '断食方案开始入口不可操作'
    active = dump()
    if not has(active, '已坚持') or not has(active, '放弃'):
        return False, '开始后未显示进行中断食状态'
    if not relaunch_app() or not ensure_today_tab() or not tap('断食', settle=3.0):
        return False, '重启后无法返回断食页'
    persisted = dump()
    if not has(persisted, '已坚持') or not has(persisted, '放弃'):
        return False, '重启后没有读回进行中断食记录'
    if not tap('放弃', settle=2.0) or not has(dump(), '选择方案'):
        return False, '无法清理本次断食测试记录'
    return True, '新装断食表可写；重启后恢复进行中方案并可结束'


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

    print('=== 首次使用五步引导 ===')
    if not complete_onboarding_for_test():
        print('首次使用引导未完成，已停止后续测试。')
        return 7
    print('    PASS  五步引导完成并进入今日页')

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

    print('\n=== V4 饮水/断食表写入与重启持久化 ===')
    check('饮水 V4 持久化', c_water_v4_persistence); shot('v_09_water_v4')
    check('断食首屏还原', c_fasting_intro); shot('v_10_fasting_intro')
    check('断食 V4 持久化', c_fasting_v4_persistence); shot('v_11_fasting_v4')

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
