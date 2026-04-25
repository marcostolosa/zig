const Options = @This();

const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const Configuration = std.Build.Configuration;

const PrintDeclError = std.Io.Writer.Error || std.mem.Allocator.Error;
const indent_width = 4;
const indent_str: *const [indent_width]u8 = &@splat(' ');

step: Step,
generated_file: Configuration.GeneratedFileIndex,
contents: std.ArrayList(u8) = .empty,
args: std.ArrayList(Arg) = .empty,
printed_types: std.StringHashMapUnmanaged(void),

pub const base_tag: Step.Tag = .options;

pub const Arg = struct {
    name: Configuration.String,
    path: LazyPath,
};

pub fn create(owner: *std.Build) *Options {
    const graph = owner.graph;
    const arena = graph.arena;

    const options = arena.create(Options) catch @panic("OOM");
    options.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "options",
            .owner = owner,
        }),
        .generated_file = graph.addGeneratedFile(&options.step),
        .printed_types = .empty,
    };

    return options;
}

pub fn addOption(options: *Options, comptime T: type, name: []const u8, value: T) void {
    if (name.len == 0) @panic("name cannot be empty");
    return printDecl(options, T, name, value) catch @panic("unhandled error");
}

fn printDecl(options: *Options, comptime T: type, name: []const u8, value: T) PrintDeclError!void {
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    try printTypeDefinition(options, T);
    try out.print(gpa, "pub const {f}: ", .{fmtId(name)});
    try printTypeName(options, T, 0);
    try out.appendSlice(gpa, " = ");
    try printValue(options, T, value, 0);
    try out.appendSlice(gpa, ";\n\n");
}

fn printTypeDefinition(options: *Options, comptime T: type) PrintDeclError!void {
    if (T == std.SemanticVersion) return;

    const type_info = @typeInfo(T);
    switch (type_info) {
        inline .array, .optional => |info| return printTypeDefinition(options, info.child),
        .pointer => |pointer| {
            switch (pointer.size) {
                .one, .slice => return printTypeDefinition(options, pointer.child),
                .many => unsupported("many-item pointer", T),
                .c => unsupported("C pointer", T),
            }
        },
        .void, .bool, .int, .float, .comptime_int, .comptime_float, .enum_literal => return,
        .@"enum" => {},
        .@"struct" => |@"struct"| if (@"struct".is_tuple) unsupported("tuple", T),
        .@"union" => |@"union"| if (@"union".tag_type == null) unsupported("untagged union", T),
        else => |tag| unsupported(@tagName(tag), T),
    }

    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    const type_name = @typeName(T);
    const gop = try options.printed_types.getOrPut(gpa, type_name);
    if (gop.found_existing) return;

    switch (type_info) {
        .@"enum" => {
            try out.print(gpa, "pub const {f} = ", .{fmtId(type_name)});
            try printEnumDefinition(options, T);
            try out.appendSlice(gpa, ";\n\n");
        },
        .@"struct" => |@"struct"| {
            inline for (@"struct".field_types) |@"type"| {
                try printTypeDefinition(options, @"type");
            }

            try out.print(gpa, "pub const {f} = ", .{fmtId(type_name)});
            try printStructDefinition(options, T);
            try out.appendSlice(gpa, ";\n\n");
        },
        .@"union" => |@"union"| {
            try printTypeDefinition(options, @"union".tag_type.?);
            inline for (@"union".field_types) |@"type"| {
                try printTypeDefinition(options, @"type");
            }

            try out.print(gpa, "pub const {f} = ", .{fmtId(type_name)});
            try printUnionDefinition(options, T);
            try out.appendSlice(gpa, ";\n\n");
        },
        else => comptime unreachable,
    }
}

inline fn unsupported(comptime description: []const u8, comptime T: type) noreturn {
    @compileError(std.fmt.comptimePrint("{s} type '{s}' is not supported as a build option", .{ description, @typeName(T) }));
}

fn printEnumDefinition(options: *Options, comptime T: type) !void {
    const @"enum" = @typeInfo(T).@"enum";
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    try out.appendSlice(gpa, "enum(");
    try printTypeName(options, @"enum".tag_type, 0);
    try out.appendSlice(gpa, ")");
    if (@"enum".field_names.len == 0) {
        const body = switch (@"enum".mode) {
            .exhaustive => " {}",
            .nonexhaustive => " { _ }",
        };
        return out.appendSlice(gpa, body);
    }
    try out.appendSlice(gpa, " {\n");

    inline for (@"enum".field_names, @"enum".field_values) |name, value| {
        try out.print(gpa, indent_str ++ "{f} = {d},\n", .{ fmtEnumFieldName(name), value });
    }

    if (@"enum".mode == .nonexhaustive) {
        try out.appendSlice(gpa, indent_str ++ "_,\n");
    }

    try out.appendSlice(gpa, "}");
}

fn printStructDefinition(options: *Options, comptime T: type) !void {
    const @"struct" = @typeInfo(T).@"struct";
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    switch (@"struct".layout) {
        .auto => try out.appendSlice(gpa, "struct"),
        .@"extern" => try out.appendSlice(gpa, "extern struct"),
        .@"packed" => {
            try out.appendSlice(gpa, "packed struct(");
            try printTypeName(options, @"struct".backing_integer.?, 0);
            try out.appendSlice(gpa, ")");
        },
    }
    try printStructOrUnionBody(options, T);
}

fn printUnionDefinition(options: *Options, comptime T: type) !void {
    const @"union" = @typeInfo(T).@"union";
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    try out.appendSlice(gpa, "union(");
    try printTypeName(options, @"union".tag_type.?, 0);
    try out.appendSlice(gpa, ")");
    try printStructOrUnionBody(options, T);
}

fn printStructOrUnionBody(options: *Options, comptime T: type) !void {
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    const type_info = switch (@typeInfo(T)) {
        inline .@"struct", .@"union" => |info| info,
        else => comptime unreachable,
    };
    if (type_info.field_names.len == 0) return out.appendSlice(gpa, " {}");
    try out.appendSlice(gpa, " {\n");
    inline for (type_info.field_names, type_info.field_types, type_info.field_attrs) |name, @"type", attrs| {
        try out.appendSlice(gpa, indent_str);
        try out.print(gpa, "{f}: ", .{fmtStructUnionFieldName(name)});
        try printTypeName(options, @"type", indent_width);
        if (attrs.@"align") |alignment| try out.print(gpa, " align({d})", .{alignment});
        try out.appendSlice(gpa, ",\n");
    }
    try out.appendSlice(gpa, "}");
}

fn printTypeName(options: *Options, comptime T: type, indent: u8) !void {
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    if (T == std.SemanticVersion) {
        return out.appendSlice(gpa, "@import(\"std\").SemanticVersion");
    }

    switch (@typeInfo(T)) {
        .array => |array| {
            try out.print(gpa, "[{d}", .{array.len});
            if (array.sentinel()) |sentinel| {
                try out.appendSlice(gpa, ":");
                try printValue(options, array.child, sentinel, indent);
            }
            try out.appendSlice(gpa, "]");
            try printTypeName(options, array.child, indent);
        },
        .pointer => |pointer| {
            switch (pointer.size) {
                .one => try out.appendSlice(gpa, "*"),
                .slice => {
                    try out.appendSlice(gpa, "[");
                    if (pointer.sentinel()) |sentinel| {
                        try out.appendSlice(gpa, ":");
                        try printValue(options, pointer.child, sentinel, indent);
                    }
                    try out.appendSlice(gpa, "]");
                },
                .many, .c => comptime unreachable,
            }
            if (pointer.attrs.@"align") |alignment| try out.print(gpa, "align({d}) ", .{alignment});
            try out.appendSlice(gpa, "const ");
            try printTypeName(options, pointer.child, indent);
        },
        .optional => |optional| {
            try out.appendSlice(gpa, "?");
            try printTypeName(options, optional.child, indent);
        },
        .void, .bool, .int, .comptime_int, .enum_literal, .float, .comptime_float => try out.print(gpa, "{s}", .{@typeName(T)}),
        .@"enum", .@"struct", .@"union" => try out.print(gpa, "{f}", .{fmtId(@typeName(T))}),
        else => comptime unreachable,
    }
}

fn printValue(options: *Options, comptime T: type, value: T, indent: u8) PrintDeclError!void {
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    switch (@typeInfo(T)) {
        .array => try printArrayOrSlice(options, T, value, indent),
        .pointer => |pointer| {
            switch (pointer.size) {
                .one => {
                    const child_info = @typeInfo(pointer.child);
                    if (child_info == .array and child_info.array.child == u8 and (child_info.array.sentinel() orelse 0) == 0) {
                        return out.print(gpa, "\"{f}\"", .{std.zig.fmtString(value)});
                    }
                    try out.appendSlice(gpa, "&");
                    try printValue(options, pointer.child, value.*, indent);
                },
                .slice => {
                    if (pointer.child == u8 and (pointer.sentinel() orelse 0) == 0) {
                        return out.print(gpa, "\"{f}\"", .{std.zig.fmtString(value)});
                    }
                    try out.appendSlice(gpa, "&");
                    try printArrayOrSlice(options, T, value, indent);
                },
                .many, .c => comptime unreachable,
            }
        },
        .optional => |optional| {
            if (value) |inner| {
                try printValue(options, optional.child, inner, indent);
            } else {
                try out.appendSlice(gpa, "@as(");
                try printTypeName(options, T, indent);
                try out.appendSlice(gpa, ", null)");
            }
        },
        .void => try out.appendSlice(gpa, "{}"),
        .bool => try out.appendSlice(gpa, if (value) "true" else "false"),
        .int, .comptime_int => try out.print(gpa, "{d}", .{value}),
        .enum_literal => try out.print(gpa, ".{f}", .{fmtEnumFieldName(@tagName(value))}),
        .float => {
            if (std.math.isFinite(value))
                return out.print(gpa, "{e}", .{value});

            if (std.math.isPositiveInf(value))
                try out.appendSlice(gpa, "@import(\"std\").math.inf(")
            else if (std.math.isNegativeInf(value))
                try out.appendSlice(gpa, "-@import(\"std\").math.inf(")
            else if (std.math.isNan(value))
                try out.appendSlice(gpa, "@import(\"std\").math.snan(")
            else
                unreachable;

            try printTypeName(options, T, indent);
            try out.appendSlice(gpa, ")");
        },
        .comptime_float => try out.print(gpa, "{e}", .{value}),
        .@"enum" => |@"enum"| {
            switch (@"enum".mode) {
                .exhaustive => try out.print(gpa, ".{f}", .{fmtEnumFieldName(@tagName(value))}),
                .nonexhaustive => {
                    if (std.enums.tagName(T, value)) |name| {
                        try out.print(gpa, ".{f}", .{fmtEnumFieldName(name)});
                    } else {
                        try out.print(gpa, "@fromBackingInt({d})", .{@backingInt(value)});
                    }
                },
            }
        },
        .@"union" => {
            try out.appendSlice(gpa, ".{ ");
            switch (value) {
                inline else => |payload, tag| {
                    try out.print(gpa, ".{f} = ", .{fmtStructUnionFieldName(@tagName(tag))});
                    try printValue(options, @FieldType(T, @tagName(tag)), payload, indent);
                },
            }
            try out.appendSlice(gpa, " }");
        },
        .@"struct" => |@"struct"| {
            if (@"struct".field_names.len == 0) return out.appendSlice(gpa, ".{}");

            try out.appendSlice(gpa, ".{\n");
            inline for (@"struct".field_names, @"struct".field_types) |name, @"type"| {
                const field_indent = indent +| indent_width;
                try out.appendNTimes(gpa, ' ', field_indent);
                try out.print(gpa, ".{f} = ", .{fmtStructUnionFieldName(name)});
                try printValue(options, @"type", @field(value, name), field_indent);
                try out.appendSlice(gpa, ",\n");
            }
            try out.appendNTimes(gpa, ' ', indent);
            try out.appendSlice(gpa, "}");
        },
        else => comptime unreachable,
    }
}

fn printArrayOrSlice(options: *Options, comptime T: type, collection: T, indent: u8) PrintDeclError!void {
    const gpa = options.step.owner.allocator;
    const out = &options.contents;

    if (collection.len == 0) return out.appendSlice(gpa, ".{}");
    try out.appendSlice(gpa, ".{\n");

    const elem_indent = indent +| indent_width;
    for (collection) |item| {
        try out.appendNTimes(gpa, ' ', elem_indent);
        try printValue(options, std.meta.Child(T), item, elem_indent);
        try out.appendSlice(gpa, ",\n");
    }

    try out.appendNTimes(gpa, ' ', indent);
    try out.appendSlice(gpa, "}");
}

const fmtId = std.zig.fmtId;

fn fmtEnumFieldName(field_name: []const u8) std.zig.FormatId {
    return std.zig.fmtIdFlags(field_name, .{ .allow_primitive = true });
}

fn fmtStructUnionFieldName(field_name: []const u8) std.zig.FormatId {
    return std.zig.fmtIdFlags(field_name, .{ .allow_primitive = true, .allow_underscore = true });
}

/// The added option has type `[]const u8` and value of the provided path.
pub fn addOptionPath(options: *Options, name: []const u8, path: LazyPath) void {
    const graph = options.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;

    options.args.append(arena, .{
        .name = wc.addString(name) catch @panic("OOM"),
        .path = path.dupe(options.step.owner.graph),
    }) catch @panic("OOM");
    path.addStepDependencies(&options.step);
}

pub fn createModule(options: *Options) *std.Build.Module {
    return options.step.owner.createModule(.{
        .root_source_file = options.getOutput(),
    });
}

/// Returns the main artifact of this Build Step which is a Zig source file
/// generated from the key-value pairs of the Options.
pub fn getOutput(options: *Options) LazyPath {
    return .{ .generated = .{ .index = options.generated_file } };
}
