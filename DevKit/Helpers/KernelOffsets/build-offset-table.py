#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 kernelcache 语料库生成 Relaxin 内置偏移表。

对语料库中每个 kernelcache 运行 rlx-dump-kernel-offsets（它编译的是引擎自己的
StaticProfile.c / Patterns.c，因此结果与设备端逐位一致），把输出汇总成一张按
"<设备标识>|<系统 Build>" 索引的 XML plist，供 Task02 直接查表。

    ./build-offset-table.py                       # 默认语料库与输出路径
    ./build-offset-table.py --corpus ~/kernelcaches
    ./build-offset-table.py --min-version 16.5.1 --max-version 17.3.1
    ./build-offset-table.py --report              # 只打印覆盖率，不写文件

默认收录语料库里的全部 arm64e kernelcache。Task01 目前只放行 iOS 16.5.1 ~ 17.3.1，
区间外的条目暂时走不到 Task02；但表本身不做这个裁剪，多出来的条目只值几十 KB，
而支持窗口一旦放宽就不必重新生成。用 --min-version / --max-version 可以收窄。
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import os
import plistlib
import subprocess
import sys
from dataclasses import dataclass

# --------------------------------------------------------------------------- #
# 常量
# --------------------------------------------------------------------------- #

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DEFAULT_CORPUS = os.path.expanduser("~/kernelcaches")
DEFAULT_TOOL = os.path.join(ROOT, "build", "KernelOffsets", "rlx-dump-kernel-offsets")
DEFAULT_OUTPUT = os.path.join(ROOT, "Relaxin", "Resources", "KernelOffsets.plist")

# 与 RLXKernelOffsetTable.m 中的解析器共用的格式号。改动布局必须同时改两处。
TABLE_SCHEMA = 1

# 与 ROCKET_STATIC_PROFILE_VERSION 对应。
PROFILE_VERSION = 1

# 与 RLXKernelOffsetTable.m 的 RLXKernelOffsetProfileFlag 对应。
FLAG_ARM64E = 1 << 0
FLAG_SPTM = 1 << 1
FLAG_FILESET = 1 << 2
FLAG_PPL_TEXT = 1 << 3
FLAG_GFX_OFFSETS = 1 << 4

SYMBOL_KEYS = (
    "cpu_ttep",
    "gVirtBase",
    "gPhysBase",
    "gPhysSize",
    "ptov_table",
    "allproc",
    "vm_map_pmap",
    "arm_tt_l1_index_mask",
    "t1sz_boot",
    "kernel_el",
)

GFX_KEYS = (
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
    "ioGpuUserClientTypeStaticAddress",
    "mobileFramebufferUserClientTypeStaticAddress",
    "agxSubmitHandlerVtableAddress",
)


def signed64(value: int) -> int:
    """
    plist 的整数是有符号的，而内核地址会超过 Int64 最大值。

    存二进制补码，读端用 -unsignedLongLongValue 取回原值：位模式不变，两边都不
    需要额外的约定。
    """
    if value >= 1 << 63:
        return value - (1 << 64)
    return value


def version_key(version: str) -> tuple:
    parts = []
    for component in version.split("."):
        try:
            parts.append(int(component))
        except ValueError:
            parts.append(0)
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)


# --------------------------------------------------------------------------- #
# 语料库
# --------------------------------------------------------------------------- #


@dataclass
class Kernelcache:
    version: str
    build: str
    path: str
    sha256: str
    devices: tuple


def load_corpus(corpus: str, min_version: str, max_version: str) -> list:
    index_path = os.path.join(corpus, "index.json")
    if not os.path.isfile(index_path):
        sys.exit(f"[-] 语料库索引缺失: {index_path}")

    with open(index_path, "r", encoding="utf-8") as stream:
        index = json.load(stream)

    low = version_key(min_version)
    high = version_key(max_version)

    entries = []
    for entry in index.get("kernelcaches", []):
        version = entry.get("version", "")
        if not (low <= version_key(version) <= high):
            continue
        if entry.get("arch") != "arm64e":
            continue
        path = os.path.join(corpus, entry["path"])
        if not os.path.isfile(path):
            print(f"[!] 跳过缺失文件: {path}", file=sys.stderr)
            continue
        entries.append(
            Kernelcache(
                version=version,
                build=entry["build"],
                path=path,
                sha256=entry["sha256"],
                devices=tuple(entry.get("devices", [])),
            )
        )
    return entries


# --------------------------------------------------------------------------- #
# 提取
# --------------------------------------------------------------------------- #


def dump_kernelcache(tool: str, path: str) -> dict:
    result = subprocess.run(
        [tool, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(message or f"退出码 {result.returncode}")
    return json.loads(result.stdout.decode("utf-8"))


def profile_from_dump(dump: dict, sha256: str) -> dict:
    if dump.get("profileVersion") != PROFILE_VERSION:
        raise RuntimeError(
            f"profileVersion={dump.get('profileVersion')} 与生成器的 {PROFILE_VERSION} 不符"
        )

    flags = 0
    if dump["isArm64e"]:
        flags |= FLAG_ARM64E
    if dump["isSPTMDevice"]:
        flags |= FLAG_SPTM
    if dump["isFileset"]:
        flags |= FLAG_FILESET
    if dump["hasPPLTextSection"]:
        flags |= FLAG_PPL_TEXT
    if dump["hasGFXOffsets"]:
        flags |= FLAG_GFX_OFFSETS

    offsets = {}
    for key, value in dump["offsetDictionary"].items():
        # 引擎交给 libjailbreak 的字典只有 uint64；出现别的类型说明 XPF 的集合
        # 变了，宁可让生成失败也不要悄悄丢一个偏移。
        if value["type"] != "uint64":
            raise RuntimeError(f"偏移 {key} 的类型是 {value['type']}，不是 uint64")
        offsets[key] = signed64(value["value"])

    profile = {
        "kernelcacheSHA256": sha256,
        "xnuBuild": dump["xnuBuild"],
        "osVersion": dump["osVersion"],
        "flags": flags,
        "staticKernelBase": signed64(dump["staticKernelBase"]),
        "sptmArgs": signed64(dump["sptmArgs"]),
        "xnuVersionPacked": signed64(dump["xnuVersionPacked"]),
        "symbols": {key: signed64(dump["symbols"][key]) for key in SYMBOL_KEYS},
        "offsetSets": list(dump["offsetSets"]),
        "offsets": offsets,
    }
    if dump["hasGFXOffsets"]:
        profile["gfx"] = {key: signed64(dump["gfxOffsets"][key]) for key in GFX_KEYS}
    return profile


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #


def main() -> int:
    parser = argparse.ArgumentParser(
        description="生成 Relaxin 内置 kernelcache 偏移表",
    )
    parser.add_argument("--corpus", default=DEFAULT_CORPUS, help="kernelcache 语料库目录")
    parser.add_argument("--tool", default=DEFAULT_TOOL, help="rlx-dump-kernel-offsets 路径")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="输出 plist 路径")
    parser.add_argument("--min-version", default="0", help="最低 iOS 版本（含）")
    parser.add_argument("--max-version", default="99", help="最高 iOS 版本（含）")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--report", action="store_true", help="只打印覆盖率，不写文件")
    arguments = parser.parse_args()

    if not os.access(arguments.tool, os.X_OK):
        sys.exit(
            f"[-] 找不到提取工具: {arguments.tool}\n"
            f"    先运行 make -C DevKit/Helpers/KernelOffsets"
        )

    entries = load_corpus(arguments.corpus, arguments.min_version, arguments.max_version)
    if not entries:
        sys.exit("[-] 语料库在给定版本区间内没有 arm64e kernelcache")

    # 同一个 kernelcache 会出现在多个 IPSW 里；按内容去重后每个只提取一次。
    unique = {}
    for entry in entries:
        unique.setdefault(entry.sha256, entry)
    print(
        f"[+] 语料库 {len(entries)} 条记录 / {len(unique)} 个不同 kernelcache "
        f"（{arguments.min_version} ~ {arguments.max_version}）",
        file=sys.stderr,
    )

    dumps = {}
    failures = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=arguments.jobs) as pool:
        futures = {
            pool.submit(dump_kernelcache, arguments.tool, entry.path): entry
            for entry in unique.values()
        }
        completed = 0
        for future in concurrent.futures.as_completed(futures):
            entry = futures[future]
            completed += 1
            try:
                dumps[entry.sha256] = profile_from_dump(future.result(), entry.sha256)
            except Exception as error:  # noqa: BLE001 — 逐条记录，不中断整批
                failures[entry.sha256] = (entry, str(error))
            print(
                f"\r    {completed}/{len(unique)}  失败 {len(failures)}",
                end="",
                file=sys.stderr,
            )
    print("", file=sys.stderr)

    for entry, message in failures.values():
        print(
            f"[!] {entry.version}/{entry.build} {os.path.basename(entry.path)}: {message}",
            file=sys.stderr,
        )

    # 内容相同的 profile 合并成一条，索引指向同一下标。
    profiles = []
    profile_index = {}
    index = {}
    conflicts = []
    covered_versions = {}

    for entry in sorted(entries, key=lambda item: (version_key(item.version), item.build)):
        profile = dumps.get(entry.sha256)
        if profile is None:
            continue
        fingerprint = json.dumps(profile, sort_keys=True)
        position = profile_index.get(fingerprint)
        if position is None:
            position = len(profiles)
            profile_index[fingerprint] = position
            profiles.append(profile)
        for device in entry.devices:
            key = f"{device}|{entry.build}"
            existing = index.get(key)
            if existing is not None and existing != position:
                conflicts.append(key)
                continue
            index[key] = position
            covered_versions.setdefault(entry.version, set()).add(device)

    conflicts = sorted(set(conflicts))
    for key in conflicts:
        print(f"[!] {key} 有两个不同的 profile，拒绝生成", file=sys.stderr)

    print(
        f"[+] {len(index)} 个 设备|Build 条目，{len(profiles)} 个去重后的 profile",
        file=sys.stderr,
    )
    for version in sorted(covered_versions, key=version_key):
        print(
            f"    {version:<8} {len(covered_versions[version])} 台设备",
            file=sys.stderr,
        )

    if arguments.report:
        return 1 if failures or conflicts else 0

    if failures or conflicts:
        print("[-] 提取失败或索引冲突，保留现有偏移表不变", file=sys.stderr)
        return 1

    table = {
        "schema": TABLE_SCHEMA,
        "profileVersion": PROFILE_VERSION,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat(),
        "source": (
            f"{os.path.basename(os.path.normpath(arguments.corpus))} "
            f"iOS {arguments.min_version}-{arguments.max_version}"
        ),
        "profiles": profiles,
        "index": index,
    }

    os.makedirs(os.path.dirname(arguments.output), exist_ok=True)
    with open(arguments.output, "wb") as stream:
        plistlib.dump(table, stream, fmt=plistlib.FMT_XML, sort_keys=True)
    size = os.path.getsize(arguments.output)
    print(f"[+] 已写入 {arguments.output} ({size / 1024:.1f} KiB)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
