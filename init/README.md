## How the Zig init works

1. Signal handler setup (lines 33-37)

std.posix.sigaction(.CHLD, &sa, null);
Registers onSigchld as the kernel callback for child exits. Without this, PID 1 would never reap zombie processes every time ash exits, the child would stay as <defunct> forever.

2. Filesystem mounts (lines 39-49)

Each mount() call is the kernel mount(2) syscall the raw Linux equivalent of what mount -t proc proc /proc does in a shell script. devtmpfs on /dev is the kernel's built-in device-filesystem that auto-populates device nodes like /dev/tty1 without needing mknod. /dev/pts, /tmp, /run are tmpfs mounts so they're writable (the initramfs itself is read-only).

3. Device nodes & symlinks (lines 51-56)

mknod creates /dev/console and /dev/null as fallbacks in case devtmpfs isn't available (older kernel configs). /dev/fd → /proc/self/fd and friends are POSIX convention that tools like bash depend on.

4. Hostname & PATH (lines 58-61)

sethostname sets the kernel hostname (what uname -n returns). setenv("PATH", ...) and setenv("HOME", "/root") are libc functions (we link musl statically) that write into the process's environ array all child processes inherit this, so ash and busybox find each other.

5. Fork/exec loop (lines 63, 97-116)

spawn(svc);
fork() duplicates the process: the child gets PID 0 from the syscall's return value, stays in main(), calls setsid() (new session needed for controlling terminal), opens the tty as stdin/stdout/stderr via dup3(), then execve("/bin/ash", ["ash", "-l"], environ) replaces itself with the shell. The parent (PID 1) goes back to the loop.

6. Main loop (line 65)

while (true) _ = linux.pause();
pause() sleeps PID 1 until any signal arrives. SIGCHLD wakes it → onSigchld reaps zombies → back to sleep. When no signal is pending, the kernel idles (near-zero CPU).