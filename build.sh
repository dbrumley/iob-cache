patch -p1 < verilog.patch
patch -p1 < testbench.patch
export AFL_LLVM_LAF_ALL=1
make sim SIMULATOR=verilator CC=afl-clang CXX=afl-clang++ LINK=afl-clang\
++ CFLAGS="-O2 -ggdb" CXXFLAGS="-O2 -ggdb" LDFLAGS="-O2 -ggdb"
./add-assertion.sh
