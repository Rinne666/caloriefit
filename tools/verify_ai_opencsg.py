# -*- coding: utf-8 -*-
"""端到端核验 App 的 AI 识别链路打 OpenCSG 网关是否成立。

做三件事：
  1. 从 **App 源码** 里原样抠出 system prompt（AiConstants.ets）与 user prompt（AiPrompt.ets），
     并按 AiRecognitionService.buildRequestBody 的结构复刻请求体 —— 避免脚本与 App 漂移。
  2. 用 AiResponseParser 的判定规则（严格字段 + Atwater 宏量守卫 + 位置字段）逐条校验返回。
  3. 拿仓库里已入库的真实食物照片（entry/src/ohosTest/resources/rawfile/food*.jpg）跑。

密钥**不写进仓库**。取值顺序：
  1) 环境变量 OPENCSG_KEY
  2) 本机 ~/.minimax/config.yaml 里的 provider.opencsg.options.apiKey

用法：
  OPENCSG_KEY=gk_xxx python3 tools/verify_ai_opencsg.py
  python3 tools/verify_ai_opencsg.py --model deepseek-v4.1-flash-1017 --images a.jpg b.jpg
"""
import argparse
import base64
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

REPO = Path(__file__).resolve().parent.parent
ETS_COMMON = REPO / 'entry/src/main/ets/common/AiConstants.ets'
ETS_PROMPT = REPO / 'entry/src/main/ets/services/AiPrompt.ets'
DEFAULT_IMAGES = sorted((REPO / 'entry/src/ohosTest/resources/rawfile').glob('food*.jpg'))

BASE_URL = 'https://opencsg.com/aigateway/v1'
MODEL = 'deepseek-v4.1-flash-1017'

# ---- App 侧的判定常量（与 AiConstants.ets 保持一致）----
MACRO_TOLERANCE = 0.20
MACRO_MAX_G = 999


def read_api_key() -> str:
    key = os.environ.get('OPENCSG_KEY', '').strip()
    if key:
        return key
    cfg = Path.home() / '.minimax/config.yaml'
    if cfg.exists():
        try:
            import yaml
            data = yaml.safe_load(cfg.read_text(encoding='utf-8')) or {}
            # 运行时可能把自定义服务方放在 provider 下，也可能在迁移后放到 custom_provider 下
            for section in ('provider', 'custom_provider'):
                entry = (data.get(section) or {}).get('opencsg') or {}
                key = (entry.get('options') or {}).get('apiKey', '')
                if key:
                    return str(key).strip()
        except Exception:
            pass
    return ''


def app_prompts() -> tuple:
    """从 App 源码原样取出 system / user prompt。"""
    common = ETS_COMMON.read_text(encoding='utf-8')
    system = re.search(r'AI_SYSTEM_PROMPT: string = `(.*?)`;', common, re.S)
    if not system:
        raise SystemExit('cannot locate AI_SYSTEM_PROMPT in AiConstants.ets')
    prompt_src = ETS_PROMPT.read_text(encoding='utf-8')
    user = re.search(r"userPrompt\(\): string \{\s*return '(.*?)';", prompt_src, re.S)
    if not user:
        raise SystemExit('cannot locate userPrompt() in AiPrompt.ets')
    return system.group(1), user.group(1)


def build_body(model: str, system: str, user: str, image_path: Path) -> dict:
    """复刻 AiRecognitionService.buildRequestBody。"""
    raw = base64.b64encode(image_path.read_bytes()).decode()
    return {
        'model': model,
        'stream': False,
        'enable_thinking': False,
        'temperature': 0.2,
        'max_tokens': 512,
        'response_format': {'type': 'json_object'},
        'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': [
                {'type': 'text', 'text': user},
                {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,' + raw}},
            ]},
        ],
    }


def post(base_url: str, api_key: str, body: dict, timeout: int = 60):
    req = urllib.request.Request(
        base_url.rstrip('/') + '/chat/completions',
        data=json.dumps(body).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + api_key,
            'Accept-Encoding': 'identity',
        })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
            if resp.headers.get('content-encoding') == 'gzip' or data[:2] == b'\x1f\x8b':
                data = gzip.decompress(data)
            return resp.status, data.decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        data = e.read()
        try:
            if data[:2] == b'\x1f\x8b':
                data = gzip.decompress(data)
        except Exception:
            pass
        return e.code, data.decode('utf-8', 'replace')


def read_macro(v):
    """等价于 AiResponseParser.readMacro。"""
    if v is None:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    if not float(v).is_integer():
        return None
    if v < 0 or v > MACRO_MAX_G:
        return None
    return int(v)


def parse_like_app(content: str) -> dict:
    """等价于 AiResponseParser.parseContent 的判定，返回每项的通过状态。"""
    checks = {}
    try:
        obj = json.loads(content)
    except Exception as e:
        return {'ok': False, 'checks': {'JSON 合法': False}, 'detail': f'JSON 解析失败: {e}'}
    if not isinstance(obj, dict):
        return {'ok': False, 'checks': {'JSON 合法': False}, 'detail': '不是 JSON 对象'}

    name = obj.get('foodName')
    checks['foodName 合法'] = isinstance(name, str) and 1 <= len(name.strip()) <= 40

    kcal = obj.get('estimatedTotalKcal')
    if kcal is None:
        checks['kcal 合法'] = True
    else:
        checks['kcal 合法'] = (isinstance(kcal, (int, float)) and not isinstance(kcal, bool)
                               and float(kcal).is_integer() and 1 <= kcal <= 10000)

    conf = obj.get('confidence')
    checks['confidence 合法'] = isinstance(conf, (int, float)) and not isinstance(conf, bool) and 0 <= conf <= 1

    notes = obj.get('notes')
    checks['notes 合法'] = isinstance(notes, str) and len(notes) <= 60

    p, c, f = read_macro(obj.get('proteinG')), read_macro(obj.get('carbsG')), read_macro(obj.get('fatG'))
    macros_ok = True
    dev = None
    if p is not None and c is not None and f is not None and kcal:
        back = p * 4 + c * 4 + f * 9
        dev = abs(back - kcal) / kcal
        macros_ok = dev <= MACRO_TOLERANCE
    checks['宏量自洽'] = macros_ok

    region = obj.get('foodBox')
    checks['foodBox 可用'] = isinstance(region, dict) and all(
        isinstance(region.get(k), (int, float)) and not isinstance(region.get(k), bool)
        and 0 <= region.get(k) <= 1000 for k in ('x', 'y', 'width', 'height'))
    poly = obj.get('foodPolygon')
    checks['foodPolygon 可用'] = isinstance(poly, list) and len(poly) >= 3 and all(
        isinstance(pt, list) and len(pt) >= 2 for pt in poly)

    return {'ok': all(checks.values()), 'checks': checks, 'obj': obj, 'deviation': dev}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default=MODEL)
    ap.add_argument('--base-url', default=BASE_URL)
    ap.add_argument('--images', nargs='*', default=None)
    ap.add_argument('--timeout', type=int, default=60)
    args = ap.parse_args()

    api_key = read_api_key()
    if not api_key:
        raise SystemExit('缺少 API Key：请设置 OPENCSG_KEY 环境变量')

    system, user = app_prompts()
    images = [Path(p) for p in args.images] if args.images else DEFAULT_IMAGES
    if not images:
        raise SystemExit('没有可用的测试图片')

    print(f'模型 {args.model} | 网关 {args.base_url} | 图片 {len(images)} 张')
    print(f'system prompt {len(system)} 字, user prompt {len(user)} 字（均取自 App 源码）')
    print('=' * 72)

    failed = 0
    for image in images:
        body = build_body(args.model, system, user, image)
        started = time.time()
        status, raw = post(args.base_url, api_key, body, args.timeout)
        elapsed = time.time() - started
        print(f'\n[{image.name}] HTTP {status}  {elapsed:.1f}s')
        if status != 200:
            print('  ✗ 失败：', raw[:400])
            failed += 1
            continue
        try:
            j = json.loads(raw)
            content = j['choices'][0]['message']['content']
        except Exception as e:
            print('  ✗ 响应结构异常：', e, raw[:300])
            failed += 1
            continue
        result = parse_like_app(content)
        obj = result.get('obj', {})
        print(f"  foodName : {obj.get('foodName')}")
        print(f"  kcal     : {obj.get('estimatedTotalKcal')} | confidence {obj.get('confidence')}")
        print(f"  P/C/F    : {obj.get('proteinG')}/{obj.get('carbsG')}/{obj.get('fatG')}"
              + (f" | Atwater 偏差 {result['deviation']*100:.1f}%" if result.get('deviation') is not None else ''))
        print(f"  notes    : {obj.get('notes')}")
        for name, ok in result['checks'].items():
            print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
        if not result['ok']:
            failed += 1

    print('\n' + '=' * 72)
    print('✓ 全部通过' if failed == 0 else f'✗ {failed}/{len(images)} 张未通过')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
