# param must be in the begin of PowerShell Script
param ($TARGET = "faiss-win64.7z")

# install 7zip ZSTD plugin
if (!(Get-Command 7z -errorAction SilentlyContinue)) {
    Write-Output "::group::Install 7-Zip ..."
    winget install --id 7zip-zstd -e --silent
    $env:PATH += ";C:\Program Files\7-Zip-Zstandard"
    Write-Output "::endgroup::"
}

# define MKL path
$VCPKG_INSTALL = "$PWD\vcpkg\installed\x64-windows-static"
$MKL_PATH = "$VCPKG_INSTALL\lib"
$MKL_LIBRARIES = "${MKL_PATH}\mkl_intel_lp64.lib;${MKL_PATH}\mkl_intel_thread.lib;${MKL_PATH}\mkl_core.lib;${MKL_PATH}\libiomp5md.lib"
$IOMP_DLL = "$VCPKG_INSTALL\bin\libiomp5md.dll"
$DIST_PATH = "$PWD\dist"

# install required 3rd party libraries
if (!(Test-Path $VCPKG_INSTALL)) {
    # refer to https://github.com/facebookresearch/faiss/issues/2641
    # replace MKL interface to LP, and threading to Intel OpenMP
    $MKL_CMAKE = ".\vcpkg\ports\intel-mkl\portfile.cmake"

    # the port installs the Intel OpenMP runtime DLL only for dynamic library
    # linkage, then purges bin\*.dll again for static linkage. faiss.dll links
    # mkl_intel_thread and needs libiomp5md.dll at runtime, so keep both.
    $OMP_LIB_COPY = 'file(COPY "${compiler_dir}/lib/" DESTINATION "${CURRENT_PACKAGES_DIR}/lib/")'
    $OMP_BIN_COPY = '  file(COPY "${compiler_dir}/bin/" DESTINATION "${CURRENT_PACKAGES_DIR}/bin/")'
    $BIN_PURGE = '"${CURRENT_PACKAGES_DIR}/bin/*${to_remove_suffix}"'

    (Get-Content $MKL_CMAKE) | ForEach-Object {
        $line = $_ -replace "ilp64", "lp64" -replace "sequential", "intel_thread"
        if ($line.Trim() -eq $BIN_PURGE) { return }
        $line
        if ($line.Contains($OMP_LIB_COPY)) { $OMP_BIN_COPY }
    } | Set-Content $MKL_CMAKE

    Write-Output "::group::Install vcpkg libraries ..."
    .\vcpkg\bootstrap-vcpkg.bat
    .\vcpkg\vcpkg install intel-mkl --triplet x64-windows-static --clean-after-build
    Write-Output "::endgroup::"
}

# fail early and loudly if the intel-mkl port layout changed again
foreach ($file in ($MKL_LIBRARIES -split ';') + $IOMP_DLL) {
    if (!(Test-Path $file)) {
        throw "intel-mkl layout changed, file not found: $file"
    }
}

# configure build and compile
Write-Output "::group::Configure CMake and Build ..."
if (Test-Path build) {
    rm -r build
}
if (Test-Path dist) {
    rm -r $DIST_PATH
}
cmake -Bbuild `
    -G "Visual Studio 17 2022" -A "x64" `
    -Wno-dev `
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" `
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_ENABLE_GPU=OFF `
    -DBUILD_TESTING=OFF `
    -DBLA_VENDOR=Intel10_64lp `
    -DMKL_LIBRARIES="${MKL_LIBRARIES}" `
    -DBUILD_SHARED_LIBS=ON `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

Write-Output "::group::Pack artifacts ..."

# copy artifacts and change config
cp $IOMP_DLL $DIST_PATH\bin

# remap absolute path to relative dist path
$DOUBLE_QUOTE_PATH = $MKL_PATH.Replace('\', '\\')
$FAISS_CMAKE = "$DIST_PATH\share\faiss\faiss-targets.cmake"
(Get-content $FAISS_CMAKE) | Foreach-Object {
    $_.Replace("$DOUBLE_QUOTE_PATH", '${_IMPORT_PREFIX}\\lib')
} | Set-Content $FAISS_CMAKE

# copy license files into dist so they are included in the archive
cp LICENSE, THIRD-PARTY-NOTICES $DIST_PATH

# pack binary
Push-Location $DIST_PATH
7z a -mx=9 ..\$TARGET * | Out-Null
Pop-Location

Write-Output "::endgroup::"
