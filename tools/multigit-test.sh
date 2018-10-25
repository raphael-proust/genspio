#! /bin/sh

set -e

genspio_multigit=_build/default/src/examples/multigit.exe

tmpdir=/tmp/multigittest/

rm -fr $tmpdir

$genspio_multigit $tmpdir/bin

export PATH=$tmpdir/bin:$PATH

try_cmd () {
    echo "================================================================================"
    echo "==== Running: [ $1 ]"
    sh -c "$1"
}

try_cmd 'git multi-status -h'

try_cmd "git multi-status --version"

moregits=$tmpdir/moregits
mkdir -p $moregits
(
    cd $moregits
    git clone https://github.com/hammerlab/ketrew.git
    git clone https://github.com/hammerlab/biokepi.git
    echo "GREEEAAAT" >> biokepi/README.md
    echo "Boooo" >> biokepi/LICENSE
    git clone https://github.com/hammerlab/coclobas.git
    echo "GREEEAAAT" >> coclobas/README.md
    echo "Stuff" > coclobas/doeas-not-exist
)

try_cmd "git multi-status $moregits"

try_cmd "git multi-status $moregits 2>&1 | grep ketrew | grep 'M: 0'"
try_cmd "git multi-status $moregits 2>&1 | grep biokepi | grep 'M: 2'"
try_cmd "git multi-status $moregits 2>&1 | grep coclobas | grep 'U: 1'"

