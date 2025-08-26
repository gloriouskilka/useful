sudo apt install bison libxi-dev libxtst-dev
    [? not for libtorch[core]? libxrender-dev [libx11-dev libgles2-mesa-dev]]

<!-- Fails to auto- download, loading from mirror -->
curl -L -o ./vcpkg/downloads/gettext-0.22.5.tar.gz https://ftpmirror.gnu.org/gnu/gettext/gettext-0.22.5.tar.gz

<!-- ./vcpkg/vcpkg install libtorch --triplet x64-linux -->
 
./vcpkg/vcpkg install 'libtorch[core]' --triplet x64-linux
