#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用户流程验收轮（2026-10-21 晚）的定向验证。

对应《模拟器用户验收报告》里的 F01~F13。这一轮的核心是**记餐闭环**：
选择餐次 → 新增 → 核对营养 → 编辑 → 返回即更新 → 删除。

为什么单独写这个脚本：
  verify_all / verify_blackboard / verify_board_canvas 都不覆盖
  「从某一餐进入新增会不会记错餐次」「编辑后返回详情是不是最新」
  「点一下贴纸会不会偷偷改掉用户的餐次」这几条 ——
  而这几条正是这一轮最要命的。

用法：
    python -u verify_user_flow.py
"""

import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_all as V  # noqa: E402
from verify_fix_round import goto_tab, tap_dialog_button  # noqa: E402
from verify_blackboard import all_nodes  # noqa: E402

TEST_NAME = 'UFLOW_Rice'


def step(name, ok, detail=''):
    print(f'  {"PASS" if ok else "FAIL"}  {name}  {detail}')
    return ok


def texts():
    return ' '.join(n['text'] for n in V.dump())


def board_kcal():
    """黑板顶部的「今日摄入」数字。"""
    nodes = V.dump()
    for i, n in enumerate(nodes):
        if n['text'] == '今日摄入':
            for m in nodes[i + 1:i + 6]:
                t = m['text'].replace(',', '')
                if t.isdigit():
                    return int(t)
    return None


def find_sticker_image():
    """画布上第一张尺寸合理的图片节点（贴纸本身）。

    注意：贴纸是**没有文字的 Image 节点**，`V.dump()` 只收有文字的节点，
    收不到 —— 必须读完整节点树（同 verify_blackboard 的做法）。
    """
    for n in all_nodes():
        if n['type'] != 'Image':
            continue
        nums = [int(x) for x in re.findall(r'\d+', n['bounds'] or '')]
        if len(nums) < 4:
            continue
        w = nums[2] - nums[0]
        h = nums[3] - nums[1]
        if 60 <= w <= 700 and 60 <= h <= 700:
            return {'tl': (nums[0], nums[1]), 'w': w, 'h': h}
    return None


def scroll_to_meal_cards():
    """把首页滚到「今日餐食」那一段。"""
    for _ in range(10):
        nodes = V.dump()
        if any('点击添加' in n['text'] for n in nodes):
            return True
        V.sh('shell', 'uitest', 'uiInput', 'swipe', '640', '2000', '640', '900',
             str(V.SCAN_VELOCITY))
        time.sleep(V.SCAN_SETTLE)
    return False


def add_manual_food(name, weight, kcal_per_100g):
    """在当前的「新增食物」表单里录一条手动记录并保存。

    页面结构（FoodEditPage）：名称 / 用餐类型 / 重量 / 每100g热量 / 三大宏量 / 保存。
    宏量留空即不记录 —— 留空比填 0 更安全（不以 0 冒充未记录）。
    """
    nodes = V.dump()
    inputs = [n for n in nodes if n.get('type') == 'TextInput']
    if len(inputs) < 3:
        return False
    if not V._set_field(0, name):
        return False
    if not V._set_field(1, weight):
        return False
    if not V._set_field(2, kcal_per_100g):
        return False
    # 收键盘，否则「保存记录」按钮被键盘挡住
    V.sh('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
    time.sleep(1.0)
    return V.tap('保存记录', settle=3.0)


def open_foodlog_page(tries=3):
    """进「全部餐食」页（按餐次分组，页面上直接写着每餐小计）。

    刚做完一次写操作后立刻导航时，页面还在过渡，
    第一次点击经常落在还没就位的元素上 —— 所以**点本身也要重试**，
    不能只重试整条导航。
    """
    for _ in range(tries):
        V.home_top()
        # strict=False：目标页可能停在滚动位置，marker 滚出可见区时
        # goto_tab 会判成「没切过去」（假阴性）。这里只看点击有没有发出。
        goto_tab('我的', strict=False)
        V.scroll_top()
        for _ in range(3):
            if '饮食记录' in texts():
                return True
            if V.find_and_tap('全部餐食', settle=2.5):
                time.sleep(1.2)
                if '饮食记录' in texts():
                    return True
            time.sleep(1.0)
    return False


def open_meal_detail(meal_label, tries=2):
    """从首页的餐食卡进入某一餐的详情页。"""
    for _ in range(tries):
        if not V.home_top():
            time.sleep(1.5)
            continue
        if not scroll_to_meal_cards():
            time.sleep(1.0)
            continue
        nodes = V.dump()
        target = None
        for n in nodes:
            t = n['text']
            if t == meal_label or (t.startswith(meal_label + ' ') and '点击添加' not in t):
                target = n
                break
        if target is not None:
            c = V.center(target['bounds'])
            if c:
                V.sh('shell', 'uitest', 'uiInput', 'click', str(c[0]), str(c[1]))
                time.sleep(2.5)
                if '餐食详情' in texts():
                    return True
        time.sleep(1.0)
    return False


def macro_summary_and_detail():
    """餐食详情页上的「汇总三值」与「明细行宏量」。"""
    nodes = V.dump()
    summary = []
    for i, n in enumerate(nodes):
        if n['text'] in ('蛋白 g', '碳水 g', '脂肪 g'):
            for m in reversed(nodes[:i]):
                if m['text'].isdigit():
                    summary.append(int(m['text']))
                    break
    detail = ''
    for n in nodes:
        if '蛋白' in n['text'] and '碳水' in n['text'] and 'g' in n['text']:
            detail = n['text']
            break
    nums = []
    for part in detail.replace('·', ' ').split():
        if part.endswith('g') and part[:-1].isdigit():
            nums.append(int(part[:-1]))
    return summary, nums, detail


def meal_subtotal(meal_label):
    """「全部餐食」页上某一餐的小计热量。没有这一餐返回 None。"""
    nodes = V.dump()
    for i, n in enumerate(nodes):
        if n['text'] == meal_label:
            for m in nodes[i + 1:i + 4]:
                if m['text'].startswith('小计'):
                    nums = re.findall(r'\d+', m['text'].replace(',', ''))
                    if nums:
                        return int(nums[0])
    return None


def delete_all_foodlog():
    """删掉「全部餐食」页上的全部记录。"""
    if not open_foodlog_page():
        return False
    for _ in range(8):
        nodes = V.dump()
        if '暂无记录' in texts() or '今天还没有饮食记录' in texts():
            return True
        if not V.find_and_tap('删除', max_scroll=8, settle=2.5):
            return False
        tap_dialog_button('删除')
        time.sleep(1.5)
    return '暂无记录' in texts() or '今天还没有饮食记录' in texts()


def main():
    if not V.connected():
        print('设备桥接不可用。')
        return 2

    print('=== 首启与引导 ===')
    # complete_onboarding_for_test 用「今日摄入」判断是否已就绪，
    # 页面停在别处时这个文案不在可见区里，会误判成「没走过引导」。
    # 但首启同意页上根本没有底栏，home_top() 会去点底栏 —— 那时不要调它。
    if not V.has(V.dump(), '请先阅读隐私说明'):
        V.home_top()
    if not V.accept_privacy_for_test():
        print('  同意流程未就绪')
        return 5
    if not V.complete_onboarding_for_test():
        print('  引导未完成')
        return 5
    if not V.enable_demo_mode():
        print('  演示模式未启用')
        return 7
    print('  已就绪')

    results = []

    # ---------- F01 空餐次的「点击添加」不是死路 ----------
    print('\n[F01] 空餐次进入详情要有添加入口')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    if not scroll_to_meal_cards():
        results.append(step('找到餐食卡', False))
        return report(results)
    if not V.tap('午餐 · 点击添加', settle=2.5):
        results.append(step('点开空的午餐卡', False))
        return report(results)
    tl = texts()
    results.append(step('进入空的午餐详情', '这一餐还没有记录' in tl, tl[:50]))
    results.append(step('空状态有添加入口（不是死路）', '添加食物到午餐' in tl, tl[:80]))
    V.shot('uf_01_empty_meal')

    # ---------- F02 从这一餐新增，要落在这一餐 ----------
    print('\n[F02] 从午餐新增 → 记到午餐')
    if not V.tap('添加食物到午餐', settle=2.5):
        results.append(step('点「添加食物到午餐」', False))
        return report(results)
    if not add_manual_food(TEST_NAME, '100', '120'):
        results.append(step('录入一条食物', False))
        return report(results)
    results.append(step('录入一条食物', True))
    time.sleep(1.0)
    tl = texts()
    results.append(step('回到午餐详情且能看到新记录', TEST_NAME in tl, tl[:80]))
    V.shot('uf_02_added_to_lunch')

    # ---------- F03 编辑后返回详情是最新数据 ----------
    print('\n[F03] 编辑后返回详情')
    if not V.tap(TEST_NAME, settle=2.5):
        results.append(step('点开记录进编辑页', False))
        return report(results)
    if not V._set_field(2, '240'):
        results.append(step('改热量为 240', False))
        return report(results)
    V.sh('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
    time.sleep(1.0)
    if not V.tap('保存修改', settle=3.0):
        results.append(step('保存修改', False))
        return report(results)
    results.append(step('保存修改', True))
    time.sleep(1.5)
    tl = texts()
    # 明细行也要更新（不只是上方小计）
    results.append(step('返回详情显示新热量 240', '240kcal/100g' in tl, tl[:100]))
    V.shot('uf_03_after_edit')

    # ---------- F05 黑板贴纸跟着更新 ----------
    print('\n[F05] 黑板贴纸与总数一致')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    total = board_kcal()
    tl = texts()
    results.append(step('黑板上出现新热量 240（不用切日期）', '240' in tl,
                        f'今日摄入 {total}'))
    V.shot('uf_05_board_updated')

    # ---------- F06 单击贴纸不改餐次 ----------
    print('\n[F06] 分栏开启时单击贴纸不改餐次')
    if not V.tap('分栏', settle=2.0):
        results.append(step('打开粉笔分栏', False))
    else:
        results.append(step('打开粉笔分栏', True))
        target = find_sticker_image()
        if target is None:
            results.append(step('点开贴纸', False, '画布上没找到贴纸'))
        else:
            x = target['tl'][0] + target['w'] // 2
            y = target['tl'][1] + target['h'] // 2
            V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
            time.sleep(2.5)
            opened = '碎碎念' in texts()
            results.append(step('点开贴纸抽屉', opened))
            if opened:
                V.sh('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
                time.sleep(2.0)
            V.shot('uf_06_after_tap')
            # 用「全部餐食」页的小计判断餐次有没有被改（它按餐次分组，最不容易看错）
            if open_foodlog_page():
                lunch = meal_subtotal('午餐')
                breakfast = meal_subtotal('早餐')
                results.append(step('单击后记录仍在午餐（餐次没被改）',
                                    lunch == 240 and breakfast == 0,
                                    f'午餐 {lunch} / 早餐 {breakfast}'))
            else:
                results.append(step('进「全部餐食」页核对餐次', False))

    # ---------- F10 视图设置不丢 ----------
    print('\n[F10] 切网格后视图模式要保住')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    if not V.tap('网格', settle=2.5):
        results.append(step('切到网格视图', False))
    else:
        results.append(step('切到网格视图', True))
        time.sleep(1.0)
        V.tap('20', settle=2.0)
        V.tap('21', settle=2.5)
        tl = texts()
        # 网格视图下操作排里「自由」是可点的（切回自由画布）；自由画布下显示「网格」
        results.append(step('切日期回来仍是网格视图', '自由' in tl, tl[:70]))
        V.shot('uf_10_grid_kept')
        V.tap('自由', settle=2.0)

    # ---------- F07 / F08 / F04：AI 记录 ----------
    print('\n[F07/F08/F04] AI 记录：份量文案、宏量可改、汇总一致')
    if not V.home_top():
        results.append(step('回到今日首页', False))
        return report(results)
    if not V.tap('拍照', settle=4.0):
        results.append(step('进入 AI 识别页', False))
    else:
        results.append(step('进入 AI 识别页', True))
        if not V.tap('没有照片？用内置示例图试一下', settle=3.5):
            results.append(step('载入示例图', False))
        elif not V.tap('开始 AI 识别', settle=12.0):
            results.append(step('演示模式识别', False))
        else:
            time.sleep(4.0)
            results.append(step('识别出结果', '演示食物（模拟识别）' in texts()))
            if not V.find_and_tap('使用结果并编辑', settle=3.5):
                results.append(step('进入 AI 编辑页', False))
            else:
                # F08：AI 模式也要有宏量表单
                tl = texts()
                has_macro = '三大宏量' in tl
                results.append(step('AI 编辑页有三大宏量表单', has_macro, tl[:70]))
                V.shot('uf_08_ai_macro_form')
                if V.tap('确认保存', settle=4.0):
                    results.append(step('保存 AI 记录', True))
                    time.sleep(1.5)
                    # F07：份量文案不能是 nullg
                    if open_foodlog_page():
                        tl = texts()
                        ok = 'nullg' not in tl and 'AI 整份估算' in tl
                        results.append(step('AI 记录份量显示「AI 整份估算」而非 nullg',
                                            ok, tl[:110]))
                        V.shot('uf_07_ai_portion')
                        # F04：餐食详情页的汇总必须与明细一致（AI 记录带 38/72/19 g）
                        if open_meal_detail('早餐'):
                            summary, nums, detail = macro_summary_and_detail()
                            results.append(step('明细行显示 AI 宏量',
                                                len(nums) == 3, detail))
                            results.append(step('汇总三值与明细一致',
                                                len(summary) == 3 and summary == nums,
                                                f'汇总 {summary} vs 明细 {nums}'))
                            V.shot('uf_04_ai_summary')
                        else:
                            results.append(step('进入早餐餐食详情', False))
                    else:
                        results.append(step('进「全部餐食」页核对', False))
                else:
                    results.append(step('保存 AI 记录', False))

    results.append(step('清理本次创建的记录', delete_all_foodlog()))

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
