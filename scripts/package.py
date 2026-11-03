"""Portable UTF-8 ZIPs; never include the developer's local progress/logs."""
from pathlib import Path
import hashlib
import shutil
import sys
import zipfile
import plistlib

root = Path(__file__).resolve().parent.parent
platform = sys.argv[1]
version = plistlib.loads((root / "macos/Info.plist").read_bytes())["CFBundleShortVersionString"]
dist = root / "dist"
stage = dist / ("QiaoQiao-macOS" if platform == "macos" else "QiaoQiao-Windows-x64")
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir(parents=True)
if platform == "macos":
    shutil.copytree(dist / "敲敲.app", stage / "敲敲.app", symlinks=True)
    instructions = f"敲敲 {version} · macOS 13+ · Apple Silicon / Intel\n\n把敲敲.app 拖进应用程序文件夹后打开。\n首次打开按系统提示在隐私与安全性中允许打开，再授予输入监控权限。\n右键头像打开菜单，可缩放、换装、定时提醒和设置休息间隔。\n小计时器里可设下班时间、自由倒计时或番茄钟；点击头像下的时间可打开计时面板。\n这是尚未公证的个人分享版本。没有申请 Apple Developer ID。\n更新后若不计数，请在系统设置→隐私与安全性→输入监控中重新添加应用程序里的敲敲。\n"
else:
    shutil.copytree(dist / "windows", stage, dirs_exist_ok=True)
    instructions = f"敲敲 {version} · Windows 10/11 x64 · 预览版\n\n请完整解压整个文件夹，再运行 QiaoQiao.exe。\n已经包含 .NET 运行时，不需要另外安装。\n右键头像或系统托盘图标打开菜单，小计时器里可设下班、自由倒计时和番茄钟。\n数字是当天按键＋鼠标点击次数，/min 是最近60秒。移动、滚动只算活跃。\n100次解锁一套装扮。进度保存在 %LOCALAPPDATA%\\QiaoQiao\\state.json。\n这是未进行代码签名的个人分享版本。\n程序不需要管理员权限，不记录文字内容，不联网上传。\nWindows 版经过自动构建和启动/渲染检查，尚未完成实体 Windows 电脑人工体验验收。\n"
(stage / "开始使用.txt").write_text(instructions, encoding="utf-8-sig")
shutil.copy2(root / "NOTICE.md", stage / "NOTICE.md")
shutil.copy2(root / "LICENSE", stage / "LICENSE")
shutil.copy2(root / "macos/MG-STYLES-15-LICENSE.txt", stage / "MG-STYLES-15-LICENSE.txt")
if platform == "windows":
    shutil.copytree(root / "third-party", stage / "third-party", dirs_exist_ok=True)
target = dist / (stage.name + f"-{version}.zip")
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in sorted(stage.rglob("*")):
        if p.is_file() and p.name != ".DS_Store":
            z.write(p, p.relative_to(dist))
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    assert not any("state.json" in n or "report.json" in n for n in z.namelist())
checksum = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix(".zip.sha256").write_text(checksum + "  " + target.name + "\n", encoding="ascii")
print(f"{target.name}: {target.stat().st_size / 1048576:.1f} MiB, SHA256 {checksum}")
