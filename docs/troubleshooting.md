# Troubleshooting

## VS Code 提示安装损坏

现象：

```text
Your Code installation appears to be corrupt. Please reinstall.
```

原因通常不是 VS Code 真坏了，而是修改了 `workbench.desktop.main.css` 后，没有同步更新 `product.json` 中记录的 SHA256 校验和。

本项目的 `Install-VSCodeBeautyOneClick.ps1` 在修补 CSS 后会重新计算 hash 并写回 `product.json`，所以不会留下这个提示。如果你手动改了 CSS，请重新运行脚本，或恢复原始 CSS。

## Remote-SSH 报 JSON.parse 错误

现象：

```text
Could not establish connection to "...": Unexpected token '﻿', "﻿{
    "n"... is not valid JSON
```

这通常不是远端 SSH 主机的问题。已确认的一种原因是本机 VS Code 安装目录里的 `resources\app\product.json` 被保存成了 UTF-8 with BOM。Remote-SSH 会直接 `JSON.parse` 这个文件，遇到文件头的 BOM 就会在真正连接远端前失败。

本项目脚本已改为 UTF-8 without BOM 写入 `product.json`、`settings.json` 和 workbench CSS。旧版本脚本造成的问题可以这样修：

```powershell
$product = Get-ChildItem "$env:LOCALAPPDATA\Programs\Microsoft VS Code" -Recurse -Filter product.json -File | Select-Object -First 1
$bytes = [IO.File]::ReadAllBytes($product.FullName)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Copy-Item -LiteralPath $product.FullName -Destination "$($product.FullName).bak-remove-bom"
    [IO.File]::WriteAllBytes($product.FullName, $bytes[3..($bytes.Length - 1)])
}
```

处理后 reload VS Code window，或完全关闭 VS Code 再打开。

## 字体仍然不对

先确认三件事：

```powershell
# 当前用户字体文件是否存在
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" -Include *.ttf,*.ttc,*.otf -Recurse

# HKCU Fonts 是否注册
Get-ItemProperty "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

# VS Code settings.json 中 editor.fontFamily 是否正确
Get-Content "$env:APPDATA\Code\User\settings.json"
```

如果刚安装完字体，已经打开的应用可能不会立刻刷新。脚本会广播 `WM_FONTCHANGE`，但少数应用仍可能需要重新打开。

## Todo Tree 找不到 ripgrep

部分 VS Code 版本或插件组合下，Todo Tree 无法自动定位 VS Code 自带的 `rg.exe`。脚本会在 VS Code 安装目录下查找 `@vscode\ripgrep-*`，并把结果写入：

```json
{
  "todo-tree.ripgrep": "..."
}
```

如果 VS Code 更新后路径变了，重新运行脚本即可。

## VS Code 更新后样式消失

VS Code 更新会替换安装目录中的 workbench CSS，这是正常现象。更新后重新运行：

```powershell
.\scripts\Install-VSCodeBeautyOneClick.ps1 -PayloadPath . -SkipVSCodeInstall
```

## 私人 Profile 不要提交到 Git

VS Code 用户数据可能包含登录状态、扩展缓存、机器路径、历史记录等私人内容。请把自己的 Profile 放在仓库外部，通过 `-UserDataPath` 和 `-ExtensionsPath` 传给脚本。

仓库已经包含本项目使用的公共字体和对应许可证；其它私人字体不要提交到 Git。
