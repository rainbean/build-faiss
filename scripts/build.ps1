
# Set path
$env:Path += ";C:\Program Files\CMake\bin\;C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\;C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.1\bin"
$env:Path += "$PWD\vcpkg\installed\x64-windows\bin"

# install required 3rd party libraries
if (!(Test-Path .\vcpkg\installed\x64-windows-static)) {
    # refer to https://github.com/facebookresearch/faiss/issues/2641
    # replace MKL interface to LP
    $MKL_CMAKE = ".\vcpkg\ports\intel-mkl\portfile.cmake"
    (Get-content $MKL_CMAKE) | Foreach-Object {$_ -replace "ilp64", "lp64" -replace "sequential", "intel_thread" } | Set-Content $MKL_CMAKE

    Write-Output "::group::Install vcpkg libraries ..."
    .\vcpkg\bootstrap-vcpkg.bat
    .\vcpkg\vcpkg install intel-mkl --triplet x64-windows-static --clean-after-build
    Write-Output "::endgroup::"
}

# fix demo app build error in Windows
cp demo_ivfpq_indexing.cpp .\faiss\demos\

# configure build and compile
Write-Output "::group::Configure CMake and Build ..."
$MKL_PATH = "$PWD\vcpkg\installed\x64-windows-static\lib\intel64\"

cmake -Bbuild `
    -G "Visual Studio 16 2019" -A "x64" `
    -Wno-dev `
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_OPT_LEVEL=avx2 `
    -DFAISS_ENABLE_GPU=OFF `
    -DBLA_VENDOR=Intel10_64lp `
    -DMKL_LIBRARIES="${MKL_PATH}/mkl_intel_lp64.lib;${MKL_PATH}/mkl_intel_thread.lib;${MKL_PATH}/mkl_core.lib;${MKL_PATH}/libiomp5md.lib" `
    faiss
MSBuild build\faiss.sln /t:faiss /t:demo_ivfpq_indexing /p:Configuration=Release 
Write-Output "::endgroup::"

dir .\vcpkg\installed\x64-windows-static\bin\libiomp5md.dll
dir .\build\faiss\Release\faiss.lib
dir .\build\demos\Release\demo_ivfpq_indexing.exe
