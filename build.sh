#!/bin/bash
# ============================================================================
# KangarooBTC Build Script for Linux
# Auto-detects CUDA and GPU compute capability
# Usage: ./build.sh [--cpu-only] [--debug] [--ccap=XX]
# ============================================================================

set -e

# Defaults
CPU_ONLY=0
DEBUG=0
CCAP=""
JOBS=$(nproc 2>/dev/null || echo 4)

# Parse arguments
for arg in "$@"; do
  case $arg in
    --cpu-only)   CPU_ONLY=1 ;;
    --debug)      DEBUG=1 ;;
    --ccap=*)     CCAP="${arg#*=}" ;;
    --help|-h)
      echo "Usage: $0 [--cpu-only] [--debug] [--ccap=XX]"
      echo "  --cpu-only   Build without GPU support"
      echo "  --debug      Build with debug symbols"
      echo "  --ccap=XX    Set compute capability (e.g., 89 for RTX 4090)"
      echo ""
      echo "Common compute capabilities:"
      echo "  61  - GTX 1070/1080 (Pascal)"
      echo "  75  - RTX 2070/2080 (Turing)"
      echo "  86  - RTX 3060/3070/3080 (Ampere)"
      echo "  89  - RTX 4090 (Ada Lovelace)"
      echo "  90  - H100 (Hopper)"
      echo "  120 - RTX 5090 (Blackwell)"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

echo "============================================"
echo " KangarooBTC Build System"
echo "============================================"

# Detect CUDA
CUDA_PATH=""
NVCC=""
if [ "$CPU_ONLY" -eq 0 ]; then
  # Try common CUDA locations
  for path in /usr/local/cuda "$CUDA_HOME" /usr/local/cuda-13* /usr/local/cuda-12* /usr/local/cuda-11*; do
    if [ -n "$path" ] && [ -x "$path/bin/nvcc" ]; then
      CUDA_PATH="$path"
      NVCC="$CUDA_PATH/bin/nvcc"
      break
    fi
  done

  if [ -z "$CUDA_PATH" ]; then
    # Try nvcc in PATH
    if command -v nvcc &>/dev/null; then
      NVCC=$(command -v nvcc)
      CUDA_PATH=$(dirname $(dirname "$NVCC"))
    fi
  fi

  if [ -z "$CUDA_PATH" ]; then
    echo "[WARN] CUDA not found. Building CPU-only version."
    CPU_ONLY=1
  else
    CUDA_VER=$("$NVCC" --version | grep "release" | sed 's/.*release //' | sed 's/,.*//')
    echo "[INFO] CUDA found: $CUDA_PATH (version $CUDA_VER)"
  fi
fi

# Auto-detect compute capability if not specified and GPU mode
if [ "$CPU_ONLY" -eq 0 ] && [ -z "$CCAP" ]; then
  if command -v nvidia-smi &>/dev/null; then
    # Query compute capability from nvidia-smi
    GPU_INFO=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$GPU_INFO" ]; then
      CCAP=$(echo "$GPU_INFO" | tr -d '.')
      echo "[INFO] Detected GPU compute capability: $GPU_INFO (sm_$CCAP)"
    fi
  fi
  if [ -z "$CCAP" ]; then
    CCAP=89
    echo "[INFO] Could not detect GPU. Using default compute capability: sm_$CCAP"
  fi
fi

# Create obj directories
mkdir -p obj/SECPK1 obj/GPU

# Build
set +e
if [ "$CPU_ONLY" -eq 1 ]; then
  echo "[INFO] Building CPU-only version..."
  make -j"$JOBS"
  BUILD_RET=$?
else
  echo "[INFO] Building with GPU support (sm_$CCAP)..."
  if [ "$DEBUG" -eq 1 ]; then
    make gpu=1 ccap="$CCAP" debug=1 CUDA="$CUDA_PATH" -j"$JOBS"
  else
    make gpu=1 ccap="$CCAP" CUDA="$CUDA_PATH" -j"$JOBS"
  fi
  BUILD_RET=$?
fi
set -e

echo ""
echo "============================================"
if [ $BUILD_RET -eq 0 ] && [ -f kangaroo ]; then
  echo " Build successful! Binary: ./kangaroo"
else
  echo " Build failed! (exit code: $BUILD_RET)"
  echo " Check error messages above for details."
  exit 1
fi
echo "============================================"
