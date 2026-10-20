#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""今日黑板专项验证：抠图贴纸 → 保存记录 → 便签墙。

覆盖三件新东西：
  1. AI 识别页是否产出抠好的贴纸（Canvas destination-out 是否真的生效）
  2. 保存后记录里是否带上了贴纸路径
  3. 「今日黑板」页是否渲染出便签墙

贴纸本身是**没有文字的 Image 节点**，verify_all.dump() 只收有 text 的节点，
收不到 —— 所以这里自己读回完整节点树。抠图是否真的透明，交给截图肉眼判定。
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_all as V  # noqa: E402


def all_nodes():
    """读回最后一次 dump 的**完整**节点树（含无文字的 Image 节点）。"""
    V.dump()
    with open(V.TREE, 'r', encoding='utf-8') as f:
        data = json.load(f)
    out = []

    def walk(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or {}
        out.append({
            'text': a.get('text', ''),
            'bounds': a.get('bounds', ''),
            'type': a.get('type', '')
        })
        for c in (n.get('children') or []):
            walk(c)

    walk(data)
    return out


def big_images(nodes, min_side=40, max_side=700):
    """挑出尺寸合理的 Image 节点 —— 贴纸容器内的图就是这个量级。

    上限放宽到 700px：贴纸容器是 92vp，在密度 3.5 左右的模拟器上
    实际渲染宽度约 330px，按 220 过滤会漏掉真正的贴纸。
    """
    hits = []
    for n in nodes:
        if n['type'] != 'Image':
            continue
        nums = [int(x) for x in __import__('re').findall(r'\d+', n['bounds'] or '')]
        if len(nums) < 4:
            continue
        w = nums[2] - nums[0]
        h = nums[3] - nums[1]
        if min_side <= w <= max_side and min_side <= h <= max_side:
            hits.append((w, h))
    return hits


def step(name, ok, detail=''):
    print(f'  {"PASS" if ok else "FAIL"}  {name}  {detail}')
    return ok


def ensure_ready():
    """确保停在今日主界面。

    幂等：可能上一轮回归已经走过首启同意与引导，这时再跑一遍引导流程
    反而会失败（引导页不会再出现），所以先判断当前是不是已经在主界面。
    """
    # install -r 之后应用可能停在后台，必须先拉起来再谈后续。
    V.sh('shell', 'aa', 'start', '-b', V.BUNDLE, '-a', V.ABILITY)
    time.sleep(4.0)
    if V.has(V.dump(), '今日热量'):
        return True
    if not V.accept_privacy_for_test():
        return False
    if V.has(V.dump(), '今日热量'):
        return True
    return V.complete_onboarding_for_test()


def tap_dialog_delete():
    """点确认弹窗里的「删除」。

    列表行末尾和确认弹窗的按钮**同名**（都是「删除」）。两者靠位置区分：
    弹窗按钮在屏幕更下方（实测列表行 bounds y≈1327、弹窗按钮 y≈1533），
    所以取**纵坐标最大**的那个，而不是 UI 树里最后一个 ——
    树的顺序会随渲染顺序变，不可靠。
    """
    nodes = V.dump()
    hits = [n for n in nodes if n['text'] == '删除']
    if len(hits) < 2:
        # 弹窗还没出现（只有一个「删除」= 只有列表行那一个）
        return False
    hits.sort(key=lambda n: V.center(n['bounds'])[1])
    x, y = V.center(hits[-1]['bounds'])
    V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
    time.sleep(2.0)
    return True


def cleanup_created_record():
    """删掉本次脚本创建的饮食记录。

    不清理的话，脚本每次跑都会往当天多留一条记录：
    一是数据越堆越多，二是会让别的回归项（如餐食详情页的空态判定）误判。

    走「全部餐食」列表行末尾的删除入口 —— 和真实用户操作同一条路径。
    （列表按 created_at DESC 排序，刚创建的那条在第一行。）
    """
    if not V.home_top():
        return False
    if not V.tap('我的', settle=2.5):
        return False
    V.scroll_top()
    if not V.find_and_tap('全部餐食', settle=3.0):
        return False
    for _ in range(2):
        if not V.find_and_tap('删除', max_scroll=6, settle=3.0):
            return False
        if tap_dialog_delete():
            # 用页面回到空态作为「真的删掉了」的判据，不靠点击没报错来猜
            time.sleep(1.5)
            texts = ' '.join(n['text'] for n in V.dump())
            if '今天还没有饮食记录' in texts:
                return True
    return False


def main():
    if not V.connected():
        print('设备桥接不可用。')
        return 2
    if not os.path.isfile(V.HAP):
        print(f'HAP 不存在：{V.HAP}')
        return 3

    print('=== 安装 ===')
    r = V.sh('install', '-r', V.HAP)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        print(out[-300:])
        return 4
    print('  已安装')

    print('=== 首启与引导 ===')
    if not ensure_ready():
        print('  首启/引导未就绪')
        return 5
    if not V.enable_demo_mode():
        print('  演示模式未启用')
        return 7
    print('  已就绪')

    results = []

    # ---------- 1. 抠图 ----------
    print('\n[1] AI 识别产出食物轮廓贴纸')
    if not V.home_top():
        results.append(step('回到今日首页', False, '无法回到首页'))
    else:
        results.append(step('回到今日首页', True))
    if not V.tap('拍照识别食物', settle=4.0):
        results.append(step('进入 AI 识别页', False))
        return report(results)
    results.append(step('进入 AI 识别页', True))

    if not V.tap('没有照片？用内置示例图试一下', settle=3.5):
        results.append(step('载入内置示例图', False))
        return report(results)
    results.append(step('载入内置示例图', True))

    if not V.tap('开始 AI 识别', settle=12.0):
        results.append(step('演示模式识别', False))
        return report(results)
    nodes = V.dump()
    ok = V.has(nodes, '识别结果') and V.has(nodes, '演示食物（模拟识别）')
    results.append(step('识别出结果', ok))
    V.shot('bb_01_recognize')

    # 贴纸是**后台**生成的（结果先显示、贴纸后到），这里多等一会儿再判
    time.sleep(4.0)
    imgs = big_images(all_nodes())
    results.append(step('结果页出现贴纸图', len(imgs) > 0, f'{len(imgs)} 个图像节点'))
    V.shot('bb_02_sticker')

    # ---------- 2. 保存记录（带上贴纸路径） ----------
    print('\n[2] 保存记录并带上贴纸')
    if not V.find_and_tap('使用结果并编辑', settle=3.5):
        results.append(step('进入编辑页', False))
        return report(results)
    results.append(step('进入编辑页', True))
    V.shot('bb_03_edit')
    if not V.tap('确认保存', settle=4.0):
        results.append(step('确认保存', False))
    else:
        results.append(step('确认保存', True))
    # 不要再多按一次返回 —— AI 模式保存时已经把识别页和编辑页一起 pop 掉了，
    # 再 back 一次会退出应用到桌面，底 Tab 也就找不到了。

    # ---------- 3. 黑板页 ----------
    print('\n[3] 今日黑板便签墙')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    results.append(step('回到今日首页', True))
    if not V.tap('今日黑板', settle=4.0):
        results.append(step('进入今日黑板', False))
        return report(results)
    results.append(step('进入今日黑板', True))

    nodes = V.dump()
    # 超预算时右侧文案会变成「已超出」，两种都要认
    ok = V.has(nodes, '今日摄入') and (V.has(nodes, '还可以吃') or V.has(nodes, '已超出'))
    results.append(step('黑板表头渲染', ok))
    ok = V.has(nodes, '演示食物（模拟识别）')
    results.append(step('便签上出现食物名', ok))
    ok = V.has(nodes, '620 kcal')
    results.append(step('便签上出现热量', ok))
    imgs = big_images(all_nodes())
    results.append(step('便签上出现贴纸图', len(imgs) > 0, f'{len(imgs)} 个图像节点'))
    V.shot('bb_04_blackboard')

    # 清理本次创建的记录，保证脚本可重复运行、不污染其它回归项
    results.append(step('清理本次创建的记录', cleanup_created_record()))

    return report(results)


def report(results):
    passed = sum(1 for r in results if r)
    failed = len(results) - passed
    print('\n================ 汇总 ================')
    for r in results:
        print(f'  {"PASS" if r else "FAIL"}')
    print(f'\n{passed} passed, {failed} failed ({len(results)} checks)')
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    raise SystemExit(main())
