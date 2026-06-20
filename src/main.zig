const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");
const scan = @import("scan.zig");

const ScanRequest = struct {
    componentName: []const u8,
    scanDir: []const u8,
};

const ScanResult = struct {
    used: bool,
    file: ?[]const u8 = null,
};

const ScanUnusedRequest = struct {
    componentsDir: []const u8,
    scanDir: []const u8,
};

fn runScan(io: std.Io, allocator: std.mem.Allocator, payload: []const u8, output: []u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const parsed = try std.json.parseFromSlice(ScanRequest, a, payload, .{});
    const req = parsed.value;

    const match = try scan.findUsage(io, a, req.componentName, req.scanDir);

    if (match) |path| {
        var path_buf: [4096]u8 = undefined;
        const json_path = zero_native.bridge.writeJsonStringValue(&path_buf, path);
        return std.fmt.bufPrint(output, "{{\"used\":true,\"file\":{s}}}", .{json_path});
    }

    return std.fmt.bufPrint(output, "{{\"used\":false}}", .{});
}

fn runScanUnused(io: std.Io, allocator: std.mem.Allocator, payload: []const u8, output: []u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const parsed = try std.json.parseFromSlice(ScanUnusedRequest, a, payload, .{});
    const req = parsed.value;

    const comps = try scan.findUnused(io, a, req.componentsDir, req.scanDir);

    var w = std.Io.Writer.fixed(output);
    try w.print("{{\"total\":{d},\"unused\":[", .{comps.len});
    var first = true;
    var name_buf: [1024]u8 = undefined;
    var path_buf: [4096]u8 = undefined;
    for (comps) |c| {
        if (c.used) continue;
        if (!first) try w.writeByte(',');
        first = false;
        const jn = zero_native.bridge.writeJsonStringValue(&name_buf, c.name);
        const jp = zero_native.bridge.writeJsonStringValue(&path_buf, c.path);
        try w.print("{{\"name\":{s},\"path\":{s}}}", .{ jn, jp });
    }
    try w.writeAll("]}");
    return w.buffered();
}

fn scanUnused(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]const u8 {
    const self: *App = @ptrCast(@alignCast(context));
    return runScanUnused(self.io, self.allocator, invocation.request.payload, output);
}

fn scanComponent(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]const u8 {
    const self: *App = @ptrCast(@alignCast(context));
    return runScan(self.io, self.allocator, invocation.request.payload, output);
}

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

const command_policies = [_]zero_native.BridgeCommandPolicy{
    .{ .name = "native.scanComponent" },
    .{ .name = "native.scanUnused" },
};

const builtin_command_policies = [_]zero_native.BridgeCommandPolicy{
    .{ .name = "zero-native.dialog.openFile" },
};

const App = struct {
    env_map: *std.process.Environ.Map,
    io: std.Io,
    allocator: std.mem.Allocator,
    handlers: [2]zero_native.BridgeHandler = undefined,

    fn app(self: *@This()) zero_native.App {
        return .{
            .context = self,
            .name = "component-cleaner",
            .source = zero_native.frontend.productionSource(.{ .dist = "frontend/dist" }),
            .source_fn = source,
        };
    }

    fn bridge(self: *@This()) zero_native.BridgeDispatcher {
        self.handlers = .{
            .{ .name = "native.scanComponent", .context = self, .invoke_fn = scanComponent },
            .{ .name = "native.scanUnused", .context = self, .invoke_fn = scanUnused },
        };
        return .{
            .policy = .{ .enabled = true, .commands = &command_policies },
            .registry = .{ .handlers = &self.handlers },
        };
    }

    fn source(context: *anyopaque) anyerror!zero_native.WebViewSource {
        const self: *@This() = @ptrCast(@alignCast(context));
        return zero_native.frontend.sourceFromEnv(self.env_map, .{
            .dist = "frontend/dist",
            .entry = "index.html",
        });
    }
};

const dev_origins = [_][]const u8{ "zero://app", "zero://inline", "http://127.0.0.1:5173" };

pub fn main(init: std.process.Init) !void {
    var app = App{
        .env_map = init.environ_map,
        .io = init.io,
        .allocator = std.heap.smp_allocator,
    };
    try runner.runWithOptions(app.app(), .{
        .app_name = "Component Cleaner",
        .window_title = "Component Cleaner",
        .bundle_id = "dev.zero_native.component-cleaner",
        .icon_path = "assets/icon.icns",
        .bridge = app.bridge(),
        .builtin_bridge = .{ .enabled = true, .commands = &builtin_command_policies },
        .security = .{
            .navigation = .{ .allowed_origins = &dev_origins },
        },
    }, init);
}

test "app name is configured" {
    try std.testing.expectEqualStrings("component-cleaner", "component-cleaner");
}

test "runScan reports a used component" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var output: [4096]u8 = undefined;
    const payload =
        \\{"componentName":"BaseButton","scanDir":"test-fixtures"}
    ;
    const json = try runScan(io, std.testing.allocator, payload, &output);

    const parsed = try std.json.parseFromSlice(ScanResult, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.used);
    try std.testing.expect(parsed.value.file != null);
}

test "runScan reports an unused component" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var output: [4096]u8 = undefined;
    const payload =
        \\{"componentName":"NopeNotHere","scanDir":"test-fixtures"}
    ;
    const json = try runScan(io, std.testing.allocator, payload, &output);

    const parsed = try std.json.parseFromSlice(ScanResult, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(!parsed.value.used);
}
