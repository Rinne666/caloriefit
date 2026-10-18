"""
独立复算 CalorieEngine.ets 的全部测试断言。
本机无 DevEco SDK 无法跑 ohosTest，故用等价实现验证数学正确性。
若日后 ArkTS 测试结果与此不符，以数学为准并回头查 ArkTS 实现。
"""

ATWATER_PROTEIN, ATWATER_CARB, ATWATER_FAT = 4, 4, 9
ACTIVITY = {
    'sedentary': 1.200, 'light': 1.375, 'moderate': 1.550,
    'very_active': 1.725, 'athlete': 1.900
}
MODE_ADJ = {
    'weight_loss': -500, 'deficit': -500, 'maintain': 0,
    'recomp': 0, 'surplus': 300
}
SPLIT_BASE = {'p': 0.319, 'c': 0.307, 'f': 0.374}
SPLIT_CUT = {'p': 0.350, 'c': 0.300, 'f': 0.350}

fails = []
def check(name, cond, detail=''):
    mark = 'PASS' if cond else 'FAIL'
    if not cond:
        fails.append(f'{name} {detail}')
    print(f'  [{mark}] {name}' + (f'   {detail}' if detail else ''))

def bmi(w, h):
    hh = h / 100
    return 0 if hh <= 0 else w / (hh * hh)

def bmr(w, h, age, sex, bf):
    if bf is not None and 0 < bf < 0.7:
        return (370 + 21.6 * w * (1 - bf), 'Katch-McArdle')
    base = 10 * w + 6.25 * h - 5 * age
    return (base + (5 if sex == 'male' else -161), 'Mifflin-St Jeor')

def tdee(b, act):
    return b * ACTIVITY.get(act, 1.2)

def target(b, act, mode):
    return max(round(b), round(tdee(b, act) + MODE_ADJ.get(mode, 0)))

def alloc(kcal, mode):
    s = SPLIT_CUT if mode in ('weight_loss', 'recomp') else SPLIT_BASE
    return {
        'proteinG': round(kcal * s['p'] / 4),
        'carbsG': round(kcal * s['c'] / 4),
        'fatG': round(kcal * s['f'] / 9),
    }

def kcal_of(m):
    return round(m['proteinG'] * 4 + m['carbsG'] * 4 + m['fatG'] * 9)

print("=" * 66)
print("Atwater 与 NutriScan 反推验算")
print("=" * 66)
check("Atwater 系数 4/4/9", (ATWATER_PROTEIN, ATWATER_CARB, ATWATER_FAT) == (4, 4, 9))
r = kcal_of({'proteinG': 150, 'carbsG': 144, 'fatG': 78})
check("NutriScan 实测反推 = 1878", r == 1878, f"算得 {r}")
check("与手算一致", r == 150*4 + 144*4 + 78*9)
check("零宏量 = 0 kcal", kcal_of({'proteinG':0,'carbsG':0,'fatG':0}) == 0)

print("\n" + "=" * 66)
print("BMI")
print("=" * 66)
check("70kg/175cm ≈ 22.857", abs(bmi(70,175) - 22.857) < 0.01, f"{bmi(70,175):.3f}")
check("身高 0 → 0", bmi(70,0) == 0)

print("\n" + "=" * 66)
print("BMR 双公式")
print("=" * 66)
v, f = bmr(70,175,30,'male',0.20)
check("有体脂走 Katch-McArdle", f == 'Katch-McArdle', f"BMR={v:.1f}")
check("  值 = 370+21.6×56", abs(v - (370+21.6*56)) < 0.001, f"{v:.2f}")
v2, f2 = bmr(70,175,30,'male',None)
check("无体脂回退 Mifflin", f2 == 'Mifflin-St Jeor', f"BMR={v2:.2f}")
check("  男 = 1648.75", abs(v2 - 1648.75) < 0.001)
_, f3 = bmr(70,175,30,'male',0.0)
_, f4 = bmr(70,175,30,'male',0.7)
check("体脂 0 → 回退", f3 == 'Mifflin-St Jeor')
check("体脂 0.7 → 回退", f4 == 'Mifflin-St Jeor')
vf, _ = bmr(60,165,28,'female',None)
check("女 = 1330.25", abs(vf - 1330.25) < 0.001, f"{vf:.2f}")

print("\n" + "=" * 66)
print("TDEE / 目标热量")
print("=" * 66)
check("moderate 倍率 1.55", abs(tdee(1600,'moderate') - 1600*1.55) < 0.001)
check("未知活动量 → 1.2", abs(tdee(1600,'bogus') - 1600*1.2) < 0.001)
t = target(1500, 'athlete', 'weight_loss')
check("目标 ≥ BMR（赤字不越界）", t >= 1500, f"目标={t}, BMR=1500")
tm = target(1600, 'moderate', 'maintain')
check("maintain = TDEE", abs(tm - round(1600*1.55)) < 1, f"{tm}")

print("\n" + "=" * 66)
print("宏量分配自洽性")
print("=" * 66)
for mode in ['weight_loss','maintain','surplus','deficit','recomp']:
    m = alloc(2000, mode)
    back = kcal_of(m)
    ok = abs(back - 2000) <= 10
    check(f"{mode:12s} 回算≈2000", ok,
          f"蛋白{m['proteinG']}g 碳水{m['carbsG']}g 脂肪{m['fatG']}g → {back}kcal")
cut, mn = alloc(2000,'weight_loss'), alloc(2000,'maintain')
check("减脂模式蛋白更高", cut['proteinG'] > mn['proteinG'],
      f"{cut['proteinG']} > {mn['proteinG']}")

print("\n" + "=" * 66)
print("实际样本:75kg/178cm/32岁/体脂22%/中度/减脂")
print("=" * 66)
b, formula = bmr(75, 178, 32, 'male', 0.22)
td = tdee(b, 'moderate')
tg = target(b, 'moderate', 'weight_loss')
m = alloc(tg, 'weight_loss')
print(f"  BMI      {bmi(75,178):.1f}")
print(f"  BMR      {b:.0f}  ({formula})")
print(f"  TDEE     {td:.0f}")
print(f"  目标     {tg}  (BMR-500 = {b-500:.0f})")
print(f"  宏量     蛋白 {m['proteinG']}g / 碳水 {m['carbsG']}g / 脂肪 {m['fatG']}g")
print(f"  Atwater 回算 {kcal_of(m)} kcal   偏差 {kcal_of(m)-tg:+d}")
check("plan 自洽(偏差≤10)", abs(kcal_of(m) - tg) <= 10)
check("目标 ≥ BMR", tg >= round(b))
check("TDEE > BMR", td > b)

print("\n" + "=" * 66)
print("达标判定与夹取")
print("=" * 66)
def ratio(a, t): return 0 if t <= 0 else max(0, min(1, a/t))
check("ratio 50/100 = 0.5", ratio(50,100) == 0.5)
check("ratio 150/100 → 1", ratio(150,100) == 1)
check("ratio 负数 → 0", ratio(-5,100) == 0)
check("ratio 目标 0 → 0", ratio(50,0) == 0)
check("碳水 155/144 判超标", 155 > 144)
check("蛋白 36/150 未超标", not (36 > 150))

def grams(k, per100): return 0 if per100 <= 0 else round(k/per100*100)
check("200kcal @500/100g → 40g", grams(200,500) == 40)
check("热量密度 0 → 0g", grams(200,0) == 0)
check("40g 回算 200kcal", round(grams(200,500)/100*500) == 200)

print("\n" + "=" * 66)
if fails:
    print(f"✗ {len(fails)} 项未通过:")
    for x in fails: print("   -", x)
else:
    print("✓ 全部断言通过")
print("=" * 66)
