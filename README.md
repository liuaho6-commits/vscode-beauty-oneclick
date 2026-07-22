# VS Code Beauty One-Click

Windows 上的一键 VS Code 美化迁移脚本。它不是把某台电脑的私密配置直接公开，而是提供一套可复用流程：你自己准备 `payload`，脚本负责安装 VS Code、恢复用户配置和插件、安装当前用户字体、修补 workbench CSS，并处理 VS Code 校验和，避免出现 `Your Code installation appears to be corrupt. Please reinstall.`。

> 本仓库不包含字体文件、VS Code 用户数据、插件缓存或任何私人 payload。请只把脚本和教程开源，自己的 `payload/` 保持本地私有。

## 适用场景

- Windows 10/11
- VS Code User Installer，也就是默认安装到 `%LOCALAPPDATA%\Programs\Microsoft VS Code`
- 想把一台电脑上的 VS Code 样式、设置、插件和字体迁移到另一台电脑
- 想在本机模拟新装 VS Code，然后完整测试一键美化流程

## 目录

```text
vscode-beauty-oneclick/
  scripts/
    Install-VSCodeBeautyOneClick.ps1
    Run-OneClick-Beauty.cmd
    Reset-VSCodeBeautyLab.ps1
    Install-FreshVSCodeForLab.ps1
  docs/
    font-installation.md
    troubleshooting.md
  payload/                 # 你自己准备，不要提交到 Git
    user-data/
    extensions/
    fonts/
```

## 准备 payload

在源机器上准备一个 `payload` 文件夹：

```text
payload/
  user-data/       # 通常来自 %APPDATA%\Code
  extensions/      # 通常来自 %USERPROFILE%\.vscode\extensions
  fonts/           # .ttf/.ttc/.otf 字体文件
```

建议至少包含：

- `payload/user-data/User/settings.json`
- `payload/user-data/User/keybindings.json`，如果你有自定义快捷键
- `payload/user-data/User/snippets`，如果你有代码片段
- `payload/extensions`，如果你希望插件版本也跟源机器一致
- `payload/fonts`，如果主题依赖 JetBrains Mono、HarmonyOS Sans SC、Inter 等字体

## 一键美化

把 `payload` 放在仓库根目录后，可以双击：

```bat
scripts\Run-OneClick-Beauty.cmd
```

也可以在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath .
```

常用参数：

```powershell
# 先备份并清理旧的 VS Code 用户数据、插件和字体，再恢复
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -CleanFirst

# 已经安装好 VS Code，只恢复美化内容
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -SkipVSCodeInstall

# 只恢复配置和插件，不安装字体
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -SkipFonts

# 不修补 workbench CSS
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -SkipWorkbenchCss
```

## 本机实验流程

如果你想模拟一台“新电脑”，可以按这个顺序测试：

```powershell
# 谨慎：会清理当前用户的 VS Code 配置、插件和 payload 中同名字体
.\scripts\Reset-VSCodeBeautyLab.ps1 -PayloadPath .\payload

# 重新安装最新版 VS Code User Installer
.\scripts\Install-FreshVSCodeForLab.ps1

# 跑一键美化
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -CleanFirst
```

`Reset-VSCodeBeautyLab.ps1` 默认只处理当前用户可控范围。它不会自动去改 `C:\Windows\Fonts` 或 HKLM 字体注册表；如果要清理全局字体，请先确认风险再手动处理。

## 脚本做了什么

- 检测并安装 VS Code User Installer
- 备份或清理旧的 `%APPDATA%\Code`
- 恢复 `payload/user-data`
- 恢复 `%USERPROFILE%\.vscode\extensions`
- 将 `payload/fonts` 安装到当前用户字体目录 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
- 写入 HKCU 字体注册表，并广播 `WM_FONTCHANGE`
- 修补 VS Code `workbench.desktop.main.css`
- 重新计算并写回 `product.json` 中对应 CSS 的 SHA256 校验和
- 自动配置 Todo Tree 的 `todo-tree.ripgrep`

## 重要说明

VS Code 更新后可能会覆盖 workbench CSS，更新完重新运行一键脚本即可。

字体不要盲目写入 `C:\Windows\Fonts` 或 HKLM。当前脚本采用“当前用户安装”方案，更适合迁移和回滚，也不容易影响系统其它用户。

更多细节见：

- [docs/font-installation.md](docs/font-installation.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
