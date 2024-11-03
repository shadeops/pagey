# Pagey

This is a small demo app of how to monitor which file pages are
currently loaded into resident memory.

Pagey was used as part of a demo in the 
[Tales From the Ticket Queue](https://softwareyoucanlove.ca/talks/tales-from-the-ticket-queue) from the
[Software You Can Love 2023](https://softwareyoucanlove.ca) conference in Vancouver.

# To Use:
```
git clone --recursive https://github.com/shadeops/pagey.git
cd pagey
zig build
./zig-out/bin/pagey <some file>

# If you wish to flush your kernel page cache then you can do
sudo ./zig-out/bin/flush
```

Once Pagey is running:
* LMB triggers a file page to load through a pread64()
* RMB triggers a file page to load through a mmap() file handle.
* F1 - Sets madvise to NORMAL
* F2 - Sets madvise to SEQUENTIAL
* F3 - Sets madivse to RANDOM

# Requirements
* Linux x86
* [Zig 0.12.1](https://ziglang.org/download/)
