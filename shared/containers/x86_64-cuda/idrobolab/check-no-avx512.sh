#!/usr/bin/env bash
# Fail when an ELF file or static archive under DIR contains AVX-512 instructions, so that
# what the image ships runs on CPUs without AVX-512 (AMD Milan on Delta and Perlmutter).
# Usage: check-no-avx512.sh DIR     (run on the QE staging directory by the Dockerfile)
#
# An AVX-512 instruction is one that names a zmm register, an opmask register (k0-k7) or
# one of the registers xmm16-31/ymm16-31 that only the EVEX encoding reaches.
# shortcut: EVEX code that names only xmm0-15/ymm0-15 (AVX-512VL) is not detected; a build
# for an AVX-512 host emits zmm throughout, which is what this check is for.
# The NVIDIA HPC SDK files that stage-qe-libs.sh lists in DIR/NVIDIA-REDIST-FILES.txt
# (first column: the file name in DIR/lib) are counted and reported, not checked: they are
# NVIDIA's prebuilt runtime libraries, not built here.
set -euo pipefail

DIR="$1"
[ -d "$DIR" ] || { echo "ERROR: $DIR is not a directory" >&2; exit 1; }
sdk=" "
[ -f "${DIR}/NVIDIA-REDIST-FILES.txt" ] && sdk+="$(awk '{printf "%s ", $1}' "${DIR}/NVIDIA-REDIST-FILES.txt")"

dis="$(mktemp)"
trap 'rm -f "$dis"' EXIT
bad=0
checked=0
while IFS= read -r -d '' f; do
    case "$(head -c 7 "$f" | od -An -c | tr -d ' ')" in
        177ELF*|'!<arch>') ;;
        *) continue ;;
    esac
    objdump -d "$f" > "$dis"   # a failing objdump stops the script (set -e)
    n="$(grep -c -E '%(zmm[0-9]|k[0-7]\b|[xy]mm(1[6-9]|2[0-9]|3[01])\b)' "$dis" || [ $? -eq 1 ])"
    case "$sdk" in
        *" $(basename "$f") "*) echo "SDK file, not checked: ${f#"$DIR"/}: $n AVX-512 instructions"; continue ;;
    esac
    checked=$((checked + 1))
    if [ "$n" -gt 0 ]; then
        echo "AVX-512: ${f#"$DIR"/}: $n instructions"
        bad=$((bad + 1))
    fi
done < <(find "$DIR" -type f -print0 | sort -z)

echo ">> ${checked} files checked for AVX-512 under ${DIR}"
[ "$checked" -gt 0 ] || { echo "ERROR: no ELF file or archive under ${DIR}" >&2; exit 1; }
if [ "$bad" -gt 0 ]; then
    echo "ERROR: ${bad} file(s) under ${DIR} contain AVX-512 instructions" >&2
    exit 1
fi
