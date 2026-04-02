@echo off
REM ============================================================================
REM KangarooBTC Build Script for Windows
REM Auto-detects CUDA and GPU compute capability
REM Usage: build.bat [/cpu-only] [/debug] [/ccap=XX]
REM ============================================================================

setlocal enabledelayedexpansion

set CPU_ONLY=0
set DEBUG=0
set CCAP=
set CUDA_PATH=
set NVCC=

REM Parse arguments
:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="/cpu-only" (set CPU_ONLY=1& shift& goto :parse_args)
if /i "%~1"=="/debug" (set DEBUG=1& shift& goto :parse_args)
if /i "%~1"=="/help" goto :show_help
if /i "%~1"=="/?" goto :show_help
echo %~1| findstr /r "^/ccap=" >nul 2>&1
if %errorlevel%==0 (
    for /f "tokens=2 delims==" %%a in ("%~1") do set CCAP=%%a
    shift& goto :parse_args
)
echo Unknown option: %~1
exit /b 1

:show_help
echo Usage: build.bat [/cpu-only] [/debug] [/ccap=XX]
echo   /cpu-only   Build without GPU support
echo   /debug      Build with debug symbols
echo   /ccap=XX    Set compute capability (e.g., 89 for RTX 4090)
echo.
echo Common compute capabilities:
echo   61  - GTX 1070/1080 (Pascal)
echo   75  - RTX 2070/2080 (Turing)
echo   86  - RTX 3060/3070/3080 (Ampere)
echo   89  - RTX 4090 (Ada Lovelace)
echo   90  - H100 (Hopper)
echo   120 - RTX 5090 (Blackwell)
exit /b 0

:done_args

echo ============================================
echo  KangarooBTC Build System (Windows)
echo ============================================

REM Detect Visual Studio
set VCVARS=
for %%v in (2022 2019 2017) do (
    for %%e in (Enterprise Professional Community BuildTools) do (
        if exist "C:\Program Files\Microsoft Visual Studio\%%v\%%e\VC\Auxiliary\Build\vcvars64.bat" (
            set "VCVARS=C:\Program Files\Microsoft Visual Studio\%%v\%%e\VC\Auxiliary\Build\vcvars64.bat"
            echo [INFO] Found Visual Studio %%v %%e
            goto :found_vs
        )
    )
)
for %%e in (Enterprise Professional Community BuildTools) do (
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\%%e\VC\Auxiliary\Build\vcvars64.bat" (
        set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\%%e\VC\Auxiliary\Build\vcvars64.bat"
        echo [INFO] Found Visual Studio 2019 %%e (x86)
        goto :found_vs
    )
)
echo [ERROR] Visual Studio not found. Install VS 2019 or later with C++ workload.
exit /b 1

:found_vs
call "%VCVARS%" >nul 2>&1

REM Detect CUDA
if %CPU_ONLY%==1 goto :skip_cuda

REM Try CUDA_PATH env var first
if defined CUDA_PATH (
    if exist "%CUDA_PATH%\bin\nvcc.exe" (
        set "NVCC=%CUDA_PATH%\bin\nvcc.exe"
        goto :found_cuda
    )
)

REM Search common CUDA install locations
for /d %%d in ("C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*") do (
    if exist "%%d\bin\nvcc.exe" (
        set "CUDA_PATH=%%d"
        set "NVCC=%%d\bin\nvcc.exe"
        goto :found_cuda
    )
)

REM Try nvcc in PATH
where nvcc.exe >nul 2>&1
if %errorlevel%==0 (
    for /f "tokens=*" %%p in ('where nvcc.exe') do (
        set "NVCC=%%p"
        for %%i in ("%%~dpi..") do set "CUDA_PATH=%%~fi"
        goto :found_cuda
    )
)

echo [WARN] CUDA not found. Building CPU-only version.
set CPU_ONLY=1
goto :skip_cuda

:found_cuda
for /f "tokens=5" %%v in ('"%NVCC%" --version ^| findstr "release"') do (
    set CUDA_VER=%%v
    set CUDA_VER=!CUDA_VER:,=!
)
echo [INFO] CUDA found: %CUDA_PATH% (version %CUDA_VER%)

REM Auto-detect compute capability
if "%CCAP%"=="" (
    where nvidia-smi.exe >nul 2>&1
    if !errorlevel!==0 (
        for /f "skip=1 tokens=*" %%g in ('nvidia-smi --query-gpu^=compute_cap --format^=csv,noheader 2^>nul') do (
            set "GPU_CC=%%g"
            set "GPU_CC=!GPU_CC: =!"
            set "CCAP=!GPU_CC:.=!"
            echo [INFO] Detected GPU compute capability: !GPU_CC! (sm_!CCAP!)
            goto :ccap_done
        )
    )
    set CCAP=89
    echo [INFO] Could not detect GPU. Using default: sm_89
)
:ccap_done

:skip_cuda

REM Create obj directories
if not exist obj mkdir obj
if not exist obj\SECPK1 mkdir obj\SECPK1
if not exist obj\GPU mkdir obj\GPU

REM Source files
set SRC_CPP=main.cpp Kangaroo.cpp HashTable.cpp Thread.cpp Timer.cpp Check.cpp Backup.cpp Network.cpp Merge.cpp PartMerge.cpp
set SRC_SECPK1=SECPK1\Int.cpp SECPK1\IntMod.cpp SECPK1\IntGroup.cpp SECPK1\Point.cpp SECPK1\SECP256K1.cpp SECPK1\Random.cpp

REM Compiler flags
set CXXFLAGS=/O2 /EHsc /W2 /D WIN64 /I. /nologo
if %CPU_ONLY%==0 (
    set "CXXFLAGS=%CXXFLAGS% /DWITHGPU /I"%CUDA_PATH%\include""
)
if %DEBUG%==1 (
    set CXXFLAGS=/Zi /Od /EHsc /W2 /D WIN64 /I. /nologo
    if %CPU_ONLY%==0 set "CXXFLAGS=!CXXFLAGS! /DWITHGPU /I"%CUDA_PATH%\include""
)

echo.
echo [INFO] Compiling C++ sources...

REM Compile C++ files
for %%f in (%SRC_CPP%) do (
    echo   %%f
    cl %CXXFLAGS% /Fo"obj\%%~nf.obj" /c %%f
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to compile %%f
        exit /b 1
    )
)

for %%f in (%SRC_SECPK1%) do (
    echo   %%f
    cl %CXXFLAGS% /Fo"obj\SECPK1\%%~nf.obj" /c %%f
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to compile %%f
        exit /b 1
    )
)

REM Compile CUDA kernel
if %CPU_ONLY%==0 (
    echo.
    echo [INFO] Compiling CUDA kernel (sm_%CCAP%)...
    set NVCCFLAGS=-DWIN64 -DWITHGPU -maxrregcount=0 --ptxas-options=-v -m64 -I"%CUDA_PATH%\include" -gencode=arch=compute_%CCAP%,code=sm_%CCAP%
    if %DEBUG%==1 (
        set NVCCFLAGS=-G -O0 !NVCCFLAGS!
    ) else (
        set NVCCFLAGS=-O2 !NVCCFLAGS!
    )
    "%NVCC%" !NVCCFLAGS! --compile -o obj\GPU\GPUEngine.obj -c GPU\GPUEngine.cu
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to compile CUDA kernel
        exit /b 1
    )
)

REM Link
echo.
echo [INFO] Linking...
set OBJ_FILES=obj\main.obj obj\Kangaroo.obj obj\HashTable.obj obj\Thread.obj obj\Timer.obj obj\Check.obj obj\Backup.obj obj\Network.obj obj\Merge.obj obj\PartMerge.obj
set OBJ_FILES=%OBJ_FILES% obj\SECPK1\Int.obj obj\SECPK1\IntMod.obj obj\SECPK1\IntGroup.obj obj\SECPK1\Point.obj obj\SECPK1\SECP256K1.obj obj\SECPK1\Random.obj

set LIBS=ws2_32.lib
if %CPU_ONLY%==0 (
    set OBJ_FILES=!OBJ_FILES! obj\GPU\GPUEngine.obj
    set "LIBS=!LIBS! "%CUDA_PATH%\lib\x64\cudart_static.lib""
)

link /OUT:kangaroo.exe /nologo %OBJ_FILES% %LIBS%
if %errorlevel% neq 0 (
    echo [ERROR] Linking failed
    exit /b 1
)

echo.
echo ============================================
if exist kangaroo.exe (
    echo  Build successful! Binary: kangaroo.exe
) else (
    echo  Build failed!
    exit /b 1
)
echo ============================================

endlocal
