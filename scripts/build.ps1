# param must be in the begin of PowerShell Script
# NOTE: TARGET stays first so CI can keep passing the artifact name positionally.
param (
    $TARGET = "",
    [ValidateSet("mkl", "openblas")]
    $Blas = "mkl"
)

if (!$TARGET) {
    $TARGET = if ($Blas -eq "openblas") { "faiss-win64-openblas.7z" } else { "faiss-win64.7z" }
}

# install 7zip ZSTD plugin
if (!(Get-Command 7z -errorAction SilentlyContinue)) {
    Write-Output "::group::Install 7-Zip ..."
    winget install --id 7zip-zstd -e --silent
    $env:PATH += ";C:\Program Files\7-Zip-Zstandard"
    Write-Output "::endgroup::"
}

$DIST_PATH = "$PWD\dist"

if ($Blas -eq "mkl") {
    # define MKL path
    $VCPKG_INSTALL = "$PWD\vcpkg\installed\x64-windows-static"
    $BLAS_LIB_PATH = "$VCPKG_INSTALL\lib"
    $MKL_LIBRARIES = "${BLAS_LIB_PATH}\mkl_intel_lp64.lib;${BLAS_LIB_PATH}\mkl_intel_thread.lib;${BLAS_LIB_PATH}\mkl_core.lib;${BLAS_LIB_PATH}\libiomp5md.lib"
    $RUNTIME_DLL = "$VCPKG_INSTALL\bin\libiomp5md.dll"
    $EXPECTED_FILES = ($MKL_LIBRARIES -split ';') + $RUNTIME_DLL

    # faiss calls find_package(MKL) first and only falls back to BLAS/LAPACK
    # when it fails, so passing MKL_LIBRARIES selects the MKL path.
    $BLAS_ARGS = @(
        "-DBLA_VENDOR=Intel10_64lp"
        "-DMKL_LIBRARIES=${MKL_LIBRARIES}"
    )

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
}
else {
    # The vcpkg openblas port is built with BUILD_WITHOUT_LAPACK=ON/NOFORTRAN=ON
    # and cannot do DYNAMIC_ARCH on MSVC, so it is unusable here: faiss requires
    # LAPACK (ssyev_/dsyev_/sgesvd_/sgeqrf_/sorgqr_). The upstream Windows
    # release ships full LAPACK, runtime CPU dispatch and an MSVC import library.
    $OPENBLAS_VERSION = "0.3.34"
    $OPENBLAS_ROOT = "$PWD\build-deps\OpenBLAS-${OPENBLAS_VERSION}-x64"
    $BLAS_LIB_PATH = "$OPENBLAS_ROOT\lib"
    $RUNTIME_DLL = "$OPENBLAS_ROOT\bin\libopenblas.dll"
    $EXPECTED_FILES = @("$BLAS_LIB_PATH\libopenblas.lib", $RUNTIME_DLL)

    # BLA_VENDOR=OpenBLAS makes FindBLAS look for a library named openblas;
    # CMAKE_PREFIX_PATH points it at the extracted release.
    $BLAS_ARGS = @(
        "-DBLA_VENDOR=OpenBLAS"
        "-DCMAKE_PREFIX_PATH=${OPENBLAS_ROOT}"
    )

    if (!(Test-Path $OPENBLAS_ROOT)) {
        Write-Output "::group::Download OpenBLAS ${OPENBLAS_VERSION} ..."
        $zip = "$PWD\build-deps\OpenBLAS-${OPENBLAS_VERSION}-x64.zip"
        New-Item -ItemType Directory -Force "$PWD\build-deps" | Out-Null
        if (!(Test-Path $zip)) {
            # -x64 is the LP64 build; the -x64-64 asset is ILP64, which faiss cannot use
            $url = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/OpenBLAS-${OPENBLAS_VERSION}-x64.zip"
            Invoke-WebRequest -Uri $url -OutFile $zip
        }
        Expand-Archive $zip -DestinationPath $OPENBLAS_ROOT -Force
        Write-Output "::endgroup::"
    }
}

# fail early and loudly if the BLAS provider layout changed
foreach ($file in $EXPECTED_FILES) {
    if (!(Test-Path $file)) {
        throw "${Blas}: expected file not found: $file"
    }
}

# configure build and compile
Write-Output "::group::Configure CMake and Build ($Blas) ..."
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
    @BLAS_ARGS `
    -DBUILD_SHARED_LIBS=ON `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

Write-Output "::group::Pack artifacts ..."

# copy the BLAS runtime next to faiss.dll
cp $RUNTIME_DLL $DIST_PATH\bin

# remap absolute path to relative dist path
$DOUBLE_QUOTE_PATH = $BLAS_LIB_PATH.Replace('\', '\\')
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
