# Xv6 x86

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This is a fork of the original Xv6 x86 educational operating system. The main goal of this repository is to serve as a personal playground for learning OS concepts by implementing new features, tweaking the kernel, and experimenting with drivers and filesystems. All modifications and experiments are documented through the commit history.

## Building and running
1.  **Build the disk image:**
    ```bash
    make all
    ```
2.  **Run Xv6 in QEMU:**
    ```bash
    make qemu
    ```
3. **Run Xv6 in QEMU without graphics:**
    ```bash
    make qemu-nox
    ```
4.  **Clean the build files:**
    ```bash
    make clean
    ```

## Project structure
```
.
├── build       => All build artifacts (out-of-source)
├── include     => Shared headers for kernel and user space
├── kernel      => Kernel source files
├── tools       => Host tools to build the filesystem and disk images
└── user        => User space sources and libraries
    ├── apps        => User programs included in the final disk image
    ├── include     => Headers for custom user libraries
    ├── lib         => Core user libraries (printf, ulib, etc.)
    └── src         => Source code for custom user libraries
```

## Toolchain

You need a 32-bit x86 cross-toolchain (gcc/binutils) to build.

I personally use versions [recommended by MIT](https://pdos.csail.mit.edu/6.828/2018/tools.html).
```
gmp 5.0.2
mpfr 3.1.2
mpc 0.9
binutils 2.21.1
gcc 4.6.4 (i386-jos-elf)
gdb 7.3.1
```

Also Python 2.4.6 [(For older patched version of QEMU)](https://github.com/mit-pdos/6.828-qemu).

## What this repo is / is not

Is: educational experiments, kernel tweaks, toy drivers, filesystem experiments.

Is not: production OS, security-hardened, or hardened for real deployment.

## License
MIT — see [LICENSE](./LICENSE)