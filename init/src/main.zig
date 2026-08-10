// init.zig Zig PID 1 for distrox (Zig 0.16.0)
// Replaces: init.sh + /sbin/init + OpenRC
// Build:   zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall

const std = @import("std");
const linux = std.os.linux;

// ---------------------------------------------------------------
// inittab declarative service list
// ---------------------------------------------------------------
const Service = struct {
    tty: [:0]const u8,
    cmd: [:0]const u8,
    args: [:0]const u8, // extra arg (e.g. "-l" for login shell)
    respawn: bool,
};

const services = [_]Service{
    .{ .tty = "/dev/tty1",  .cmd = "/bin/ash", .args = "-l", .respawn = true },
    .{ .tty = "/dev/ttyS0", .cmd = "/bin/ash", .args = "-l", .respawn = true },
};

// ---------------------------------------------------------------
// Linux mount flags
// ---------------------------------------------------------------
const MS_RDONLY = 1;
const MS_NOSUID  = 2;
const MS_NODEV   = 4;
const MS_NOEXEC  = 8;
const MS_NOATIME = 1024;

pub fn main() u8 {
    const sa: std.posix.Sigaction = .{
        .handler = .{ .sigaction = sigchldHandler },
        .mask = std.posix.sigemptyset(),
        .flags = linux.SA.SIGINFO | linux.SA.RESTART | linux.SA.NOCLDSTOP,
    };
    std.posix.sigaction(.CHLD, &sa, null);

    mount("proc",    "/proc",     "proc",      MS_NOSUID|MS_NOEXEC|MS_NODEV, null) catch {};
    mount("sysfs",   "/sys",      "sysfs",     MS_NOSUID|MS_NOEXEC|MS_NODEV, null) catch {};
    mount("devtmpfs","/dev",      "devtmpfs",  MS_NOSUID, null) catch {};
    _ = linux.mkdirat(linux.AT.FDCWD, "/dev/pts", 0o755);
    mount("devpts",  "/dev/pts",  "devpts",    0, "mode=0620,gid=5") catch {};
    _ = linux.mkdirat(linux.AT.FDCWD, "/tmp", 0o777);
    mount("tmpfs",   "/tmp",      "tmpfs",     MS_NOSUID|MS_NODEV, null) catch {};
    _ = linux.mkdirat(linux.AT.FDCWD, "/run", 0o755);
    mount("tmpfs",   "/run",      "tmpfs",     MS_NOSUID|MS_NODEV|MS_NOEXEC, null) catch {};

    mknod("/dev/console", 0o600, (5 << 8) | 1);
    mknod("/dev/null",    0o666, (1 << 8) | 3);

    std.fs.cwd().symLink("/proc/self/fd",    "/dev/fd",     .{}) catch {};
    std.fs.cwd().symLink("/proc/self/fd/0",  "/dev/stdin",  .{}) catch {};
    std.fs.cwd().symLink("/proc/self/fd/1",  "/dev/stdout", .{}) catch {};
    std.fs.cwd().symLink("/proc/self/fd/2",  "/dev/stderr", .{}) catch {};

    const host = "distrox";
    _ = linux.syscall2(.sethostname, @intFromPtr(host.ptr), host.len);

    for (services) |svc| spawn(svc);

    while (true) _ = linux.pause();
}

// =============================================================
// Signal handler (three-arg SA_SIGINFO)
// =============================================================

fn sigchldHandler(
    sig: std.posix.SIG,
    info: *const std.posix.siginfo_t,
    ctx: ?*anyopaque,
) callconv(.c) void {
    _ = sig;
    _ = info;
    _ = ctx;

    var status: u32 = 0;
    while (true) {
        const pid = linux.waitpid(-1, &status, linux.W.NOHANG);
        if (pid == 0 or pid > 0x7FFFFFFF) break;
    }
}

// =============================================================
// spawn fork + exec a service on its tty
// =============================================================

fn spawn(svc: Service) void {
    const pid = blk: {
        const p = linux.fork();
        if (p > 0x7FFFFFFF) return; // EAGAIN/ENOMEM
        break :blk p;
    };

    if (pid == 0) {
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

        const argv: [4:null]?[*:0]const u8 = .{
            svc.cmd, svc.args, null, null,
        };
        _ = linux.execve(svc.cmd, &argv, &std.os.environ);
        std.process.exit(1);
    }
}

// =============================================================
// mount thin wrapper around mount(2)
// =============================================================

fn mount(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
    data: ?[:0]const u8,
) !void {
    const data_ptr: usize = if (data) |d| @intFromPtr(d.ptr) else 0;
    _ = linux.mount(source, target, fstype, flags, data_ptr);
}

// =============================================================
// mknod create a character device node
// =============================================================

fn mknod(path: [:0]const u8, mode: u32, dev: u32) void {
    const S_IFCHR = 0o20000;
    _ = linux.mknodat(linux.AT.FDCWD, path, S_IFCHR | mode, dev);
}
