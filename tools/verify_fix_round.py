#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本轮缺陷修复的定向验证：重点是**通用确认弹窗**与几个交互语义。

为什么单独写这个脚本：
  verify_all / verify_blackboard / verify_board_canvas 都不覆盖
  「点确认弹窗的『确认』，回调到底有没有执行」——
  而这恰恰是本轮 P1-1 的根因（判了 `action === 1`，
  而依赖回调的是 `DialogAction.SURE = -2`）。
  这个问题在编译期和截图里都看不出来，只有真的点一次才知道。

覆盖：
  ① 通用确认弹窗：点「删除」→ 弹确认 → 点确认 → **记录真的没了**
     （用「今日摄入」回到 0 作为判据，不靠「点击没报错」来猜）
  ② 取消不执行：点「取消」→ 记录还在
  ③ 宏量目标表单真的能打开（不再只是一个 toast）
  ④ 进度页跟着记录更新刷新（不用手动切统计范围）
  ⑤ 网格视图也能分享（之前必然报「生成失败：undefined」）

用法：
    python -u verify_fix_round.py
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_all as V  # noqa: E402
from verify_blackboard import ensure_ready, image_nodes  # noqa: E402

# 底栏没有文字（标签转成了 accessibilityText，不进 dumpLayout），
# 只能按顺序点。这里给每个 Tab 几个**页面内独有的文案**做切过去的判据。
# 必须是**一组**而不是一个：页面可能停在滚动的位置上，
# 单个文案可能不在可见区里（判成「没切过去」是假阴性）。
TAB_MARKER = {
    '今日': ('今日摄入', '拍照', '还可以吃', '已超出'),
    '进度': ('日均 kcal', '连续记录', '热量摄入'),
    '我的': ('外观', '数据来源', '版本与授权', '体征档案', '每日目标设置')
}


def step(name, ok, detail=''):
    print(f'  {"PASS" if ok else "FAIL"}  {name}  {detail}')
    return ok


def texts():
    return ' '.join(n['text'] for n in V.dump())


def goto_tab(label, tries=3, strict=True):
    """切到底栏 Tab，并**确认真的切过去了**。

    底栏没有文字（标签转成了 accessibilityText，不进 dumpLayout），
    只能按顺序点。这里不用 verify_all.tap_tab —— 它的 tab_centers()
    会把**底栏区域内的其它可点元素**也算进去（比如进度页最后一张卡
    恰好伸进底栏那条带子里），按下标点就会点错。
    改成直接按 TabBar 自身几何等分：Tabs 的页签本来就是等宽均分的。

    strict=True 时要求**页面内独有的文案**可见才算切过去。
    但目标页可能停在滚动位置上（marker 滚出可见区），
    这时判成「没切过去」是假阴性 —— strict=False 时只要求点击已发出。
    """
    markers = TAB_MARKER.get(label, ())
    if label not in V.TAB_ORDER:
        return False
    idx = V.TAB_ORDER.index(label)
    for _ in range(tries):
        nodes = V.dump_all()
        bar = next((n for n in nodes if n['type'] == 'TabBar'), None)
        if bar is None:
            time.sleep(1.0)
            continue
        bx0, by0, bx1, by1 = V._bounds(bar['bounds'])
        n = len(V.TAB_ORDER)
        x = int(bx0 + (idx + 0.5) * (bx1 - bx0) / n)
        y = int((by0 + by1) / 2)
        V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
        time.sleep(2.2)
        tl = texts()
        if any(m in tl for m in markers):
            return True
        if not strict:
            return True
    return False


def consumed_kcal():
    """今日摄入的数字。

    板面表头是「今日摄入」+ 一个大数字 + 「/ NNNN kcal」，
    这里取大数字那个文本节点。
    """
    nodes = V.dump()
    for i, n in enumerate(nodes):
        if n['text'] == '今日摄入':
            for m in nodes[i + 1:i + 6]:
                t = m['text']
                if t.isdigit():
                    return int(t)
    return None


def tap_dialog_button(label):
    """点确认弹窗里的按钮（取消 / 确认）。

    弹窗按钮与页面上的同名按钮靠**纵坐标**区分：
    弹窗永远在屏幕更下方，取纵坐标最大的那个。
    """
    nodes = V.dump()
    hits = [n for n in nodes if n['text'] == label]
    if not hits:
        return False
    hits.sort(key=lambda n: V.center(n['bounds'])[1])
    x, y = V.center(hits[-1]['bounds'])
    V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
    time.sleep(2.0)
    return True


def create_demo_record():
    """用演示模式造一条真实饮食记录（走真实的识别→保存链路）。

    必须是真的 food_log 记录：示例贴纸是 DEMO_STICKER，
    不挂在饮食记录上，删它不会走确认弹窗。
    """
    if not V.home_top():
        return False
    if not V.tap('拍照', settle=4.0):
        return False
    if not V.tap('没有照片？用内置示例图试一下', settle=3.5):
        return False
    if not V.tap('开始 AI 识别', settle=12.0):
        return False
    time.sleep(4.0)
    if not V.find_and_tap('使用结果并编辑', settle=3.5):
        return False
    if not V.tap('确认保存', settle=4.5):
        return False
    return V.home_top()


def open_sticker_editor():
    """点开黑板上那张**真实记录**的贴纸，打开编辑抽屉。

    真实记录的贴纸标题是「演示食物（模拟识别）」，示例贴纸不是。
    抽屉里的判据用「碎碎念」「便签纸」这类抽屉内字段。
    """
    imgs = [n for n in image_nodes() if 60 <= n['w'] <= 700 and 60 <= n['h'] <= 700]
    if not imgs:
        return False
    target = imgs[0]
    x = target['tl'][0] + target['w'] // 2
    y = target['tl'][1] + target['h'] // 2
    V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
    time.sleep(2.0)
    return V.has(V.dump(), '碎碎念')


def main():
    if not V.connected():
        print('设备桥接不可用。')
        return 2

    print('=== 首启与引导 ===')
    # ensure_ready 判「就绪」用的是今日页的判据（今日摄入）。
    # 如果上一轮结束时停在别的 Tab，它会误判为「没就绪」并去重走引导 ——
    # 而引导早就走过了，必然失败。所以先把底栏切回今日。
    V.tap_tab('今日', settle=2.0)
    if not ensure_ready():
        print('  首启/引导未就绪')
        return 5
    if not V.enable_demo_mode():
        print('  演示模式未启用')
        return 7
    print('  已就绪')

    results = []

    # ---------- ① 先访问进度页（复现报告里的顺序） ----------
    # 报告的复现路径是「先访问进度页 → 回今日页新增 → 返回进度页」，
    # 所以必须**先**把进度页逛一遍，否则测的是「首次进入就带新数据」，
    # 证明不了刷新逻辑。
    print('\n[1] 先访问进度页')
    ok = goto_tab('进度')
    results.append(step('切到进度页', ok))
    time.sleep(1.0)

    # ---------- ② 建一条真实记录 ----------
    print('\n[2] 回今日页造一条真实饮食记录')
    if not goto_tab('今日'):
        results.append(step('回到今日页', False))
        return report(results)
    if not create_demo_record():
        results.append(step('造出真实记录', False))
        return report(results)
    results.append(step('造出真实记录', True))
    kcal = consumed_kcal()
    results.append(step('今日摄入已更新', kcal is not None and kcal > 0, f'{kcal} kcal'))
    V.shot('fr_01_record')

    # ---------- ③ 进度页跟着记录更新刷新 ----------
    print('\n[3] 回到进度页：应立刻显示新记录')
    ok = goto_tab('进度')
    tl = texts()
    results.append(step('切回进度页', ok))
    # 千分位：1240 在界面上是「1,240」，两种写法都认
    candidates = [str(kcal), f'{kcal:,}']
    ok = any(c in tl for c in candidates)
    results.append(step('进度页立刻显示新记录（未切统计范围）', ok,
                        f'期望含 {candidates[0]}，实际：{tl[:80]}'))
    V.shot('fr_02_progress')

    # ---------- ④ 宏量目标表单 ----------
    print('\n[4] 宏量目标表单')
    if not goto_tab('我的'):
        results.append(step('切到我的页', False))
    else:
        V.scroll_top()
        opened = V.find_and_tap('修改宏量', settle=2.5)
        tl = texts()
        ok = opened and ('蛋白（g）' in tl or '蛋白' in tl)
        results.append(step('「修改宏量」打开真实表单', ok, tl[:60]))
        V.shot('fr_03_macro')
        # 关掉浮层（点右上角 ✕）
        nodes = V.dump()
        close = [n for n in nodes if n['text'] == '✕']
        if close:
            x, y = V.center(close[-1]['bounds'])
            V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
            time.sleep(1.5)

    # ---------- ⑤ 确认弹窗：取消不执行 ----------
    print('\n[5] 黑板删除：取消不执行')
    if not goto_tab('今日'):
        results.append(step('回到今日页', False))
        return report(results)
    if not open_sticker_editor():
        results.append(step('打开贴纸编辑抽屉', False))
        return report(results)
    results.append(step('打开贴纸编辑抽屉', True))
    if not V.find_and_tap('删除记录', settle=2.0):
        results.append(step('点「删除记录」', False))
        return report(results)
    tl = texts()
    ok = '删除这条饮食记录' in tl
    results.append(step('弹出确认框并说明后果', ok, tl[:70]))
    V.shot('fr_04_confirm')
    tap_dialog_button('取消')
    time.sleep(1.0)
    after = consumed_kcal()
    results.append(step('点「取消」后记录还在', after == kcal, f'{after} vs {kcal}'))

    # ---------- ⑥ 确认弹窗：确认真的执行 ----------
    print('\n[6] 黑板删除：确认真的执行')
    if not open_sticker_editor():
        results.append(step('再次打开编辑抽屉', False))
        return report(results)
    if not V.find_and_tap('删除记录', settle=2.0):
        results.append(step('再次点「删除记录」', False))
        return report(results)
    if not tap_dialog_button('删除'):
        results.append(step('点确认框的「删除」', False))
        return report(results)
    time.sleep(1.5)
    after = consumed_kcal()
    results.append(step('点「确认」后记录真的被删掉',
                        after is not None and after < kcal, f'{after} vs {kcal}'))
    V.shot('fr_05_deleted')

    # ---------- ⑦ 网格视图也能分享 ----------
    print('\n[7] 网格视图分享')
    if not goto_tab('今日'):
        results.append(step('回到今日页', False))
        return report(results)
    ok_grid = V.tap('网格', settle=2.5)
    results.append(step('切到网格视图', ok_grid))
    if ok_grid:
        if V.tap('分享', settle=5.0):
            tl = texts()
            ok = '今日手帐分享卡' in tl and '生成失败' not in tl
            results.append(step('网格视图也能生成分享卡', ok, tl[:60]))
            V.shot('fr_06_grid_share')
            # 关掉预览页（底部固定的关闭按钮）
            nodes = V.dump()
            close = [n for n in nodes if n['text'] == '关闭']
            if close:
                x, y = V.center(close[-1]['bounds'])
                V.sh('shell', 'uitest', 'uiInput', 'click', str(x), str(y))
                time.sleep(1.5)
        else:
            results.append(step('网格视图也能生成分享卡', False, '点不到「分享」'))
        # 切回自由画布
        V.tap('自由', settle=2.0)

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
