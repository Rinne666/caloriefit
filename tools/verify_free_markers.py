# -*- coding: utf-8 -*-
"""定向验证：首启同意页的政策入口可见性 + 政策全文 + AI 生成显性标识。

为什么单独写这个而不是跑 verify_all 全量：
    本机模拟器桥接反复自退，全量回归一次要 12 分钟、期间掉线就得重来。
    这三处是本轮实际改动过的界面，用一个脚本一次跑完更稳。

复用了 verify_all 的设备交互与开关读取逻辑，避免两套实现跑偏。

用法：python -u tools/verify_free_markers.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

import verify_all as V  # noqa: E402

fails = []


def check(name, cond, detail=''):
    print(f'  [{"PASS" if cond else "FAIL"}] {name}   {detail}')
    if not cond:
        fails.append(name)


def texts():
    return [n['text'] for n in V.dump()]


def has(needle, tl=None):
    tl = texts() if tl is None else tl
    return any(needle in t for t in tl)


print('=== 准备：清数据 → 冷启动 ===')
V.sh('shell', 'power-shell', 'wakeup')
V.sh('shell', 'bm', 'clean', '-n', V.BUNDLE, '-d')
V.sh('shell', 'aa', 'force-stop', V.BUNDLE)
time.sleep(2)
V.sh('shell', 'aa', 'start', '-b', V.BUNDLE, '-a', V.ABILITY)
time.sleep(10)

print('=== 1. 首启同意页 ===')
tl = texts()
check('同意页出现', has('请先阅读隐私说明', tl))
check('政策入口在首屏可见', has('阅读完整隐私政策', tl),
      '（上一轮加计步说明后被挤到折叠线以下）')
check('计步传感器已如实披露', has('计步传感器', tl))
V.shot('v_free_consent')

if has('阅读完整隐私政策', tl):
    V.tap('阅读完整隐私政策', settle=2.0)
    pol = texts()
    check('政策全文可打开', has('运营主体与联系渠道', pol))
    check('政策写明计步传感器来源', has('计步传感器', pol))
    # §5（AI 接收方）在折叠线以下，UI 树只含已布局的文本，要滚下去才看得到
    for _ in range(4):
        V.sh('shell', 'uitest', 'uiInput', 'swipe', '640', '2100', '640', '900', str(V.SCAN_VELOCITY))
        time.sleep(V.SCAN_SETTLE)
        pol = texts()
        if has('百炼', pol):
            break
    check('政策写明百炼域名限定', has('百炼', pol))
    check('政策写明开发者与接收方无合作关系', has('不存在合作', pol))
    V.shot('v_free_policy')
    # 用页面内的返回箭头关掉浮层。系统返回键会退出整个应用（已加 onBackPress 修复，
    # 但这里用浮层自己的箭头更稳，不依赖那次修复）
    V.tap('‹', settle=2.0)
    tl2 = texts()
    check('返回后回到同意页', has('请先阅读隐私说明', tl2))

print('=== 2. 同意 → 引导 → 今日页 ===')
V.tap('我已阅读并同意', settle=0.8)
V.tap('我单独同意处理', settle=0.8)
V.tap('同意并继续', settle=6.0)
tl = texts()
check('进入引导首屏', has('你想达成什么', tl) or has('目标', tl), str(tl[:3]))

# 引导流程复用 verify_all 里已验证过的实现（自己重写过一版，走不完）
if not V.complete_onboarding_for_test():
    check('引导完成', False, 'complete_onboarding_for_test 返回 False')
else:
    check('引导完成并进入今日页', has('今日热量', texts()))

print('=== 3. AI 演示模式 → 结果卡显性标识 ===')
V.tap('我的', settle=2.5)
V.scroll_top()
ok = V.find_and_tap('AI 食物识别设置', max_scroll=20, settle=3.0)
check('进入 AI 设置页', ok)
if ok:
    toggles = V.read_toggles()
    check('找到演示模式开关', len(toggles) >= 2, f'toggles={len(toggles)}')
    if len(toggles) >= 2 and toggles[1]['checked'] != 'true':
        p = V.center(toggles[1]['bounds'])
        V.sh('shell', 'uitest', 'uiInput', 'click', str(p[0]), str(p[1]))
        time.sleep(1.2)
    V.back()
    V.tap('今日', settle=2.5)
    V.scroll_top()
    V.tap('拍照识别食物', settle=3.0)
    # 必须先选示例图，否则「开始 AI 识别」点的是空状态，停在选图页出不来结果
    V.tap('示例图', settle=2.5)
    V.tap('开始 AI 识别', settle=8.0)
    tl = texts()
    check('出现「AI 生成估算」显性标识', has('AI 生成估算', tl), str(tl[:6]))
    check('出现 AI 生成声明行', has('均为 AI 生成', tl))
    check('演示模式标注仍在', has('演示模式', tl))
    V.shot('v_free_ai_marker')

print('=== 汇总 ===')
if fails:
    print(f'{len(fails)} 项失败: ' + '; '.join(fails))
    sys.exit(1)
print('全部通过')
sys.exit(0)
