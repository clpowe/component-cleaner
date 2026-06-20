const std = @import("std");

pub const Component = struct {
    name: []const u8,
    path: []const u8,
    used: bool = false,
};

fn isComponentFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".vue") or
        std.mem.endsWith(u8, path, ".tsx") or
        std.mem.endsWith(u8, path, ".jsx");
}

fn baseName(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/');
    const start = if (slash) |s| s + 1 else 0;
    const file = path[start..];
    const dot = std.mem.lastIndexOfScalar(u8, file, '.');
    return if (dot) |d| file[0..d] else file;
}

/// Identifier character: what a JS/TS symbol may contain. Used for whole-word
/// matching so "BaseButton" does not match inside "BaseButtonGroup".
fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

/// Kebab-tag character: what a kebab-case tag name may contain, so
/// "base-button" does not match inside "base-button-group".
fn isKebabChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-';
}

/// Whole-word substring search: finds `needle` in `haystack` only where it is
/// NOT flanked by characters `isWord` accepts. Avoids prefix false positives.
fn containsWord(haystack: []const u8, needle: []const u8, comptime isWord: fn (u8) bool) bool {
    if (needle.len == 0) return false;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, needle)) |idx| : (i = idx + 1) {
        const before_ok = idx == 0 or !isWord(haystack[idx - 1]);
        const after = idx + needle.len;
        const after_ok = after >= haystack.len or !isWord(haystack[after]);
        if (before_ok and after_ok) return true;
    }
    return false;
}

/// Convert a PascalCase name to its kebab-case tag form, matching how Vue
/// templates may reference it: "BaseButton" -> "base-button". Caller owns result.
fn toKebab(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (name, 0..) |c, idx| {
        if (c >= 'A' and c <= 'Z') {
            if (idx != 0) try out.append(allocator, '-');
            try out.append(allocator, c + 32);
        } else {
            try out.append(allocator, c);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// True if `content` references the component by either its PascalCase name
/// (tag, import, or registration) or its kebab-case tag.
fn isUsed(content: []const u8, name: []const u8, kebab: []const u8) bool {
    return containsWord(content, name, isIdentChar) or
        containsWord(content, kebab, isKebabChar);
}

/// Enumerate component files under `components_dir_path`, then scan
/// `scan_dir_path` once, marking each component used or unused. A component's
/// own definition file is skipped so a self-reference does not count as usage.
/// Caller owns the returned slice (allocator-backed).
pub fn findUnused(
    io: std.Io,
    allocator: std.mem.Allocator,
    components_dir_path: []const u8,
    scan_dir_path: []const u8,
) ![]Component {
    var components: std.ArrayList(Component) = .empty;
    var kebabs: std.ArrayList([]const u8) = .empty;
    // kebab tags are scratch — only needed during the scan pass below.
    defer {
        for (kebabs.items) |k| allocator.free(k);
        kebabs.deinit(allocator);
    }

    // Pass 1: collect every component definition file and its kebab tag.
    {
        var dir = try std.Io.Dir.cwd().openDir(io, components_dir_path, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!isComponentFile(entry.path)) continue;
            const name = try allocator.dupe(u8, baseName(entry.path));
            const path = try allocator.dupe(u8, entry.path);
            try components.append(allocator, .{ .name = name, .path = path });
            try kebabs.append(allocator, try toKebab(allocator, name));
        }
    }

    // Pass 2: read each source file once; mark any component it references.
    {
        var dir = try std.Io.Dir.cwd().openDir(io, scan_dir_path, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(allocator);
        defer walker.deinit();
        var read_buf: [64 * 1024]u8 = undefined;
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!isScanableFile(entry.path)) continue;

            const file = dir.openFile(io, entry.path, .{}) catch continue;
            defer file.close(io);
            var fr = file.reader(io, &read_buf);
            const content = fr.interface.allocRemaining(allocator, std.Io.Limit.limited(max_file_bytes)) catch continue;
            defer allocator.free(content);

            for (components.items, kebabs.items) |*comp, kebab| {
                if (comp.used) continue;
                if (std.mem.endsWith(u8, entry.path, comp.path)) continue; // own def file
                if (isUsed(content, comp.name, kebab)) comp.used = true;
            }
        }
    }

    return components.toOwnedSlice(allocator);
}

pub fn isScanableFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".vue") or
        std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".js") or
        std.mem.endsWith(u8, path, ".tsx") or
        std.mem.endsWith(u8, path, ".jsx");
}

const max_file_bytes = 5 * 1024 * 1024;

/// Returns the first file path where the component is used, or null.
/// Caller owns the returned slice.
pub fn findUsage(
    io: std.Io,
    allocator: std.mem.Allocator,
    component_name: []const u8,
    scan_dir_path: []const u8,
) !?[]const u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, scan_dir_path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    const open_tag = try std.fmt.allocPrint(allocator, "<{s}", .{component_name});
    defer allocator.free(open_tag);
    const import_name = try std.fmt.allocPrint(allocator, "import {s}", .{component_name});
    defer allocator.free(import_name);

    var read_buf: [64 * 1024]u8 = undefined;

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isScanableFile(entry.path)) continue;

        const file = dir.openFile(io, entry.path, .{}) catch continue;
        defer file.close(io);

        var file_reader = file.reader(io, &read_buf);
        const content = file_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(max_file_bytes)) catch continue;
        defer allocator.free(content);

        if (std.mem.indexOf(u8, content, open_tag) != null or
            std.mem.indexOf(u8, content, import_name) != null)
        {
            return try allocator.dupe(u8, entry.path);
        }
    }
    return null;
}

test "finds a used component" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const match = try findUsage(io, std.testing.allocator, "BaseButton", "test-fixtures");
    defer if (match) |m| std.testing.allocator.free(m);
    try std.testing.expect(match != null);
}

test "containsWord respects boundaries" {
    try std.testing.expect(containsWord("<BaseButton>", "BaseButton", isIdentChar));
    try std.testing.expect(containsWord("import BaseButton from \"x\"", "BaseButton", isIdentChar));
    try std.testing.expect(!containsWord("<BaseButtonGroup>", "BaseButton", isIdentChar));
    try std.testing.expect(containsWord("<base-button />", "base-button", isKebabChar));
    try std.testing.expect(!containsWord("<base-button-group />", "base-button", isKebabChar));
}

test "toKebab converts PascalCase" {
    const k = try toKebab(std.testing.allocator, "BaseButton");
    defer std.testing.allocator.free(k);
    try std.testing.expectEqualStrings("base-button", k);
}

// Exercises `baseName`/`toKebab`/`findUnused` end to end (and forces them to
// be analyzed by the test build). Fixtures: test-fixtures/components has four
// components; app/ uses BaseButton (Pascal tag + import) and BaseCard (kebab
// tag), leaving OldBanner and UnusedWidget dead.
test "findUnused flags dead components" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const comps = try findUnused(io, std.testing.allocator, "test-fixtures/components", "test-fixtures");
    defer {
        for (comps) |c| {
            std.testing.allocator.free(c.name);
            std.testing.allocator.free(c.path);
        }
        std.testing.allocator.free(comps);
    }

    var base_button_used = false;
    var base_card_used = false;
    var old_banner_used = false;
    var unused_widget_used = false;
    for (comps) |c| {
        if (std.mem.eql(u8, c.name, "BaseButton")) base_button_used = c.used;
        if (std.mem.eql(u8, c.name, "BaseCard")) base_card_used = c.used;
        if (std.mem.eql(u8, c.name, "OldBanner")) old_banner_used = c.used;
        if (std.mem.eql(u8, c.name, "UnusedWidget")) unused_widget_used = c.used;
    }

    try std.testing.expectEqual(@as(usize, 4), comps.len);
    try std.testing.expect(base_button_used); // Pascal tag + import
    try std.testing.expect(base_card_used); // kebab tag <base-card>
    try std.testing.expect(!old_banner_used); // dead
    try std.testing.expect(!unused_widget_used); // dead
}
