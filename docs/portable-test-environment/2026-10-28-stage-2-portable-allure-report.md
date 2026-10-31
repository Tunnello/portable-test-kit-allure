# 便携式 Allure 报告实施计划

> **供智能体执行：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 子技能，按任务逐项执行本计划。每个步骤使用复选框（`- [ ]`）跟踪。

**目标：** 扩展 Windows x64 便携测试包，使 pytest 运行结束后生成 Allure 报告并自动在仅本机可访问的网站中打开；离线交付包内包含 Allure CLI 和 Java 运行时。

**架构：** 将 pytest 和 `allure-pytest` 纳入 Python 依赖锁定文件，并单独打包固定版本的 Allure Commandline 和 Windows x64 便携 JRE。测试启动器每次运行前清理本次运行专用的结果目录，即使测试失败也生成报告，随后在 `127.0.0.1` 上同步提供报告服务并自动打开浏览器；启动器保留 pytest 退出码，并明确报告工具错误。

**技术栈：** Windows x64、PowerShell、CMD、包内 WinPython/Python 3.13、pytest、`allure-pytest`、Allure Commandline、Windows x64 便携 JRE。

**设计文档：** [docs/portable-test-environment/design.md](./design.md) 是第一阶段基线。本计划在其基础上扩展第二阶段的 Allure/JRE 要求和仅本机报告工作流。

## 全局约束

- 交付包面向 Windows x64；目标设备无需预装 Python、uv、Java/JRE 或 Allure CLI，也无需联网。
- 交付包必须包含兼容且固定版本的 `allure-pytest`、Allure Commandline 和便携 JRE；所有下载归档均须使用固定 HTTPS 来源并验证 SHA-256。
- 运行时的报告生成和服务只能使用包内工具，不得下载依赖。
- 报告网站只能绑定 `127.0.0.1`，不得暴露给局域网或公网。
- 每次运行都从干净的、由包管理的 `allure-results` 和报告输出目录开始；清理操作只能作用于包根目录下这两个明确路径。
- 即使 pytest 报告测试失败，也必须继续生成 Allure 结果和报告，以便报告中包含失败测试。
- 报告生成并且本机报告服务关闭后，启动器必须保留 pytest 的非零退出码；报告生成或服务启动失败时也必须明确报错，不能伪装成成功。
- 不得持久修改系统 `PATH`、`JAVA_HOME`、注册表或环境变量。Java 相关环境值只能设置给子进程。
- 保留第一阶段的安全边界：仅运行 `test_public_examples.py` 中的公开示例，不需要管理员权限，不修改系统配置，不写入磁盘。
- 当前工作区不是 Git 仓库；不得假设可以创建提交。

---

## 文件清单

| 路径 | 职责 |
|---|---|
| `docs/portable-test-environment/design.md` | 增加第二阶段范围、软件包和运行时边界、报告生命周期、失败处理和验收标准。 |
| `tools/portable-test-env/requirements.in` | 在 pytest 依赖旁增加直接 Python 依赖 `allure-pytest`。 |
| `tools/portable-test-env/requirements.lock` | 为所选 Python/Windows 目标锁定插件及其全部 Python 传递依赖和哈希。 |
| `tools/portable-test-env/bundle-manifest.json` | 固定 Allure CLI 和便携 JRE 的版本、归档名、HTTPS URL、SHA-256、解压路径和可执行文件路径。 |
| `tools/portable-test-env/build.ps1` | 校验、下载或复用并验证 CLI/JRE；离线安装 Python 依赖；组装文件并生成包清单。 |
| `tools/portable-test-env/run-tests.cmd` | 继续作为相对路径入口，并将用户的 pytest 参数传给包内运行器。 |
| `tools/portable-test-env/run_tests.py` | 编排 pytest、Allure 结果清理和报告生成、本机报告服务、浏览器启动、日志和退出码处理。 |
| `tools/portable-test-env/validate-bundle.ps1` | 离线验证包内 Python 依赖、Allure CLI、JRE、清单哈希/版本和测试收集。 |
| `tools/portable-test-env/README.md` | 说明构建、离线目标设备要求、自动打开报告、报告路径、服务生命周期和诊断方法。 |
| `tools/portable-test-env/tests/test_report_runner.py` | 使用模拟子进程测试运行器顺序、清理范围、环境隔离、测试失败时生成报告及退出码语义。 |
| `tools/portable-test-env/tests/test_build_script.py` | 扩展构建器测试，覆盖缺失或错误的 Allure/JRE 元数据和归档哈希错误。 |
| `tools/portable-test-env/tests/test_launcher.py` | 验证 CMD 启动器调用包内 Python 报告运行器，并在运行器缺失时给出明确错误。 |
| `tools/portable-test-env/tests/test_validate_bundle.py` | 验证包验收器能发现 Allure/JRE 组件缺失或版本不匹配。 |
| `dist/portable-test-kit/` | 构建输出目录，包含 Python、Allure CLI、便携 JRE、测试、报告运行器、日志及生成的报告/结果目录。 |

## 任务 1：明确第二阶段报告契约

**文件：**
- 修改：`docs/portable-test-environment/design.md`
- 阅读：`docs/portable-test-environment/implementation-plan.md`
- 阅读：`tools/portable-test-env/README.md`

- [ ] **步骤 1：明确第二阶段范围和外部前置条件**

说明第二阶段为第一阶段的便携测试包增加 Allure 报告。目标设备仍需提供可用的 `ping.exe` 和可读的 `C:\` 根目录；网络连通性用例需要出站 ICMP。目标设备不需要预装 Java、Python 或 Allure。

- [ ] **步骤 2：规定报告生命周期和失败处理**

明确启动器仅清理包内由本工具管理的旧结果/报告目录；运行 pytest 时启用 Allure 结果输出；只要存在结果文件，即使测试失败也继续生成报告；随后使用固定版本的 Allure CLI 在 `http://127.0.0.1` 上打开新生成的报告。说明本机服务会保持运行，直到用户关闭（按 Ctrl+C）；服务关闭后，启动器返回 pytest 原始退出码。如果报告生成或服务启动失败，必须输出诊断并返回非零，不得打开旧报告。

- [ ] **步骤 3：规定兼容性和离线验收要求**

要求在包内 Python 版本上共同验证 `allure-pytest`、Allure Commandline 和 Windows x64 JRE 的选定版本；固定归档哈希并保留许可证声明；在断网的干净设备上验收自动打开的本机报告网站及其中的测试结果。

- [ ] **步骤 4：检查契约是否存在歧义**

确认报告服务仅绑定本机、浏览器会自动打开、新旧测试结果不会混用，且文档中的失败处理和退出码规则与启动器设计一致。

## 任务 2：固定 Python、Allure CLI 和 JRE 依赖

**文件：**
- 修改：`tools/portable-test-env/requirements.in`
- 修改：`tools/portable-test-env/requirements.lock`
- 修改：`tools/portable-test-env/bundle-manifest.json`
- 阅读：`tools/portable-test-env/build.ps1`

- [ ] **步骤 1：选择兼容且可再分发的版本**

选择与项目固定版本的 pytest 和 Python 3.13 兼容的 `allure-pytest` 版本；选择支持所需 `generate` 和 `open` 命令的 Allure Commandline 版本；再选择该 CLI 支持的 Windows x64 便携 JRE。记录精确版本、归档 URL、SHA-256、解压目录名、可执行文件路径及许可证/声明来源，并写入清单或单独的第三方声明文件。不能只依据“最新版本”标签选型；须核实实际发布归档及兼容性。

- [ ] **步骤 2：将 Allure pytest 插件加入直接 Python 依赖**

在 `requirements.in` 中将选定版本的 `allure-pytest` 与 pytest 一并固定。Allure Commandline 和 Java 是单独下载的运行时制品，不应加入 Python 锁定文件。

- [ ] **步骤 3：重新生成带哈希的 Windows x64 Python 依赖锁**

按照项目现有锁定流程，为包内 Python 3.13 和 Windows x64 重新生成 `requirements.lock`。确保所有包均有哈希，并包含该插件的完整依赖闭包。

- [ ] **步骤 4：添加 CLI/JRE 制品元数据**

在清单中增加明确的 `allure` 和 `java_runtime` 段，记录固定版本、HTTPS 归档 URL、SHA-256、归档名、解压子目录及包内 CLI/JRE 路径。构建器输入校验必须拒绝缺失、格式错误或非 HTTPS 的元数据。

- [ ] **步骤 5：验证依赖集合和发布归档**

在干净的构建环境中下载带哈希锁定的 Python wheel 及选定的 CLI/JRE 归档，逐一校验归档 SHA-256；确认 Java 可执行文件报告的版本正确，并确认 Allure CLI 只使用包内 JRE 时报告的版本正确。

## 任务 3：构建完整的离线 Allure/JRE 软件包

**文件：**
- 修改：`tools/portable-test-env/build.ps1`
- 修改：`tools/portable-test-env/bundle-manifest.json`
- 修改：`tools/portable-test-env/tests/test_build_script.py`
- 输出：`dist/portable-test-kit/`

- [ ] **步骤 1：测试错误的 CLI/JRE 构建元数据**

使用临时项目根目录添加构建器测试，验证缺少 CLI/JRE 段、归档哈希格式错误、制品 URL 非 HTTPS 时，`-ValidateOnly` 会失败，指出具体字段并返回非零退出码。

- [ ] **步骤 2：测试解压前拒绝错误归档哈希**

使用本地测试归档和故意设置错误的清单哈希添加测试。断言构建器会指出对应制品的 SHA-256 不匹配；此时既未创建暂存的可执行文件，也未替换已有交付包。

- [ ] **步骤 3：扩展构建器输入校验**

校验全部 CLI/JRE 元数据，并解析来源路径或用户提供的归档路径。必须先验证归档，再解压；任一制品缺失或哈希不匹配时立即失败。

- [ ] **步骤 4：暂存 Python wheels、Allure CLI 和便携 JRE**

使用 `--no-index`、`--find-links` 和 `--require-hashes` 安装已锁定的 Python wheels。将校验通过的 Allure 和 JRE 归档解压到暂存目录中固定的包内目录；验收暂存包前，核实 CLI/Java 可执行文件路径和版本。

- [ ] **步骤 5：记录包内版本和哈希**

生成交付包清单，记录 Python 锁文件哈希和已解析的包版本、CLI/JRE 来源元数据及归档哈希、包内可执行文件相对路径和外部前置条件。将必要的第三方许可证声明一并放入交付包。

- [ ] **步骤 6：构建并验证交付包**

将包构建到现有的 `dist/portable-test-kit` 目录；仅在明确传入 `-Force` 时替换已有输出。确认包内包含全部运行时文件，并可在断网时报告 Python、pytest、插件、CLI 和 Java 的版本。

## 任务 4：实现报告编排和本机自动打开

**文件：**
- 新建：`tools/portable-test-env/run_tests.py`
- 修改：`tools/portable-test-env/run-tests.cmd`
- 新建：`tools/portable-test-env/tests/test_report_runner.py`
- 修改：`tools/portable-test-env/tests/test_launcher.py`

**接口：**
- `run-tests.cmd` 只能通过 `%~dp0` 相对路径调用 `python\python.exe run_tests.py`，并转发用户的 pytest 参数。
- `run_tests.py` 从清单读取包内路径，调用包内 pytest 并指定由其管理的 Allure 结果目录；使用包内 Allure CLI 生成报告，并通过主机地址 `127.0.0.1` 打开报告。
- Java 相关环境变量只传给子进程；不得更改父进程或机器级配置。

- [ ] **步骤 1：使用模拟子进程添加运行器行为测试**

测试命令顺序和参数：只清理包内的 `allure-results` 与 `allure-report`；运行 pytest 并指定受管理的结果目录；生成报告；通过 `127.0.0.1` 主机地址打开报告；为子进程传递指向包内 JRE 的 `JAVA_HOME`。

- [ ] **步骤 2：测试运行结果和诊断信息**

验证 pytest 失败时仍会继续生成并打开报告，且报告服务关闭后返回原始非零退出码。验证 pytest 成功时，只有报告生成和服务启动均成功才返回零。验证缺少结果文件、报告生成失败或服务启动失败时会给出明确错误，并且不会打开旧报告。

- [ ] **步骤 3：实现 Python 报告运行器**

以运行器所在的包目录为基准解析路径，读取并校验清单中的可执行文件路径；拒绝用户传入 `--alluredir`，由运行器统一管理结果路径。只删除包内固定的两个输出目录。使用 `--alluredir <包目录>\allure-results` 运行 pytest 并保留其退出码；存在结果文件时，使用固定版本的 Allure CLI 以清理模式生成 `allure-report`。报告生成成功后，同步调用 CLI 并指定 `--host 127.0.0.1` 打开报告。报告服务进程必须与启动器生命周期绑定，用户可按 Ctrl+C 关闭。如果测试和报告处理都失败，输出报告处理错误，但最终仍保留 pytest 的失败退出码。

- [ ] **步骤 4：保持 CMD 入口精简并使用相对路径**

修改 `run-tests.cmd`：检查包内 Python 和 `run_tests.py` 是否存在；创建或使用包内日志目录；从 `%~dp0` 调用运行器；转发 pytest 参数；显示诊断信息；返回 Python 运行器的退出码。不得回退到系统 Python，也不得用 `start` 启动脱离启动器管理的服务。

- [ ] **步骤 5：验证启动器和运行器行为**

运行新增的运行器专项测试和现有启动器测试。随后使用真实打包工具，通过启动器分别运行一个成功示例和一个失败示例；确认两份报告分别包含对应结果，并确认用户关闭本机服务后，失败示例仍返回非零退出码。

## 任务 5：加强离线软件包验收

**文件：**
- 修改：`tools/portable-test-env/validate-bundle.ps1`
- 修改：`tools/portable-test-env/tests/test_validate_bundle.py`
- 修改：`tools/portable-test-env/build.ps1`

- [ ] **步骤 1：测试缺失或版本不匹配的 Allure/JRE 组件**

扩展验收器测试，覆盖 Allure CLI 缺失、Java 可执行文件缺失、CLI 版本不匹配和 Java 版本不匹配。每种情形都必须报告预期的包内路径或版本信息并失败。

- [ ] **步骤 2：校验软件包文件及元数据完整性**

校验清单字段和包内相对路径、CLI/JRE 必需文件、Python 锁文件哈希、声明的包版本及第三方许可证声明。解析路径时必须将路径约束在包根目录内，并拒绝指向包外的元数据路径。

- [ ] **步骤 3：离线校验运行工具**

运行包内 Python，校验 pytest 和 `allure-pytest`；运行包内 Java 可执行文件核对版本；使用包内 Java 环境运行 Allure CLI，核对版本和报告命令。不得联网、打开浏览器或修改系统配置。

- [ ] **步骤 4：验证完整包和人为损坏的副本**

确认完整交付包可通过离线验收。在临时副本中每次移除一个 CLI/JRE 组件，确认验收器针对具体缺失项失败，且不会修改原始包。

## 任务 6：更新文档并完成端到端验收

**文件：**
- 修改：`tools/portable-test-env/README.md`
- 修改：`docs/portable-test-environment/design.md`
- 阅读：`tools/portable-test-env/bundle-manifest.json`
- 输出：`dist/portable-test-kit/`

- [ ] **步骤 1：说明构建流程和离线目标设备运行方式**

记录固定的 Python/插件、Allure CLI 和 JRE 版本；说明构建及使用缓存制品的选项、目标设备前置条件、测试命令、浏览器自动打开行为、本机专用地址、停止服务的方法、报告结果文件位置，以及测试/报告失败对退出码的影响。明确目标设备无需安装 Java、Allure、Python，也无需联网。

- [ ] **步骤 2：验证构建和专项测试**

运行构建器、启动器、报告运行器和验收器测试。使用已验证的缓存制品重新构建交付包，并在禁用网络的条件下运行 `validate-bundle.ps1`。

- [ ] **步骤 3：在 Windows x64 上验证浏览器和报告内容**

在未预装 Python、Java 或 Allure 且断网的干净 Windows x64 目标设备上，将交付包复制到包含空格且当前用户可写的路径。分别运行一个成功用例和一个失败用例；每次都确认浏览器自动打开 `127.0.0.1` 报告网站，报告包含本次运行结果，服务持续可用直至用户关闭，并且启动器随后返回正确的 pytest 状态。

- [ ] **步骤 4：验证环境隔离且不会混入旧报告**

连续运行两次不同的测试，确认第二份报告仅包含第二次运行结果。确认机器持久化的 `PATH`、`JAVA_HOME`、注册表和环境变量均未改变；确认没有服务监听非回环网卡，且运行时没有下载网络资源。

- [ ] **步骤 5：记录验收状态**

在第二阶段文档中记录精确的运行时/工具版本、Windows 版本、断网状态、浏览器启动结果、报告 URL、成功/失败退出码以及目标设备前置条件。明确区分已在当前环境验证的内容和仍需在干净目标设备上完成的验收。

## 完成标准

- 交付包包含哈希校验通过的 Allure CLI 和便携 JRE，以及哈希锁定的 `allure-pytest` 依赖。
- 交付包可在无需网络、无需在系统中安装 Java/Python 的情况下通过验收并生成报告。
- 启动器运行 pytest，生成包含失败测试的 Allure 报告，并自动打开仅绑定 `127.0.0.1` 的报告网站。
- 报告服务不会对外暴露；报告不会过期或与之前运行结果混合；启动器会保留测试和报告处理的失败状态。
- 第一阶段关于公开示例、无需管理员权限和不修改系统配置的约束继续有效。
