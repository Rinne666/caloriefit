# -*- coding: utf-8 -*-
"""探测本机已存的 GitHub / Gitee 凭据是否可用（不打印任何密钥）。

只做只读调用：
  GitHub: GET  https://api.github.com/user
  Gitee:  GET  https://gitee.com/api/v5/user
输出：平台、登录名、可用性、以及 token 具备的 scope（若能取到）。
"""
import json
import os
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')


def load_creds():
    out = []
    if not os.path.exists(CRED):
        return out
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line or '@' not in line:
                continue
            try:
                head, tail = line.split('@', 1)
                scheme_user = head.split('://', 1)[-1]
                user, token = scheme_user.split(':', 1)
                host = tail.split('/')[0]
                out.append((host, user, token))
            except ValueError:
                continue
    return out


def get_json(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.status, json.loads(r.read().decode('utf-8'))


for host, user, token in load_creds():
    if host == 'github.com':
        try:
            st, data = get_json('https://api.github.com/user', {
                'Authorization': f'Bearer {token}',
                'User-Agent': 'caloriefit-setup',
                'Accept': 'application/vnd.github+json',
            })
            scopes = data.get('_scopes', '')
            print(f'GitHub  OK   登录={data.get("login")}  账号类型={data.get("type")}  '
                  f'公开仓库数={data.get("public_repos")}  私有仓库数={data.get("total_private_repos")}')
            if scopes:
                print(f'        token scope: {scopes}')
        except urllib.error.HTTPError as e:
            print(f'GitHub  FAIL HTTP {e.code} {e.reason}')
        except Exception as e:
            print(f'GitHub  FAIL {type(e).__name__}: {e}')
    elif host == 'gitee.com':
        try:
            st, data = get_json('https://gitee.com/api/v5/user', {'User-Agent': 'caloriefit-setup'})
            print(f'Gitee   OK   登录={data.get("login")}  用户名={data.get("name")}')
        except urllib.error.HTTPError as e:
            print(f'Gitee   FAIL HTTP {e.code} {e.reason}')
        except Exception as e:
            print(f'Gitee   FAIL {type(e).__name__}: {e}')
