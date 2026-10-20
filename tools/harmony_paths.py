# -*- coding: utf-8 -*-
"""
跨平台路径解析：Windows 与 macOS 都能用。

原脚本把 `C:\\Program Files\\Huawei\\DevEco Studio\\...` 和
`C:\\Users\\18165\\Desktop\\calories\\...` 写死，迁到 Mac 立刻失效。
现在改成：
  · 仓库内路径一律从本文件位置反推（`__file__` → 仓库根），跟着仓库走；
  · DevEco SDK 位置按平台探测，也可用环境变量 DEVECO_SDK_HOME 覆盖。

环境变量（可选）：
  DEVECO_SDK_HOME   覆盖 SDK 根目录
  HARMONY_HDC       覆盖 hdc 可执行文件路径
"""
import os
import shutil
import sys

# tools/ 的上一级就是仓库根
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS_DIR = os.path.join(REPO_ROOT, 'tools')

IS_MAC = sys.platform.startswith('darwin')
IS_WIN = os.name == 'nt'


def dev_eco_sdk_home() -> str:
    """返回 HarmonyOS SDK 根目录（含 default/ 的那一层）。"""
    env = os.environ.get('DEVECO_SDK_HOME')
    if env and os.path.isdir(env):
        return env
    candidates = []
    if IS_MAC:
        candidates += [
            '/Applications/DevEco-Studio.app/Contents/sdk',
            os.path.expanduser('~/Applications/DevEco-Studio.app/Contents/sdk'),
        ]
    elif IS_WIN:
        for base in [r'C:\Program Files\Huawei\DevEco Studio\sdk',
                     os.path.expanduser('~\\AppData\\Local\\Huawei\\DevEco Studio\\sdk')]:
            candidates.append(base)
    for c in candidates:
        if os.path.isdir(c):
            return c
    # 兜底：交由调用方报错
    return candidates[0] if candidates else ''


def hdc_path() -> str:
    """返回 hdc 可执行文件路径。找不到就抛错，别静默返回一个错的路径。"""
    env = os.environ.get('HARMONY_HDC')
    if env and os.path.exists(env):
        return env
    name = 'hdc.exe' if IS_WIN else 'hdc'
    rel = os.path.join('default', 'openharmony', 'toolchains', name)
    for root in [dev_eco_sdk_home(),
                 os.path.join(REPO_ROOT, 'sdk')]:
        p = os.path.join(root, rel)
        if os.path.exists(p):
            return p
    found = shutil.which(name)
    if found:
        return found
    raise FileNotFoundError(
        '找不到 hdc。请设置环境变量 HARMONY_HDC 指向 hdc 可执行文件，'
        '或设置 DEVECO_SDK_HOME 指向 DevEco Studio 的 sdk 目录。')


def repo_path(*parts) -> str:
    """仓库内路径（自动创建中间目录）。"""
    p = os.path.join(REPO_ROOT, *parts)
    d = os.path.dirname(p)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    return p


def shots_dir() -> str:
    """截图目录。仓库内 tools/shots（不入库，见 .gitignore）。"""
    d = os.path.join(TOOLS_DIR, 'shots')
    if not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    return d


def entry_dir() -> str:
    """entry 模块目录。"""
    return os.path.join(REPO_ROOT, 'entry')
