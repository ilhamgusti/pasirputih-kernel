#!/usr/bin/env bash
# Builds the pasirputih guest kernel: upstream Linux (longterm 6.1, pinned
# and sha256-checked) with Firecracker's CI guest config plus
# configs/pasirputih.config.
#
#   ./build.sh [aarch64|x86_64]     (default: this machine's arch)
#
# Output in out/ (OUT=...):
#   vmlinux-<version>-<arch>        the kernel Firecracker boots (arm64: Image)
#   config-<version>-<arch>         its .config
#   SHA256SUMS
# Cross-compiling: set CROSS_COMPILE (e.g. aarch64-linux-gnu-).
set -euo pipefail

KERNEL_VERSION=6.1.192
KERNEL_SHA256=1e88e317e20dbc79a2cb9e3d9667e908b262d12e76eb66eed894c5460eb87fca
# Bump when configs/ change; part of the version (uname -r: 6.1.192-pp1).
PP_REV=1

here=$(cd "$(dirname "$0")" && pwd)
arch=${1:-$(uname -m)}
case $arch in
aarch64 | arm64) arch=aarch64 karch=arm64 target=Image image=arch/arm64/boot/Image ;;
x86_64 | amd64) arch=x86_64 karch=x86_64 target=vmlinux image=vmlinux ;;
*) echo "unsupported arch $arch" >&2; exit 2 ;;
esac
version=$KERNEL_VERSION-pp$PP_REV
out=${OUT:-$here/out}
work=${WORK:-$here/build}
jobs=${JOBS:-$(nproc)}
src=$work/linux-$KERNEL_VERSION-$arch
mkdir -p "$work" "$out"

tarball=$work/linux-$KERNEL_VERSION.tar.xz
if ! echo "$KERNEL_SHA256  $tarball" | sha256sum -c --status 2>/dev/null; then
	echo ">> download linux-$KERNEL_VERSION"
	curl -fsSL -o "$tarball.part" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz"
	echo "$KERNEL_SHA256  $tarball.part" | sha256sum -c --quiet
	mv "$tarball.part" "$tarball"
fi
if [ ! -d "$src" ]; then
	echo ">> extract"
	rm -rf "$src.part" && mkdir "$src.part"
	tar -xJf "$tarball" -C "$src.part" --strip-components=1
	mv "$src.part" "$src"
fi

echo ">> config"
cp "$here/configs/microvm-kernel-ci-$arch-6.1.config" "$src/.config"
mk() { make -C "$src" ARCH=$karch ${CROSS_COMPILE:+CROSS_COMPILE=$CROSS_COMPILE} "$@"; }
(cd "$src" && ARCH=$karch scripts/kconfig/merge_config.sh -m -O "$src" .config "$here/configs/pasirputih.config" > /dev/null)
"$src/scripts/config" --file "$src/.config" --set-str LOCALVERSION "-pp$PP_REV" --disable LOCALVERSION_AUTO
mk -s olddefconfig
# Every line of the fragment must have survived olddefconfig (a missing
# dependency silently drops an option).
missing=0
while IFS= read -r line; do
	case $line in CONFIG_*) ;; *) continue ;; esac
	if ! grep -qxF "$line" "$src/.config"; then
		echo "!! $line did not stick: $(grep -E "^(# )?${line%%=*}[= ]" "$src/.config" || echo absent)" >&2
		missing=1
	fi
done < "$here/configs/pasirputih.config"
[ $missing = 0 ] || exit 1

echo ">> build $target with $jobs jobs"
export KBUILD_BUILD_USER=pasirputih KBUILD_BUILD_HOST=pasirputih-kernel
export KBUILD_BUILD_TIMESTAMP=${KBUILD_BUILD_TIMESTAMP:-$(LC_ALL=C date -u -R -d @"${SOURCE_DATE_EPOCH:-$(git -C "$here" log -1 --format=%ct 2>/dev/null || date +%s)}")}
mk -s -j"$jobs" $target
got=$(mk -s kernelrelease)
[ "$got" = "$version" ] || { echo "!! kernelrelease $got, want $version" >&2; exit 1; }

cp "$src/$image" "$out/vmlinux-$version-$arch"
cp "$src/.config" "$out/config-$version-$arch"
(cd "$out" && sha256sum vmlinux-* config-* > SHA256SUMS)
echo ">> $out/vmlinux-$version-$arch"
cat "$out/SHA256SUMS"
