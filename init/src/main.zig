// init.zig Zig PID 1 for distrox (Zig 0.16.0)
// Replaces: init.sh + /sbin/init + OpenRC
// Build:   zig build --release=small -Dtarget=x86_64-linux-musl

const std = @import("std");
const linux = std.os.linux;

const Service = struct {
    tty: [:0]const u8,
    cmd: [:0]const u8,
    args: [:0]const u8,
    respawn: bool,
};

const services = [_]Service{
    .{ .tty = "/dev/tty1",  .cmd = "/bin/ash", .args = "-l", .respawn = true },
    .{ .tty = "/dev/ttyS0", .cmd = "/bin/ash", .args = "-l", .respawn = true },
};

const MS_RDONLY = 1;
const MS_NOSUID  = 2;
const MS_NODEV   = 4;
const MS_NOEXEC  = 8;

pub fn main() u8 {
    const sa: std.posix.Sigaction = .{
        .handler = .{ .sigaction = onSigchld },
        .mask = std.posix.sigemptyset(),
        .flags = linux.SA.SIGINFO | linux.SA.RESTART | linux.SA.NOCLDSTOP,
    };
    std.posix.sigaction(.CHLD, &sa, null);

    mount("proc",    "/proc",     "proc",      MS_NOSUID|MS_NOEXEC|MS_NODEV, "");
    mount("sysfs",   "/sys",      "sysfs",     MS_NOSUID|MS_NOEXEC|MS_NODEV, "");
    mount("devtmpfs","/dev",      "devtmpfs",  MS_NOSUID, "");
    _ = linux.mkdirat(linux.AT.FDCWD, "/dev/pts", 0o755);
    mount("devpts",  "/dev/pts",  "devpts",    0, "mode=0620,gid=5");
    _ = linux.mkdirat(linux.AT.FDCWD, "/tmp", 0o777);
    mount("tmpfs",   "/tmp",      "tmpfs",     MS_NOSUID|MS_NODEV, "");
    _ = linux.mkdirat(linux.AT.FDCWD, "/run", 0o755);
    mount("tmpfs",   "/run",      "tmpfs",     MS_NOSUID|MS_NODEV|MS_NOEXEC, "");

    mknod("/dev/console", 0o600, (5 << 8) | 1);
    mknod("/dev/null",    0o666, (1 << 8) | 3);

    symlink("/proc/self/fd",    "/dev/fd");
    symlink("/proc/self/fd/0",  "/dev/stdin");
    symlink("/proc/self/fd/1",  "/dev/stdout");
    symlink("/proc/self/fd/2",  "/dev/stderr");

    const host = "distrox";
    _ = linux.syscall2(.sethostname, @intFromPtr(host.ptr), host.len);

    for (services) |svc| spawn(svc);

    while (true) _ = linux.pause();
}

// =============================================================
// SIGCHLD handler (three-arg, SA_SIGINFO)
// =============================================================

fn onSigchld(
    _: std.posix.SIG,
    _: *const std.posix.siginfo_t,
    _: ?*anyopaque,
) callconv(.c) void {
    var status: u32 = 0;
    while (true) {
        const pid = linux.waitpid(-1, &status, linux.W.NOHANG);
        if (pid == 0 or pid > 0x7FFFFFFF) break;
    }
}

// =============================================================
// spawn fork + exec ash on a tty
// =============================================================

fn spawn(svc: Service) void {
    const pid = blk: {
        const p = linux.fork();
        if (p > 0x7FFFFFFF) return;
        break :blk p;
    };
    if (pid != 0) return;

    _ = linux.setsid();

    const fd = linux.openat(linux.AT.FDCWD, svc.tty, linux.O{
        .ACCMODE = .RDWR,
        .NOCTTY = true,
    }, 0);
    if (fd <= 0x7FFFFFFF) {
        _ = linux.dup3(@intCast(fd), 0, 0);
        _ = linux.dup3(@intCast(fd), 1, 0);
        _ = linux.dup3(@intCast(fd), 2, 0);
        if (fd > 2) _ = linux.close(@intCast(fd));
    }

    var argv: [4:null]?[*:0]const u8 = undefined;
    argv[0] = svc.cmd;
    argv[1] = svc.args;
    argv[2] = null;
    argv[3] = null;
    _ = linux.execve(svc.cmd, &argv, @ptrCast(std.c.environ));
    std.process.exit(1);
}

// =============================================================
// mount mount(2) wrapper (all args are string literals)
// =============================================================

fn mount(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
    data: [:0]const u8,
) void {
    _ = linux.mount(source, target, fstype, flags, @intFromPtr(data.ptr));
}

// =============================================================
// mknod create a character device (S_IFCHR)
// =============================================================

fn mknod(path: [:0]const u8, mode: u32, dev: u32) void {
    _ = linux.mknodat(linux.AT.FDCWD, path, 0o20000 | mode, dev);
}

// =============================================================
// symlink symlinkat(2) wrapper
// =============================================================

fn symlink(existing: [:0]const u8, newpath: [:0]const u8) void {
    _ = linux.symlinkat(existing, linux.AT.FDCWD, newpath);
}
