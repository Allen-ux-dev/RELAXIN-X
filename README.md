# RELAXIN-X

RELAXIN-X is a maintained experimental branch built on the public Relaxin snapshot. It keeps the upstream jailbreak engine and RootHide foundation while adding runtime/backend abstraction, recovery and repair orchestration, package-manager compatibility work, and a more reliable local build pipeline.

The current bundled stable runtime profile follows the support contract of the public Relaxin snapshot. Product UI and recovery logic are capability-driven rather than tied directly to a hard-coded OS-version branch, so additional runtime profiles and backends can be added without rewriting the upper layers.

Build and package locally with the top-level Makefile or `BuildIPA.command`.

## Development

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

## RELAXIN-X Maintainer

- [Allen-ux-dev](https://github.com/Allen-ux-dev)

The RELAXIN-X maintainer block is intentionally separate from the upstream roster so branch maintenance and original-project attribution remain unambiguous.

## Original Relaxin / Upstream

RELAXIN-X is based on the public Relaxin snapshot from OwnGoal Studio. Original upstream project credits remain preserved:

- [@Lakr233](https://x.com/Lakr233)
- [@0x88FFA357](https://x.com/0x88FFA357)
- [@82Flex](https://x.com/82Flex)
- [@roothideDev](https://x.com/roothideDev)
- [@pattern_F_](https://x.com/pattern_F_)

RELAXIN-X also uses external software and binaries during the jailbreak; refer to the Software License section inside the app.

## License

The upstream Relaxin snapshot is licensed under the MIT License. See `LICENSE` for details. Third-party components retain their respective licenses.
