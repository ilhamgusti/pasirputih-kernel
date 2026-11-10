# pasirputih-kernel

Guest kernel for [Firecracker](https://github.com/firecracker-microvm/firecracker)
microVMs, used by pasirputih's sandboxes and code runners. It is upstream
Linux (longterm 6.1, pinned and sha256-checked) built with Firecracker's own
CI guest config plus a small fragment that adds what VPNs need inside a VM:

- **WireGuard** in the kernel (`CONFIG_WIREGUARD`)
- **TUN** (`/dev/net/tun`) for OpenVPN, wireguard-go, Tailscale, ...
- policy routing, iptables raw/connmark and nftables, which `wg-quick` and
  Tailscale use for full-tunnel routing and kill switches

Every VM has its own kernel and network stack, so each one can run its own
VPN without touching the host or other VMs.

## Download

Releases have `vmlinux-<version>-aarch64` (an arm64 `Image`) and
`vmlinux-<version>-x86_64` (ELF `vmlinux`), their `.config` and `SHA256SUMS`:

```bash
gh release download -R ilhamgusti/pasirputih-kernel --pattern '*aarch64' --pattern SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

Then boot it like any Firecracker guest kernel (`kernel_image_path`), or for
pasirputih: `PP_KERNEL=/path/vmlinux-6.1.192-pp1-aarch64`.

## Build

```bash
./build.sh            # this machine's arch; or: ./build.sh aarch64 | x86_64
ls out/               # vmlinux-6.1.192-pp1-<arch>, config-..., SHA256SUMS
```

Needs gcc, make, bc, bison, flex, libelf-dev, libssl-dev (Debian/Ubuntu
names). Cross-compile with `CROSS_COMPILE=aarch64-linux-gnu-`. A Raspberry Pi
5 takes about half an hour for aarch64.

`build.sh` downloads the kernel from kernel.org and checks its sha256,
starts from `configs/microvm-kernel-ci-<arch>-6.1.config`, merges
`configs/pasirputih.config`, and fails if any option of the fragment did not
make it into the final config (a missing dependency would drop it silently).
`uname -r` is `<kernel version>-pp<PP_REV>`.

CI builds both architectures on every push; a `v*` tag publishes a release.

## Sources

- `configs/microvm-kernel-ci-{aarch64,x86_64}-6.1.config`: copied unchanged
  from firecracker-microvm/firecracker at `v1.17.0`
  (`resources/guest_configs/`), sha256
  `5c73202d00b5591ad987d9f808208a318e317fd32dbc17de613c5a93fabe2939`
  (aarch64) and
  `153ca1b40f3312bfb40b7587b471ea548a915f98f480f0d0892a1537957a2147`
  (x86_64). Firecracker is Apache-2.0.
- Linux itself is GPL-2.0; the released kernels are built from the unmodified
  kernel.org tarball named in `build.sh`, so that tarball plus the release's
  `config-*` file is the complete corresponding source.

## Updating

- New 6.1 point release: change `KERNEL_VERSION` and `KERNEL_SHA256` in
  `build.sh` (from kernel.org's `sha256sums.asc`), reset `PP_REV=1`.
- Config change: edit `configs/pasirputih.config`, bump `PP_REV`.
- Then tag `v<kernel version>-pp<PP_REV>`, e.g. `v6.1.192-pp1`.

Scripts are MIT (see LICENSE).
