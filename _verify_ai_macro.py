"""
独立复算 AiResponseParser 的宏量守卫逻辑。
本机无 DevEco SDK 跑不了 ohosTest，用等价实现验证判定边界。
"""

import json

TOLERANCE = 0.20
MACRO_MAX = 999

fails = []
def check(name, cond, detail=''):
    if not cond:
        fails.append(f'{name} {detail}')
    print(f'  [{"PASS" if cond else "FAIL"}] {name}' + (f'   {detail}' if detail else ''))

def read_macro(v):
    """等价于 readMacro()：畸形返回 None 而不抛错"""
    if v is None:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    if isinstance(v, float) and v != int(v):
        return None
    if v < 0 or v > MACRO_MAX:
        return None
    return int(v)

def parse(kcal, p, c, f, notes='测试'):
    obj = {'foodName': '测试食物', 'estimatedTotalKcal': kcal,
           'proteinG': p, 'carbsG': c, 'fatG': f,
           'confidence': 0.8, 'notes': notes}
    # 严格字段校验（等价 ArkTS 侧）
    if not isinstance(obj['foodName'], str) or not (1 <= len(obj['foodName'].strip()) <= 40):
        raise ValueError('foodName')
    k = obj['estimatedTotalKcal']
    if k is not None:
        if isinstance(k, bool) or not isinstance(k, (int, float)):
            raise ValueError('kcal type')
        if isinstance(k, float) and k != int(k):
            raise ValueError('kcal not int')
        if k < 1 or k > 10000:
            raise ValueError('kcal range')
        k = int(k)

    P, C, F = read_macro(p), read_macro(c), read_macro(f)
    consistent = False
    if P is not None and C is not None and F is not None and k is not None and k > 0:
        back = P*4 + C*4 + F*9
        dev = abs(back - k) / k
        if dev <= TOLERANCE:
            consistent = True
        else:
            P = C = F = None
            notes = (notes + f' 宏量与总热量偏差 {round(dev*100)}%，已忽略。')[:500]
    return {'kcal': k, 'p': P, 'c': C, 'f': F,
            'consistent': consistent, 'notes': notes,
            'has': P is not None and C is not None and F is not None}

print("=" * 68)
print("正常路径")
print("=" * 68)
r = parse(1878, 150, 144, 78)
check("参考样本 150/144/78→1878 保留", r['has'] and r['consistent'])
check("  三值原样", (r['p'], r['c'], r['f']) == (150, 144, 78))

demo = parse(620, 38, 72, 19, '本地演示数据')
check("演示数据 611 vs 620 通过", demo['has'] and demo['consistent'],
      f"回算={38*4+72*4+19*9}")

print("\n" + "=" * 68)
print("容差边界")
print("=" * 68)
r = parse(1000, 100, 100, 0)      # 回算 800，偏差 20.0%
check("偏差恰等容差 → 保留", r['has'] and r['consistent'])
r = parse(1000, 100, 100, 1)      # 回算 809，偏差 19.1%
check("偏差 19.1% → 保留", r['has'] and r['consistent'])
r = parse(1000, 100, 100, 20)     # 回算 980，偏差 2.0%
check("偏差 2.0% → 保留", r['has'] and r['consistent'])
r = parse(300, 100, 100, 0)       # 回算 800，偏差 166.7%
check("严重不一致 → 丢弃宏量", not r['has'] and not r['consistent'])
check("  总热量仍保留", r['kcal'] == 300)
check("  备注写入原因", '已忽略' in r['notes'])

print("\n" + "=" * 68)
print("缺失场景不做判断")
print("=" * 68)
r = parse(500, None, None, None)
check("宏量全 null", not r['has'] and not r['consistent'] and r['kcal'] == 500)
r = parse(None, 10, 10, 10)
check("热量 null → 不误判", r['kcal'] is None and not r['consistent'])
# 老版本模型不返回宏量键
old = json.dumps({'foodName':'旧','estimatedTotalKcal':400,'confidence':0.7,'notes':''})
o = json.loads(old)
r = parse(o['estimatedTotalKcal'], o.get('proteinG'), o.get('carbsG'), o.get('fatG'))
check("缺字段视作 null", not r['has'] and r['kcal'] == 400)

print("\n" + "=" * 68)
print("单字段畸形不拖垮其余")
print("=" * 68)
r = parse(1000, 12.5, 200, 10)
check("小数蛋白 → None", r['p'] is None)
check("  碳水脂肪保留", r['c'] == 200 and r['f'] == 10)
check("  不做一致性判断", not r['consistent'])
r = parse(1000, -5, 100, 10)
check("负数 → None", r['p'] is None)
r = parse(1000, MACRO_MAX + 1, 100, 10)
check(f"> {MACRO_MAX} → None", r['p'] is None)
r = parse(MACRO_MAX * 9, 0, 0, MACRO_MAX)
check(f"上界 {MACRO_MAX} 接受", r['f'] == MACRO_MAX and r['consistent'])
r = parse(1000, '50', 100, 10)
check("字符串 → None", r['p'] is None)
r = parse(1000, True, 100, 10)
check("布尔 → None", r['p'] is None)

print("\n" + "=" * 68)
print("常量")
print("=" * 68)
check("容差 = 20%", TOLERANCE == 0.20)
back = 100*4 + 100*4 + 0
check("边界样本偏差恰 20%", abs(abs(back-1000)/1000 - TOLERANCE) < 0.0001)

print("\n" + "=" * 68)
print("真实场景抽样")
print("=" * 68)
cases = [
    ("米饭一碗 200g", 260, 5, 57, 1),
    ("鸡胸100g", 165, 31, 0, 3.6),
    ("沙拉含油醋汁", 180, 3, 12, 15),
    ("奶茶全糖", 350, 6, 48, 14),
    ("外卖盖饭", 850, 32, 110, 28),
]
for name, kcal, p, c, f in cases:
    # 浮点宏量统一取整，模拟模型输出
    r = parse(kcal, round(p), round(c), round(f))
    back = (round(p) or 0)*4 + (round(c) or 0)*4 + (round(f) or 0)*9
    dev = abs(back - kcal)/kcal*100
    verdict = '保留' if r['has'] else '丢弃'
    print(f"  {name:16s} {kcal:>4}kcal  宏量 {round(p)}/{round(c)}/{round(f)}"
          f"  回算 {back:>4}  偏差 {dev:5.1f}%  → {verdict}")

print("\n" + "=" * 68)
if fails:
    print(f"✗ {len(fails)} 项未通过")
    for x in fails: print("   -", x)
else:
    print("✓ 全部断言通过")
print("=" * 68)
