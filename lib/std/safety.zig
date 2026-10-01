//! Collection of primitives to declare valid program state and help assert
//! that the program at runtime respects it.
//!
//! In their default configuration, in debug and safe modes the state is
//! carried and the checks are always generated, and a violation triggers a
//! panic.
//! In fast and small modes the primitives that carry state are zero-sized and
//! the checks are optimized away, so declaring valid state costs nothing there.
//!
//! User code should not branch on the internal state of these primitives, nor
//! otherwise change program behavior upon them, since in some configurations
//! they are erased entirely.

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const io = std.Options.debug_io;

/// Invokes detectable illegal behavior when `ok` is `false`.
///
/// In debug and safe modes, calls to this function are always
/// generated, and the `unreachable` statement triggers a panic.
///
/// In fast and small modes, calls to this function are optimized
/// away, and in fact the optimizer is able to use the assertion in its
/// heuristics.
///
/// Inside a test block, it is best to use the `testing` module rather than
/// this function, because this function may not detect a test failure in
/// fast and small mode. Outside of a test block, this assert
/// function is the correct function to use.
pub fn assert(ok: bool) void {
    @disableInstrumentation();
    if (!ok) unreachable; // assertion failure
}

/// Carries the configuration options and their default values for this
/// module's primitives.
pub const Config = struct {
    /// When false the primitive is zero-sized and its checks compile away,
    /// so declaring the state costs nothing.
    enabled: bool = std.lang.Optimize.runtimeSafety(builtin.optimize),
    /// Serializes the checks through the type's `CheckMutex`, so that they do
    /// not race when values are shared between threads.
    thread_safe: bool = !builtin.single_threaded,
    /// How many frames each captured trace keeps. 0 captures nothing, which
    /// is what a disabled primitive is forced to regardless of this value.
    stack_trace_frames: usize = 6,

    fn traceFrames(config: Config) usize {
        return if (config.enabled and std.debug.sys_can_stack_trace)
            config.stack_trace_frames
        else
            0;
    }
};

fn fail(
    comptime headline: []const u8,
    headline_args: anytype,
    comptime trace_label: []const u8,
    trace_label_args: anytype,
    trace: anytype,
    ret_addr: usize,
) noreturn {
    @branchHint(.cold);

    const stack_trace = trace.stackTrace();
    if (stack_trace.return_addresses.len == 0)
        std.debug.panicExtra(ret_addr, headline, headline_args);

    std.debug.panicExtra(
        ret_addr,
        headline ++ "\n\n" ++ trace_label ++ ":{f}\nviolation occurred at:",
        headline_args ++ trace_label_args ++ .{std.debug.FormatStackTrace{
            .stack_trace = stack_trace,
            .terminal_mode = .no_color,
        }},
    );
}

/// A mutex that makes the safety checks of `Owner` thread-safe.
/// It guards the checks only: when `config.enabled` or `config.thread_safe`
/// is false it compiles to nothing, so it must never protect program data.
pub fn CheckMutex(Owner: type, config: Config) type {
    return struct {
        pub const present = config.enabled and config.thread_safe;

        // Referencing `Owner` makes it part of this type's identity, so each
        // owner gets its own `inner` instead of all of them sharing one.
        comptime {
            _ = Owner;
        }

        var inner: std.Io.Mutex = .init;

        pub fn lock() void {
            if (present) inner.lockUncancelable(io);
        }

        pub fn unlock() void {
            if (present) inner.unlock(io);
        }
    };
}

test CheckMutex {
    // Test that each owner gets its own mutex
    const A = struct {};
    const B = struct {};
    try testing.expect(&CheckMutex(A, .{}).inner != &CheckMutex(B, .{}).inner);
    try testing.expect(&CheckMutex(A, .{}).inner == &CheckMutex(A, .{}).inner);
}

/// Text used when a state assertion fails.
pub const StateMessages = struct {
    /// Names the thing whose state this is, as in "expected the state to be
    /// used, found unused".
    name: []const u8 = "the state",
    /// Labels the trace of the most recent transition.
    last_transition: []const u8 = "last transition at",
};

pub fn ConfigurableState(States: type, config: Config, messages: StateMessages) type {
    const Enum = switch (@typeInfo(States)) {
        .@"enum" => States,
        .@"union" => |info| info.tag_type orelse
            @compileError("State needs a tagged union, found untagged " ++ @typeName(States)),
        else => @compileError("State needs an enum or a tagged union, found " ++ @typeName(States)),
    };

    return struct {
        const S = @This();

        const TransitionTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const mutex = CheckMutex(S, config);

        state: if (config.enabled) Enum else void,
        last_transition: TransitionTrace,

        /// Initializes the state to `initial_state`, without capturing a
        /// stack trace.
        pub fn init(initial_state: Enum) S {
            return .{
                .state = if (config.enabled) initial_state else {},
                .last_transition = .empty,
            };
        }

        /// Initializes the state to `initial_state` and captures the current
        /// stack trace.
        pub fn initAndCapture(initial_state: Enum) S {
            return .initAndCaptureAt(initial_state, @returnAddress());
        }

        /// `initAndCapture`, capturing from `ret_addr`.
        pub fn initAndCaptureAt(initial_state: Enum, ret_addr: usize) S {
            if (!config.enabled) return .{
                .state = {},
                .last_transition = .empty,
            };

            return .{
                .state = initial_state,
                .last_transition = .captured(ret_addr),
            };
        }

        /// Transitions to `next_state`.
        pub fn transition(self: *S, next_state: Enum) void {
            self.transitionAt(next_state, @returnAddress());
        }

        /// `transition`, capturing from `ret_addr`.
        pub fn transitionAt(self: *S, next_state: Enum, ret_addr: usize) void {
            if (!config.enabled) return;

            const trace: TransitionTrace = .captured(ret_addr);

            mutex.lock();
            defer mutex.unlock();

            self.transitionUnsafe(next_state, trace);
        }

        fn transitionUnsafe(self: *S, next_state: Enum, trace: TransitionTrace) void {
            if (!config.enabled) return;

            self.state = next_state;
            self.last_transition = trace;
        }

        /// Asserts that the current state is equal to the one provided.
        pub fn assertEql(self: *const S, comptime expected: Enum) void {
            self.assertEqlAnyOfAt(&.{expected}, @returnAddress());
        }

        /// `assertEql`, reporting from `ret_addr`.
        pub fn assertEqlAt(self: *const S, comptime expected: Enum, ret_addr: usize) void {
            self.assertEqlAnyOfAt(&.{expected}, ret_addr);
        }

        /// Asserts that the current state is equal to any of the provided states.
        pub fn assertEqlAnyOf(self: *const S, comptime expect_any_of: []const Enum) void {
            self.assertEqlAnyOfAt(expect_any_of, @returnAddress());
        }

        /// `assertEqlAnyOf`, reporting from `ret_addr`.
        pub fn assertEqlAnyOfAt(
            self: *const S,
            comptime expect_any_of: []const Enum,
            ret_addr: usize,
        ) void {
            if (!config.enabled) return;

            mutex.lock();
            defer mutex.unlock();

            for (expect_any_of) |expected| {
                if (self.state == expected) return;
            }

            self.failUnsafe(expect_any_of, ret_addr);
        }

        fn failUnsafe(
            self: *const S,
            comptime expected: []const Enum,
            ret_addr: usize,
        ) noreturn {
            @branchHint(.cold);

            const expected_list = comptime list: {
                var buf: []const u8 = "";
                for (expected, 0..) |e, i| {
                    const separator = if (i == 0)
                        ""
                    else if (i == expected.len - 1)
                        " or "
                    else
                        ", ";

                    buf = buf ++ separator ++ @tagName(e);
                }

                break :list buf;
            };

            const headline = "expected " ++ messages.name ++ " to be " ++ expected_list ++ ", found ";

            if (std.enums.tagName(Enum, self.state)) |found| fail(
                headline ++ "{s}",
                .{found},
                messages.last_transition,
                .{},
                &self.last_transition,
                ret_addr,
            ) else fail(
                headline ++ "{d}",
                .{@backingInt(self.state)},
                messages.last_transition,
                .{},
                &self.last_transition,
                ret_addr,
            );
        }
    };
}

test ConfigurableState {
    const Disabled = ConfigurableState(enum { a, b }, .{ .enabled = false }, .{});

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    var disabled: Disabled = .init(.a);
    disabled.assertEql(.b); // Should fail but since it's disabled nothing should happen.
    disabled.transition(.b);
    disabled.assertEqlAnyOf(&.{.a}); // Same as before.

    // Test correct behavior
    const Enabled = ConfigurableState(enum { a, b }, .{}, .{});
    var enabled: Enabled = .init(.a);
    enabled.assertEql(.a);
    enabled.transition(.b);
    enabled.assertEqlAnyOf(&.{.b});

    const Body = union(enum) { none, content_length: u64, end };
    var body: Body = .{ .content_length = 3 };
    var tracked: ConfigurableState(Body, .{ .enabled = true }, .{}) = .init(body);
    tracked.assertEql(.content_length);
    body = .end;
    tracked.transition(body);
    tracked.assertEqlAnyOf(&.{ .none, .end });
    try testing.expectEqual(@sizeOf(ConfigurableState(Body, .{ .enabled = false }, .{})), 0);
}

/// Tracks which state the program is in, and asserts the transitions respect the
/// ones it declares, much like a finite state machine.
/// A failure reports the state found and where the last transition was made.
///
/// See `ConfigurableState` to name the thing being tracked, and to configure
/// enable/disabled, thread safety and more.
pub fn State(States: type) type {
    return ConfigurableState(States, .{}, .{});
}

/// Text used when an obligation assertion fails. Each headline is followed by
/// the count the assertion asked for and the one found, worded from its
/// comparison: "obligations still outstanding (expected 0 obligation(s), found 2)".
///
/// A `discharge` with nothing outstanding reports as `too_few`, since that is
/// what it is: one was expected, none was there.
pub const ObligationsMessages = struct {
    /// Fewer are outstanding than the assertion asked for.
    too_few: []const u8 = "fewer obligations outstanding than expected",
    /// More are outstanding than the assertion asked for.
    too_many: []const u8 = "obligations still outstanding",
    /// Noun for whatever is counted, as in "(expected at least 1 obligation(s), found 0)".
    counted: []const u8 = "obligation(s)",
    /// Labels the trace of the most recent discharge.
    last_discharge: []const u8 = "previously discharged at",
    /// Labels the trace of the most recent incur
    last_incur: []const u8 = "last incurred at",
};

pub fn ConfigurableObligations(config: Config, messages: ObligationsMessages) type {
    return struct {
        const O = @This();

        const ObligationsTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const mutex = CheckMutex(O, config);

        counter: if (config.enabled) u32 else void,
        last_incur: ObligationsTrace,
        last_discharge: ObligationsTrace,

        pub const none: O = .{
            .counter = if (config.enabled) 0 else {},
            .last_incur = .empty,
            .last_discharge = .empty,
        };

        /// Takes an obligation.
        pub fn incur(self: *O) void {
            self.incurAt(@returnAddress());
        }

        /// `incur`, capturing from `ret_addr`.
        pub fn incurAt(self: *O, ret_addr: usize) void {
            if (!config.enabled) return;

            const trace: ObligationsTrace = .captured(ret_addr);

            mutex.lock();
            defer mutex.unlock();

            self.incurUnsafe(trace);
        }

        fn incurUnsafe(self: *O, trace: ObligationsTrace) void {
            if (!config.enabled) return;

            self.counter += 1;
            self.last_incur = trace;
        }

        /// Asserts one obligation is outstanding, then discharges it.
        pub fn discharge(self: *O) void {
            self.dischargeAt(@returnAddress());
        }

        /// `discharge`, capturing and reporting from `ret_addr`.
        pub fn dischargeAt(self: *O, ret_addr: usize) void {
            if (!config.enabled) return;

            const trace: ObligationsTrace = .captured(ret_addr);

            mutex.lock();
            defer mutex.unlock();

            self.dischargeUnsafe(trace, ret_addr);
        }

        fn dischargeUnsafe(self: *O, trace: ObligationsTrace, ret_addr: usize) void {
            if (!config.enabled) return;

            if (self.counter == 0)
                self.failUnsafe(.gte, 1, ret_addr); // Discharge expects at least 1 outstanding

            self.counter -= 1;
            self.last_discharge = trace;
        }

        /// Asserts the outstanding count compares to `rhs` as `op` says:
        /// `assertCount(.eq, 0)` expects nothing outstanding,
        /// `assertCount(.gte, 1)` expects at least one.
        pub fn assertCount(self: *const O, op: std.math.CompareOperator, rhs: u32) void {
            self.assertCountAt(op, rhs, @returnAddress());
        }

        /// `assertCount`, reporting from `ret_addr`.
        pub fn assertCountAt(self: *const O, op: std.math.CompareOperator, rhs: u32, ret_addr: usize) void {
            if (!config.enabled) return;

            mutex.lock();
            defer mutex.unlock();

            if (!std.math.compare(self.counter, op, rhs))
                self.failUnsafe(op, rhs, ret_addr);
        }

        fn failUnsafe(self: *const O, op: std.math.CompareOperator, rhs: u32, ret_addr: usize) noreturn {
            @branchHint(.cold);

            const too_many = switch (op) {
                .lt, .lte => true,
                .gt, .gte => false,
                .eq => self.counter > rhs,
                // Landed on the one forbidden count: an incur put it there,
                // unless the count is zero, which only a discharge reaches.
                .neq => self.counter != 0,
            };

            const op_string = switch (op) {
                .eq => "",
                .neq => "anything but ",
                .lt => "fewer than ",
                .lte => "at most ",
                .gt => "more than ",
                .gte => "at least ",
            };

            fail(
                "{s} (expected {s}{d} {s}, found {d})",
                .{
                    if (too_many) messages.too_many else messages.too_few,
                    op_string,
                    rhs,
                    messages.counted,
                    self.counter,
                },
                "{s}",
                .{if (too_many) messages.last_incur else messages.last_discharge},
                if (too_many) &self.last_incur else &self.last_discharge,
                ret_addr,
            );
        }
    };
}

test ConfigurableObligations {
    const Disabled = ConfigurableObligations(.{ .enabled = false }, .{});

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    var disabled: Disabled = .none;
    disabled.assertCount(.gte, 1); // Should fail since nothing is outstanding.
    disabled.discharge(); // Same as before.

    // Test correct behavior
    const Enabled = ConfigurableObligations(.{ .enabled = true }, .{});
    var enabled: Enabled = .none;
    enabled.assertCount(.eq, 0);
    enabled.incur();
    enabled.assertCount(.gte, 1);
    enabled.discharge();
    enabled.assertCount(.eq, 0);

    // Test that obligations are counted rather than collapsed
    enabled.incur();
    enabled.incur();
    enabled.assertCount(.eq, 2);
    enabled.discharge();
    enabled.assertCount(.gte, 1);
    enabled.assertCount(.lt, 2);
    enabled.discharge();
    enabled.assertCount(.eq, 0);
}

/// Declares that what is taken must later be given back, and asserts the
/// program does it. Every `incur` leaves one obligation outstanding until a
/// `discharge` settles it; `assertCount` checks the outstanding count wherever
/// the program has an expectation about it.
///
/// Obligations are counted, not identified: discharging the same one twice
/// while another is outstanding goes unnoticed until the count reaches zero.
///
/// See `ConfigurableObligations` to configure enable/disabled, thread safety,
/// messages and more.
pub const Obligations = ConfigurableObligations(.{}, .{});

/// Text used when a lock assertion fails.
pub const LockMessages = struct {
    /// Names the lock where a message is about its exclusive claim, as in
    /// "expected the lock to be held, found free".
    name: []const u8 = "the lock",
    /// Held shared where that is not what the caller needed.
    held_shared: []const u8 = "the lock is held shared",
    /// Expected a shared holder, found none; also what `unlockShared`
    /// reports when nobody holds it.
    not_held_shared: []const u8 = "the lock is not held shared",
    /// Noun for a shared claim, as in "(expected 0 reader(s), found 2)".
    counted: []const u8 = "reader(s)",
    /// Labels the trace of the most recent `lockShared`.
    last_lock_shared: []const u8 = "last locked shared at",
    /// Labels the trace of the most recent `unlockShared`.
    last_unlock_shared: []const u8 = "previously unlocked shared at",
};

pub fn ConfigurableLock(config: Config, messages: LockMessages) type {
    return struct {
        const L = @This();

        /// The inner primitives are checked under this lock's `mutex`, so they
        /// do not take their own.
        const inner_config: Config = .{
            .enabled = config.enabled,
            .thread_safe = false,
            .stack_trace_frames = config.stack_trace_frames,
        };

        /// Tracks the exclusive claim. Shared claims leave it `free`, so this
        /// alone cannot tell readers from an idle lock; `readers` does.
        const LockState = ConfigurableState(
            enum { free, held },
            inner_config,
            .{ .name = messages.name },
        );

        /// Counts the shared claims, one obligation per reader, so the last
        /// `unlockShared` is what returns the lock to idle.
        const LockObligations = ConfigurableObligations(inner_config, .{
            .too_few = messages.not_held_shared,
            .too_many = messages.held_shared,
            .counted = messages.counted,
            .last_discharge = messages.last_unlock_shared,
            .last_incur = messages.last_lock_shared,
        });

        const mutex = CheckMutex(L, config);

        const Trace = std.debug.CapturedStackTrace(config.traceFrames());

        /// Checked as one unit under `mutex`, since a claim is only valid
        /// against both halves at once.
        state: LockState = .init(.free),
        readers: LockObligations = .none,

        /// Held by nobody, exclusively or shared. Same as `.{}`.
        pub const unlocked: L = .{};

        /// Claims exclusive access. Use when mutating data.
        /// Asserts nobody holds it, exclusively or shared.
        pub fn lock(self: *L) void {
            const ret_addr = @returnAddress();
            const trace: Trace = .captured(ret_addr);
            mutex.lock();
            defer mutex.unlock();

            self.assertUnlockedUnsafe(ret_addr);
            self.state.transitionUnsafe(.held, trace);
        }

        /// Releases the exclusive claim. Asserts it is the one held.
        pub fn unlock(self: *L) void {
            const ret_addr = @returnAddress();
            const trace: Trace = .captured(ret_addr);
            mutex.lock();
            defer mutex.unlock();

            self.assertLockedUnsafe(ret_addr);
            self.state.transitionUnsafe(.free, trace);
        }

        /// Claims shared access, alongside any other readers. Use when
        /// consuming data in a read-only manner. Asserts nobody holds it
        /// exclusively.
        pub fn lockShared(self: *L) void {
            const ret_addr = @returnAddress();
            const trace: Trace = .captured(ret_addr);
            mutex.lock();
            defer mutex.unlock();

            self.state.assertEqlAt(.free, ret_addr);
            self.readers.incurUnsafe(trace);
        }

        /// Releases one shared claim. Asserts one is held, so a reader that
        /// releases twice is caught rather than cancelling out another.
        pub fn unlockShared(self: *L) void {
            const ret_addr = @returnAddress();
            const trace: Trace = .captured(ret_addr);
            mutex.lock();
            defer mutex.unlock();

            self.state.assertEqlAt(.free, ret_addr);
            self.readers.dischargeUnsafe(trace, ret_addr);
        }

        /// Asserts nobody holds it, exclusively or shared.
        pub fn assertUnlocked(self: *const L) void {
            const ret_addr = @returnAddress();
            mutex.lock();
            defer mutex.unlock();

            self.assertUnlockedUnsafe(ret_addr);
        }

        /// Asserts it is held exclusively, as a mutator should before writing.
        pub fn assertLocked(self: *const L) void {
            const ret_addr = @returnAddress();
            mutex.lock();
            defer mutex.unlock();

            self.assertLockedUnsafe(ret_addr);
        }

        /// Asserts at least one reader holds it, as a reader should before
        /// reading. Says nothing about which reader, only that a shared claim
        /// is outstanding.
        pub fn assertLockedShared(self: *const L) void {
            const ret_addr = @returnAddress();
            mutex.lock();
            defer mutex.unlock();

            self.state.assertEqlAt(.free, ret_addr);
            self.readers.assertCountAt(.gte, 1, ret_addr);
        }

        fn assertUnlockedUnsafe(self: *const L, ret_addr: usize) void {
            self.readers.assertCountAt(.eq, 0, ret_addr);
            self.state.assertEqlAt(.free, ret_addr);
        }

        fn assertLockedUnsafe(self: *const L, ret_addr: usize) void {
            self.readers.assertCountAt(.eq, 0, ret_addr);
            self.state.assertEqlAt(.held, ret_addr);
        }
    };
}

test ConfigurableLock {
    const Disabled = ConfigurableLock(.{ .enabled = false }, .{});

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    var disabled: Disabled = .{};
    disabled.assertLocked(); // Should fail since nobody holds it.
    disabled.unlock(); // Same as before.

    // Test correct behavior
    const Enabled = ConfigurableLock(.{ .enabled = true }, .{});
    var enabled: Enabled = .unlocked;
    enabled.assertUnlocked();
    enabled.lock();
    enabled.assertLocked();
    enabled.unlock();
    enabled.assertUnlocked();

    // Test that readers share, and that the last one returns it to idle
    enabled.lockShared();
    enabled.lockShared();
    enabled.unlockShared();
    enabled.assertLockedShared();
    enabled.unlockShared();
    enabled.assertUnlocked();

    // Test that the claims don't re-enter the mutex, which is not recursive
    var thread_safe: ConfigurableLock(.{ .enabled = true, .thread_safe = true }, .{}) = .{};
    thread_safe.lock();
    thread_safe.unlock();
    thread_safe.lockShared();
    thread_safe.unlockShared();
}

/// Declares who may read and who may mutate, and asserts the program keeps to
/// it. Access is either exclusive, held by one mutator, or shared, held by any
/// number of readers at once; the two never overlap.
///
/// See `ConfigurableLock` to configure enable/disabled, thread safety, messages and more.
pub const Lock = ConfigurableLock(.{}, .{});

/// Text used when a binding assertion fails.
pub const BoundToMessages = struct {
    /// The identity differs from the one bound; "(was x, now y)" is appended.
    mismatch: []const u8 = "accessed with a different identity than the one bound",
    /// Labels the trace of the bind that established the bound identity.
    last_bind: []const u8 = "bound at",
};

pub fn ConfigurableBoundTo(
    identityFn: anytype,
    args: anytype,
    config: Config,
    messages: BoundToMessages,
) type {
    if (@typeInfo(@TypeOf(identityFn)) != .@"fn")
        @compileError("identityFn must be a function");

    if (@typeInfo(@TypeOf(identityFn)).@"fn".param_types.len != args.len + 1)
        @compileError("identityFn must take the binding as its first parameter, " ++
            "followed by args; discard it when the identity does not depend on it");

    return struct {
        const B = @This();

        pub const Identity = @typeInfo(@TypeOf(identityFn)).@"fn".return_type.?;

        fn queryIdentity(self: *const B) Identity {
            return @call(.auto, identityFn, .{@as(*const anyopaque, self)} ++ args);
        }

        const BindTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const mutex = CheckMutex(B, config);

        identity: if (config.enabled) ?Identity else void,
        last_bind: BindTrace,

        /// Binds lazily: the first assertion binds whatever identity it sees.
        pub const unbound: B = .{
            .identity = if (config.enabled) null else {},
            .last_bind = .empty,
        };

        /// Binds `identity` up front, without capturing a stack trace, so the
        /// first assertion checks against it instead of binding whatever it
        /// sees.
        ///
        /// Use it when the identity is known at creation.
        pub fn init(identity: Identity) B {
            return .{
                .identity = if (config.enabled) identity else {},
                .last_bind = .empty,
            };
        }

        /// `init`, also capturing the current stack trace, so a failure
        /// reports where the binding was created.
        pub fn initAndCapture(identity: Identity) B {
            return .initAndCaptureAt(identity, @returnAddress());
        }

        /// `initAndCapture`, capturing from `ret_addr`.
        pub fn initAndCaptureAt(identity: Identity, ret_addr: usize) B {
            if (!config.enabled) return .{
                .identity = {},
                .last_bind = .empty,
            };

            return .{
                .identity = identity,
                .last_bind = .captured(ret_addr),
            };
        }

        /// Binds the identity returned by `identityFn` if unbound, otherwise
        /// asserts it matches the bound one.
        pub fn assertIdentity(self: *B) void {
            if (!config.enabled) return;
            self.assertEqlAt(self.queryIdentity(), @returnAddress());
        }

        /// `assertIdentity`, capturing and reporting from `ret_addr`.
        pub fn assertIdentityAt(self: *B, ret_addr: usize) void {
            if (!config.enabled) return;
            self.assertEqlAt(self.queryIdentity(), ret_addr);
        }

        /// Binds `identity` if unbound, otherwise asserts it matches the bound
        /// one. Unlike `State.assertEql`, the first call never fails.
        pub fn assertEql(self: *B, identity: Identity) void {
            self.assertEqlAt(identity, @returnAddress());
        }

        /// `assertEql`, capturing and reporting from `ret_addr`.
        pub fn assertEqlAt(self: *B, identity: Identity, ret_addr: usize) void {
            if (!config.enabled) return;

            mutex.lock();
            defer mutex.unlock();

            const bound_identity = self.identity orelse
                return self.bindUnsafe(identity, .captured(ret_addr));

            if (!std.meta.eql(bound_identity, identity))
                self.failUnsafe(bound_identity, identity, ret_addr);
        }

        /// Binds `identity`, replacing any existing binding.
        pub fn rebind(self: *B, identity: Identity) void {
            self.rebindAt(identity, @returnAddress());
        }

        /// `rebind`, capturing from `ret_addr`.
        pub fn rebindAt(self: *B, identity: Identity, ret_addr: usize) void {
            if (!config.enabled) return;

            const trace: BindTrace = .captured(ret_addr);

            mutex.lock();
            defer mutex.unlock();

            self.bindUnsafe(identity, trace);
        }

        /// Binds the identity returned by `identityFn`, replacing any existing
        /// binding.
        pub fn rebindIdentity(self: *B) void {
            if (!config.enabled) return;
            self.rebindAt(self.queryIdentity(), @returnAddress());
        }

        /// `rebindIdentity`, capturing from `ret_addr`.
        pub fn rebindIdentityAt(self: *B, ret_addr: usize) void {
            if (!config.enabled) return;
            self.rebindAt(self.queryIdentity(), ret_addr);
        }

        /// Drops the binding, so the next access binds afresh.
        pub fn unbind(self: *B) void {
            if (!config.enabled) return;

            mutex.lock();
            defer mutex.unlock();

            self.identity = null;
        }

        fn bindUnsafe(self: *B, identity: Identity, trace: BindTrace) void {
            self.identity = identity;
            self.last_bind = trace;
        }

        fn failUnsafe(self: *const B, bound_identity: Identity, found_identity: Identity, ret_addr: usize) noreturn {
            fail(
                messages.mismatch ++ " (was {any}, now {any})",
                .{ bound_identity, found_identity },
                messages.last_bind,
                .{},
                &self.last_bind,
                ret_addr,
            );
        }
    };
}

test ConfigurableBoundTo {
    const Id = struct {
        var current: usize = 0;

        fn identity(_: *const anyopaque) usize {
            return current;
        }
    };

    const Disabled = ConfigurableBoundTo(Id.identity, .{}, .{ .enabled = false }, .{});

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    Id.current = 1;
    var disabled: Disabled = .unbound;
    disabled.assertIdentity();
    Id.current = 2;
    disabled.assertIdentity(); // Should fail since the identity changed.

    // Test correct behavior
    const Enabled = ConfigurableBoundTo(Id.identity, .{}, .{ .enabled = true }, .{});
    Id.current = 7;
    var enabled: Enabled = .unbound;

    enabled.assertIdentity(); // The first access binds.
    enabled.assertEql(7);

    // Test that a new identity needs the old binding released, or acknowledged
    Id.current = 8;
    enabled.unbind();
    enabled.assertIdentity();

    Id.current = 9;
    enabled.rebindIdentity();

    enabled.rebind(10);

    // Test that an eager binding is in place before the first access
    var eager: Enabled = .init(11);
    try testing.expectEqual(11, eager.identity.?);
    Id.current = 11;
    eager.assertIdentity();
}

/// Asserts that every access happens under the same identity, where the
/// identity is whatever `identityFn(self, args)` returns: the current thread,
/// task, generation counter, and so on.
///
/// A failure reports the bound and found identities, and where the binding
/// was made.
///
/// See `ConfigurableBoundTo` to configure enable/disabled, thread safety,
/// messages and more.
pub fn BoundTo(identityFn: anytype, args: anytype) type {
    return ConfigurableBoundTo(identityFn, args, .{}, .{});
}

test BoundTo {
    const Arena = struct {
        generation: u32 = 0,

        /// Invalidates every handle into this arena, and no other's.
        fn reset(arena: *@This()) void {
            arena.generation += 1;
        }

        fn handle(arena: *const @This()) Handle {
            return .{
                .arena_generation = &arena.generation,
                .generation = .initAndCapture(arena.generation),
            };
        }

        const Handle = struct {
            const BoundToGeneration = BoundTo(currentGeneration, .{});

            arena_generation: *const u32,
            generation: BoundToGeneration,

            fn currentGeneration(taken_in: *const anyopaque) u32 {
                const generation: *const BoundToGeneration = @ptrCast(@alignCast(taken_in));
                const h: *const Handle = @fieldParentPtr("generation", generation);
                return h.arena_generation.*;
            }
        };
    };

    var a: Arena = .{};
    var b: Arena = .{};

    var handle_into_a = a.handle();
    var handle_into_b = b.handle();

    handle_into_a.generation.assertIdentity();
    handle_into_b.generation.assertIdentity();

    b.reset();

    // `a` was not reset, so its handle is still valid.
    handle_into_a.generation.assertIdentity();
    // `handle_into_b.generation.assertIdentity()` would now panic: it was taken
    // in generation 0 and `b` is at 1. The panic reports where it was taken.

    var new_handle_into_b = b.handle();
    new_handle_into_b.generation.assertIdentity();
}

/// An identity function that returns whatever `ptr` holds at the moment it is
/// called, for binding to an identity that lives elsewhere and changes over
/// time: a generation counter, an epoch, an owner slot.
///
/// `BoundTo(valueAt(&generation), .{})` binds the generation current at first
/// use and fails once it moves on, which catches a stale handle surviving the
/// reuse of whatever it referred to.
pub fn valueAt(comptime ptr: anytype) fn (*const anyopaque) @typeInfo(@TypeOf(ptr)).pointer.child {
    const info = @typeInfo(@TypeOf(ptr));

    if (info != .pointer or info.pointer.size != .one)
        @compileError("valueAt needs a single-item pointer, found " ++ @typeName(@TypeOf(ptr)));

    return struct {
        fn identity(_: *const anyopaque) info.pointer.child {
            return ptr.*;
        }
    }.identity;
}

test valueAt {
    const Gen = struct {
        var counter: u32 = 0;
    };

    // Test that the binding follows the pointee at the time of the call
    Gen.counter = 1;
    var b: ConfigurableBoundTo(valueAt(&Gen.counter), .{}, .{ .enabled = true }, .{}) = .unbound;
    b.assertIdentity();

    // Test that moving the generation on needs the stale binding released
    Gen.counter = 2;
    b.unbind();
    b.assertIdentity();
}

fn addressOf(self: *const anyopaque) *const anyopaque {
    return self;
}

pub fn ConfigurablePinned(config: Config) type {
    return ConfigurableBoundTo(addressOf, .{}, config, .{
        .mismatch = "pinned value was copied or moved",
        .last_bind = "pinned at",
    });
}

test ConfigurablePinned {
    const Disabled = ConfigurablePinned(.{ .enabled = false });

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    var disabled: Disabled = .unbound;
    disabled.assertIdentity();
    var disabled_copy = disabled;
    disabled_copy.assertIdentity(); // Should fail since the value was copied.

    // Test correct behavior
    const Enabled = ConfigurablePinned(.{ .enabled = true });
    var enabled: Enabled = .unbound;
    enabled.assertIdentity(); // The first access pins it here.

    // Test that releasing the pin lets the value move
    enabled.unbind();
    var moved = enabled;
    moved.assertIdentity();

    // Test that a move can be acknowledged after the fact instead
    var moved_again = moved;
    moved_again.rebindIdentity();
    moved_again.assertIdentity();
}

/// Detects when an address-sensitive value has been copied or moved.
///
/// Embed it in any struct that other code reaches through a pointer to one of
/// its fields (`@fieldParentPtr`), or that intrusive data structures point
/// into. `assertIdentity` pins the value at its current address the first time it
/// is called and asserts it has not moved on every later call, so it can be
/// called on every use.
///
/// A copy panics, reporting both addresses and where the original was pinned.
/// A copy carries the original's pin trace with it, so that trace shows where
/// the original was first checked, not where the copy was made.
///
/// See `ConfigurablePinned` to configure enable/disabled, thread safety and more.
pub const Pinned = ConfigurablePinned(.{});
