#!/bin/bash
# Builds llvm;clang;lld;compiler-rt in build-${id} with
# logs in log-${id].txt and install in ~/local-${id}
#
# AFAIK, llvm is always built
#Examples:
# Default it builds clang
# $ ./simple.sh clang
#
# To build only llvm either set enable_projects=llvm or none
# these are exactly the same
# $ enable_projects=none ./simple.sh llvm
# $ enable_projects=llvm ./simple.sh llvm
#
# Make clang lld and compiler-rt
# $ enabled_projects= ./simple.sh clang-lld-compiler-rt

id=$1
log=../log-${id}.txt
build_dir=build-${id}
install_dir=~/local-${id}

if [ "${id}" == "" ]; then printf "Usage: $0 id\n Missing id\n"; exit 1; fi

mkdir -p ${build_dir}
cd ${build_dir}

if [ "${jobcnt}" == "" ]; then
  jobcnt=${jobcnt:-$(( $(nproc) - 1 ))};
fi
if [[ ${jobcnt} < 1 ]]; then jobcnt=1; fi

rm -f ${log}
touch ${log}

#enable_projects="clang;clang-tools-extra;compiler-rt;libclc;libcxx;libcxxabi"

# Use set -x so we see the commands.
# Substitue check-all for others like check-tsan:
#    -DLLVM_ENABLE_PROJECTS=\"${enable_projects}\" \
cmd="set -x ; \
  cmake ../llvm -G Ninja \
    -C ../clang/cmake/caches/DistributionExample.cmake \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_USE_LINKER=gold \
    -DLLVM_BINUTILS_INCDIR=/usr/include \
    -DLLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON \
    && \
  ninja -j${jobcnt} stage2-distribution -v"

# Set the pipefail flag so the exit status is from ${cmd} and not time or tee
set -o pipefail

# In a subshell time the evaluated command and log the output
# of the subshell with 2>&1 | tee $(log). The log includes the time
# the command took as well as all output from the commands.
( time eval ${cmd} ) 2>&1 | tee ${log}
