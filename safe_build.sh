#!/usr/bin/env bash
# Usage: nix-build-safe .#rosPackages.jazzy.mavros

# 1. Determine total RAM in Gigabytes and actual CPU threads based on the OS
if [ "$(uname)" = "Darwin" ]; then
    # macOS
    RAM_BYTES=$(sysctl -n hw.memsize)
    RAM_GB=$((RAM_BYTES / 1024 / 1024 / 1024))
    CPU_THREADS=$(sysctl -n hw.logicalcpu)
else
    # Linux
    RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    RAM_GB=$((RAM_KB / 1024 / 1024))
    CPU_THREADS=$(nproc)
fi

# 2. Calculate allowed cores (Total RAM / 3GB per core)
ALLOWED_CORES=$((RAM_GB / 3))

# 3. Apply bounds (Minimum 1 core, Maximum = actual hardware threads)
if [ "$ALLOWED_CORES" -lt 1 ]; then 
    ALLOWED_CORES=1
fi

if [ "$ALLOWED_CORES" -gt "$CPU_THREADS" ]; then 
    ALLOWED_CORES=$CPU_THREADS
fi

echo "🧠 System RAM: ${RAM_GB}GB | Hardware Threads: ${CPU_THREADS}"
echo "🚀 Allocating 3GB per core -> Running Nix with --cores ${ALLOWED_CORES}"
echo "------------------------------------------------------"

# 4. Execute the Nix build with the dynamic core count
nix build "$@" --cores "$ALLOWED_CORES"
