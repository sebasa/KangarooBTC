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
set CUDA_PATH_LOC=
set NVCC=

REM Parse arguments
:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="/cpu-only" (set CPU_ONLY=1& shift& goto :parse_args)
if /i "%~1"=="/debug"    (set DEBUG=1&    shift& goto :parse_args)
if /i "%~1"=="/help"     goto :show_help
if /i "%~1"=="/?"        goto :show_help
echo %~1 | findstr /r "^/ccap=" >nul 2>&1
if not errorlevel 1 (
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
call "!VCVARS!" >nul 2>&1

REM Detect CUDA
if %CPU_ONLY%==1 goto :skip_cuda

REM Try env var CUDA_PATH first
if defined CUDA_PATH (
    if exist "%CUDA_PATH%\bin\nvcc.exe" (
        set "CUDA_PATH_LOC=%CUDA_PATH%"
        set "NVCC=%CUDA_PATH%\bin\nvcc.exe"
        goto :found_cuda
    )
)

REM Search common CUDA install locations (last dir = newest version)
for /d %%d in ("C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*") do (
    if exist "%%d\bin\nvcc.exe" (
        set "CUDA_PATH_LOC=%%d"
        set "NVCC=%%d\bin\nvcc.exe"
    )
)
if defined NVCC goto :found_cuda

REM Try nvcc in PATH
where nvcc.exe >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%p in ('where nvcc.exe') do (
        set "NVCC=%%p"
        set "CUDA_PATH_LOC=%%~dpp.."
        goto :found_cuda
    )
)

echo [WARN] CUDA not found. Building CPU-only version.
set CPU_ONLY=1
goto :skip_cuda

:found_cuda
echo [INFO] CUDA found: !CUDA_PATH_LOC!

REM Auto-detect compute capability (no skip=1 ? noheader format has no header line)
if "%CCAP%"=="" (
    where nvidia-smi.exe >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=*" %%g in ('nvidia-smi --query-gpu^=compute_cap --format^=csv^,noheader 2^>nul') do (
            set "GPU_CC=%%g"
            set "GPU_CC=!GPU_CC: =!"
            set "CCAP=!GPU_CC:.=!"
            echo [INFO] Detected GPU sm_!CCAP!
            goto :ccap_done
        )
    )
    set CCAP=89
    echo [INFO] GPU not detected. Using default sm_89
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

REM Compiler flags ? avoid nested quotes by using a temp variable for CUDA include
set CXXFLAGS=/O2 /EHsc /W2 /D WIN64 /I. /nologo
if %DEBUG%==1 set CXXFLAGS=/Zi /Od /EHsc /W2 /D WIN64 /I. /nologo
if %CPU_ONLY%==0 (
    set CXXFLAGS=!CXXFLAGS! /DWITHGPU
    set "CUDA_INC=!CUDA_PATH_LOC!\include"
)

echo.
echo [INFO] Compiling C++ sources...

for %%f in (%SRC_CPP%) do (
    echo   %%f
    if %CPU_ONLY%==0 (
        cl !CXXFLAGS! /I"!CUDA_INC!" /Foobj\%%~nf.obj /c %%f
    ) else (
        cl !CXXFLAGS! /Foobj\%%~nf.obj /c %%f
    )
    if errorlevel 1 ( echo [ERROR] Failed to compile %%f & exit /b 1 )
)

for %%f in (%SRC_SECPK1%) do (
    echo   %%f
    if %CPU_ONLY%==0 (
        cl !CXXFLAGS! /I"!CUDA_INC!" /Foobj\SECPK1\%%~nf.obj /c %%f
    ) else (
        cl !CXXFLAGS! /Foobj\SECPK1\%%~nf.obj /c %%f
    )
    if errorlevel 1 ( echo [ERROR] Failed to compile %%f & exit /b 1 )
)

if %CPU_ONLY%==1 goto :link

echo.
echo [INFO] Compiling CUDA kernel (sm_!CCAP!)...
if %DEBUG%==1 (
    "!NVCC!" -DWIN64 -DWITHGPU -G -O0 -maxrregcount=0 --ptxas-options=-v -m64 -I"!CUDA_INC!" -gencode=arch=compute_!CCAP!,code=sm_!CCAP! --compile -o obj\GPU\GPUEngine.obj -c GPU\GPUEngine.cu
) else (
    "!NVCC!" -DWIN64 -DWITHGPU -O2 -maxrregcount=0 --ptxas-options=-v -m64 -I"!CUDA_INC!" -gencode=arch=compute_!CCAP!,code=sm_!CCAP! --compile -o obj\GPU\GPUEngine.obj -c GPU\GPUEngine.cu
)
if errorlevel 1 ( echo [ERROR] Failed to compile CUDA kernel & exit /b 1 )

:link
echo.
echo [INFO] Linking...
set OBJS=obj\main.obj obj\Kangaroo.obj obj\HashTable.obj obj\Thread.obj obj\Timer.obj obj\Check.obj obj\Backup.obj obj\Network.obj obj\Merge.obj obj\PartMerge.obj
set OBJS=!OBJS! obj\SECPK1\Int.obj obj\SECPK1\IntMod.obj obj\SECPK1\IntGroup.obj obj\SECPK1\Point.obj obj\SECPK1\SECP256K1.obj obj\SECPK1\Random.obj
set LIBS=ws2_32.lib

if %CPU_ONLY%==0 (
    set OBJS=!OBJS! obj\GPU\GPUEngine.obj
    set "CUDA_LIB=!CUDA_PATH_LOC!\lib\x64\cudart_static.lib"
)

if %CPU_ONLY%==0 (
    link /OUT:kangaroo.exe /nologo !OBJS! !LIBS! "!CUDA_LIB!"
) else (
    link /OUT:kangaroo.exe /nologo !OBJS! !LIBS!
)
if errorlevel 1 ( echo [ERROR] Linking failed & exit /b 1 )

echo.
echo ============================================
if exist kangaroo.exe (
    echo  Build successful^^!  Binary: kangaroo.exe
) else (
    echo  Build failed^^!
    exit /b 1
)
echo ============================================

endlocal
