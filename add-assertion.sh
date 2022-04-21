cp Viob_cache_backup.cpp hardware/simulation/verilator/obj_dir/Viob_cache.cpp
echo "Rebuilding Viob_cache.cpp"
cd hardware/simulation/verilator/obj_dir/ && \
   /usr/bin/afl-clang-fast++  -I.  -MMD -I/usr/share/verilator/include -I/usr/share/verilator/include/vltstd -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TRACE=1 -faligned-new -fcf-protection=none -Wno-bool-operation -Wno-sign-compare -Wno-uninitialized -Wno-unused-but-set-variable -Wno-unused-parameter -Wno-unused-variable -Wno-shadow     -O2 -ggdb  -Os -c -o Viob_cache__ALL.o Viob_cache__ALL.cpp && \
   ar -cr Viob_cache__ALL.a Viob_cache__ALL.o && \
   ranlib Viob_cache__ALL.a && \
   afl-clang-fast++ testbench.o verilated.o verilated_vcd_c.o Viob_cache__ALL.a  -o Viob_cache
