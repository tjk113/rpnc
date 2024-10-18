const builtin = @import("builtin");
const std = @import("std");

const CompilerError = error{ UnsupportedOperation, ParseError };

const Operation = enum { Add, Sub, Mul, Div, Pow };

const Token = union(enum) {
    kind: Operation,
    value: u32,

    fn print(self: *const Token) void {
        switch (self.*) {
            .kind => {
                std.debug.print("Token (Operation): {}\n", .{self.*.kind});
            },
            .value => {
                std.debug.print("Token (Value): {}\n", .{self.*.value});
            },
        }
    }
};

const QBEType = enum { Int32, Int64, Float32, Float64 };

const QBEValue = union(enum) {
    int32: u32,
    int64: u64,
    float32: f32,
    float64: f64,
};

const QBEVariable = struct { kind: QBEType, value: QBEValue, name: []const u8 };

fn qbe_type_to_char(kind: QBEType) u8 {
    return switch (kind) {
        .Int32 => 'w',
        .Int64 => 'l',
        .Float32 => 's',
        .Float64 => 'd',
    };
}

fn emit_function_signature(name: []const u8, return_type: QBEType, exported: bool, out: *std.ArrayList(u8).Writer) !void {
    if (exported) {
        try out.*.print("export ", .{});
    }
    try out.*.print("function {c} ${s}(", .{ qbe_type_to_char(return_type), name });
    // TODO: function parameters
    try out.*.print(") {{\n@start\n", .{});
}

fn emit_operand(operand: Token, print_comma: bool, out: *std.ArrayList(u8).Writer) !void {
    try out.*.print("{d}", .{operand.value});
    if (print_comma) {
        try out.*.print(", ", .{});
    } else {
        try out.*.print("\n", .{});
    }
}

fn emit_operation(op: Token, var_name: []const u8, variable_stack: *std.ArrayList(QBEVariable), out: *std.ArrayList(u8).Writer) !void {
    // TODO: more parameters and operations
    switch (op.kind) {
        Operation.Add => {
            try out.*.print("\t{s} =w add {s}, {s}\n", .{ var_name, variable_stack.*.pop().name, variable_stack.*.pop().name });
        },
        Operation.Sub => {
            try out.*.print("\t{s} =w sub {s}, {s}\n", .{ var_name, variable_stack.*.pop().name, variable_stack.*.pop().name });
        },
        Operation.Mul => {
            try out.*.print("\t{s} =w mul {s}, {s}\n", .{ var_name, variable_stack.*.pop().name, variable_stack.*.pop().name });
        },
        Operation.Div => {
            try out.*.print("\t{s} =w div {s}, {s}\n", .{ var_name, variable_stack.*.pop().name, variable_stack.*.pop().name });
        },
        Operation.Pow => {
            return CompilerError.UnsupportedOperation;
        },
    }
}

fn emit_variable(variable: QBEVariable, out: *std.ArrayList(u8).Writer) !void {
    try out.*.print("\t{s} =", .{variable.name});
    switch (variable.value) {
        .int32 => {
            try out.*.print("w copy {d}\n", .{variable.value.int32});
        },
        .int64 => {
            try out.*.print("l copy {d}\n", .{variable.value.int64});
        },
        .float32 => {
            try out.*.print("s copy {}\n", .{variable.value.float32});
        },
        .float64 => {
            try out.*.print("d copy {}\n", .{variable.value.float64});
        },
    }
}

fn emit_return(value: []const u8, out: *std.ArrayList(u8).Writer) !void {
    try out.*.print("\tret {s}\n", .{value});
}

// For simplicity's sake, each value gets its own temporary variable.
fn emit_function(name: []const u8, return_type: QBEType, exported: bool, queue: *std.ArrayList(Token), file: std.fs.File, allocator: std.mem.Allocator) !void {
    // Using an arena allocator here because of all of
    // the calls made to `std.fmt.allocPrint` are hard
    // to manage manually.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var buffer = std.ArrayList(u8).init(arena_allocator);
    var out = buffer.writer();

    try emit_function_signature(name, return_type, exported, &out);

    var variable_stack = std.ArrayList(QBEVariable).init(arena_allocator);
    var var_index: usize = 0;
    var res_index: usize = 0;
    while (queue.*.items.len > 0) {
        const token = queue.*.pop();
        switch (token) {
            .kind => {
                const res_name = try std.fmt.allocPrint(arena_allocator, "%res{d}", .{res_index});
                try emit_operation(token, res_name, &variable_stack, &out);
                try variable_stack.append(.{ .kind = .Int32, .name = res_name, .value = undefined });
                res_index += 1;
            },
            .value => {
                try variable_stack.append(.{ .kind = .Int32, .value = .{ .int32 = token.value }, .name = try std.fmt.allocPrint(arena_allocator, "%v{d}", .{var_index}) });
                try emit_variable(variable_stack.getLast(), &out);
                var_index += 1;
            },
        }
    }

    // Return final result.
    const res_name = try std.fmt.allocPrint(arena_allocator, "%res{d}", .{res_index - 1});
    try emit_return(res_name, &out);

    try out.print("}}", .{});

    _ = try file.write(buffer.items);
}

fn is_operation(op: u8) bool {
    return switch (op) {
        '+', '-', '*', '/', '^' => true,
        else => false,
    };
}

fn to_operation(op: u8) CompilerError!Operation {
    return switch (op) {
        '+' => .Add,
        '-' => .Sub,
        '*' => .Mul,
        '/' => .Div,
        '^' => .Pow,
        else => CompilerError.UnsupportedOperation,
    };
}

/// Check whether all elements of `array` meet `condition`.
fn all(comptime T: type, array: []const T, condition: fn (elem: T) bool) bool {
    for (array) |elem| {
        if (!condition(elem)) {
            return false;
        }
    }
    return true;
}

fn tokenize(s: []const u8) !Token {
    if (all(u8, s, std.ascii.isDigit)) {
        return .{ .value = try std.fmt.parseInt(u32, s, 10) };
    } else if (is_operation(s[0])) {
        return .{ .kind = try to_operation(s[0]) };
    }
    return CompilerError.ParseError;
}

fn free_run_result(res: *std.process.Child.RunResult, allocator: std.mem.Allocator) void {
    allocator.free(res.*.stderr);
    allocator.free(res.*.stdout);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("error: no input file\n", .{});
        return;
    }

    const input_file = try std.fs.cwd().openFile(args[1], .{});
    defer input_file.close();
    const source = try input_file.readToEndAlloc(allocator, (try input_file.stat()).size);
    defer allocator.free(source);

    var queue = std.ArrayList(Token).init(allocator);
    defer queue.deinit();

    var split = std.mem.splitScalar(u8, source, ' ');
    while (split.next()) |token| {
        const tokenized = try tokenize(token);
        try queue.insert(0, tokenized);
    }

    const output_file = try std.fs.cwd().createFile("out.ssa", .{});
    defer output_file.close();

    try emit_function("main", QBEType.Int32, true, &queue, output_file, allocator);

    const qbe_args = [_][]const u8{ "./qbe-1.2/qbe", "out.ssa" };
    const compiler_args_1 = [_][]const u8{ "zig", "cc", "-c", "out.s", "-o", "out.o" };
    var compiler_args_2 = [_][]const u8{ "zig", "cc", "out.o", "-o", "out" };
    if (builtin.os.tag == .windows) {
        compiler_args_2[4] = "out.exe";
    }

    var compiler_proc = try std.process.Child.run(.{ .argv = &qbe_args, .allocator = allocator });
    if (compiler_proc.stderr.len > 0) {
        std.debug.print("QBE error: {s}\n", .{compiler_proc.stderr});
        return;
    }

    const asm_file = try std.fs.cwd().createFile("out.s", .{});
    defer asm_file.close();
    var asm_source: []u8 = undefined;

    // Look away! Ugly hack for Windows GCC incoming!
    // Explanation: QBE emits some extra assembler directives that
    // I assume are Linux/POSIX-specific. On Windows, GCC does
    // not like them. So they need to be stripped off here.
    if (builtin.os.tag == .windows) {
        var lines = std.ArrayList([]const u8).init(allocator);
        defer lines.deinit();
        split = std.mem.splitScalar(u8, compiler_proc.stdout, '\n');
        const bad_line_beginnings = [_][]const u8{ ".type", ".size", "/*", ".section" };
        var dont_append = false;
        while (split.next()) |line| {
            for (bad_line_beginnings) |bad_line_beginning| {
                dont_append = std.mem.startsWith(u8, line, bad_line_beginning);
                if (dont_append) {
                    break;
                }
            }
            if (!dont_append) {
                try lines.append(line);
            }
        }
        asm_source = try std.mem.join(allocator, "\n", lines.items);
        _ = try asm_file.write(asm_source);
        allocator.free(asm_source);
    } else {
        asm_source = compiler_proc.stdout;
        _ = try asm_file.write(asm_source);
    }
    free_run_result(&compiler_proc, allocator);

    compiler_proc = try std.process.Child.run(.{ .argv = &compiler_args_1, .allocator = allocator });
    if (compiler_proc.stderr.len > 0) {
        std.debug.print("CC error: {s}\n", .{compiler_proc.stderr});
        return;
    }
    free_run_result(&compiler_proc, allocator);

    compiler_proc = try std.process.Child.run(.{ .argv = &compiler_args_2, .allocator = allocator });
    if (compiler_proc.stderr.len > 0) {
        std.debug.print("CC error: {s}\n", .{compiler_proc.stderr});
        return;
    }
    free_run_result(&compiler_proc, allocator);
}
