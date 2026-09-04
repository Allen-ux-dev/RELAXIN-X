#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
审计生成好的内置偏移表，找出偏离预期的条目。

XPF 与 GFX pattern recovery 是模式匹配，不是查表：某个 kernelcache 上匹配到了、
候选互相一致，并不等于匹配对了。`xpf_construct_offset_dictionary` 只保证每个 metric
解析出了非零值，`physrw_gfx_resolve_patterns` 只保证每个候选通过对应的结构约束。
两者都可能在某个从没验证过的内核上给出一个“看起来合理”的错值，而错值会一直传到
设备上的页表遍历里。

所以这里做的不是“再算一遍”（那只会得到同样的错值），而是横向比对：同一个 iOS
build 上所有设备的结构体偏移必须一致；同一台设备跨 build 的保护模式必须稳定；同一
代 GPU 的 GFX 偏移必须成簇。任何一条不成立，都说明某个 kernelcache 上的某个 finder
走偏了。

    ./audit-offset-table.py                      # 审计默认位置的表
    ./audit-offset-table.py --table <plist> --corpus <dir>
    ./audit-offset-table.py --verbose            # 连同分组明细一起打印
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DEFAULT_TABLE = os.path.join(ROOT, "Relaxin", "Resources", "KernelOffsets.plist")
DEFAULT_CORPUS = os.path.expanduser("~/kernelcaches")

FLAG_ARM64E = 1 << 0
FLAG_SPTM = 1 << 1
FLAG_FILESET = 1 << 2
FLAG_PPL_TEXT = 1 << 3
FLAG_GFX_OFFSETS = 1 << 4

# coverage.json 对部分机型没有填 platform，这里按机型名补全。只影响审计的期望值，
# 不进入产物。
SUPPLEMENTAL_PLATFORM = {
    "iPad12,1": "t8030", "iPad12,2": "t8030",          # iPad 9 · A13
    "iPad13,18": "t8101", "iPad13,19": "t8101",        # iPad 10 · A14
    "iPad14,1": "t8110", "iPad14,2": "t8110",          # iPad mini 6 · A15
    "iPad14,3": "t8112", "iPad14,4": "t8112",          # iPad Pro 4 · M2
    "iPad14,5": "t8112", "iPad14,6": "t8112",          # iPad Pro 6 · M2
    "iPhone14,2": "t8110", "iPhone14,3": "t8110",      # iPhone 13 Pro · A15
    "iPhone14,4": "t8110", "iPhone14,5": "t8110",      # iPhone 13 · A15
    "iPhone14,7": "t8110", "iPhone14,8": "t8110",      # iPhone 14 · A15
    "iPhone15,2": "t8120", "iPhone15,3": "t8120",      # iPhone 14 Pro · A16
    "iPhone15,4": "t8120", "iPhone15,5": "t8120",      # iPhone 15 · A16
    "iPhone16,1": "t8130", "iPhone16,2": "t8130",      # iPhone 15 Pro · A17 Pro
}

# 每种 SoC 走哪条后端。A12/A12X/A12Z 走 DMAFail，从不读 GFX 偏移，其 kernelcache
# 里也没有 AGXG fileset；其余都走 direct-gfx，必须有 GFX 偏移。
PLATFORM_USES_DMA_BACKEND = {
    "t8020": True,    # A12
    "t8027": True,    # A12X
    "t8028": True,    # A12Z
    "t8030": False,   # A13
    "t8101": False,   # A14
    "t8103": False,   # M1
    "t8110": False,   # A15
    "t8112": False,   # M2
    "t8120": False,   # A16
    "t8130": False,   # A17 Pro
}

# 保护模式由这份 kernelcache 决定，不由 SoC 决定，所以期望值按 (SoC, 大版本) 给。
# SPTM 是 iOS 17 才铺开的：同一颗 A15 在 iOS 16 上是 PPL，在 iOS 17 上是 SPTM，而
# 同代的 M2 在 iOS 17 上仍然是 PPL——PatternRecovery.c 的注释说的就是这件事。
PLATFORM_PROTECTION = {
    ("t8020", 16): "PPL", ("t8020", 17): "PPL",
    ("t8027", 16): "PPL", ("t8027", 17): "PPL",
    ("t8028", 16): "PPL", ("t8028", 17): "PPL",
    ("t8030", 16): "PPL", ("t8030", 17): "PPL",
    ("t8101", 16): "PPL", ("t8101", 17): "PPL",
    ("t8103", 16): "PPL", ("t8103", 17): "PPL",
    ("t8110", 16): "PPL", ("t8110", 17): "SPTM",
    ("t8112", 16): "PPL", ("t8112", 17): "PPL",
    ("t8120", 16): "PPL", ("t8120", 17): "SPTM",
    ("t8130", 17): "SPTM",
}

# Task01 的产品下限是 iOS 16.5.1 / 20F75。20F75 kernelcache 的内建 OS 版本
# 仍可报 16.5，因此此处按 kernelcache 元数据保留 16.5 下界；产品运行时门禁不使用
# 这个常量。窗口外的条目进表是有意的，但只有窗口内的条目不可用才需要立刻处理。
SUPPORTED_MIN = (16, 5, 0, 0)
SUPPORTED_MAX = (17, 3, 1, 0)

# 同一个 iOS build 下，这些值描述的是 XNU 自身的结构与常量，与机型无关，必须逐位
# 相同。任何一台设备对不上，就说明那份 kernelcache 上的 finder 匹配到了别的东西。
#
# PT_INDEX_MAX、pointer_mask、T1SZ_BOOT、kernel_el 不在其中：它们描述的是这颗芯片
# 的地址空间几何，本来就随机型不同。它们由 check_geometry_correlation 单独校验。
BUILD_INVARIANT_KEYS = (
    "kernelConstant.mach_trap_count",
    "kernelConstant.nsysent",
    "kernelStruct.proc.struct_size",
    "kernelStruct.task.itk_space",
    "kernelStruct.vm_map.pmap",
)

# 这些随机型变化，但必须与 T1SZ_BOOT 一一对应：同一个 T1SZ 出现两种取值，说明其中
# 一个 finder 读错了。
GEOMETRY_KEYS = ("kernelConstant.pointer_mask",)

# GFX 的 12 个字段是被 patch 的对象在结构体里的位置，同一代 GPU 上应当成簇。
GFX_OFFSET_KEYS = (
    "userClientToOwnerOffset",
    "submitObjectAddressOffset",
    "ownerToStateOffset",
    "stateControlOffset",
    "ownerPatchedPointerOffset",
    "stateSubmitObjectOffset",
    "stateAddressBiasOffset",
    "stateLengthOffset",
    "ownerResourceTableOffset",
    "resourceTableEntriesOffset",
    "resourceObjectMemoryOffset",
    "resourceMemoryAddressOffset",
)
GFX_ADDRESS_KEYS = (
    "ioGpuUserClientTypeStaticAddress",
    "mobileFramebufferUserClientTypeStaticAddress",
    "agxSubmitHandlerVtableAddress",
)

# 符号相对静态基址的最大距离。fileset kernelcache 连同全部 kext 也远小于 1 GiB，
# 超出说明解析到的根本不是这份内核里的地址。
MAX_SYMBOL_SPAN = 1 << 30
KERNEL_PAGE_SIZE = 0x4000


class Findings:
    def __init__(self) -> None:
        self.errors: list = []
        self.warnings: list = []
        self.notes: list = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)


def u64(value: int) -> int:
    return value & 0xFFFFFFFFFFFFFFFF


def version_key(version: str) -> tuple:
    parts = []
    for component in version.split("."):
        parts.append(int(component) if component.isdigit() else 0)
    return tuple(parts + [0] * (4 - len(parts)))


BUILD_PATTERN = re.compile(r"^(\d+)([A-Z])(\d+)([a-z]*)$")

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")

def check_integrity_metadata(profiles: list, findings: Findings) -> None:
    """校验 v0.5.0 起可选携带的 SPTM/TXM 完整性元数据。"""
    count = 0
    for position, profile in enumerate(profiles):
        has_sptm = "sptmSHA256" in profile
        has_txm = "txmSHA256" in profile
        if has_sptm != has_txm:
            findings.error(f"profile {position}: sptmSHA256/txmSHA256 必须成对出现")
            continue
        if not has_sptm:
            continue
        count += 1
        for key in ("sptmSHA256", "txmSHA256"):
            value = profile.get(key)
            if not isinstance(value, str) or SHA256_PATTERN.fullmatch(value) is None:
                findings.error(f"profile {position}: {key} 不是合法的小写 SHA-256")
    findings.note(f"{count} 条 profile 携带 SPTM/TXM SHA-256 完整性元数据")


def build_key(build: str) -> tuple:
    """Apple build 号的真实先后。字典序会把 20H115 排在 20H19 前面，序号得按整数比。"""
    match = BUILD_PATTERN.match(build)
    if match is None:
        return (0, "", 0, build)
    return (int(match.group(1)), match.group(2), int(match.group(3)), match.group(4))


def load_platforms(corpus: str) -> dict:
    platforms = dict(SUPPLEMENTAL_PLATFORM)
    coverage_path = os.path.join(corpus, "coverage.json")
    if os.path.isfile(coverage_path):
        with open(coverage_path, "r", encoding="utf-8") as stream:
            coverage = json.load(stream)
        for device, info in coverage.get("devices", {}).items():
            if info.get("platform"):
                platforms[device] = info["platform"]
    return platforms


def load_corpus_pairs(corpus: str) -> dict:
    """语料库里应当被收录的 (设备, build) → 版本。"""
    index_path = os.path.join(corpus, "index.json")
    if not os.path.isfile(index_path):
        return {}
    with open(index_path, "r", encoding="utf-8") as stream:
        index = json.load(stream)
    pairs = {}
    for entry in index.get("kernelcaches", []):
        if entry.get("arch") != "arm64e":
            continue
        for device in entry.get("devices", []):
            pairs[(device, entry["build"])] = entry["version"]
    return pairs


# --------------------------------------------------------------------------- #
# 各项检查
# --------------------------------------------------------------------------- #


def check_coverage(table: dict, corpus_pairs: dict, findings: Findings) -> None:
    if not corpus_pairs:
        findings.note("没有语料库索引，跳过覆盖完整性检查")
        return
    indexed = set(tuple(key.split("|", 1)) for key in table["index"])
    missing = sorted(set(corpus_pairs) - indexed)
    extra = sorted(indexed - set(corpus_pairs))
    if missing:
        findings.error(
            f"语料库里有 {len(missing)} 个 设备|Build 没有进表，"
            f"说明对应 kernelcache 提取失败：{missing[:10]}"
        )
    if extra:
        findings.warn(f"表里有 {len(extra)} 个条目不在语料库索引内：{extra[:10]}")


def check_scalar_domains(profiles: list, findings: Findings) -> None:
    t1sz_values = Counter()
    kernel_el_values = Counter()
    l1_mask_by_t1sz = defaultdict(Counter)

    for position, profile in enumerate(profiles):
        tag = f"profile[{position}] {profile['osVersion']} {profile['kernelcacheSHA256'][:12]}"
        base = u64(profile["staticKernelBase"])

        if base == 0:
            findings.error(f"{tag}: staticKernelBase 为 0")
            continue
        if base % KERNEL_PAGE_SIZE:
            findings.error(f"{tag}: staticKernelBase 0x{base:x} 未按 16K 对齐")
        if base >> 40 not in (0xFFFFFF, 0xFFFFFE):
            findings.error(f"{tag}: staticKernelBase 0x{base:x} 不在内核地址段")

        for name, value in profile["symbols"].items():
            value = u64(value)
            if name in ("vm_map_pmap", "t1sz_boot", "kernel_el", "arm_tt_l1_index_mask"):
                continue
            if value < base or value - base > MAX_SYMBOL_SPAN:
                findings.error(
                    f"{tag}: 符号 {name} = 0x{value:x} 落在内核映像之外"
                    f"（基址 0x{base:x}）"
                )
            if value % 8:
                findings.warn(f"{tag}: 符号 {name} = 0x{value:x} 未按 8 字节对齐")

        t1sz = u64(profile["symbols"]["t1sz_boot"])
        kernel_el = u64(profile["symbols"]["kernel_el"])
        l1_mask = u64(profile["symbols"]["arm_tt_l1_index_mask"])
        pmap_offset = u64(profile["symbols"]["vm_map_pmap"])
        t1sz_values[t1sz] += 1
        kernel_el_values[kernel_el] += 1
        l1_mask_by_t1sz[t1sz][l1_mask] += 1

        if t1sz not in (25, 17):
            findings.error(f"{tag}: T1SZ_BOOT = {t1sz}，既不是 25 也不是 17")
        if kernel_el not in (1, 2):
            findings.error(f"{tag}: kernel_el = {kernel_el}")
        if l1_mask == 0 or l1_mask & 0x3FFF:
            findings.error(f"{tag}: ARM_TT_L1_INDEX_MASK = 0x{l1_mask:x} 不合理")
        if pmap_offset == 0 or pmap_offset > 0x1000:
            findings.error(f"{tag}: vm_map.pmap 偏移 = 0x{pmap_offset:x} 不像结构体偏移")

        packed = u64(profile["xnuVersionPacked"])
        if packed == 0:
            findings.error(f"{tag}: xnuVersionPacked 为 0")
        elif (packed >> 40) & 0x7FFF == 0:
            findings.error(f"{tag}: xnuVersionPacked 的 major 为 0")

        flags = profile["flags"]
        if not flags & FLAG_ARM64E:
            findings.error(f"{tag}: 不是 arm64e 内核")
        if not flags & FLAG_FILESET:
            findings.warn(f"{tag}: 不是 fileset kernelcache")
        sptm = bool(flags & FLAG_SPTM)
        if sptm and u64(profile["sptmArgs"]) == 0:
            findings.error(f"{tag}: SPTM 内核但 sptm_args 为 0")
        if not sptm and u64(profile["sptmArgs"]) != 0:
            findings.error(f"{tag}: 非 SPTM 内核却有 sptm_args")
        if not sptm and not flags & FLAG_PPL_TEXT:
            findings.error(f"{tag}: 既不是 SPTM 也没有 PPL __TEXT")
        if sptm and flags & FLAG_PPL_TEXT:
            findings.error(f"{tag}: 同时报告 SPTM 与 PPL __TEXT")

    findings.note(f"T1SZ_BOOT 取值分布：{dict(t1sz_values)}")
    findings.note(f"kernel_el 取值分布：{dict(kernel_el_values)}")
    for t1sz, masks in sorted(l1_mask_by_t1sz.items()):
        if len(masks) > 1:
            findings.error(
                f"T1SZ_BOOT={t1sz} 对应了多个 ARM_TT_L1_INDEX_MASK："
                + ", ".join(f"0x{m:x}×{n}" for m, n in masks.items())
            )
        else:
            mask = next(iter(masks))
            findings.note(f"T1SZ_BOOT={t1sz} → ARM_TT_L1_INDEX_MASK=0x{mask:x}（{masks[mask]} 条）")


def check_platform_expectations(entries: list, platforms: dict, findings: Findings) -> None:
    unknown = set()
    unusable_supported = []
    unusable_unsupported = defaultdict(list)

    for device, build, profile in entries:
        platform = platforms.get(device)
        if not platform or platform not in PLATFORM_USES_DMA_BACKEND:
            unknown.add(f"{device}({platform or '?'})")
            continue

        major = version_key(profile["osVersion"])[0]
        protection = "SPTM" if profile["flags"] & FLAG_SPTM else "PPL"
        expected = PLATFORM_PROTECTION.get((platform, major))
        if expected and protection != expected:
            findings.error(
                f"{device}|{build}（{platform} / iOS {major}）保护模式为 {protection}，"
                f"预期 {expected}"
            )
        elif not expected:
            findings.note(f"{platform} / iOS {major} 没有保护模式期望值，已跳过")

        # 这份 profile 对这台设备够用吗？判据与 rocket_static_profile_supports_cpu_family
        # 完全一致：非 DMAFail 后端必须有 GFX 偏移。
        has_gfx = bool(profile["flags"] & FLAG_GFX_OFFSETS)
        needs_gfx = not PLATFORM_USES_DMA_BACKEND[platform]
        if needs_gfx and not has_gfx:
            in_window = SUPPORTED_MIN <= version_key(profile["osVersion"]) <= SUPPORTED_MAX
            if in_window:
                unusable_supported.append(f"{device}|{build}")
            else:
                unusable_unsupported[profile["osVersion"]].append(device)
        if not needs_gfx and has_gfx:
            findings.warn(
                f"{device}|{build}（{platform}）走 DMAFail 后端却带着 GFX 偏移，"
                f"多余但无害"
            )

    if unusable_supported:
        findings.error(
            f"支持窗口内有 {len(unusable_supported)} 个条目缺 GFX 偏移，对本机不可用："
            f"{unusable_supported[:10]}"
        )
    for version in sorted(unusable_unsupported, key=version_key):
        devices = unusable_unsupported[version]
        findings.note(
            f"iOS {version}：{len(devices)} 个条目缺 GFX 偏移，运行时按未命中处理"
            f"（设备族 {sorted({d.split(',')[0] for d in devices})}）"
        )
    if unknown:
        findings.note(f"没有 SoC 期望值、已跳过分类检查的设备：{sorted(unknown)}")


def check_geometry_correlation(entries: list, findings: Findings) -> None:
    """地址空间几何相关的常量必须与 T1SZ_BOOT 一一对应。"""
    for key in GEOMETRY_KEYS:
        by_t1sz = defaultdict(Counter)
        for _, _, profile in entries:
            by_t1sz[u64(profile["symbols"]["t1sz_boot"])][u64(profile["offsets"][key])] += 1
        for t1sz, values in sorted(by_t1sz.items()):
            if len(values) > 1:
                findings.error(
                    f"T1SZ_BOOT={t1sz} 下 {key} 有多个取值："
                    + ", ".join(f"0x{v:x}×{n}" for v, n in values.items())
                )
            else:
                value = next(iter(values))
                findings.note(f"T1SZ_BOOT={t1sz} → {key}=0x{value:x}（{values[value]} 条）")

    # PT_INDEX_MAX 跟的是芯片代际而不是 T1SZ，所以只要求同一台设备跨 build 稳定。
    by_device = defaultdict(Counter)
    for device, _, profile in entries:
        by_device[device][u64(profile["offsets"]["kernelConstant.PT_INDEX_MAX"])] += 1
    unstable = {d: dict(v) for d, v in by_device.items() if len(v) > 1}
    if unstable:
        findings.error(f"PT_INDEX_MAX 在同一设备的不同 build 间变动：{unstable}")
    else:
        spread = Counter()
        for values in by_device.values():
            spread[next(iter(values))] += 1
        findings.note(
            "PT_INDEX_MAX 按设备稳定，取值分布："
            + ", ".join(f"0x{v:x}×{n} 台" for v, n in sorted(spread.items()))
        )


def check_build_invariants(entries: list, findings: Findings) -> None:
    """同一 build 下与机型无关的值必须逐位相同。"""
    by_build = defaultdict(list)
    for device, build, profile in entries:
        by_build[build].append((device, profile))

    for build in sorted(by_build):
        members = by_build[build]
        for key in BUILD_INVARIANT_KEYS:
            groups = defaultdict(list)
            for device, profile in members:
                groups[u64(profile["offsets"].get(key, 0))].append(device)
            if len(groups) > 1:
                rendered = "; ".join(
                    f"0x{value:x} ← {len(devices)} 台（{sorted(devices)[:4]}…）"
                    for value, devices in sorted(groups.items())
                )
                findings.error(f"build {build} 的 {key} 在机型间不一致：{rendered}")
            elif 0 in groups:
                findings.error(f"build {build} 的 {key} 全部为 0")


def check_device_stability(entries: list, findings: Findings) -> None:
    """同一台设备、同一大版本内，分类与 GFX 结构偏移应当稳定。

    跨大版本不做要求：SPTM 就是 iOS 17 才在 A15/A16 上启用的，把它当成异常只会把
    真实的平台变化埋进噪声里。
    """
    by_device_major = defaultdict(list)
    for device, build, profile in entries:
        major = version_key(profile["osVersion"])[0]
        by_device_major[(device, major)].append((build, profile))

    for (device, major) in sorted(by_device_major):
        rows = by_device_major[(device, major)]
        classifications = defaultdict(list)
        for build, profile in rows:
            key = (
                bool(profile["flags"] & FLAG_SPTM),
                bool(profile["flags"] & FLAG_GFX_OFFSETS),
                u64(profile["symbols"]["t1sz_boot"]),
                u64(profile["symbols"]["kernel_el"]),
            )
            classifications[key].append(build)
        if len(classifications) > 1:
            rendered = "; ".join(
                f"(SPTM={k[0]}, GFX={k[1]}, T1SZ={k[2]}, EL={k[3]}) ← {sorted(v)}"
                for k, v in classifications.items()
            )
            findings.error(f"{device} 在 iOS {major} 内部分类不稳定：{rendered}")

    by_device = defaultdict(list)
    for device, build, profile in entries:
        if "gfx" in profile:
            by_device[device].append((profile["osVersion"], build, profile))
    for device in sorted(by_device):
        rows = by_device[device]
        if len(rows) < 2:
            continue
        for key in GFX_OFFSET_KEYS:
            values = defaultdict(list)
            for version, build, profile in rows:
                values[u64(profile["gfx"][key])].append(f"{version}({build})")
            if len(values) > 1:
                ordered = sorted(values.items(), key=lambda item: -len(item[1]))
                rendered = "; ".join(
                    f"0x{value:x} ← {sorted(builds)}" for value, builds in ordered
                )
                if any(len(builds) <= 1 for _, builds in ordered[1:]):
                    findings.warn(f"{device} 的 GFX {key} 有孤例取值：{rendered}")
                else:
                    findings.note(f"{device} 的 GFX {key} 随版本变化：{rendered}")


def check_gfx_clusters(entries: list, platforms: dict, findings: Findings, verbose: bool) -> None:
    """同一 build、同一代 GPU 的 12 个 GFX 偏移应当完全一致。"""
    by_build_platform = defaultdict(list)
    for device, build, profile in entries:
        if "gfx" not in profile:
            continue
        platform = platforms.get(device)
        if not platform:
            continue
        by_build_platform[(build, platform)].append((device, profile))

    for (build, platform), members in sorted(by_build_platform.items()):
        signatures = defaultdict(list)
        for device, profile in members:
            signature = tuple(u64(profile["gfx"][key]) for key in GFX_OFFSET_KEYS)
            signatures[signature].append(device)
        if len(signatures) > 1:
            rendered = "; ".join(
                f"{sorted(devices)} → " + ",".join(f"0x{v:x}" for v in signature)
                for signature, devices in signatures.items()
            )
            findings.error(f"build {build} / {platform} 的 GFX 偏移在同代设备间分裂：{rendered}")

    # 地址类字段必须落在本 kernelcache 的地址窗口内。
    for device, build, profile in entries:
        if "gfx" not in profile:
            continue
        base = u64(profile["staticKernelBase"])
        for key in GFX_ADDRESS_KEYS:
            value = u64(profile["gfx"][key])
            if value == 0:
                findings.error(f"{device}|{build}: GFX {key} 为 0")
            elif value < base or value - base > MAX_SYMBOL_SPAN:
                findings.error(
                    f"{device}|{build}: GFX {key} = 0x{value:x} 落在内核映像之外"
                    f"（基址 0x{base:x}）"
                )
        for key in GFX_OFFSET_KEYS:
            value = u64(profile["gfx"][key])
            if value == 0:
                findings.error(f"{device}|{build}: GFX {key} 为 0")
            elif value > 0x100000:
                findings.warn(f"{device}|{build}: GFX {key} = 0x{value:x} 大得反常")

    if verbose:
        for (build, platform), members in sorted(by_build_platform.items()):
            device, profile = members[0]
            rendered = ",".join(f"0x{u64(profile['gfx'][k]):x}" for k in GFX_OFFSET_KEYS)
            print(f"    {build:<8} {platform:<8} {len(members):2}台  {rendered}")


def check_key_sets(profiles: list, findings: Findings) -> None:
    key_sets = Counter()
    set_lists = Counter()
    for profile in profiles:
        key_sets[frozenset(profile["offsets"])] += 1
        set_lists[tuple(profile["offsetSets"])] += 1

    findings.note(f"偏移字典的 key 集合共有 {len(key_sets)} 种")
    reference = max(key_sets, key=lambda k: key_sets[k])
    for keys, count in key_sets.items():
        if keys == reference:
            continue
        missing = sorted(reference - keys)
        extra = sorted(keys - reference)
        # perfkrw 只在 iOS 15/16 受 XPF 支持，多出这四个键是版本差异而非缺陷。
        perfkrw = {
            "kernelSymbol.cdevsw",
            "kernelSymbol.perfmon_dev_open",
            "kernelSymbol.perfmon_devices",
            "kernelSymbol.vn_kqfilter",
        }
        if not missing and set(extra) == perfkrw:
            findings.note(f"{count} 条 profile 额外带有 perfkrw 的四个键（iOS 15/16 专属）")
        else:
            findings.warn(
                f"{count} 条 profile 的 key 集合与主流不同：缺 {missing}，多 {extra}"
            )
    for sets, count in set_lists.items():
        findings.note(f"XPF set 组合 {list(sets)} ← {count} 条")


def check_duplicates(table: dict, entries: list, findings: Findings) -> None:
    """不同 kernelcache 不该产出完全相同的 profile。"""
    by_signature = defaultdict(set)
    for position, profile in enumerate(table["profiles"]):
        signature = json.dumps(
            {k: v for k, v in profile.items() if k != "kernelcacheSHA256"},
            sort_keys=True,
        )
        by_signature[signature].add(profile["kernelcacheSHA256"])

    digest_to_builds = defaultdict(set)
    for device, build, profile in entries:
        digest_to_builds[profile["kernelcacheSHA256"]].add(build)
    collisions = Counter()
    for digests in by_signature.values():
        if len(digests) < 2:
            continue
        builds = frozenset(b for d in digests for b in digest_to_builds[d])
        collisions[tuple(sorted(builds))] += 1
    for builds, count in sorted(collisions.items()):
        if len(builds) == 1:
            findings.error(
                f"build {builds[0]} 内有 {count} 组不同 kernelcache 产出了相同 profile"
            )
        else:
            # 同一份内核二进制被两个 build 各自签名分发，IM4P 外壳不同、载荷相同。
            findings.note(
                f"{count} 组 profile 被 {list(builds)} 共用，"
                f"即这些 build 之间内核二进制未变"
            )

    # 同一 build 的同一台设备只应有一条。
    seen = Counter((device, build) for device, build, _ in entries)
    duplicates = [key for key, count in seen.items() if count > 1]
    if duplicates:
        findings.error(f"重复的 设备|Build 条目：{duplicates[:10]}")


def check_version_progression(entries: list, findings: Findings) -> None:
    """同一台设备上，XNU 版本应当随 iOS 版本单调不降。

    profile 里的 osVersion 是 kernelcache 自报的，只到次版本：16.7、16.7.1、16.7.2
    三个 build 都写 16.7（同 20F75 写 16.5）。所以同一 osVersion 内必须再按 build
    排序才是真实先后，否则 20H115 会被排在 20H19 之前，凭空造出一次版本倒退。
    """
    by_device = defaultdict(list)
    for device, build, profile in entries:
        by_device[device].append((profile["osVersion"], build, u64(profile["xnuVersionPacked"])))
    for device in sorted(by_device):
        rows = sorted(by_device[device], key=lambda r: (version_key(r[0]), build_key(r[1])))
        for (previous_version, previous_build, previous), (version, build, current) in zip(
            rows, rows[1:]
        ):
            if current < previous:
                findings.error(
                    f"{device}: {previous_version}({previous_build}) 的 XNU 版本"
                    f" {previous:#x} 高于 {version}({build}) 的 {current:#x}"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description="审计内置 kernelcache 偏移表")
    parser.add_argument("--table", default=DEFAULT_TABLE)
    parser.add_argument("--corpus", default=DEFAULT_CORPUS)
    parser.add_argument("--verbose", action="store_true", help="打印分组明细")
    arguments = parser.parse_args()

    with open(arguments.table, "rb") as stream:
        table = plistlib.load(stream)

    profiles = table["profiles"]
    entries = [
        (key.split("|", 1)[0], key.split("|", 1)[1], profiles[position])
        for key, position in table["index"].items()
    ]
    platforms = load_platforms(arguments.corpus)
    corpus_pairs = load_corpus_pairs(arguments.corpus)

    print(
        f"表：{arguments.table}\n"
        f"  schema={table['schema']} profileVersion={table['profileVersion']} "
        f"generated={table['generatedAt']}\n"
        f"  {len(table['index'])} 个 设备|Build，{len(profiles)} 个去重 profile，"
        f"{os.path.getsize(arguments.table) / 1024:.1f} KiB\n"
    )

    findings = Findings()
    check_coverage(table, corpus_pairs, findings)
    check_scalar_domains(profiles, findings)
    check_integrity_metadata(profiles, findings)
    check_platform_expectations(entries, platforms, findings)
    check_geometry_correlation(entries, findings)
    check_build_invariants(entries, findings)
    check_device_stability(entries, findings)
    check_gfx_clusters(entries, platforms, findings, arguments.verbose)
    check_key_sets(profiles, findings)
    check_duplicates(table, entries, findings)
    check_version_progression(entries, findings)

    if findings.notes:
        print("说明：")
        for note in findings.notes:
            print(f"  · {note}")
        print()
    if findings.warnings:
        print(f"警告（{len(findings.warnings)}）：")
        for warning in findings.warnings:
            print(f"  ! {warning}")
        print()
    if findings.errors:
        print(f"错误（{len(findings.errors)}）：")
        for error in findings.errors:
            print(f"  ✗ {error}")
        print()
        return 1

    print("未发现偏离预期的条目。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
