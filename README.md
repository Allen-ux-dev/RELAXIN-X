# RELAXIN-X

[English](#english) | [简体中文](#简体中文)

> An unofficial experimental derivative of Relaxin, focused on pushing its runtime, recovery, package-management, and upgrade architecture further.
>
> RELAXIN-X 是 Relaxin 的非官方实验性衍生项目，重点扩展运行时、恢复机制、包管理兼容性与后续升级架构。

---

## English

RELAXIN-X is a maintained experimental branch built on the public Relaxin snapshot. It preserves the upstream jailbreak engine and RootHide foundation while adding runtime/backend abstraction, environment recovery and repair orchestration, package-manager compatibility work, and a more upgrade-ready internal architecture.

The current internal baseline tracks Relaxin v0.5.0 release data where it can be verified safely, including refreshed kernel-offset metadata and A17/SPTM integrity information. Unsupported future hardware may be recognized by the framework, but is never advertised as supported without a verified backend.

### Highlights

- Runtime/backend abstraction with generation-aware resolution
- Relaxin v0.5.0 upstream baseline tracking
- A17/SPTM metadata and integrity gating
- Environment inspection, recovery, and repair planning
- Sileo + Zebra package-manager support
- Upgrade-ready baseline/registry architecture for future Relaxin releases
- Host-side contracts and regression tests for release safety

### Build

Build and package locally with the top-level Makefile or `BuildIPA.command`.

```bash
make build               # Build the iOS app (unsigned)
make ipa                 # Build and package an unsigned IPA
make tipa                # Build and package a no-sandbox TIPA
make bootstrap-resources # Download, ad-hoc sign, and stage the RootHide bootstrap
make check               # Validate the zstd integration contract
make test-host           # Run host-side contracts and portable tests
make format              # Run Swift and C-family formatters (write)
make format-lint         # Run Swift and C-family formatters in check mode
make scan-license        # Refresh Relaxin/Resources/Licenses.txt from Vendor
make clean               # Remove derived data and generated BaseBin resources
```

### Maintainer

- [Allen-ux-dev](https://github.com/Allen-ux-dev)

The RELAXIN-X maintainer block is intentionally separate from the upstream roster so branch maintenance and original-project attribution remain unambiguous.

### Original Relaxin / Upstream

RELAXIN-X is based on the public Relaxin snapshot from OwnGoal Studio. Original upstream project credits remain preserved:

- [@Lakr233](https://x.com/Lakr233)
- [@0x88FFA357](https://x.com/0x88FFA357)
- [@82Flex](https://x.com/82Flex)
- [@roothideDev](https://x.com/roothideDev)
- [@pattern_F_](https://x.com/pattern_F_)

RELAXIN-X also uses external software and binaries during the jailbreak; refer to the Software License section inside the app.

### License

The upstream Relaxin snapshot is licensed under the MIT License. See `LICENSE` for details. Third-party components retain their respective licenses.

RELAXIN-X is an independent derivative and is **not an official OwnGoal Studio release**.

---

## 简体中文

RELAXIN-X 是基于 Relaxin 公开源码快照持续维护的实验性分支。项目保留上游越狱引擎与 RootHide 基础，同时增加运行时/后端抽象、环境检查与恢复、修复编排、包管理器兼容，以及更便于后续升级的内部架构。

当前内部基线在可安全验证的范围内跟进 Relaxin v0.5.0，包括更新后的 KernelOffsets 元数据以及 A17/SPTM 完整性信息。对于未来尚未验证的新硬件，框架可以先识别，但在没有经过验证的 backend 之前不会把它标记为“已支持”。

### 主要特性

- 带 generation 管理的 Runtime / Backend 抽象
- Relaxin v0.5.0 上游基线跟踪
- A17 / SPTM 元数据与完整性门禁
- 环境检查、恢复与 Repair Plan
- Sileo + Zebra 双包管理器支持
- 面向未来 Relaxin 版本的 Baseline / Registry 升级架构
- Host 侧契约测试与回归检查

### 构建

可以使用项目根目录的 Makefile 或 `BuildIPA.command` 在本地构建和打包。

```bash
make build               # 构建 iOS App（未签名）
make ipa                 # 构建并打包未签名 IPA
make tipa                # 构建并打包 no-sandbox TIPA
make bootstrap-resources # 下载、临时签名并准备 RootHide bootstrap 资源
make check               # 检查 zstd 集成契约
make test-host           # 运行 Host 侧契约与可移植测试
make format              # 格式化 Swift 与 C-family 代码
make format-lint         # 仅检查格式，不写入
make scan-license        # 根据 Vendor 刷新 Relaxin/Resources/Licenses.txt
make clean               # 清理派生数据与生成的 BaseBin 资源
```

### 维护者

- [Allen-ux-dev](https://github.com/Allen-ux-dev)

RELAXIN-X 的维护者信息与上游作者列表分开保留，以避免把分支维护与原项目署名混在一起。

### 原始 Relaxin / 上游

RELAXIN-X 基于 OwnGoal Studio 的 Relaxin 公开源码快照。原项目作者与贡献者署名继续保留：

- [@Lakr233](https://x.com/Lakr233)
- [@0x88FFA357](https://x.com/0x88FFA357)
- [@82Flex](https://x.com/82Flex)
- [@roothideDev](https://x.com/roothideDev)
- [@pattern_F_](https://x.com/pattern_F_)

RELAXIN-X 在越狱过程中还会使用第三方软件和二进制组件，详细许可信息请参考 App 内的 Software License 页面以及仓库中的许可证文件。

### 许可证

上游 Relaxin 公开源码快照采用 MIT License，详见 `LICENSE`。第三方组件继续遵循各自原始许可证。

RELAXIN-X 是独立维护的非官方衍生项目，**不是 OwnGoal Studio 的官方发行版**。
