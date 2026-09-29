#!/bin/bash
# Usage: ./measure_sampler.sh <label>   e.g. isaext or extpp
set -e
OUT=sampler_stats/$1; mkdir -p $OUT
run() {  # $1=target  $2=define  $3=output name
  ./bazelisk.sh build --copt=$2 //sw/otbn/crypto/tests:$1
  ELF=$(ls -t bazel-out/*/bin/sw/otbn/crypto/tests/$1.elf | head -1)
  ./bazelisk.sh run --copt=$2 //hw/ip/otbn/dv/otbnsim:standalone -- $PWD/$ELF --dump-stats $PWD/$OUT/$3.txt
  echo "== $3"; grep "^OTBN executed" $OUT/$3.txt; grep -E "^(poly_gen_matrix|poly_uniform) " $OUT/$3.txt
}
for k in 2 3 4; do run otbn_mlkem_isaext_keypair_test -DKYBER_K=$k mlkem_k${k}_keypair; done
for m in 2 3 5; do run otbn_mldsa_isaext_keypair_test -DDILITHIUM_MODE=$m mldsa_mode${m}_keypair; done
