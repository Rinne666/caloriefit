# -*- coding: utf-8 -*-
"""Emulator-only checks for AI credential persistence, upload confirmation, and deletion."""
import json
import os
import re
import subprocess
import time

from harmony_paths import hdc_path, repo_path, shots_dir

HDC = hdc_path()
BUNDLE = "com.rinne.caloriefit"
ABILITY = "EntryAbility"
TREE_REMOTE = "/data/local/tmp/privacy_runtime_layout.json"
TREE_LOCAL = repo_path('tools', '_privacy_runtime_layout.json')


def sh(*args, timeout=120):
    return subprocess.run([HDC, *args], capture_output=True, text=True, timeout=timeout)


def dump_root():
    sh("shell", "uitest", "dumpLayout", "-p", TREE_REMOTE)
    sh("file", "recv", TREE_REMOTE, TREE_LOCAL)
    with open(TREE_LOCAL, "r", encoding="utf-8") as f:
        return json.load(f)


def walk(root):
    result = []

    def visit(node):
        if not isinstance(node, dict):
            return
        attrs = node.get("attributes") or {}
        result.append(attrs)
        for child in node.get("children") or []:
            visit(child)

    visit(root)
    return result


def texts(attrs):
    return [str(a.get("text", "")) for a in attrs if a.get("text")]


def center(bounds):
    nums = [int(v) for v in re.findall(r"\d+", bounds or "")]
    return ((nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2) if len(nums) >= 4 else None


def tap(label, settle=2.0):
    attrs = walk(dump_root())
    hit = next((a for a in attrs if a.get("text") == label), None)
    if hit is None:
        hit = next((a for a in attrs if label in str(a.get("text", ""))), None)
    if hit is None:
        print(f"    missing UI text: {label}")
        return False
    point = center(hit.get("bounds", ""))
    if point is None:
        print(f"    no bounds for UI text: {label}")
        return False
    sh("shell", "uitest", "uiInput", "click", str(point[0]), str(point[1]))
    time.sleep(settle)
    return True


def back(settle=1.5):
    sh("shell", "uitest", "uiInput", "keyEvent", "Back")
    time.sleep(settle)


def scroll_top(times=8):
    for _ in range(times):
        sh("shell", "uitest", "uiInput", "swipe", "640", "900", "640", "2100", "250")
        time.sleep(0.35)
    time.sleep(0.8)


def find_and_tap(label, max_scroll=20, settle=2.2):
    for _ in range(max_scroll):
        attrs = walk(dump_root())
        hit = next((a for a in attrs if a.get("text") == label), None)
        if hit is None:
            hit = next((a for a in attrs if label in str(a.get("text", ""))), None)
        if hit is not None:
            point = center(hit.get("bounds", ""))
            # dumpLayout can include Scroll children outside the viewport.
            # Do not report a tap when the text exists only off-screen.
            if point is not None and 0 <= point[0] < 1280 and 0 <= point[1] < 2832:
                sh("shell", "uitest", "uiInput", "click", str(point[0]), str(point[1]))
                time.sleep(settle)
                return True
        sh("shell", "uitest", "uiInput", "swipe", "640", "2000", "640", "900", "300")
        time.sleep(0.5)
    return False


def has(attrs, label):
    return any(label == str(a.get("text", "")) or label in str(a.get("text", "")) for a in attrs)


def toggles():
    return [a for a in walk(dump_root()) if a.get("type") == "Toggle"]


def set_toggle(index, value):
    items = toggles()
    if index >= len(items):
        return False
    checked = str(items[index].get("checked", "false")).lower() == "true"
    if checked == value:
        return True
    point = center(items[index].get("bounds", ""))
    if point is None:
        return False
    sh("shell", "uitest", "uiInput", "click", str(point[0]), str(point[1]))
    time.sleep(1)
    items = toggles()
    return index < len(items) and str(items[index].get("checked", "false")).lower() == str(value).lower()


def navigate_to_ai_settings():
    attrs = walk(dump_root())
    if has(attrs, "模型名称"):
        return True
    labels = texts(attrs)
    if "饮食记录" in labels:
        back()
        attrs = walk(dump_root())
        labels = texts(attrs)
    if "我的" not in labels or not tap("我的", settle=2.5):
        return False
    scroll_top()
    if not find_and_tap("AI 食物识别设置", max_scroll=20, settle=2.5):
        return False
    attrs = walk(dump_root())
    return has(attrs, "模型名称") and has(attrs, "API Key") and len(toggles()) >= 2


def snapshot(name):
    remote = "/data/local/tmp/privacy_runtime.jpeg"
    local = os.path.join(shots_dir(), f"{name}.jpeg")
    sh("shell", "snapshot_display", "-f", remote)
    sh("file", "recv", remote, local)


def main():
    print("=== AI credential persistence ===")
    state = sh("list", "targets", "-v")
    if state.returncode != 0 or "Connected" not in (state.stdout or ""):
        print("HDC target is not online")
        return 2

    if not navigate_to_ai_settings():
        print("FAIL  Cannot open AI settings")
        return 3
    attrs = walk(dump_root())
    input_nodes = [a for a in attrs if a.get("type") == "TextInput"]
    if len(input_nodes) < 3:
        print(f"FAIL  Expected 3 settings fields; found {len(input_nodes)}")
        return 4
    key_point = center(input_nodes[2].get("bounds", ""))
    if key_point is None:
        print("FAIL  API Key input has no bounds")
        return 5
    sh("shell", "uitest", "uiInput", "click", str(key_point[0]), str(key_point[1]))
    time.sleep(0.5)
    # Deliberately fake credential. It is never authorized for a network request.
    sh("shell", "uitest", "uiInput", "text", "sk-local-ui-test-only")
    time.sleep(0.5)
    back(settle=1.0)
    if not set_toggle(0, True) or not set_toggle(1, False):
        print("FAIL  Could not enable secure remember and disable demo mode")
        return 6
    if not tap("保存配置", settle=2.0):
        print("FAIL  Could not save the test credential")
        return 7
    attrs = walk(dump_root())
    if not has(attrs, "已存储，输入可更换"):
        print("FAIL  Securely stored key indicator did not appear")
        return 8
    print("PASS  Fake API Key saved with system secure storage enabled")

    sh("shell", "aa", "force-stop", BUNDLE)
    launch = sh("shell", "aa", "start", "-b", BUNDLE, "-a", ABILITY)
    if launch.returncode != 0:
        print("FAIL  App did not relaunch")
        return 9
    time.sleep(6)
    if has(walk(dump_root()), "请先阅读隐私说明"):
        print("FAIL  Privacy consent did not persist across restart")
        return 10
    if not navigate_to_ai_settings():
        print("FAIL  Could not reopen AI settings after restart")
        return 11
    attrs = walk(dump_root())
    if not has(attrs, "已存储，输入可更换"):
        print("FAIL  Securely stored key was not reloaded after restart")
        return 12
    print("PASS  Stored-key indicator remains after force-stop/relaunch")

    print("=== Just-in-time AI upload confirmation ===")
    back()
    if not tap("今日", settle=2.5):
        print("FAIL  Could not return to Today tab")
        return 13
    scroll_top()
    if not tap("拍照识别食物", settle=3.0):
        print("FAIL  Could not open AI recognition")
        return 14
    if not tap("没有照片？用内置示例图试一下", settle=2.0):
        print("FAIL  Could not load built-in sample image")
        return 15
    if not tap("开始 AI 识别", settle=1.0):
        print("FAIL  Could not request recognition")
        return 16
    attrs = walk(dump_root())
    if not has(attrs, "确认发送食物照片") or not has(attrs, "同意并识别") or \
       not has(attrs, "https://dashscope.aliyuncs.com/compatible-mode/v1"):
        print("FAIL  Live AI upload confirmation is missing required disclosure")
        return 17
    snapshot("v_09_upload_consent")
    if not tap("取消", settle=1.5):
        print("FAIL  Could not cancel the upload confirmation")
        return 18
    attrs = walk(dump_root())
    if has(attrs, "确认发送食物照片") or has(attrs, "识别结果"):
        print("FAIL  Cancel did not leave the request unsubmitted")
        return 19
    print("PASS  Upload disclosure shown; cancellation returned without an AI result")

    print("=== Delete data and revoke consent ===")
    back()
    if not tap("我的", settle=2.5):
        print("FAIL  Could not return to profile tab")
        return 20
    scroll_top()
    if not find_and_tap("删除数据并撤回同意", max_scroll=20, settle=1.0):
        print("FAIL  Could not open local data deletion")
        return 21
    attrs = walk(dump_root())
    if not has(attrs, "删除健康数据和 AI 配置"):
        print("FAIL  Deletion confirmation dialog did not appear")
        return 22
    if not tap("删除", settle=6.0):
        print("FAIL  Could not confirm deletion")
        return 23
    attrs = walk(dump_root())
    if not has(attrs, "请先阅读隐私说明"):
        print("FAIL  Consent was not revoked after deletion")
        return 24
    if has(attrs, "AI 识别设置") or has(attrs, "已存储，输入可更换"):
        print("FAIL  App did not leave the personal-data area after deletion")
        return 25
    snapshot("v_10_data_deleted_revoked")
    print("PASS  App returned to first-run consent after the delete/revoke action")
    print("PASS  Test session complete; no AI request was submitted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
