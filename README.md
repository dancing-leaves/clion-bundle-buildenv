# clion-bundle-buildenv
Dockerfiles and PKGBUILD scripts for building GDB and LLDB for MinGW-W64 and Linux


## Building

### MinGW-W64

Run the Docker container with the repository root (containing `build.sh`) mounted as `/workdir`:
```
docker build -t abusalimov/clion-bundle-buildenv/mingw:latest -f dockerfiles/mingw.Dockerfile dockerfiles
docker run -v $(pwd):/workdir -it abusalimov/clion-bundle-buildenv/mingw:latest
```

Run the `./build.sh` script inside the Docker container:
```
./build.sh -P mingw -c makepkg-mingw32.conf -- gdb lldb
```
(Use `makepkg-mingw64.conf` to build 64-bit packages instead.)

Artifacts will appear in the `artifacts-i686-w64-mingw32` directory:
```
$ ls artifacts-i686-w64-mingw32/bundle*
artifacts-i686-w64-mingw32/bundle.tar.xz

artifacts-i686-w64-mingw32/bundle:
win
```


### Linux

Run the Docker container with the repository root (containing `build.sh`) mounted as `/workdir`:
```
docker build -t abusalimov/clion-bundle-buildenv/linux:latest -f dockerfiles/linux.Dockerfile dockerfiles
docker run -v $(pwd):/workdir -it abusalimov/clion-bundle-buildenv/linux:latest
```

Run the `./build.sh` script inside the Docker container:
```
cd linux
./build.sh -P linux -- gdb lldb
```

Artifacts will appear in the `artifacts-x86_64-redhat-linux` directory:
```
$ ls artifacts-x86_64-redhat-linux/bundle*
artifacts-x86_64-redhat-linux/bundle.tar.xz

artifacts-x86_64-redhat-linux/bundle:
linux
```

