# -*- coding: utf-8 -*-
"""删库重建：彻底清掉含密钥的不可达对象。

为什么必须删库而不是只 force push：
    GitHub 对不可达对象（unreachable / dangling）**不会立即回收**，
    旧提交仍能按 SHA 直接访问并读出密钥。
    code search 命中 0 并不代表安全 —— 知道 SHA 的人照样能取到。
    删除并重建是唯一能由本机完全保证「旧对象不存在」的做法。

前提：token 需带 `delete_repo` scope。经典 PAT 默认不带，
可在 GitHub → Settings → Developer settings → Personal access tokens 里重新生成时勾上。

**密钥不能出现在本仓库里**，用 $env:LEAKED_SECRET / $env:LEAKED_OLD_COMMIT 传进来。
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')
OWNER, NAME = 'Rinne666', 'caloriefit'
API = 'https://api.github.com'
SECRET = os.environ.get('LEAKED_SECRET', '')
OLD = os.environ.get('LEAKED_OLD_COMMIT', '')
DESC = 'CalorieFit —— HarmonyOS 饮食/饮水/运动/步数记录应用（ArkTS / ArkUI）'


def token():
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'github.com' in line:
                return line.split('://', 1)[1].split(':', 1)[1].split('@', 1)[0]
    raise SystemExit('no token')


H = {'Authorization': f'Bearer {token()}', 'User-Agent': 'caloriefit-cleanup',
     'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}


def api(method, path, payload=None):
    data = json.dumps(payload).encode('utf-8') if payload is not None else None
    req = urllib.request.Request(API + path, data=data, headers=H, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode('utf-8')
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', errors='replace')


def git(*args, timeout=300):
    return subprocess.run(['git', *args], cwd=REPO, capture_output=True, text=True,
                          timeout=timeout)


print('=== 1. 删除远端仓库 ===')
st, body = api('DELETE', f'/repos/{OWNER}/{NAME}')
if st == 204:
    print('  已删除')
elif st == 403 and 'admin rights' in str(body):
    print('  [!] token 缺 delete_repo scope，无法删库。')
    print('      → 给 token 加上 delete_repo 权限后重跑本脚本；')
    print('      → 或在 GitHub 网页端 Settings → Danger Zone → Delete 手动删除后重跑。')
    sys.exit(2)
else:
    print(f'  HTTP {st}: {str(body)[:300]}')
    sys.exit(1)

print('=== 2. 等待 GitHub 释放对象 ===')
if OLD:
    for i in range(6):
        time.sleep(3)
        st, _ = api('GET', f'/repos/{OWNER}/{NAME}/commits/{OLD}')
        if st == 404:
            print(f'  旧提交已不可达（第 {i+1} 次检查）')
            break
        print(f'  仍在（第 {i+1} 次）…')

print('=== 3. 重建同名私有仓库 ===')
st, data = api('POST', '/user/repos', {
    'name': NAME, 'private': True, 'description': DESC, 'auto_init': False})
if st not in (200, 201):
    print(f'  重建失败 HTTP {st}: {data}')
    sys.exit(1)
print(f'  已重建：{data.get("html_url")}  private={data.get("private")}')

print('=== 4. 推送干净历史 ===')
for b in ['main', 'feature/glass-poster-ui']:
    r = git('push', '-u', 'origin', b)
    print(f'  {b:28} {"OK" if r.returncode == 0 else "FAIL"}')
    if r.returncode != 0:
        print('    ' + (r.stderr or r.stdout).strip()[:400])

print('=== 5. 核验 ===')
if OLD:
    st, _ = api('GET', f'/repos/{OWNER}/{NAME}/commits/{OLD}')
    print(f'  旧提交 {OLD[:10]}：HTTP {st} '
          + ('[OK] 已取不到' if st == 404 else '[!] 仍可访问'))
st, d = api('GET', f'/repos/{OWNER}/{NAME}/contents/_verify_ai_e2e.py?ref=feature/glass-poster-ui')
if st == 200:
    import base64
    c = base64.b64decode(json.loads(d)['content']).decode('utf-8', errors='replace')
    if SECRET:
        print(f'  远端文件含密钥：{SECRET in c}  '
              + ('[OK]' if SECRET not in c else '[!]'))
if SECRET:
    st, d = api('GET', f'/search/code?q={SECRET}+repo:{OWNER}/{NAME}')
    if st == 200:
        print(f"  code search 命中 {json.loads(d).get('total_count', 0)} 处")
st, d = api('GET', f'/repos/{OWNER}/{NAME}')
print(f"  private={d.get('private')}  visibility={d.get('visibility')}  url={d.get('html_url')}")
