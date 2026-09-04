# 内置 kernelcache 偏移表

Relaxin 在设备上要从 kernelcache 里读的每一个值，都是那个文件的纯函数：同一份
kernelcache，在设备上读和在构建机上读，结果必然一样。这里的工具把这件事提前做完，
把结果打包成 `Relaxin/Resources/KernelOffsets.plist`，让 Task02 在本地 kernelcache
来源全部落空后、开始真实下载之前查表——命中时下载、拷贝与解析都不再发生。

查不到就继续原来的下载路径：表缺失、schema 不认识、本机的设备与 build 不在表内，
或条目不适配当前 CPU family 时，Task02 才调用 libgrabkernel2。

## 组成

| 路径 | 作用 |
| --- | --- |
| `dump-kernel-offsets.c` | 单个 kernelcache 的提取器，输出 JSON |
| `build-offset-table.py` | 遍历语料库、去重、汇总成 XML plist |
| `audit-offset-table.py` | 横向比对生成结果，找出偏离预期的条目 |
| `Makefile` | 用 macOS 版 ChOma / XPF 构建提取器 |

提取器**编译的是引擎自己的源码**——`Rocket/Profile/StaticProfile.c`、
`Rocket/Backend/GFX/Patterns.c`、`Rocket/Profile/XNUVersion.c`。这是整套方案成立的
前提：表不是对设备端逻辑的第二种实现，它就是设备端逻辑，只是提前跑了一遍。

## 表里有什么

`RocketStaticKernelProfile`（见 `StaticProfile.h`）的全部字段，加上交给
`jbinfo_initialize_dynamic_offsets` 的那本偏移字典：

- 静态内核基址、arm64e / SPTM / fileset / PPL `__TEXT` 标志、XNU build 与 OS 版本；
- Rocket 建立地址翻译要用的十个 XPF 项（`cpu_ttep`、`gVirtBase`、`gPhysBase`、
  `gPhysSize`、`ptov_table`、`allproc`、`vm_map.pmap`、`ARM_TT_L1_INDEX_MASK`、
  `T1SZ_BOOT`、`kernel_el`）；
- SPTM 设备的 `sptm_args` 静态地址；
- GFX pattern recovery 的 15 个结果（DMAFail 后端不需要，A12 kernelcache 也没有
  AGXG fileset，这类 profile 记为“无 GFX 偏移”而不是失败）；
- `xpf_construct_offset_dictionary` 对本 kernelcache 支持的那组 set 的完整输出，
  外加引擎会补上的 `kernelConstant.staticBase`。

**表里没有的**：一切来自运行中内核的东西——slide、`cpu_ttep` 指向的实际值、ptov
表内容、kernel roots、stage-1 VM range。这些从来就不在文件里，仍然在设备上现读。

## 编码约定

内核地址超过 `Int64` 上限，而 plist 的整数是有符号的，所以生成器写入二进制补码，
`RLXKernelOffsetTable.m` 用 `-unsignedLongLongValue` 取回同样的位模式。表的
`schema` 与 `profileVersion` 两个版本号必须同时被生成器和读取器认识，否则整张表被
拒绝——读取器宁可让所有设备回落到读 kernelcache，也不交出半张表。

## 重新生成

需要一份本地 kernelcache 语料库，默认 `~/kernelcaches`，带 `index.json`。

```sh
make kernel-offsets
```

或者手工分两步、并指定参数：

```sh
make -C DevKit/Helpers/KernelOffsets
DevKit/Helpers/KernelOffsets/build-offset-table.py \
    --corpus ~/kernelcaches \
    --min-version 16.5.1 --max-version 17.3.1
```

默认收录语料库里的全部 arm64e kernelcache。Task01 目前只放行 iOS 16.5.1 ~ 17.3.1，
区间外的条目走不到 Task02；但表本身不裁剪，多出来的条目只值几十 KB，支持窗口一旦
放宽就不必重新生成。用 `--min-version` / `--max-version` 可以收窄。

kernelcache 内建的版本字段只到次版本：20F75 是 iOS 16.5.1 的产品 build 却报
`16.5`，16.7 / 16.7.1 / 16.7.2 的 20H19、20H30、20H115 三个 build 都报 `16.7`。
偏移表保留该原始元数据，并以产品 build 作为真实支持边界；不应把表内 `osVersion`
文本改写成产品版本号。查表的键是 `<设备>|<Build>`，不受这个字段影响；审计在同一
`osVersion` 内按 build 号排序，否则同版本多 build 会被误判成版本倒退。

`--report` 只打印覆盖率不写文件，`-j` 控制并发。单个 kernelcache 约 1 秒。

`make kernel-offsets` 在生成之后会自动跑一遍审计。再跑一遍契约测试，它会逐条校验
表内每个条目都能解析成可用 profile：

```sh
make -C DevKit/Tests/KernelOffsetTable clean test
```

## 审计在查什么

XPF 与 GFX pattern recovery 是模式匹配。`xpf_construct_offset_dictionary` 只保证
每个 metric 解析出了非零值，`physrw_gfx_resolve_patterns` 只保证每个候选通过
对应的结构约束——两者都可能在某个没验证过的内核上给出一个“看起来合理”的错值。重算一遍
只会得到同样的错值，所以审计做的是横向比对：

- 同一个 iOS build 上，所有机型的 `nsysent`、`mach_trap_count`、`proc.struct_size`、
  `task.itk_space`、`vm_map.pmap` 必须逐位相同；
- `pointer_mask` 必须与 `T1SZ_BOOT` 一一对应，`PT_INDEX_MAX` 必须在同一台设备的各
  个 build 间稳定；
- 同一台设备在同一大版本内，保护模式、GFX 有无、T1SZ、EL 必须稳定；
- 同一 build、同一代 GPU 的 12 个 GFX 结构偏移必须完全一致；
- 每个符号地址必须落在这份 kernelcache 的地址窗口内。

## iOS 16 GFX 偏移

Relaxin 额外的 `IOMobileFramebufferUserClient` finder 曾把 OSMetaClass 大小指令写死为
iOS 17 的立即数，导致 iOS 16 的 direct-gfx 条目全部生成为
`hasGFXOffsets = false`。现在 finder 保留同一 class string、引用和构造路径，但改为校验
`MOVZ W3` 的角色、对齐与合理范围；已用 iOS 16.4 和 16.6 的本地 kernelcache 验证可以完整
恢复 15 个 GFX 值。

仓库内的 `KernelOffsets.plist` 已用修复后的工具在完整语料库上重跑。A12/A12X/A12Z
走 DMAFail，不要求 GFX 偏移；其余目标的表项必须带完整 GFX 数据，否则 Task02 会把它
当作未命中并回落到运行时 kernelcache。

## 覆盖范围会过期

新的 iOS build 发布后，表不会自动包含它。那些设备会静默回落到下载 kernelcache 的
旧路径——功能正常，只是慢。要扩大覆盖，先补齐语料库再重新生成。
