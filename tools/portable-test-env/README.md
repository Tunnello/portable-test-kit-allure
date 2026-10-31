# 便携式 pytest 与 Allure 报告

此目录构建一个 Windows x64 便携测试包，包含 WinPython、锁定的 pytest 依赖、Allure CLI 2.46.1 和 Eclipse Temurin JRE 21.0.12.1+1。目标设备不需要预装 Python、Java 或 uv。ping 用例需要出站 ICMP；报告生成不需要联网。

示例用例位于 `tests\test_public_examples.py`：ping 百度、ping Google（3 秒超时）和列出 `C:\` 根目录。示例不修改文件或系统配置。

## 构建交付包

在可联网的 Windows x64 构建机上，从本目录运行：

```powershell
.\build.ps1
```

构建脚本下载清单中固定的 Python、Allure CLI 和 Temurin JRE 归档，逐一校验 SHA-256；锁定的 pytest wheels 下载后离线安装到包内。交付目录生成于仓库根目录 `dist\portable-test-kit-allure`。如果该目录已经存在，构建默认拒绝覆盖；确认可替换时显式传 `-Force`。

也可以传入已下载的归档和 wheelhouse，避免重新联网下载：

```powershell
.\build.ps1 `
  -RuntimeArchivePath "C:\cache\WinPython64-3.13.18.0dot.zip" `
  -WheelhousePath "C:\cache\pytest-wheels" `
  -AllureArchivePath "C:\cache\allure-2.46.1.zip" `
  -JavaRuntimeArchivePath "C:\cache\OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip"
```

`-ValidateOnly` 检查构建元数据和传入归档的 SHA-256，不下载或写入交付目录：

```powershell
.\build.ps1 -ValidateOnly
```

## 在目标设备运行

目标设备需要 Windows x64、`ping.exe` 和可读的 `C:\` 根目录。将交付目录复制到当前用户可写位置，打开 PowerShell 或命令提示符后运行：

```powershell
.\run-tests.cmd
```

ping 用例需要出站 ICMP。Google 在部分网络中会被拦截，此时该用例失败并保留 ping 输出，不影响 C 盘用例。示例不需要管理员权限。

每次运行会清理上次运行的托管结果，然后执行 pytest 并写入 `allure-results`。Allure 报告生成在 `allure-report`；pytest 即使有失败用例，也会尝试生成并打开报告。pytest 输出和 Allure 生成/启动日志分别保存在 `logs\pytest.log`、`logs\allure-generate.log`、`logs\allure-open.log`。启动器返回 pytest 退出码；若报告生成或启动失败且 pytest 本身成功，则返回非零退出码。

Allure CLI 会自动打开系统默认浏览器，并仅在 `127.0.0.1` 上启动临时报告服务；它不会监听外部网络接口。查看报告期间不要关闭终端，按 `Ctrl+C` 停止服务。下一次运行会清理并重新生成报告。目标设备需要系统默认浏览器；这属于外部前置条件，不随包分发。目标设备不需要安装 Java 或 Python。

## 编写与选择测试用例

新增测试用例请在源码目录 `tools\portable-test-env\tests\` 下创建或修改 `test_*.py` 文件。测试函数名以 `test_` 开头；多个测试共用的 fixture、命令行选项和测试配置放在 `tests\conftest.py`。源码修改后重新构建交付包，目标设备上的包才会包含更新后的用例。

默认运行范围由源码 `tools\portable-test-env\run_tests.py` 中 pytest 命令的 `"tests"` 参数决定。通常不需要修改它；`run-tests.cmd` 会把后续参数原样传给 pytest，可用 pytest 标准筛选语法：

```powershell
# 按测试名称或表达式筛选
.\run-tests.cmd -k "ping_baidu"

# 按已标记的测试筛选；测试需使用 @pytest.mark.smoke 标记
.\run-tests.cmd -m "smoke"
```

`-k` 和 `-m` 的表达式语法与 pytest 一致。当前示例测试没有自定义 marker；使用自定义 marker 时应在 pytest 配置中注册，以避免未知 marker 警告。若要把默认运行范围固定为某个文件或测试函数，则修改 `run_tests.py` 中的 `"tests"` 参数，例如改为 `"tests\test_public_examples.py"`，再重新构建交付包。

## 验证交付包

在交付目录运行静态和运行时校验：

```powershell
.\validate-bundle.ps1
```

验收脚本会检查必要文件、清单哈希以及包内 Python、pytest、Allure CLI 和 Java 版本，并收集测试；不会修改系统环境变量、注册表、安装服务或访问网络。

## 第三方组件

组件版本、下载地址、归档 SHA-256 和许可证信息以 `bundle-manifest.json` 与 `THIRD_PARTY_NOTICES.md` 为准。构建过程只接受匹配固定哈希的归档。
