# Windows 字体命令行安装与卸载

本项目采用“当前用户字体安装”方案。默认字体来源是仓库的 `fonts/`，也可以通过 `-FontsPath` 指向其它字体目录。

- 字体文件复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
- 注册表写入 `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`
- 调用 GDI 的 `AddFontResourceW`
- 通过 `WM_FONTCHANGE` 通知正在运行的应用刷新字体列表

这样更接近 Windows 右键“安装”的用户级效果，也更容易撤销。脚本刻意不默认写入 `C:\Windows\Fonts` 或 HKLM，避免影响系统字体和其它用户。

## 安装

核心流程在 `Install-VSCodeBeautyOneClick.ps1` 中：

1. 枚举字体来源目录下的 `.ttf`、`.ttc`、`.otf`
2. 复制到当前用户字体目录
3. 读取字体 Family 名称
4. 写入 HKCU Fonts 注册表项
5. 调用 `AddFontResourceW`
6. 广播 `WM_FONTCHANGE`

## 卸载

实验重置脚本 `Reset-VSCodeBeautyLab.ps1` 会根据仓库 `fonts/` 或 `-FontsPath` 中的文件名反向处理：

1. 删除 HKCU Fonts 中匹配的注册表项
2. 调用 `RemoveFontResourceW`
3. 删除 `%LOCALAPPDATA%\Microsoft\Windows\Fonts` 中匹配的字体文件
4. 广播 `WM_FONTCHANGE`

如果字体曾经通过“为所有用户安装”进入 `C:\Windows\Fonts`，当前用户权限通常不能可靠删除。建议使用 Windows 设置或手动交互方式处理。

## 官方依据

- [Font Installation and Deletion](https://learn.microsoft.com/en-us/windows/win32/gdi/font-installation-and-deletion)
- [AddFontResourceW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-addfontresourcew)
- [RemoveFontResourceW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-removefontresourcew)
- [WM_FONTCHANGE](https://learn.microsoft.com/en-us/windows/win32/gdi/wm-fontchange)
