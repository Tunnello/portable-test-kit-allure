# 便携式 pytest 测试环境

此目录是一个 Windows x64 便携测试包，包内含 WinPython 运行时和锁定的 pytest 依赖；目标设备不需要预装 Python 或 uv。本包只包含 Python 和 pytest，不包含 Allure 报告组件。

示例用例位于 `tests\test_public_examples.py`：ping 百度、ping Google（3 秒超时）和列出 `C:\` 根目录。示例不修改文件或系统配置。

## 构建交付包

在可联网的 Windows x64 构建机上，从本目录运行：

```powershell
.\build.ps1
```

构建脚本下载清单中固定的便携 Python 归档，校验 SHA-256，再下载锁定的 pytest wheels 并离线安装到包内。交付目录生成于仓库根目录 `dist\portable-test-kit`。如果该目录已经存在，构建默认拒绝覆盖；确认可替换时显式传 `-Force`。

也可以复用已经下载好的 Python 归档和 wheelhouse，避免重新联网下载：

```powershell
.\build.ps1 `
  -RuntimeArchivePath "C:\cache\WinPython64-3.13.18.0dot.zip" `
  -WheelhousePath "C:\cache\pytest-wheels"
```

`-ValidateOnly` 只检查构建输入，不下载或写入交付目录：

```powershell
.\build.ps1 -ValidateOnly
```

## 在目标设备运行

目标设备需要 Windows x64、`ping.exe` 和可读的 `C:\` 根目录。将交付目录复制到当前用户可写位置，打开 PowerShell 或命令提示符后运行：

```powershell
.\run-tests.cmd
```

ping 用例需要出站 ICMP。Google 在部分网络中会被拦截，此时该用例失败并保留 ping 输出，不影响 C 盘用例。示例不需要管理员权限。

pytest 输出保存在包内 `logs\pytest.log`，启动器同时将日志显示在终端并返回 pytest 退出码。

## 编写与选择测试用例

在源码目录 `tools\portable-test-env\tests\` 下创建或修改 `test_*.py` 文件。测试函数名以 `test_` 开头；多个测试共用的 fixture 和测试配置放在 `tests\conftest.py`。源码修改后重新构建交付包，目标设备上的包才会包含更新后的用例。

`run-tests.cmd` 会把后续参数原样传给 pytest，可用 pytest 标准筛选语法：

```powershell
.\run-tests.cmd -k "ping_baidu"
.\run-tests.cmd -m "smoke"
```

当前示例测试没有自定义 marker；使用自定义 marker 时应在 pytest 配置中注册，以避免未知 marker 警告。

## 验证交付包

在交付目录运行静态和运行时校验：

```powershell
.\validate-bundle.ps1
```

验收脚本会检查必要文件、清单哈希、包内 Python 和 pytest 版本，并收集测试；不会修改系统环境变量、注册表、安装服务或访问网络。
