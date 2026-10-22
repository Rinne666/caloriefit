# -*- coding: utf-8 -*-
"""
鸿蒙模拟器 UI 驱动：按**文本**定位并点击，替代手算坐标。

背景：这轮调试里手算点击坐标反复落空 —— 页面滚动位置随布局变化，
凭截图估的坐标点不中，排查一度被带偏。
`uitest dumpLayout` 给出的 bounds 才是准的，所以这里直接从树里找目标文本。

用法：
    python -u ui_drive.py tap "假期模式"
    python -u ui_drive.py shot <输出名>
    python -u ui_drive.py probe "假期模式"     # 只打印 bounds，不点
"""
import json
import os
import re
import subprocess
import sys
import time

from harmony_paths import hdc_path, repo_path, shots_dir

# Windows 控制台默认 GBK，遇到 ‹ ✓ 等字符会直接抛 UnicodeEncodeError 把排查打断。
# 改成容错输出：坏字符替换掉，信息照常可见。
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

HDC = hdc_path()
DEV = "/data/local/tmp"
SHOTS = shots_dir()
# UI 树的本地落盘位置。原先 recv 写到 tools/ 而 open 读的是写死的
# C:\Users\18165\Desktop\calories\_tools\，两边对不上，跨平台必挂。
TREE = repo_path('tools', '_t.json')


def sh(*args, timeout=120):
    return subprocess.run([HDC] + list(args), capture_output=True, text=True, timeout=timeout)


def dump(retries=3):
    """拉回 UI 树并解析成扁平节点列表。

    dumpLayout 偶发写出空文件（系统侧 SCBScreen 报
    "Cannot read property length of undefined"），所以必须重试，
    否则会把一次偶发失败误判成「目标不存在」。
    """
    last = None
    for attempt in range(retries):
        sh("shell", "uitest", "dumpLayout", "-p", f"{DEV}/t.json")
        sh("file", "recv", f"{DEV}/t.json", TREE)
        try:
            with open(TREE, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:      # 空文件 / 半截文件都走这里
            last = e
            time.sleep(1.2)
            continue
        out = []

        def walk(n):
            if not isinstance(n, dict):
                return
            a = n.get("attributes") or {}
            if a.get("text"):
                out.append({"text": a["text"], "type": a.get("type", ""), "bounds": a.get("bounds", "")})
            for c in (n.get("children") or []):
                walk(c)

        walk(data)
        return out
    raise RuntimeError(f"dumpLayout failed after {retries} tries: {last}")


def center(bounds):
    n = [int(x) for x in re.findall(r"\d+", bounds or "")]
    if len(n) < 4:
        return None
    return ((n[0] + n[2]) // 2, (n[1] + n[3]) // 2)


def find(nodes, keyword):
    """精确匹配优先，其次包含匹配"""
    exact = [n for n in nodes if n["text"] == keyword]
    if exact:
        return exact[0]
    for n in nodes:
        if keyword in n["text"]:
            return n
    return None


def relaunch(bundle, ability, marker, tries=6):
    """冷启动并**确认真的在前台**再返回。

    为什么必须确认：`aa start` 对已在运行的实例不保证把界面推到前台，
    截图会拍到桌面，看起来像「app 崩了 / 白屏」。
    这轮排查中被这个现象误导过好几次 —— 判据只能是 marker 文本真的在树上。
    """
    sh("shell", "aa", "force-stop", bundle)
    sh("shell", "aa", "start", "-b", bundle, "-a", ability)
    for _ in range(tries):
        time.sleep(2.5)
        try:
            nodes = dump(retries=2)
        except Exception:
            continue
        if find(nodes, marker):
            print(f"foreground confirmed (marker={marker})")
            return True
        sh("shell", "aa", "start", "-b", bundle, "-a", ability)
    print(f"NOT foreground after {tries} tries")
    return False


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    cmd = sys.argv[1]

    if cmd == "launch":
        ok = relaunch("com.rinne.caloriefit", "EntryAbility", sys.argv[2])
        return 0 if ok else 2

    if cmd == "shot":
        name = sys.argv[2]
        sh("shell", "snapshot_display", "-f", f"{DEV}/s.jpeg")
        sh("file", "recv", f"{DEV}/s.jpeg", os.path.join(SHOTS, f"{name}.jpeg"))
        print(f"saved {name}.jpeg")
        return 0

    if cmd in ("tap", "probe"):
        kw = sys.argv[2]
        nodes = dump()
        hit = find(nodes, kw)
        if not hit:
            print(f"NOT FOUND: {kw}")
            print("visible texts:")
            for n in nodes[:60]:
                print("  ", n["text"][:40], "|", n["bounds"])
            return 2
        c = center(hit["bounds"])
        print(f"{kw} -> type={hit['type']} bounds={hit['bounds']} center={c}")
        if cmd == "probe":
            return 0
        if c is None:
            print("cannot parse bounds")
            return 2
        sh("shell", "uitest", "uiInput", "click", str(c[0]), str(c[1]))
        time.sleep(2.5)
        print("clicked")
        return 0

    print("unknown cmd")
    return 1


if __name__ == "__main__":
    sys.exit(main())
