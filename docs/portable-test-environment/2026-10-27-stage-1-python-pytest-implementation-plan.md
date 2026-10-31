# 便携式 Python 自动化测试环境 Implementation Plan

> **For agentic workers:** 按任务逐项完成并在每项结束时执行其验证。此计划实现 [2026-10-27-design.md](./2026-10-27-design.md) 的第一阶段，不提前加入 Allure/JRE。当前工作区不是 Git 仓库，不要假设可以创建提交。

**Goal:** 制作 Windows x64 可复制的最小便携测试包，在未预装 Python/uv 的设备上由包内 Python/pytest 执行 `test_public_examples.py` 中的公开示例。

**Architecture:** 在可联网的 Windows x64 构建机下载并校验固定版本的便携 Python 运行时及 pytest 依赖，组装成可复制目录。pytest 从普通 PowerShell 或命令提示符启动，直接运行 `tests/test_public_examples.py`，通过 `subprocess` 调用 `ping.exe`，并通过 `pathlib` 读取 `C:\` 根目录。

**Tech Stack:** Windows x64、PowerShell 构建脚本、便携式 Python 发行版、pytest、CMD 启动脚本。

**Spec:** [2026-10-27-design.md](./2026-10-27-design.md)

## Implementation status

The portable package has been built and validated. Tooling tests pass; the package was copied to a path on another drive containing spaces, validated and used to collect tests with system Python removed from `PATH`. The public example suite runs without administrator privileges; the Google ping case depends on outbound ICMP and may fail on restricted networks.

## Global Constraints

- 第一阶段仅支持 Windows x64。
- 目标设备不得要求预装 Python 或 uv；测试依赖必须在交付目录内。
- 示例通过 pytest 组织；网络用例调用 `ping.exe`，目录用例使用 `pathlib`。
- 目标机需提供 `ping.exe` 和可读的 `C:\` 根目录；这些外部前置条件不随包提供。
- 示例不需要管理员权限；可从普通 PowerShell 或命令提示符启动。
- 网络连通性用例需要出站 ICMP；Google 不可达时用例会失败并保留诊断。
- 示例只做网络探测和目录读取，不修改系统配置、不写入磁盘。
- 第一阶段不验收 Allure 报告生成与查看；相关能力在第二阶段处理。
- 运行时不联网安装依赖、不修改系统级 `PATH`、注册表或持久化环境变量。

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `tools\portable-test-env\requirements.in` | 列出第一阶段直接 Python 依赖，初始仅 pytest。 |
| `tools\portable-test-env\requirements.lock` | 固定 pytest 及其传递依赖版本与哈希。 |
| `tools\portable-test-env\bundle-manifest.json` | 固定便携 Python 发行版的版本、Windows x64 架构、下载来源、SHA-256 和包内路径。 |
| `tools\portable-test-env\build.ps1` | 在联网构建机下载、校验、组装便携运行时与测试文件，并生成最终交付目录。 |
| `tools\portable-test-env\run-tests.cmd` | 以相对路径运行包内 Python/pytest、转发 pytest 参数并保留退出码。 |
| `tools\portable-test-env\README.md` | 说明构建、复制、运行命令及外部前置条件。 |
| `tools\portable-test-env\tests\conftest.py` | 提供共享 pytest 配置和前置条件检查。 |
| `tools\portable-test-env\tests\test_public_examples.py` | 覆盖 ping 百度、ping Google（3 秒超时）和列出 `C:\` 根目录。 |
| `tools\portable-test-env\tests\test_build_script.py` | 验证构建器默认路径和输入缺项诊断。 |
| `tools\portable-test-env\tests\test_launcher.py` | 验证启动器在便携 Python 缺失时明确失败。 |
| `tools\portable-test-env\tests\test_validate_bundle.py` | 验证包验收器报告必需清单缺失。 |
| `dist\portable-test-kit\` | 构建生成的可复制交付目录，含 Python、pytest 依赖、测试、入口、日志和版本清单。 |

`tests\conftest.py` 和 `tests\test_public_examples.py` 已存在；执行计划要在现有实现基础上验证和打包，不重复创建相同功能。

## Task 1: 固定第一阶段 Python 依赖与便携解释器

**Files:**
- Create: `tools\portable-test-env\requirements.in`
- Create: `tools\portable-test-env\requirements.lock`
- Create: `tools\portable-test-env\bundle-manifest.json`
- Read: `tools\portable-test-env\tests\conftest.py`
- Read: `tools\portable-test-env\tests\test_public_examples.py`

- [ ] **Step 1: 确认现有示例及第一阶段依赖**

检查测试源码，确认示例覆盖 ping 百度、ping Google（3 秒超时）和列出 `C:\` 根目录；确认网络用例调用 `ping.exe`，目录用例只读取 `C:\`，均不需要管理员权限。

验证：运行 `python -m pytest tests\test_public_examples.py --collect-only -q`；应收集到三个测试。网络用例和目录用例分别运行一次，确认前置条件诊断清晰。

- [ ] **Step 2: 记录 pytest 直接依赖**

创建 `requirements.in`，初始只列入 pytest；Allure 报告生成相关依赖和 JRE 按第二阶段处理。

验证：检查解析出的依赖树只有 pytest 运行所需包，不包含 Allure 或 Java 运行时。

- [ ] **Step 3: 生成固定版本和哈希的依赖锁定文件**

使用构建端固定版本的 pip-tools 根据 `requirements.in` 生成适用于所选 Windows x64 Python ABI 的 `requirements.lock`，包含传递依赖版本与包哈希。

验证：在干净临时构建环境中按锁定文件下载 Windows x64 可用 wheel，并在无网络环境通过 `pip install --no-index --find-links <wheelhouse> --require-hashes -r requirements.lock` 安装成功。

- [ ] **Step 4: 选择并固定便携 Python 发行版**

选择可复制目录后运行、支持安装 pytest 及其 wheel 的 Windows x64 便携发行版；在 manifest 固定版本、来源 URL、SHA-256、可执行文件相对路径和 Python 版本。选择必须基于实际 smoke 测试，不接受依赖目标机 Python/uv 或系统 PATH 的发行版。

验证：核对下载归档 SHA-256；从测试目录外的路径直接启动其 Python，确认复制/移动后仍能执行 `python.exe --version` 和 `python.exe -m pytest --version`。

**Task 1 完成标准：** 第一阶段依赖锁定且可离线安装；选定的便携 Python 版本及归档校验信息已固定。  
**状态：** 已完成；Python 3.13.18 x64 归档 SHA-256 已校验，锁定的 pytest 8.3.2 及依赖通过 wheelhouse 离线安装验证。

## Task 2: 实现最小离线构建包

**Files:**
- Create: `tools\portable-test-env\build.ps1`
- Modify: `tools\portable-test-env\bundle-manifest.json`
- Read: `tools\portable-test-env\requirements.lock`
- Read: `tools\portable-test-env\tests\conftest.py`
- Read: `tools\portable-test-env\tests\test_public_examples.py`
- Output: `dist\portable-test-kit\`

- [ ] **Step 1: 校验构建输入和输出边界**

构建脚本要求 manifest、锁文件、测试文件存在并验证必要字段；构建失败时输出具体缺失项并返回非零。输出目录限定为仓库 `dist\portable-test-kit\`；清理只允许作用于该明确目录，不删除目录以外内容。

验证：分别移走一个测试文件、损坏 manifest 字段运行构建；两者均应失败并准确指出错误，不产生部分伪成功包。

- [ ] **Step 2: 获取并校验便携 Python 和 wheelhouse**

脚本从 manifest 指定来源下载便携 Python，在解压前验证 SHA-256；使用固定的 pytest 锁文件下载适配 Windows x64 的 wheel 到临时 wheelhouse。不得从目标机系统 PATH 解析 Python，也不得在下载校验失败时继续构建。

验证：故意设置错误哈希时，构建应在解压前非零退出；恢复正确哈希后下载/校验进入下一步。

- [ ] **Step 3: 离线安装 pytest 并组装包内目录**

用解压后的便携 Python 执行 pip，从 wheelhouse 运行带 `--no-index`、`--find-links` 和 `--require-hashes` 的锁定安装。将测试目录复制到包内 `tests\`，创建包内 `logs\`，并将入口和 README 一并复制。

验证：断开构建机网络后重跑依赖安装阶段仍成功；将最终目录移到另一个含空格的临时路径后，包内 Python 可输出版本，pytest 可输出版本并收集示例用例。

- [ ] **Step 4: 写入可追溯清单**

生成最终 `bundle-manifest.json`，记录目标 OS/架构、Python 发行版和版本、pytest 锁文件摘要、归档 SHA-256、构建时间及外部依赖提示（Windows x64、`ping.exe`、`C:\` 根目录、网络连通性）。不记录用户凭据。

验证：清单 JSON 可解析；清单 Python 版本与包内解释器报告一致；锁文件摘要匹配。

**Task 2 完成标准：** 可构建 `dist\portable-test-kit\`，其中带便携 Python、pytest、示例测试和可追溯清单；不含 Allure/JRE。  
**状态：** 已完成；新构建包验收通过，manifest、锁文件摘要、解释器/pytest 版本和测试收集均匹配。

## Task 3: 提供便携启动入口并跑通示例

**Files:**
- Create: `tools\portable-test-env\run-tests.cmd`
- Modify: `tools\portable-test-env\build.ps1`（复制入口并创建运行日志路径）
- Read: `tools\portable-test-env\tests\conftest.py`
- Read: `tools\portable-test-env\tests\test_public_examples.py`

- [ ] **Step 1: 编写相对路径启动器**

`run-tests.cmd` 使用 `%~dp0` 解析交付目录，检查包内 Python 和测试文件存在；以包内 Python 执行 `-m pytest`，将传给启动器的参数原样转交给 pytest。所有路径加引号，不能回退调用系统 Python。

验证：将目录复制到包含空格的路径后，入口可列出测试；临时移走包内 Python 后给出明确错误且非零退出。

- [ ] **Step 2: 保留 pytest 退出码并收集诊断输出**

入口将控制台输出和错误诊断写入包内 `logs\`，在日志处理后返回 pytest 原始退出码；不得通过 `start` 异步脱离导致退出码丢失。若日志写入失败，给出明确提示，但不得伪造测试成功。

验证：用一个隔离的临时失败用例确认启动器返回非零并记录日志；移除失败用例后确认测试退出码为 0。

- [ ] **Step 3: 运行公开示例**

在普通 PowerShell 或命令提示符中从交付目录运行 `.\run-tests.cmd`。再在含空格的路径中运行一次。

验证：两次均可收集并执行三个示例；百度、C 盘用例通过；Google 用例在 3 秒内给出成功或清晰的超时诊断；示例不修改系统配置、不写入磁盘。

- [ ] **Step 4: 验证失败前置条件可诊断**

分别模拟 `ping.exe` 不在 PATH、`C:\` 不可读、以及出站 ICMP 被拦截的环境运行。检查 pytest 或入口指出具体前置条件。

验证：三种条件均为非零结果，不误报成功；Google 超时用例给出明确的 3 秒超时诊断。

**Task 3 完成标准：** 新设备操作者只需普通用户会话、可用的 `ping.exe` 和可读的 `C:\`，可由包内 Python/pytest 跑通示例或得到明确可诊断的前置条件错误。  
**状态：** 已完成公开示例的收集和执行验证；Google 用例的结果取决于当前网络的出站 ICMP 策略。

## Task 4: 文档和干净设备验收

**Files:**
- Modify: `tools\portable-test-env\README.md`
- Create: `tools\portable-test-env\validate-bundle.ps1`
- Read: `docs\portable-test-environment\2026-10-27-design.md`
- Read: `tools\portable-test-env\bundle-manifest.json`

- [ ] **Step 1: 更新便携示例说明**

README 列出 Windows x64、复制到用户可写目录、运行 `run-tests.cmd` 的命令；说明网络用例需要出站 ICMP、Google 可能被拦截，目录用例只读取 `C:\`；明确示例不需要管理员权限，也不修改系统配置或写入磁盘。

验证：操作说明中的命令在包目录及路径含空格的目录中均可执行；文档没有承诺目标设备无需 PowerShell，也没有声称包含 Allure。

- [ ] **Step 2: 实现只读包验收脚本**

`validate-bundle.ps1` 检查包内 Python、pytest、测试文件、README 和 manifest；对每个缺少项输出具体路径并返回非零。不运行示例，不修改系统配置，不访问网络。

验证：完整包通过；分别移除 Python、pytest 或测试文件后验收脚本非零退出并指出缺项。

- [ ] **Step 3: 在无 Python/uv 的干净 Windows x64 设备验收**

复制交付目录至干净 Windows x64 虚拟机的含空格可写路径，先禁用网络运行验证脚本和 C 盘用例，再启用网络运行 ping 用例。该虚拟机需有 `ping.exe` 且可读 `C:\`。

验证：Python 与 pytest 来自交付目录；无依赖下载；示例通过；系统级 `PATH`、注册表和持久化环境变量运行前后无变化。

- [ ] **Step 4: 记录本阶段验收和后续扩展门槛**

记录 Python/pytest 版本、干净设备系统版本、示例测试结果及日志位置。只有后续用例明确要求 Allure 报告时，才新增 allure-pytest、Allure CLI、JRE 的版本锁定、打包和离线验收任务。

验证：验收记录区分已验证事项与外部前置条件；第一阶段没有 Allure/JRE 依赖或相关启动逻辑。

**Task 4 完成标准：** README 可独立操作；最小包在未预装 Python/uv 的 Windows x64 设备上可离线运行 C 盘用例、联网运行 ping 用例，且不持久化修改设备环境。  
**状态：** 部分完成；README 和包验收脚本已提供，便携包在跨盘符、含空格目录中通过验收且在无系统 Python 的 PATH 下收集成功。干净虚拟机上的完整公开示例验收仍需完成。
