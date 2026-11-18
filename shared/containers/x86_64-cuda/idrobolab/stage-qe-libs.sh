#!/usr/bin/env bash
# Copy the runtime shared libs of the QE executables in DIST/bin into DIST/lib,
# and fail unless every copied NVIDIA HPC SDK file is a Run-Time File.
# Usage: stage-qe-libs.sh SDKROOT DIST     (run by install-qe-gpu.sh)
#
# The HPC SDK license (docs/THIRD-PARTY.md) lets an application bundle only the
# files in the SDK's directories whose names begin with REDIST. A library whose
# real path is under SDKROOT must therefore also be the real path of a file
# under such a directory; any other is listed and fails the build. Libraries
# outside SDKROOT (the builder image's Ubuntu libraries) are listed, not checked.
set -euo pipefail

SDKROOT="$(readlink -f "$1")"
DIST="$2"
allowed="$(mktemp)"
wanted="$(mktemp)"

# Real paths of every file under a REDIST* directory. An incomplete listing (find
# error) can only make the check stricter, so its status is ignored.
{ find -L "$SDKROOT" -type d -name 'REDIST*' -print0 2>/dev/null \
    | xargs -0 -r -I{} find -L {} -type f -print0 2>/dev/null \
    | xargs -0 -r readlink -f | sort -u > "$allowed"; } || true
echo ">> $(wc -l < "$allowed") files under REDIST* directories of ${SDKROOT}"

# Transitive .so deps of every QE executable (ldd is recursive).
for exe in "${DIST}"/bin/*.x; do
    [ -e "$exe" ] || continue
    ldd "$exe" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u > "$wanted"

mkdir -p "${DIST}/lib"
bad=()
while read -r lib; do
    # core system libs come from the final image's base; libcuda from the driver
    case "$lib" in
        */libc.so*|*/libm.so*|*/libmvec.so*|*/libpthread.so*|*/libdl.so*|*/librt.so*|\
        */libgcc_s.so*|*/libstdc++.so*|*/ld-linux*|*/libresolv*|*/libutil*|*/librt.so*) continue ;;
        */libcuda.so*) continue ;;
    esac
    real="$(readlink -f "$lib")"
    case "$real" in
        "$SDKROOT"/*)
            if grep -qxF "$real" "$allowed"; then
                echo "SDK REDIST: $lib -> $real"
            else
                echo "SDK NOT REDIST: $lib -> $real"
                bad+=("$lib -> $real")
                continue
            fi ;;
        *) echo "outside SDK: $lib" ;;
    esac
    cp -L "$lib" "${DIST}/lib/"
done < "$wanted"

if [ "${#bad[@]}" -gt 0 ]; then
    echo "ERROR: ${#bad[@]} library(ies) from the NVIDIA HPC SDK are not under a REDIST* directory:" >&2
    printf '  %s\n' "${bad[@]}" >&2
    exit 1
fi
