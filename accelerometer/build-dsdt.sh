#!/usr/bin/env bash
# build-dsdt.sh DSDT.dat OUTDIR - build the accelerometer DSDT override from a
# dump of THIS machine's firmware table. No root needed.
#
#   OUTDIR/dsdt.dsl.orig  decompiled stock table
#   OUTDIR/dsdt.dsl       patched source (SMOCF05 -> SMO8B30, OEM revision +0x10)
#   OUTDIR/dsdt.aml       the override to install
#   OUTDIR/compile.log    iasl output
#
# The V3 BIOS has an unrelated Device (CIND) with _HID "ID9001" (6 characters),
# which iasl rejects with error 6033. -f compiles anyway and keeps it exactly as
# the firmware ships it. Any OTHER error aborts. As a final check the result is
# compared with the stock table compiled the same way; they must differ in
# exactly the three patched lines.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dat=$(realpath "$1"); out=$(realpath -m "$2")
mkdir -p "$out"; cd "$out"
command -v iasl >/dev/null || { echo "iasl missing: sudo pacman -S acpica"; exit 1; }

cp "$dat" dsdt.dat
iasl -d dsdt.dat >/dev/null 2>&1
grep -q 'EisaId ("SMOCF05")' dsdt.dsl || { echo "no SMOCF05 device in this DSDT - fix does not apply"; exit 1; }
cp dsdt.dsl dsdt.dsl.orig
python3 "$here/patch-dsdt.py" dsdt.dsl

iasl -f -tc dsdt.dsl > compile.log 2>&1 || :
errors=$(grep -c '^Error ' compile.log || :)
if [[ ! -s dsdt.aml ]] || { [[ $errors != 0 ]] && ! { [[ $errors == 1 ]] && grep -q '^Error    6033 .*(ID9001)' compile.log; }; }; then
  echo "compile failed or unexpected errors ($errors) - see $out/compile.log"; exit 1
fi

# Round trip: compile the unpatched source the same way, decompile both
# results and compare. iasl rewrites some expressions when it recompiles
# (0x00 -> Zero, a = a - b -> a -= b), so comparing against the original
# decompile would show those too; this way only the real changes remain.
mkdir -p verify/stock verify/patched
cp dsdt.dsl.orig verify/stock/dsdt.dsl && (cd verify/stock && iasl -f -tc dsdt.dsl >/dev/null 2>&1 || :)
cp dsdt.aml verify/patched/ && (cd verify/patched && iasl -d dsdt.aml >/dev/null 2>&1)
(cd verify/stock && rm -f dsdt.dsl && iasl -d dsdt.aml >/dev/null 2>&1)
changed=$(diff <(sed '1,/^ \*\//d' verify/stock/dsdt.dsl) <(sed '1,/^ \*\//d' verify/patched/dsdt.dsl) | grep -c '^>' || :)
if [[ $changed != 3 ]]; then
  echo "result differs from the stock table in $changed lines, expected 3 - not using it"; exit 1
fi
rm -rf verify dsdt.hex
echo "built $out/dsdt.aml (only the 3 intended lines changed)"
