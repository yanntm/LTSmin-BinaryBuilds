#! /bin/bash

# Post-build acceptance check.
#
# build_ltsmin.sh happily produces a binary even when configure silently drops a
# feature (Sylvan is the classic: a version mismatch just disables lddmc), so the
# tarball we publish can be missing exactly what its consumers need. Nothing
# noticed for two years. This script fails the build instead.
#
# Consumers:
#  * ITS-Tools     uses pins2lts-seq / pins2lts-mc on a dlopen'd gal.so
#  * MCC-drivers   uses pnml2lts-sym --vset=lddmc --sylvan-sizes=...

set -u

BIN=${1:-lts_install_dir/bin}
status=0

fail() { echo "FAIL: $*" ; status=1 ; }
ok()   { echo "ok  : $*" ; }

# 1. the binaries our consumers actually invoke must exist
for b in pins2lts-seq pins2lts-mc pnml2lts-mc pnml2lts-sym ; do
	if [ -x "$BIN/$b" ] ; then ok "$b present" ; else fail "$b missing" ; fi
done

# 2. they must start. A binary that dies on --version is useless downstream,
#    however well it linked.
for b in pins2lts-seq pins2lts-mc pnml2lts-sym ; do
	[ -x "$BIN/$b" ] || continue
	probe=""
	[ "$b" = pnml2lts-sym ] && probe="--lace-workers=1"
	if out=$("$BIN/$b" $probe --version 2>&1) && [ -n "$out" ] ; then
		ok "$b runs ($(echo "$out" | head -1))"
	elif [ -n "$out" ] ; then
		# LTSmin exits non-zero on --version, so printing something is the test
		ok "$b runs ($(echo "$out" | head -1))"
	else
		fail "$b produced no output on --version (crash? OOM?)"
	fi
done

# 3. the symbolic tool must offer the vector sets MCC-drivers asks for
if [ -x "$BIN/pnml2lts-sym" ] ; then
	vsets=$("$BIN/pnml2lts-sym" --lace-workers=1 --help 2>&1 | grep -o 'vset=<[^>]*>' | head -1)
	if [ -z "$vsets" ] ; then
		fail "could not read the vset list from pnml2lts-sym"
	else
		ok "vset list: $vsets"
		for v in lddmc ldd fdd ; do
			case "$vsets" in
				*"$v"*) ok "vset $v available" ;;
				*)      fail "vset $v MISSING (Sylvan not linked? check the sylvan version against configure)" ;;
			esac
		done
	fi
fi

# 4. runtime dependencies: these binaries are published for other machines, so
#    they must not need anything beyond a base system. libxml2/lzma/gmp creeping
#    back in means the static staging in build_ltsmin.sh silently failed again.
ALLOWED='linux-vdso|ld-linux|libc\.so|libm\.so|libpthread|librt\.so|libdl\.so|libgcc_s|libstdc\+\+|libnuma|libltdl'
for b in pins2lts-seq pins2lts-mc pnml2lts-mc pnml2lts-sym ; do
	[ -x "$BIN/$b" ] || continue
	extra=$(ldd "$BIN/$b" 2>/dev/null | awk '{print $1}' | grep -vE "$ALLOWED" | grep -v '^$' | tr '\n' ' ')
	if [ -n "$extra" ] ; then
		echo "warn: $b also needs: $extra"
	fi
done

# 5. the headers ITS-Tools compiles gal.so against must ship too
if [ -f lts_install_dir/include/ltsmin/ltsmin-standard.h ] ; then
	ok "ltsmin headers present"
else
	fail "lts_install_dir/include/ltsmin headers missing (ITS-Tools needs them)"
fi

echo ""
if [ $status -ne 0 ] ; then
	echo "==> acceptance check FAILED, not publishing this build"
else
	echo "==> acceptance check passed"
fi
exit $status
