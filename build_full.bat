@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

set CUDA=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0
set CXXFLAGS=/O2 /EHsc /W2 /D WIN64 /DWITHGPU /I. /I"%CUDA%\include" /nologo
set NVCCFLAGS=-DWIN64 -DWITHGPU -O2 -maxrregcount=0 -m64 -I"%CUDA%\include" -gencode=arch=compute_86,code=sm_86

mkdir obj 2>nul
mkdir obj\SECPK1 2>nul
mkdir obj\GPU 2>nul

echo Compiling C++ sources...
for %%f in (main.cpp Kangaroo.cpp HashTable.cpp Thread.cpp Timer.cpp Check.cpp Backup.cpp Network.cpp Merge.cpp PartMerge.cpp) do (
    echo   %%f
    cl %CXXFLAGS% /Foobj\%%~nf.obj /c %%f
    if errorlevel 1 ( echo FAILED: %%f & exit /b 1 )
)

for %%f in (SECPK1\Int.cpp SECPK1\IntMod.cpp SECPK1\IntGroup.cpp SECPK1\Point.cpp SECPK1\SECP256K1.cpp SECPK1\Random.cpp) do (
    echo   %%f
    cl %CXXFLAGS% /Foobj\SECPK1\%%~nf.obj /c %%f
    if errorlevel 1 ( echo FAILED: %%f & exit /b 1 )
)

echo Compiling CUDA kernel...
"%CUDA%\bin\nvcc.exe" %NVCCFLAGS% --compile -o obj\GPU\GPUEngine.obj -c GPU\GPUEngine.cu
if errorlevel 1 ( echo CUDA FAILED & exit /b 1 )

echo Linking...
set OBJS=obj\main.obj obj\Kangaroo.obj obj\HashTable.obj obj\Thread.obj obj\Timer.obj obj\Check.obj obj\Backup.obj obj\Network.obj obj\Merge.obj obj\PartMerge.obj obj\SECPK1\Int.obj obj\SECPK1\IntMod.obj obj\SECPK1\IntGroup.obj obj\SECPK1\Point.obj obj\SECPK1\SECP256K1.obj obj\SECPK1\Random.obj obj\GPU\GPUEngine.obj
link /OUT:kangaroo.exe /nologo %OBJS% ws2_32.lib "%CUDA%\lib\x64\cudart_static.lib"
if errorlevel 1 ( echo LINK FAILED & exit /b 1 )
echo BUILD SUCCESS
