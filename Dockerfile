FROM debian:bullseye-slim
RUN apt-get update && \
    apt-get install -y build-essential clang afl vim gdb libc6-dbg verilog verilator less
WORKDIR /iob-cache
COPY . .
RUN ./build.sh
CMD ["/iob-cache/hardware/simulation/verilator/obj_dir/Viob_cache"]
