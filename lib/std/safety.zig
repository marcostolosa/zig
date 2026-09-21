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

const log = std.log.scoped(.safety);

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
const Config = struct {
    /// When false the primitive is zero-sized and its checks compile away,
    /// so declaring the state costs nothing.
    enabled: bool = std.lang.Optimize.runtimeSafety(builtin.optimize),
    /// Guards the internal state with a mutex, so that the checks themselves
    /// do not race when the value is shared between threads.
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

    if (@TypeOf(trace.*).len != 0)
        log.err(
            headline ++ "\n\n" ++ trace_label ++ ":{f}",
            headline_args ++ trace_label_args ++ .{trace.fmt()},
        );

    std.debug.panicExtra(ret_addr, headline, headline_args);
}

fn OptionalMutex(config: Config) type {
    return struct {
        const M = @This();

        pub const present = config.enabled and config.thread_safe;
        const init_inner = if (present) std.Io.Mutex.init else {};

        inner: @TypeOf(init_inner) = init_inner,

        pub const init: M = .{};

        pub fn lock(m: *M) void {
            if (present) std.Io.Threaded.mutexLock(&m.inner);
        }

        pub fn unlock(m: *M) void {
            if (present) std.Io.Threaded.mutexUnlock(&m.inner);
        }
    };
}

pub fn ConfigurableState(Enum: type, config: Config) type {
    return struct {
        const S = @This();

        const TransitionTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const Mutex = OptionalMutex(config);

        const ReadPtr = if (Mutex.present) *S else *const S;

        state: if (config.enabled) Enum else void,
        last_transition: TransitionTrace,
        mutex: Mutex = .init,

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

            self.mutex.lock();
            defer self.mutex.unlock();

            self.state = next_state;
            self.last_transition.capture(ret_addr);
        }

        /// Asserts that the current state is equal to the one provided.
        pub fn assertEql(self: ReadPtr, comptime expected: Enum) void {
            self.check(&.{expected}, null, @returnAddress());
        }

        /// `assertEql`, reporting from `ret_addr`.
        pub fn assertEqlAt(self: ReadPtr, comptime expected: Enum, ret_addr: usize) void {
            self.check(&.{expected}, null, ret_addr);
        }

        /// Asserts that the current state is equal to any of the provided states.
        pub fn assertEqlAnyOf(self: ReadPtr, comptime expect_any_of: []const Enum) void {
            self.check(expect_any_of, null, @returnAddress());
        }

        /// `assertEqlAnyOf`, reporting from `ret_addr`.
        pub fn assertEqlAnyOfAt(
            self: ReadPtr,
            comptime expect_any_of: []const Enum,
            ret_addr: usize,
        ) void {
            self.check(expect_any_of, null, ret_addr);
        }

        fn assertEqlWith(
            self: ReadPtr,
            comptime expected: Enum,
            comptime message: []const u8,
            ret_addr: usize,
        ) void {
            self.check(&.{expected}, message, ret_addr);
        }

        fn check(
            self: ReadPtr,
            comptime expect_any_of: []const Enum,
            comptime message: ?[]const u8,
            ret_addr: usize,
        ) void {
            if (!config.enabled) return;

            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            for (expect_any_of) |expected| {
                if (self.state == expected) return;
            }

            self.failLocked(expect_any_of, message, ret_addr);
        }

        fn failLocked(
            self: *const S,
            comptime expected: []const Enum,
            comptime message: ?[]const u8,
            ret_addr: usize,
        ) noreturn {
            @branchHint(.cold);

            const label = "entered {s} at";
            const found = @tagName(self.state);

            if (message) |m|
                fail(m, .{}, label, .{found}, &self.last_transition, ret_addr);

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

            fail(
                "expected state " ++ expected_list ++ ", found {s}",
                .{found},
                label,
                .{found},
                &self.last_transition,
                ret_addr,
            );
        }
    };
}

test ConfigurableState {
    const Disabled = ConfigurableState(enum { a, b }, .{ .enabled = false });

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    var disabled: Disabled = .init(.a);
    disabled.assertEql(.b); // Should fail but since it's disabled nothing should happen.
    disabled.transition(.b);
    disabled.assertEqlAnyOf(&.{.a}); // Same as before.

    // Test correct behavior
    const Enabled = ConfigurableState(enum { a, b }, .{});
    var enabled: Enabled = .init(.a);
    enabled.assertEql(.a);
    enabled.transition(.b);
    enabled.assertEqlAnyOf(&.{.b});
}

/// Tracks which state the program is in, and asserts the transitions respect the
/// ones it declares, much like a finite state machine.
/// A failure reports the state found and where the last transition was made.
///
/// See `ConfigurableState` to configure enable/disabled, thread safety and more.
pub fn State(Enum: type) type {
    return ConfigurableState(Enum, .{});
}

/// Text used when an obligation assertion fails.
pub const ObligationsMessages = struct {
    /// `discharge` with nothing outstanding.
    unmatched_discharge: []const u8 = "discharged with nothing outstanding",
    /// `assertAny` with nothing outstanding.
    none_outstanding: []const u8 = "expected an outstanding obligation, found none",
    /// `assertNone` with something still outstanding.
    still_outstanding: []const u8 = "obligations still outstanding",
    /// Noun in the "(2 outstanding)" appended when a count is known.
    counted: []const u8 = "outstanding",
    /// Labels the trace of the most recent discharge.
    last_discharge: []const u8 = "previously discharged at",
    /// Labels the trace of the most recent incur
    last_incur: []const u8 = "last incurred at",
};

pub fn ConfigurableObligations(config: Config, messages: ObligationsMessages) type {
    return struct {
        const O = @This();

        const ObligationsTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const Mutex = OptionalMutex(config);

        const ReadPtr = if (Mutex.present) *O else *const O;

        counter: if (config.enabled) u32 else void,
        last_incur: ObligationsTrace,
        last_discharge: ObligationsTrace,
        mutex: Mutex = .init,

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

            self.mutex.lock();
            defer self.mutex.unlock();

            self.counter += 1;
            self.last_incur.capture(ret_addr);
        }

        /// Asserts one obligation is outstanding then discharge it.
        pub fn discharge(self: *O) void {
            self.dischargeAt(@returnAddress());
        }

        /// `discharge`, capturing and reporting from `ret_addr`.
        pub fn dischargeAt(self: *O, ret_addr: usize) void {
            if (!config.enabled) return;

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.counter == 0) fail(
                messages.unmatched_discharge,
                .{},
                messages.last_discharge,
                .{},
                &self.last_discharge,
                ret_addr,
            );

            self.counter -= 1;
            self.last_discharge.capture(ret_addr);
        }

        /// Asserts at least one obligation is outstanding.
        /// If fails, report where the last obligation was discharged.
        pub fn assertAny(self: ReadPtr) void {
            self.assertAnyAt(@returnAddress());
        }

        /// `assertAny`, reporting from `ret_addr`.
        pub fn assertAnyAt(self: ReadPtr, ret_addr: usize) void {
            if (!config.enabled) return;

            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            if (self.counter == 0) fail(
                messages.none_outstanding,
                .{},
                messages.last_discharge,
                .{},
                &self.last_discharge,
                ret_addr,
            );
        }

        /// Asserts no obligations are outstanding.
        /// If fails, report where the last obligation was incurred.
        pub fn assertNone(self: ReadPtr) void {
            self.assertNoneWith(messages.still_outstanding, @returnAddress());
        }

        /// `assertNone`, reporting from `ret_addr`.
        pub fn assertNoneAt(self: ReadPtr, ret_addr: usize) void {
            self.assertNoneWith(messages.still_outstanding, ret_addr);
        }

        fn assertNoneWith(self: ReadPtr, comptime message: []const u8, ret_addr: usize) void {
            if (!config.enabled) return;

            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            if (self.counter != 0) fail(
                message ++ " ({d} " ++ messages.counted ++ ")",
                .{self.counter},
                messages.last_incur,
                .{},
                &self.last_incur,
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
    disabled.assertAny(); // Should fail since nothing is outstanding.
    disabled.discharge(); // Same as before.

    // Test correct behavior
    const Enabled = ConfigurableObligations(.{ .enabled = true }, .{});
    var enabled: Enabled = .none;
    enabled.assertNone();
    enabled.incur();
    enabled.assertAny();
    enabled.discharge();
    enabled.assertNone();

    // Test that obligations are counted rather than collapsed
    enabled.incur();
    enabled.incur();
    enabled.discharge();
    enabled.assertAny();
    enabled.discharge();
    enabled.assertNone();
}

/// Declares that what is taken must later be given back, and asserts the
/// program does it. Every `incur` leaves one obligation outstanding until a
/// `discharge` settles it; `assertAny` and `assertNone` check at the points
/// where the program expects a debt, or none.
///
/// Obligations are counted, not identified: discharging the same one twice
/// while another is outstanding goes unnoticed until the count reaches zero.
///
/// See `ConfigurableObligations` to configure enable/disabled, thread safety,
/// messages and more.
pub const Obligations = ConfigurableObligations(.{}, .{});

/// Text used when a lock assertion fails.
pub const LockMessages = struct {
    /// Held exclusively where that is not what the caller needed.
    held_exclusively: []const u8 = "the lock is held exclusively",
    /// Held shared where that is not what the caller needed.
    held_shared: []const u8 = "the lock is held shared",
    /// Expected an exclusive holder, found none.
    not_held_exclusively: []const u8 = "the lock is not held exclusively",
    /// Expected readers, found none.
    not_held_shared: []const u8 = "the lock is not held shared",
    /// Noun in the "(2 reader(s))" appended when readers are found.
    counted: []const u8 = "reader(s)",
    /// Labels the trace of the most recent `lockShared`.
    last_lock_shared: []const u8 = "last locked shared at",
    /// Labels the trace of the most recent `unlockShared`.
    last_unlock_shared: []const u8 = "previously unlocked at",
};

pub fn ConfigurableLock(config: Config, messages: LockMessages) type {
    return struct {
        const L = @This();

        /// The inner primitives are guarded by this lock's `mutex`, so they
        /// do not take their own.
        const inner_config: Config = .{
            .enabled = config.enabled,
            .thread_safe = false,
            .stack_trace_frames = config.stack_trace_frames,
        };

        /// Tracks the exclusive claim. Shared claims leave it `unlocked`, so
        /// this alone cannot tell readers from an idle lock; `readers` does.
        const LockState = ConfigurableState(enum { locked, unlocked }, inner_config);

        /// Counts the shared claims, one obligation per reader, so the last
        /// `unlockShared` is what returns the lock to idle.
        const LockObligations = ConfigurableObligations(inner_config, .{
            .unmatched_discharge = messages.not_held_shared,
            .none_outstanding = messages.not_held_shared,
            .still_outstanding = messages.held_shared,
            .counted = messages.counted,
            .last_discharge = messages.last_unlock_shared,
            .last_incur = messages.last_lock_shared,
        });

        const Mutex = OptionalMutex(config);

        const ReadPtr = if (Mutex.present) *L else *const L;

        /// Guarded as one unit by `mutex`, since a claim is only valid against
        /// both halves at once.
        state: LockState = .init(.unlocked),
        readers: LockObligations = .none,
        mutex: Mutex = .init,

        /// Claims exclusive access. Use when mutating data.
        /// Asserts nobody holds it, exclusively or shared.
        pub fn lock(self: *L) void {
            const ret_addr = @returnAddress();
            self.mutex.lock();
            defer self.mutex.unlock();

            self.state.assertEqlWith(.unlocked, messages.held_exclusively, ret_addr);
            self.readers.assertNoneWith(messages.held_shared, ret_addr);
            self.state.transitionAt(.locked, ret_addr);
        }

        /// Releases the exclusive claim. Asserts it is the one held.
        pub fn unlock(self: *L) void {
            const ret_addr = @returnAddress();
            self.mutex.lock();
            defer self.mutex.unlock();

            self.state.assertEqlWith(.locked, messages.not_held_exclusively, ret_addr);
            self.readers.assertNoneWith(messages.held_shared, ret_addr);
            self.state.transitionAt(.unlocked, ret_addr);
        }

        /// Claims shared access, alongside any other readers. Use when
        /// consuming data in a read-only manner. Asserts nobody holds it
        /// exclusively.
        pub fn lockShared(self: *L) void {
            const ret_addr = @returnAddress();
            self.mutex.lock();
            defer self.mutex.unlock();

            self.state.assertEqlWith(.unlocked, messages.held_exclusively, ret_addr);
            self.readers.incurAt(ret_addr);
        }

        /// Releases one shared claim. Asserts one is held, so a reader that
        /// releases twice is caught rather than cancelling out another.
        pub fn unlockShared(self: *L) void {
            const ret_addr = @returnAddress();
            self.mutex.lock();
            defer self.mutex.unlock();

            self.state.assertEqlWith(.unlocked, messages.held_exclusively, ret_addr);
            self.readers.dischargeAt(ret_addr);
        }

        /// Asserts nobody holds it, exclusively or shared.
        pub fn assertUnlocked(self: ReadPtr) void {
            const ret_addr = @returnAddress();
            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            self.state.assertEqlWith(.unlocked, messages.held_exclusively, ret_addr);
            self.readers.assertNoneWith(messages.held_shared, ret_addr);
        }

        /// Asserts it is held exclusively, as a mutator should before writing.
        pub fn assertLocked(self: ReadPtr) void {
            const ret_addr = @returnAddress();
            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            self.state.assertEqlWith(.locked, messages.not_held_exclusively, ret_addr);
            self.readers.assertNoneWith(messages.held_shared, ret_addr);
        }

        /// Asserts at least one reader holds it, as a reader should before
        /// reading. Says nothing about which reader, only that a shared claim
        /// is outstanding.
        pub fn assertLockedShared(self: ReadPtr) void {
            const ret_addr = @returnAddress();
            if (Mutex.present) self.mutex.lock();
            defer if (Mutex.present) self.mutex.unlock();

            self.readers.assertAnyAt(ret_addr);
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
    var enabled: Enabled = .{};
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
    mismatch: []const u8 = "accessed from a different context than the one bound",
    /// Labels the trace of the bind that established the current context.
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
            "followed by args; discard it when the context does not depend on it");

    return struct {
        const B = @This();

        pub const Context = @typeInfo(@TypeOf(identityFn)).@"fn".return_type.?;

        fn identity(self: *const B) Context {
            return @call(.auto, identityFn, .{@as(*const anyopaque, self)} ++ args);
        }

        const BindTrace = std.debug.CapturedStackTrace(config.traceFrames());

        const Mutex = OptionalMutex(config);

        const ReadPtr = if (Mutex.present) *B else *const B;

        context: if (config.enabled) ?Context else void,
        last_bind: BindTrace,
        mutex: Mutex = .init,

        pub const unbound: B = .{
            .context = if (config.enabled) null else {},
            .last_bind = .empty,
        };

        /// Asserts the current context matches, binding it if unbound.
        pub fn assertSame(self: *B) void {
            if (!config.enabled) return;
            self.assertSameAsAt(self.identity(), @returnAddress());
        }

        /// `assertSame`, capturing and reporting from `ret_addr`.
        pub fn assertSameAt(self: *B, ret_addr: usize) void {
            if (!config.enabled) return;
            self.assertSameAsAt(self.identity(), ret_addr);
        }

        /// Asserts `context` matches the bound one, binding it if unbound.
        pub fn assertSameAs(self: *B, context: Context) void {
            self.assertSameAsAt(context, @returnAddress());
        }

        /// `assertSameAs`, capturing and reporting from `ret_addr`.
        pub fn assertSameAsAt(self: *B, context: Context, ret_addr: usize) void {
            if (!config.enabled) return;

            self.mutex.lock();
            defer self.mutex.unlock();

            const bound = self.context orelse
                return self.bindLocked(context, ret_addr);

            if (!std.meta.eql(bound, context))
                self.failLocked(bound, context, ret_addr);
        }

        /// Binds `context`, replacing any existing binding.
        pub fn rebind(self: *B, context: Context) void {
            self.rebindAt(context, @returnAddress());
        }

        /// `rebind`, capturing from `ret_addr`.
        pub fn rebindAt(self: *B, context: Context, ret_addr: usize) void {
            if (!config.enabled) return;

            self.mutex.lock();
            defer self.mutex.unlock();

            self.bindLocked(context, ret_addr);
        }

        /// Binds the context reported by `identityFn`, replacing any existing binding.
        pub fn rebindCurrent(self: *B) void {
            if (!config.enabled) return;
            self.rebindAt(self.identity(), @returnAddress());
        }

        /// `rebindCurrent`, capturing from `ret_addr`.
        pub fn rebindCurrentAt(self: *B, ret_addr: usize) void {
            if (!config.enabled) return;
            self.rebindAt(self.identity(), ret_addr);
        }

        /// Drops the binding, so the next access binds afresh.
        pub fn unbind(self: *B) void {
            if (!config.enabled) return;

            self.mutex.lock();
            defer self.mutex.unlock();

            self.context = null;
        }

        fn bindLocked(self: *B, context: Context, ret_addr: usize) void {
            self.context = context;
            self.last_bind.capture(ret_addr);
        }

        fn failLocked(self: *const B, bound: Context, current: Context, ret_addr: usize) noreturn {
            fail(
                messages.mismatch ++ " (was {any}, now {any})",
                .{ bound, current },
                messages.last_bind,
                .{},
                &self.last_bind,
                ret_addr,
            );
        }
    };
}

test ConfigurableBoundTo {
    const Ctx = struct {
        var current: usize = 0;

        fn identity(_: *const anyopaque) usize {
            return current;
        }
    };

    const Disabled = ConfigurableBoundTo(Ctx.identity, .{}, .{ .enabled = false }, .{});

    // Test that the size is 0
    try testing.expect(@sizeOf(Disabled) == 0);

    // Test that once disabled the checks don't run
    Ctx.current = 1;
    var disabled: Disabled = .unbound;
    disabled.assertSame();
    Ctx.current = 2;
    disabled.assertSame(); // Should fail since the context moved on.

    // Test correct behavior
    const Enabled = ConfigurableBoundTo(Ctx.identity, .{}, .{ .enabled = true }, .{});
    Ctx.current = 7;
    var enabled: Enabled = .unbound;

    enabled.assertSame(); // The first access binds.
    enabled.assertSameAs(7);

    // Test that a new context needs the old binding released, or acknowledged
    Ctx.current = 8;
    enabled.unbind();
    enabled.assertSame();

    Ctx.current = 9;
    enabled.rebindCurrent();

    enabled.rebind(10);
}

/// Asserts that every access originates from the same context, where the
/// context is whatever `identityFn(self, args)` returns: the current thread, task,
/// generation counter, and so on.
///
/// A failure reports the bound and current contexts, and where the binding
/// was made.
///
/// See `ConfigurableBoundTo` to configure enable/disabled, thread safety,
/// messages and more.
pub fn BoundTo(identityFn: anytype, args: anytype) type {
    return ConfigurableBoundTo(identityFn, args, .{}, .{});
}

/// An identity function that reports whatever `ptr` holds at the moment it is
/// called, for binding to a context that lives elsewhere and changes over
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
    b.assertSame();

    // Test that moving the generation on needs the stale binding released
    Gen.counter = 2;
    b.unbind();
    b.assertSame();
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
    disabled.assertSame();
    var disabled_copy = disabled;
    disabled_copy.assertSame(); // Should fail since the value was copied.

    // Test correct behavior
    const Enabled = ConfigurablePinned(.{ .enabled = true });
    var enabled: Enabled = .unbound;
    enabled.assertSame(); // The first access pins it here.

    // Test that releasing the pin lets the value move
    enabled.unbind();
    var moved = enabled;
    moved.assertSame();

    // Test that a move can be acknowledged after the fact instead
    var moved_again = moved;
    moved_again.rebindCurrent();
    moved_again.assertSame();
}

/// Detects when an address-sensitive value has been copied or moved.
///
/// Embed it in any struct that other code reaches through a pointer to one of
/// its fields (`@fieldParentPtr`), or that intrusive data structures point
/// into. `assertSame` pins the value at its current address the first time it
/// is called and asserts it has not moved on every later call, so it can be
/// called on every use.
///
/// A copy panics, reporting both addresses and where the original was pinned.
/// A copy carries the original's pin trace with it, so that trace shows where
/// the original was first checked, not where the copy was made.
///
/// See `ConfigurablePinned` to configure enable/disabled, thread safety and more.
pub const Pinned = ConfigurablePinned(.{});
