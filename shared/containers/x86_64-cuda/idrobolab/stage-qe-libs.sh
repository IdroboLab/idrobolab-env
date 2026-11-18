#!/usr/bin/env bash
# Copy the runtime shared libs of the QE executables in DIST/bin into DIST/lib,
# and fail unless every copied NVIDIA HPC SDK file is a Run-Time File and no
# library with an NVIDIA name comes from outside the SDK.
# Usage: stage-qe-libs.sh SDKROOT DIST RPATH     (run by install-qe-gpu.sh)
#
# The HPC SDK license (docs/THIRD-PARTY.md) lets an application bundle only the
# files in the SDK's directories whose names begin with REDIST. A library whose
# real path is under SDKROOT must therefore also be the real path of a file
# under such a directory, or a byte-identical copy of one of the same name; any
# other is listed and fails the build. Libraries outside SDKROOT (the builder
# image's Ubuntu libraries) are listed, not checked, except that a library with
# an NVIDIA CUDA or NCCL name there fails the build too: it is not an SDK file
# and nothing here has verified its license. The staged SDK files are listed in
# DIST/NVIDIA-REDIST-FILES.txt (name, real path in the SDK, and for a copy the
# REDIST path it matched).
# The SDK files are copied unmodified and never patched; the QE executables and
# the other staged libraries get RPATH, so they find each other without an
# image-wide LD_LIBRARY_PATH (which would shadow the base image's CUDA libs).
set -euo pipefail

SDKROOT="$(readlink -f "$1")"
DIST="$2"
RPATH="$3"
[ -d "$SDKROOT" ] || { echo "ERROR: SDK root $SDKROOT is not a directory" >&2; exit 1; }
redist="$(mktemp)"
allowed="$(mktemp)"
wanted="$(mktemp)"

# Every file under a REDIST* directory, and the real paths of them. An incomplete
# listing (find error) can only make the check stricter, so its status is ignored.
{ find -L "$SDKROOT" -type d -name 'REDIST*' -print0 2>/dev/null \
    | xargs -0 -r -I{} find -L {} -type f -print0 2>/dev/null \
    | tr '\0' '\n' > "$redist"; } || true
xargs -r -d '\n' readlink -f < "$redist" | sort -u > "$allowed"
echo ">> $(wc -l < "$allowed") files under REDIST* directories of ${SDKROOT}"
[ -s "$allowed" ] || { echo "ERROR: no files under a REDIST* directory of ${SDKROOT}" >&2; exit 1; }

# Whether SDK file $1 (real path) is a Run-Time File: a real path under REDIST*, or a
# copy of the same content and name there (REDIST may hold copies, not symlinks).
in_redist() {
    local real="$1" n f
    matched=""
    grep -qxF "$real" "$allowed" && return 0
    for n in "$(basename "$2")" "$(basename "$real")"; do
        while read -r f; do cmp -s "$f" "$real" && { matched="$f"; return 0; }; done \
            < <(awk -F/ -v n="$n" '$NF==n' "$redist")
    done
    return 1
}

# Transitive .so deps of every QE executable (ldd is recursive).
for exe in "${DIST}"/bin/*.x; do
    [ -e "$exe" ] || continue
    ldd "$exe" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u > "$wanted"

mkdir -p "${DIST}/lib"
: > "${DIST}/NVIDIA-REDIST-FILES.txt"
bad=()
sdk_libs=" "
while read -r lib; do
    # core system libs come from the final image's base; libcuda from the driver
    case "$lib" in
        */libc.so*|*/libm.so*|*/libmvec.so*|*/libpthread.so*|*/libdl.so*|*/librt.so*|\
        */libgcc_s.so*|*/libstdc++.so*|*/ld-linux*|*/libresolv*|*/libutil*) continue ;;
        */libcuda.so*) continue ;;
    esac
    real="$(readlink -f "$lib")"
    case "$real" in
        "$SDKROOT"/*)
            if in_redist "$real" "$lib"; then
                echo "SDK REDIST: $lib -> $real"
                sdk_libs+="$(basename "$lib") "
                echo "$(basename "$lib")  ${real#"$SDKROOT"/}${matched:+  ${matched#"$SDKROOT"/}}" >> "${DIST}/NVIDIA-REDIST-FILES.txt"
            else
                echo "SDK NOT REDIST: $lib -> $real"
                bad+=("not a REDIST file: $lib -> $real")
                continue
            fi ;;
        *)
            # a list of NVIDIA library names, not a license check
            case "$(basename "$lib")" in
                libcudart*|libcublas*|libcufft*|libcusolver*|libcusparse*|libcurand*|libnv*|libnccl*|\
                libcudnn*|libcupti*|libnpp*|libcufile*|libcutensor*)
                    echo "NVIDIA outside SDK: $lib"
                    bad+=("NVIDIA library outside the SDK: $lib")
                    continue ;;
            esac
            echo "outside SDK: $lib" ;;
    esac
    cp -L "$lib" "${DIST}/lib/"
done < "$wanted"

if [ "${#bad[@]}" -gt 0 ]; then
    echo "ERROR: ${#bad[@]} NVIDIA library(ies) that the image may not redistribute:" >&2
    printf '  %s\n' "${bad[@]}" >&2
    exit 1
fi

# --force-rpath: DT_RPATH on the executables also serves the lookups of SDK libs
# that carry no RUNPATH of their own.
for f in "${DIST}"/bin/*.x; do
    [ -e "$f" ] || continue
    patchelf --force-rpath --set-rpath "$RPATH" "$f" || echo "WARN: patchelf failed on $f"
done
for f in "${DIST}"/lib/*.so*; do
    [ -e "$f" ] || continue
    case "$sdk_libs" in *" $(basename "$f") "*) continue ;; esac
    patchelf --set-rpath "$RPATH" "$f" || echo "WARN: patchelf failed on $f"
done
