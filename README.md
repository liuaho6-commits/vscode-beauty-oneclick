# VS Code Beauty One-Click

Windows 上的一键 VS Code 美化迁移脚本。脚本会安装 VS Code、安装仓库内置字体、恢复你指定的 VS Code 用户配置和插件、修补 workbench CSS，并同步更新 VS Code 校验和，避免出现 `Your Code installation appears to be corrupt. Please reinstall.`。

这个仓库的定位是“脚本 + 教程 + 公共字体”，不是私人配置仓库。你的 VS Code 用户数据和插件目录应放在移动硬盘、网盘同步目录或任意外部目录中，通过参数传给脚本，不需要复制到仓库里。

## 包含字体

仓库内置当前美化方案需要的字体：

- JetBrains Mono
- Inter
- HarmonyOS Sans SC

字体文件位于 `fonts/`。许可证文本位于 `fonts/licenses/`。

重要许可说明：

- JetBrains Mono 使用 SIL Open Font License 1.1。
- Inter 使用 SIL Open Font License 1.1。
- HarmonyOS Sans Fonts 使用 HarmonyOS Sans Fonts License Agreement。本项目使用并分发未修改的 HarmonyOS Sans Fonts，并保留其许可证文本。

## 适用环境

- Windows 10/11
- VS Code User Installer，也就是默认安装到 `%LOCALAPPDATA%\Programs\Microsoft VS Code`
- 需要迁移 VS Code 设置、主题、插件、字体和 workbench CSS 美化

## 仓库结构

```text
vscode-beauty-oneclick/
  fonts/
    *.ttf
    *.ttc
    licenses/
  scripts/
    Install-VSCodeBeautyOneClick.ps1
    Run-OneClick-Beauty.cmd
    Reset-VSCodeBeautyLab.ps1
    Install-FreshVSCodeForLab.ps1
  docs/
    font-installation.md
    troubleshooting.md
```

## 推荐用法：自动识别外部 Profile

假设你把源机器的 VS Code 数据放在移动硬盘：

```text
E:\VSCodeBeautyProfile\
  user-data\       # 来自源机器 %APPDATA%\Code
  extensions\      # 来自源机器 %USERPROFILE%\.vscode\extensions
```

如果仓库和 Profile 是同级目录：

```text
E:\
  vscode-beauty-oneclick\
  VSCodeBeautyProfile\
    user-data\
    extensions\
```

在仓库目录直接运行即可，脚本会自动识别：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1
```

脚本会自动使用仓库里的 `fonts/`，所以不需要把字体再塞进 Profile。

自动识别会检查这些明确结构：

- 仓库同级的 `VSCodeBeautyProfile\user-data` 和 `VSCodeBeautyProfile\extensions`
- 仓库同级的 `profile\user-data` 和 `profile\extensions`
- 仓库同级的 `VSCodeBeautySource\user-data` 和 `VSCodeBeautySource\extensions`
- 仓库根目录下的 `user-data` 和 `extensions`
- 当前执行目录下的 `user-data` 和 `extensions`

如果找到多个候选，脚本会提示你显式传参，而不是猜一个。

也可以手动指定路径：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1 `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions"
```

如果你有额外字体目录：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1 `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions" `
  -FontsPath "E:\MyFonts"
```

## 只安装公共美化基础

没有外部 Profile 时也能运行。它会安装 VS Code、安装仓库字体、修补 workbench CSS、创建快捷方式，并跳过用户配置和插件恢复：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1
```

双击也可以：

```bat
scripts\Run-OneClick-Beauty.cmd
```

## 兼容旧 payload 格式

旧格式仍然支持，但不再推荐把它放进仓库目录：

```text
D:\VSCodeBeautySource\
  user-data\
  extensions\
  fonts\
```

运行：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath "D:\VSCodeBeautySource"
```

如果 `D:\VSCodeBeautySource\fonts` 存在，优先使用它；否则使用仓库内置 `fonts/`。

## 常用参数

```powershell
# 先备份并清理旧的 VS Code 用户数据、插件和 VS Code 安装，再安装和恢复
.\scripts\Install-VSCodeBeautyOneClick.ps1 -CleanFirst `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions"

# 已经安装好 VS Code，只恢复配置、插件、字体和 CSS
.\scripts\Install-VSCodeBeautyOneClick.ps1 -SkipVSCodeInstall `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions"

# 只恢复配置和插件，不安装字体
.\scripts\Install-VSCodeBeautyOneClick.ps1 -SkipFonts `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions"

# 不修补 workbench CSS
.\scripts\Install-VSCodeBeautyOneClick.ps1 -SkipWorkbenchCss
```

## 本机实验流程

如果你想模拟一台“新电脑”，可以按这个顺序测试：

```powershell
# 谨慎：会卸载 VS Code、清理当前用户 VS Code 配置和插件，并卸载仓库 fonts/ 中匹配的字体
.\scripts\Reset-VSCodeBeautyLab.ps1

# 重新安装最新版 VS Code User Installer
.\scripts\Install-FreshVSCodeForLab.ps1

# 跑一键美化
.\scripts\Install-VSCodeBeautyOneClick.ps1 `
  -UserDataPath "E:\VSCodeBeautyProfile\user-data" `
  -ExtensionsPath "E:\VSCodeBeautyProfile\extensions"
```

`Reset-VSCodeBeautyLab.ps1` 默认只处理当前用户可控范围。它不会自动去改 `C:\Windows\Fonts` 或 HKLM 字体注册表；如果要清理全局字体，请先确认风险再手动处理。

## 脚本做了什么

- 检测并安装 VS Code User Installer
- 备份或清理旧的 `%APPDATA%\Code`
- 恢复指定的 VS Code 用户数据
- 恢复指定的 `%USERPROFILE%\.vscode\extensions`
- 将字体安装到当前用户字体目录 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
- 写入 HKCU 字体注册表，并广播 `WM_FONTCHANGE`
- 修补 VS Code `workbench.desktop.main.css`
- 重新计算并写回 `product.json` 中对应 CSS 的 SHA256 校验和
- 自动配置 Todo Tree 的 `todo-tree.ripgrep`

## 重要说明

VS Code 更新后可能会覆盖 workbench CSS，更新完重新运行一键脚本即可。

字体安装采用“当前用户安装”方案，不默认写入 `C:\Windows\Fonts` 或 HKLM。这样更适合迁移和回滚，也不容易影响系统其它用户。

更多细节见：

- [docs/font-installation.md](docs/font-installation.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
