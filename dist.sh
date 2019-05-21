#!/bin/bash

id=$1
log=../log-${id}.txt
build_dir=build-${id}
install_dir=~/local-${id}

if [ "${id}" == "" ]; then printf "Usage: $0 id\n Missing id\n"; exit 1; fi

mkdir -p ${build_dir}
cd ${build_dir}

# Use set -x so we see the commands.
cmd="set -x ; \
  cmake ../llvm -G Ninja \
    -C ../clang/cmake/caches/DistributionExample.cmake \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    && \
  ninja stage2-distribution"

# Set the pipefail flag so the exit status is from ${cmd} and not time or tee
set -o pipefail

# In a subshell time the evaluated command and log the output
# of the subshell with 2>&1 | tee $(log). The log includes the time
# the command took as well as all output from the commands.
( time eval ${cmd} ) 2>&1 | tee ${log}
