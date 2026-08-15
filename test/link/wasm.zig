const std = @import("std");
const wasm = std.wasm;
const Build = std.Build;
const Step = Build.Step;

pub fn addCases(build: *Build, step: *Step, test_filters: []const []const u8) void {
    if (includeTest(test_filters, "wasm-function-relocation")) {
        testFunctionRelocation(build, step);
    }
    if (includeTest(test_filters, "wasm-weak-symbol")) {
        testWeakSymbol(build, step);
    }
}

fn includeTest(test_filters: []const []const u8, name: []const u8) bool {
    return for (test_filters) |filter| {
        if (std.mem.find(u8, name, filter) != null) break true;
    } else test_filters.len == 0;
}

const Builder = struct {
    output: std.Io.Writer.Allocating,

    fn init(allocator: std.mem.Allocator) Builder {
        return .{ .output = .init(allocator) };
    }

    fn bytes(b: *Builder, value: []const u8) void {
        b.output.writer.writeAll(value) catch @panic("OOM");
    }

    fn byte(b: *Builder, value: u8) void {
        b.output.writer.writeByte(value) catch @panic("OOM");
    }

    fn uleb128(b: *Builder, value: anytype) void {
        b.output.writer.writeUleb128(value) catch @panic("OOM");
    }

    fn ileb128(b: *Builder, value: anytype) void {
        b.output.writer.writeSleb128(value) catch @panic("OOM");
    }

    fn uleb128Fixed(b: *Builder, comptime size: usize, value: @Int(.unsigned, size * 7)) void {
        var encoded: [size]u8 = undefined;
        std.leb.writeUnsignedFixed(size, &encoded, value);
        b.bytes(&encoded);
    }

    fn string(b: *Builder, value: []const u8) void {
        b.uleb128(value.len);
        b.bytes(value);
    }

    fn section(b: *Builder, id: Section, value: []const u8) void {
        b.byte(@backingInt(id));
        b.uleb128(value.len);
        b.bytes(value);
    }

    fn written(b: *Builder) []const u8 {
        return b.output.written();
    }

    fn clear(b: *Builder) void {
        b.output.clearRetainingCapacity();
    }
};

const wasm_header = wasm.magic ++ wasm.version;

const ExternalKind = wasm.ExternalKind;
const Opcode = wasm.Opcode;
const Section = wasm.Section;
const Valtype = wasm.Valtype;

const LinkingSubsection = wasm.LinkingSubsection;
const LinkingSymbolFlags = wasm.LinkingSymbolFlags;
const LinkingSymbolType = wasm.LinkingSymbolType;
const RelocationType = wasm.RelocationType;

fn testFunctionRelocation(build: *Build, step: *Step) void {
    const allocator = build.allocator;

    var section: Builder = .init(allocator);
    var body: Builder = .init(allocator);
    var symbols: Builder = .init(allocator);

    var a: Builder = .init(allocator);
    a.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    a.section(.type, section.written());
    section.clear();

    // import section
    section.uleb128(1); // count
    section.string("env");
    section.string("B");
    section.byte(@backingInt(ExternalKind.function));
    section.uleb128(0); // type index
    a.section(.import, section.written());
    section.clear();

    // function section
    section.uleb128(1); // count
    section.uleb128(0);
    a.section(.function, section.written());
    section.clear();

    // code section
    // a body
    body.uleb128(0); // local count
    body.byte(@backingInt(Opcode.call));
    body.uleb128Fixed(5, 0); // relocation placeholder
    body.byte(@backingInt(Opcode.end));
    section.uleb128(1); // count
    section.string(body.written());
    a.section(.code, section.written());
    body.clear();
    section.clear();

    // linking section
    symbols.uleb128(2); // count
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{ .visibility_hidden = true })));
    symbols.uleb128(1); // function index
    symbols.string("A");
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{ .undefined = true })));
    symbols.uleb128(0); // imported function index

    section.string("linking");
    section.uleb128(2); // version
    section.byte(@backingInt(LinkingSubsection.symbol_table));
    section.string(symbols.written());
    a.section(.custom, section.written());
    symbols.clear();
    section.clear();

    // reloc.code section
    section.string("reloc.CODE");
    section.uleb128(3); // code section index in binary
    section.uleb128(1); // relocation count
    section.byte(@backingInt(RelocationType.function_index_leb));
    section.uleb128(4); // call operand offset
    section.uleb128(1); // b symbol index
    a.section(.custom, section.written());
    section.clear();

    var b: Builder = .init(allocator);
    b.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    b.section(.type, section.written());
    section.clear();

    // function section
    section.uleb128(1); // count
    section.uleb128(0);
    b.section(.function, section.written());
    section.clear();

    // code section
    // b body
    body.uleb128(0); // local count
    body.byte(@backingInt(Opcode.i32_const));
    body.ileb128(42);
    body.byte(@backingInt(Opcode.end));
    section.uleb128(1); // count
    section.string(body.written());
    b.section(.code, section.written());
    body.clear();
    section.clear();

    // linking section
    symbols.uleb128(1); // count
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{ .visibility_hidden = true })));
    symbols.uleb128(0); // function index
    symbols.string("B");

    section.string("linking");
    section.uleb128(2); // version
    section.byte(@backingInt(LinkingSubsection.symbol_table));
    section.string(symbols.written());
    b.section(.custom, section.written());
    symbols.clear();
    section.clear();

    var expected_with_export: Builder = .init(allocator);
    expected_with_export.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    expected_with_export.section(.type, section.written());
    section.clear();

    // function section
    section.uleb128(2); // count
    section.uleb128(0);
    section.uleb128(0);
    expected_with_export.section(.function, section.written());
    section.clear();

    // memory section
    section.uleb128(1); // count
    section.uleb128(0);
    section.uleb128(16);
    expected_with_export.section(.memory, section.written());
    section.clear();

    // export section
    section.uleb128(2); // count
    section.string("A");
    section.byte(@backingInt(ExternalKind.function));
    section.uleb128(0);
    section.string("memory");
    section.byte(@backingInt(ExternalKind.memory));
    section.uleb128(0);
    expected_with_export.section(.@"export", section.written());
    section.clear();

    // code section
    section.uleb128(2); // count
    // a body
    body.uleb128(0); // local count
    body.byte(@backingInt(Opcode.call));
    body.uleb128Fixed(5, 1); // b index
    body.byte(@backingInt(Opcode.end));
    section.string(body.written());
    body.clear();
    // b body
    body.uleb128(0); // local count
    body.byte(@backingInt(Opcode.i32_const));
    body.ileb128(42);
    body.byte(@backingInt(Opcode.end));
    section.string(body.written());
    expected_with_export.section(.code, section.written());
    body.clear();
    section.clear();

    var expected_without_export: Builder = .init(allocator);
    expected_without_export.bytes(&wasm_header);

    // memory section
    section.uleb128(1); // count
    section.uleb128(0);
    section.uleb128(16);
    expected_without_export.section(.memory, section.written());
    section.clear();

    // export section
    section.uleb128(1); // count
    section.string("memory");
    section.byte(@backingInt(ExternalKind.memory));
    section.uleb128(0);
    expected_without_export.section(.@"export", section.written());

    const write_files = build.addWriteFiles();
    const a_file = write_files.add("a.o", a.written());
    const b_file = write_files.add("b.o", b.written());

    const run_export = build.addSystemCommand(&.{ build.graph.zig_exe, "build-exe" });
    run_export.addFileArg(a_file);
    run_export.addFileArg(b_file);
    run_export.addArgs(&.{
        "-target",
        "wasm32-freestanding",
        "-fno-entry",
        "--export=A",
        "-fno-llvm",
        "-fno-lld",
        "-fstrip",
    });
    const actual_export = run_export.addOutputFileArg2("actual.wasm", .{ .prefix = "-femit-bin=" });

    const check_export = build.addCheckFile(actual_export, .{
        .expected_exact = expected_with_export.written(),
    });
    check_export.setName("wasm-function-relocation-export");
    step.dependOn(&check_export.step);

    const run_no_export = build.addSystemCommand(&.{ build.graph.zig_exe, "build-exe" });
    run_no_export.addFileArg(a_file);
    run_no_export.addFileArg(b_file);
    run_no_export.addArgs(&.{
        "-target",
        "wasm32-freestanding",
        "-fno-entry",
        "-fno-llvm",
        "-fno-lld",
        "-fstrip",
    });
    const actual_no_export = run_no_export.addOutputFileArg2("actual-no-export.wasm", .{ .prefix = "-femit-bin=" });

    const check_no_export = build.addCheckFile(actual_no_export, .{
        .expected_exact = expected_without_export.written(),
    });
    check_no_export.setName("wasm-function-relocation-no-export");
    step.dependOn(&check_no_export.step);
}

fn testWeakSymbol(build: *Build, step: *Step) void {
    const allocator = build.allocator;

    var section: Builder = .init(allocator);
    var body: Builder = .init(allocator);
    var symbols: Builder = .init(allocator);

    var a: Builder = .init(allocator);
    a.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    a.section(.type, section.written());
    section.clear();

    // function section
    section.uleb128(1); // count
    section.uleb128(0);
    a.section(.function, section.written());
    section.clear();

    // code section
    // weak foo body
    body.uleb128(0);
    body.byte(@backingInt(Opcode.i32_const));
    body.ileb128(1);
    body.byte(@backingInt(Opcode.end));
    section.uleb128(1); // count
    section.string(body.written());
    a.section(.code, section.written());
    body.clear();
    section.clear();

    // linking section
    symbols.uleb128(1); // count
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{
        .binding = .weak,
        .visibility_hidden = true,
    })));
    symbols.uleb128(0);
    symbols.string("foo");

    section.string("linking");
    section.uleb128(2); // version
    section.byte(@backingInt(LinkingSubsection.symbol_table));
    section.string(symbols.written());
    a.section(.custom, section.written());
    symbols.clear();
    section.clear();

    var b: Builder = .init(allocator);
    b.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    b.section(.type, section.written());
    section.clear();

    // function section
    section.uleb128(1); // count
    section.uleb128(0);
    b.section(.function, section.written());
    section.clear();

    // code section
    // strong foo body
    body.uleb128(0);
    body.byte(@backingInt(Opcode.i32_const));
    body.ileb128(42);
    body.byte(@backingInt(Opcode.end));
    section.uleb128(1); // count
    section.string(body.written());
    b.section(.code, section.written());
    body.clear();
    section.clear();

    // linking section
    symbols.uleb128(1); // count
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{ .visibility_hidden = true })));
    symbols.uleb128(0);
    symbols.string("foo");

    section.string("linking");
    section.uleb128(2); // version
    section.byte(@backingInt(LinkingSubsection.symbol_table));
    section.string(symbols.written());
    b.section(.custom, section.written());
    symbols.clear();
    section.clear();

    var c: Builder = .init(allocator);
    c.bytes(&wasm_header);

    // type section
    section.uleb128(1); // count
    section.byte(wasm.function_type); // () -> (i32)
    section.uleb128(0);
    section.uleb128(1);
    section.byte(@backingInt(Valtype.i32));
    c.section(.type, section.written());
    section.clear();

    // import section
    section.uleb128(1); // count
    section.string("env");
    section.string("__linear_memory");
    section.byte(@backingInt(ExternalKind.memory));
    section.uleb128(0);
    section.uleb128(0);
    c.section(.import, section.written());
    section.clear();

    // function section
    section.uleb128(1); // count
    section.uleb128(0);
    c.section(.function, section.written());
    section.clear();

    // code section
    // strong foo body
    body.uleb128(0);
    body.byte(@backingInt(Opcode.i32_const));
    body.ileb128(42);
    body.byte(@backingInt(Opcode.end));
    section.uleb128(1); // count
    section.string(body.written());
    c.section(.code, section.written());
    body.clear();
    section.clear();

    // linking section
    symbols.uleb128(1); // count
    symbols.byte(@backingInt(LinkingSymbolType.function));
    symbols.uleb128(@backingInt(@as(LinkingSymbolFlags, .{ .visibility_hidden = true })));
    symbols.uleb128(0);
    symbols.string("foo");

    section.string("linking");
    section.uleb128(2); // version
    section.byte(@backingInt(LinkingSubsection.symbol_table));
    section.string(symbols.written());
    c.section(.custom, section.written());

    const write_files = build.addWriteFiles();
    const a_file = write_files.add("a.o", a.written());
    const b_file = write_files.add("b.o", b.written());

    const run = build.addSystemCommand(&.{ build.graph.zig_exe, "build-obj" });
    run.addFileArg(a_file);
    run.addFileArg(b_file);
    run.addArgs(&.{
        "-target",
        "wasm32-freestanding",
        "-fno-llvm",
        "-fno-lld",
        "-fstrip",
    });
    const actual = run.addOutputFileArg2("actual.o", .{ .prefix = "-femit-bin=" });

    const check = build.addCheckFile(actual, .{
        .expected_exact = c.written(),
    });
    check.setName("wasm-weak-symbol");
    step.dependOn(&check.step);
}
