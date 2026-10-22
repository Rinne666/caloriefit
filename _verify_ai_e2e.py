"""用 App 里 AI_SYSTEM_PROMPT 的原文 + 真实食物图,验证模型返回是否符合 schema。"""
import json, urllib.request, base64, sys, io, os

# 密钥一律从环境变量读，**不要写进仓库**。
# 这个脚本曾把真实 Key 硬编码在第 4 行并提交过（已从 git 历史清除）。
# 用法：$env:DASHSCOPE_KEY = "sk-..."  然后 python _verify_ai_e2e.py
KEY   = os.environ.get("DASHSCOPE_KEY", "")
BASE  = "https://llm-6t68vtlqwy610xvj.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
MODEL = "qwen3.8-omni-flash"
IMG   = r"C:\Users\18165\Desktop\calories\shots\test_food.jpg"

# 与 entry/src/main/ets/common/AiConstants.ets 中的 AI_SYSTEM_PROMPT 保持一致
SYSTEM = (
    "你是CalorieFit的食物视觉识别与热量估算助手。识别图片中可见的食物，估算整份可食用部分的总热量kcal。"
    "考虑食物种类、份量、烹饪方式、酱料和油脂，不要把餐具计算进去。不能从照片准确确定重量时，"
    "应作保守的区间判断并在备注中说明。不得把估算说成实测值。如果不是食物图片，返回foodName为无法识别、"
    "estimatedTotalKcal为null、confidence为0。\n\n"
    "同时估算三大宏量营养素（克）：proteinG蛋白质、carbsG碳水化合物、fatG脂肪。三者必须与总热量自洽："
    "按蛋白4kcal/g、碳水4kcal/g、脂肪9kcal/g回算，回算值与estimatedTotalKcal的偏差不得超过正负20%。"
    "无法可靠估算时返回null，不要为了填满字段而编造数字。\n\n"
    "只返回一个合法JSON对象，不输出Markdown。字段必须为：\n"
    "foodName字符串，estimatedTotalKcal整数或null，confidence为0到1之间的数字，\n"
    "proteinG整数或null（0到999），carbsG整数或null（0到999），fatG整数或null（0到999），\n"
    "notes字符串，控制在60字以内。\n"
    "多种食物在foodName中合并命名，热量与宏量均返回整盘合计。"
)
USER = "请识别这张照片中的食物，估算整份热量与三大宏量（蛋白质/碳水/脂肪），严格按System要求返回JSON。"

# 压缩到 App 同款约束:长边 1280 / 2MB 内
raw = base64.b64encode(open(IMG, "rb").read()).decode()
data_url = "data:image/jpeg;base64," + raw
print(f"图片 base64: {len(raw)} 字符")

body = {
    "model": MODEL, "stream": False, "enable_thinking": False,
    "temperature": 0.2, "max_tokens": 512,
    "response_format": {"type": "json_object"},
    "messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": [
            {"type": "text", "text": USER},
            {"type": "image_url", "image_url": {"url": data_url}},
        ]},
    ],
}

req = urllib.request.Request(BASE + "/chat/completions",
    data=json.dumps(body).encode("utf-8"),
    headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
try:
    with urllib.request.urlopen(req, timeout=90) as r:
        j = json.loads(r.read().decode("utf-8", "replace"))
except urllib.error.HTTPError as e:
    print("HTTPError", e.code); print(e.read().decode("utf-8","replace")[:900]); raise SystemExit
except Exception as e:
    print("ERR", type(e).__name__, str(e)[:300]); raise SystemExit

content = j["choices"][0]["message"]["content"]
print("\n--- 模型原始返回 ---")
print(content)
print("\n--- 与 App 解析器一致的校验 ---")

# ==== 等价于 AiResponseParser.parseContent ====
TOL, MAXG = 0.20, 999
def read_macro(v):
    if v is None: return None
    if isinstance(v, bool) or not isinstance(v, (int, float)): return None
    if isinstance(v, float) and v != int(v): return None
    return int(v) if 0 <= v <= MAXG else None

try:
    o = json.loads(content)
except Exception as e:
    print("  JSON 解析失败:", e); raise SystemExit
print("  JSON 合法")
name = o.get("foodName")
print(f"  foodName   = {name}  (长度 {len(name) if isinstance(name,str) else 'N/A'})")
kcal = o.get("estimatedTotalKcal")
print(f"  kcal       = {kcal}")
conf = o.get("confidence")
print(f"  confidence = {conf}  {'OK' if isinstance(conf,(int,float)) and 0<=conf<=1 else 'FAIL'}")
notes = o.get("notes")
print(f"  notes      = {(notes or '')[:80]}")

P, C, F = read_macro(o.get("proteinG")), read_macro(o.get("carbsG")), read_macro(o.get("fatG"))
print(f"  P/C/F      = {P} / {C} / {F}")
if P is not None and C is not None and F is not None and kcal:
    back = P*4 + C*4 + F*9
    dev = abs(back - kcal) / kcal
    verdict = "保留" if dev <= TOL else "丢弃宏量"
    print(f"  Atwater    = {back} vs {kcal}  偏差 {dev*100:.1f}%  -> {verdict}")
else:
    print("  Atwater    = 跳过(字段不全或热量为 null)")
