#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""今日黑板自由画布的专项验证（2026-10-21 改造）。

覆盖设计方案里的八个核心交互，逐条对着 UI 树和像素判定：

  1. 操作排渲染（网格 / 分栏 / 规整 / 底纹 / 分享）
  2. 自由画布里真的有贴纸
  3. 贴纸能被拖动（位置前后对比）
  4. 「网格」切到按餐次分组的结构化视图，再切回来
  5. 「底纹」切主题（板面像素颜色前后对比）
  6. 「规整」重排（节点位置前后对比）
  7. 「分栏」画出早/午/晚/加餐的粉笔虚线
  8. 「分享」用 componentSnapshot 生成手帐分享卡
  9. 点贴纸打开编辑抽屉（bindSheet 半模态）

判据一律用**可观测的状态变化**，不用「点击没报错」：
手势被页面 Scroll 抢走、bindSheet 没弹出来这两种情况，
点击同样不会报错，只有看 UI 树/像素才知道。
"""

import io
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_all as V  # noqa: E402

from PIL import Image  # noqa: E402


def step(name, ok, detail=''):
    print(f'  {"PASS" if ok else "FAIL"}  {name}  {detail}')
    return bool(ok)


def ensure_ready():
    """确保停在今日主界面（首启同意 + 引导都可能被清掉过）。"""
    V.sh('shell', 'aa', 'start', '-b', V.BUNDLE, '-a', V.ABILITY)
    time.sleep(4.0)
    if V.has(V.dump(), '今日摄入'):
        return True
    if not V.accept_privacy_for_test():
        return False
    if V.has(V.dump(), '今日摄入'):
        return True
    return V.complete_onboarding_for_test()


def image_nodes():
    """UI 树里所有 Image 节点（含无文字的贴纸图）。"""
    out = []
    for n in V.dump_all():
        if n['type'] != 'Image':
            continue
        nums = [int(x) for x in re.findall(r'\d+', n['bounds'] or '')]
        if len(nums) < 4:
            continue
        out.append({'tl': (nums[0], nums[1]), 'w': nums[2] - nums[0],
                    'h': nums[3] - nums[1], 'bounds': n['bounds']})
    return out


def stickers():
    """尺寸合理的贴纸图（排除吉祥物等装饰图）。"""
    return [n for n in image_nodes() if 40 <= n['w'] <= 700 and 40 <= n['h'] <= 700]


def board_pixel():
    """取板面一块区域里的**众数颜色**，用来判底纹有没有换。

    为什么取众数而不是单点：
    板面上有粉笔字、贴纸、便签，随便取一点很可能落在文字或贴纸上，
    换个底纹色差会被内容稀释掉。
    取「板面表头下方、宏量行上方」这一条横带（只有背景，没有贴纸），
    再取其中出现最多的颜色 —— 那就是板面底色。
    """
    raw = V._shot_bytes()
    img = Image.open(io.BytesIO(raw)).convert('RGB')
    w, h = img.size
    counts = {}
    for y in range(int(h * 0.272), int(h * 0.283)):
        for x in range(int(w * 0.13), int(w * 0.72), 2):
            px = img.getpixel((x, y))
            counts[px] = counts.get(px, 0) + 1
    if not counts:
        return (0, 0, 0)
    return max(counts.items(), key=lambda kv: kv[1])[0]


def close_sheet():
    """把可能开着的编辑抽屉关掉。

    抽屉是 bindSheet 弹出的浮层，底下的按钮在 UI 树里还在，
    脚本按文字点会点到被抽屉盖住的位置 —— 判据会全线错乱。
    """
    nodes = V.dump()
    if V.has(nodes, '保存') and V.has(nodes, '碎碎念'):
        V.tap('关闭', settle=1.2)
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
    if r.returncode != 0:
        print((r.stdout + r.stderr).strip()[-300:])
        return 4
    print('  已安装')

    print('=== 首启与引导 ===')
    if not ensure_ready():
        print('  首启/引导未就绪')
        return 5
    print('  已就绪')

    results = []

    # ---------- 1. 操作排 ----------
    print('\n[1] 黑板操作排')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    nodes = V.dump()
    ok = all(V.has(nodes, t) for t in ('网格', '分栏', '规整', '底纹', '分享'))
    results.append(step('五个操作按钮都在', ok))
    V.shot('bc_01_actions')

    # ---------- 2. 自由画布里有贴纸 ----------
    print('\n[2] 自由画布')
    imgs = stickers()
    results.append(step('画布上有贴纸图', len(imgs) > 0, f'{len(imgs)} 个'))
    results.append(step('贴纸数量不少于 3',
                        len(imgs) >= 3, f'{len(imgs)} 个'))

    # ---------- 3. 拖动贴纸 ----------
    print('\n[3] 拖动贴纸')
    before = stickers()
    moved = False
    if before:
        t = before[0]
        x = t['tl'][0] + t['w'] // 2
        y = t['tl'][1] + t['h'] // 2
        V.sh('shell', 'uitest', 'uiInput', 'swipe', str(x), str(y),
             str(x + 60), str(y + 40), '1500')
        time.sleep(2.0)
        after = stickers()
        for n in after:
            if abs(n['tl'][0] - t['tl'][0]) > 10 or abs(n['tl'][1] - t['tl'][1]) > 10:
                moved = True
                break
    results.append(step('贴纸被拖动后位置改变', moved))
    V.shot('bc_02_dragged')

    # ---------- 4. 网格视图 ----------
    print('\n[4] 自由画布 ↔ 结构化网格')
    if V.tap('网格', settle=2.5):
        nodes = V.dump()
        # 网格是纵向 Scroll，屏外的分组不会挂进 UI 树 ——
        # 只要求「至少两个餐次分组标题出现」，不要求四个都在。
        groups = sum(1 for m in ('早餐', '午餐', '晚餐', '加餐') if V.has(nodes, m)) >= 2
        results.append(step('切到网格视图并按餐次分组', groups))
        V.shot('bc_03_grid')
        back = V.tap('自由', settle=2.5)
        results.append(step('切回自由画布', back and V.has(V.dump(), '分栏')))
    else:
        results.append(step('「网格」按钮可点', False))

    # ---------- 5. 底纹切换 ----------
    print('\n[5] 底纹切换')
    close_sheet()
    color_before = board_pixel()
    if V.tap('底纹', settle=2.5):
        color_after = board_pixel()
        diff = sum(abs(a - b) for a, b in zip(color_before, color_after))
        results.append(step('板面颜色随底纹切换而变', diff > 12,
                            f'{color_before} -> {color_after} Δ={diff}'))
        V.shot('bc_04_theme')
    else:
        results.append(step('「底纹」按钮可点', False))

    # ---------- 6. 一键规整 ----------
    print('\n[6] 一键规整')
    close_sheet()
    before = stickers()
    if V.tap('规整', settle=2.5):
        after = stickers()
        changed = False
        for i in range(min(len(before), len(after))):
            if abs(after[i]['tl'][0] - before[i]['tl'][0]) > 6 or \
               abs(after[i]['tl'][1] - before[i]['tl'][1]) > 6:
                changed = True
                break
        results.append(step('规整后贴纸位置改变', changed))
        V.shot('bc_05_tidy')
    else:
        results.append(step('「规整」按钮可点', False))

    # ---------- 7. 粉笔分栏 ----------
    print('\n[7] 粉笔分栏')
    close_sheet()
    if V.tap('分栏', settle=2.0):
        nodes = V.dump()
        # 分栏后画布上会多出四个餐次标题
        ok = all(V.has(nodes, m) for m in ('早餐', '午餐', '晚餐', '加餐'))
        results.append(step('分栏线与餐次标题出现', ok))
        V.shot('bc_06_dividers')
        V.tap('分栏✓', settle=1.5)
    else:
        results.append(step('「分栏」按钮可点', False))

    # ---------- 8. 分享卡 ----------
    print('\n[8] 手帐分享卡')
    close_sheet()
    if V.tap('分享', settle=4.0):
        nodes = V.dump()
        ok = V.has(nodes, '今日手帐分享卡') and V.has(nodes, '不会发送到任何服务器')
        results.append(step('分享卡预览弹窗出现', ok))
        V.shot('bc_07_poster')
        V.tap('关闭', settle=1.5)
    else:
        results.append(step('「分享」按钮可点', False))

    # ---------- 9. 编辑抽屉 ----------
    print('\n[9] 编辑抽屉（bindSheet）')
    close_sheet()
    imgs = stickers()
    opened = False
    if imgs:
        t = imgs[0]
        x = t['tl'][0] + t['w'] // 2
        y = t['tl'][1] + t['h'] // 2
        V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
        time.sleep(2.0)
        nodes = V.dump()
        # 「保存」按钮在抽屉最底部，屏外不会挂进树；
        # 用抽屉中部的字段标签判定更稳。
        opened = V.has(nodes, '碎碎念') and V.has(nodes, '便签纸')
        results.append(step('点贴纸打开编辑抽屉', opened))
        V.shot('bc_08_editor')
        if opened:
            V.tap('关闭', settle=1.5)
    else:
        results.append(step('画布上有可点的贴纸', False))

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
