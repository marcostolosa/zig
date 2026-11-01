//! Implements the `SIF CMD` and `SIF RPC` protocols.

const std = @import("std");
const uncached = std.os.ps2.uncached;

const sif = @import("sif.zig");

/// `SIF CMD` packet IDs
const Cmd = enum(u32) {
    change_saddr = 0x8000_0000,
    set_sreg = 0x8000_0001,
    init_cmd = 0x8000_0002,
    rpc_end = 0x8000_0008,
    rpc_bind = 0x8000_0009,
    rpc_call = 0x8000_000a,
    rpc_rdata = 0x8000_000c,

    _,
};

/// Header at the start of every `SIF CMD` packet
const Header = extern struct {
    size: packed struct(u32) {
        /// Size of the entire packet in bytes, including the header
        whole: u8 = 0,
        /// Size of the payload sent ahead of the packet
        payload: u24 = 0,
    } = .{},
    /// `IOP` address the payload is written to
    payload_dst: u32 = 0,
    /// `SIF CMD` ID
    cmd: Cmd,
    opt: u32 = 0,
};

/// Packets consist of a header and a command-specific body
fn Packet(comptime Body: type) type {
    return extern struct {
        hdr: Header,
        body: Body,
    };
}

/// Payload bytes in `call_buf` that go ahead of the associated packet in the same chain
const Payload = struct {
    /// `EE` address to read from
    src: u32,
    /// `IOP` address to write to
    dst: u32,
    /// Size of the payload data in bytes
    size: u32,
};

/// `.change_saddr` and `.init_cmd`: Specifies where the `EE`'s receive buffer is
const BufBody = extern struct {
    /// `EE` receive buffer address
    buf: u32,
};

/// `.set_sreg`: The `IOP` sets one of the `32` software registers
const SetSregBody = extern struct {
    /// Register index
    index: u32,
    /// Register value
    value: u32,
};

/// Begins every `SIF` RPC packet
const RpcFields = extern struct {
    /// Bit `2` and the upper half select the `IOP`'s reply slot
    rec_id: u32 = 0x5,
    packet_addr: u32 = 0,
    /// Used for send bookkeeping, not tracked by the `IOP`
    rpc_id: u32 = 0,
    /// Client data pointer
    client: u32 = 0,
};

/// Body of the `.rpc_bind` packet
const BindBody = extern struct {
    rpc: RpcFields = .{},
    /// Server ID
    sid: u32,
    _pad: [7]u32 = @splat(0),
};

/// Body of the `.rpc_call` packet
const CallBody = extern struct {
    rpc: RpcFields = .{},
    /// Function ID
    func: u32,
    /// Size of the argument buffer in bytes
    args_size: u32,
    /// Address of the function result location
    result: u32,
    /// Size of the result in bytes
    result_size: u32,
    rmode: u32 = 1,
    /// Server ID
    server: u32,
    _pad: [2]u32 = @splat(0),
};

/// `.rpc_rdata`: The `IOP` asks for `size` bytes from the `EE`
const RdataBody = extern struct {
    rpc: RpcFields = .{},
    /// `EE` source address
    src: u32,
    /// `IOP` destination address
    dst: u32,
    /// Size in bytes of the data to be transferred
    size: u32,
    _pad: [5]u32,
};

/// Body of the `.rpc_end` packet
const EndBody = extern struct {
    rpc: RpcFields = .{},
    /// Request this packet completes
    request: Cmd,
    /// Server ID
    server: u32 = 0,
    buf: u32 = 0,
    cbuf: u32 = 0,
    _pad: [4]u32 = @splat(0),
};

/// Outgoing packet to the `IOP`
const Out = enum {
    change_saddr,
    init_cmd,
    init_rpc,
    bind,
    call,
    /// Answers an `.rpc_rdata` request with the data as the payload
    end,

    fn header(comptime out: Out) Header {
        return switch (out) {
            .change_saddr => .{ .cmd = .change_saddr },
            .init_cmd => .{ .cmd = .init_cmd },
            .init_rpc => .{ .cmd = .init_cmd, .opt = 1 },
            .bind => .{ .cmd = .rpc_bind },
            .call => .{ .cmd = .rpc_call },
            .end => .{ .cmd = .rpc_end },
        };
    }

    fn Body(comptime out: Out) type {
        return switch (out) {
            .change_saddr, .init_cmd => BufBody,
            .init_rpc => extern struct {},
            .bind => BindBody,
            .call => CallBody,
            .end => EndBody,
        };
    }
};

/// Incoming packet from the `IOP`
const In = extern union {
    hdr: Header,
    change_saddr: Packet(BufBody),
    set_sreg: Packet(SetSregBody),
    rdata: Packet(RdataBody),
    end: Packet(EndBody),
};

/// List of outgoing DMA transfers
var transfer_list: [2]sif.DmaTransfer align(64) = undefined;
/// `IOP` address of its receive buffer so we can DMA to it
var iop_recv_buf: u32 = 0;

/// Outgoing packets (`EE` -> `IOP`)
var send_buf: [28]u32 align(64) = undefined;
/// Receive buffer for the `IOP`'s packets
var recv_buf: [32]u32 align(64) = undefined;
/// Shared buffer used for RPC call arguments and results. Sharing is safe as the arguments
/// are transferred in the same DMA chain ahead of the call packet, so the `IOP` reads all
/// of them before the server runs and writes the result back.
var call_buf: [128]u32 align(64) = undefined;

/// Wraps the `SIF` RPC protocol
pub const Rpc = struct {
    pub const BindError = error{
        /// No server with this ID is registered on the `IOP`
        ServerNotFound,
    };

    /// Sets up the `SIF` RPC on first use, with later calls returning the RPC instance
    /// directly. No release is required.
    pub fn acquire() @This() {
        if (iop_recv_buf != 0) return .{};

        // Write-back and invalidate the `EE` data cache so that the packet buffers are clean
        // and only accessed via the uncached mirror from now on.
        std.os.ps2.cacheOp(.dxwbin);
        @as(*volatile Header, @ptrCast(uncached(&recv_buf))).size = .{};
        if (!sif.receiveArmed()) sif.unblockReceive();

        // Store the `IOP`'s receive buffer and tell it about our receive buffer
        const recv_addr: u32 = @intFromPtr(uncached(&recv_buf));
        const known = sif.getReg(.sys_sub_addr);
        if (known != 0) {
            iop_recv_buf = known;
            send(.change_saddr, .{ .buf = recv_addr });
        } else {
            // Wait until the `IOP`'s `SIF CMD` layer is up as `.sub_addr` is only valid
            // if it's running.
            while (!@as(sif.Flag, @bitCast(sif.getReg(.sm_flag))).cmd_init) {}

            // `SIF CMD` wasn't set up yet, so the `IOP` receive buffer address is in the
            // hardware register and we mirror it to the software one to have the kernel
            // store that the handshake completed.
            iop_recv_buf = sif.getReg(.sub_addr);
            sif.setReg(.sys_sub_addr, iop_recv_buf);
            send(.init_cmd, .{ .buf = recv_addr });
        }

        // Set up the `SIF RPC` layer now that `SIF CMD` is up
        if (sif.getReg(.sys_rpc_init) == 0) {
            send(.init_rpc, .{});
            // Spin until the `IOP` tells us that RPC is ready
            while (true) {
                const packet = receive();
                if (packet.hdr.cmd == .set_sreg and packet.set_sreg.body.index == 0) break;
            }

            sif.setReg(.sys_rpc_init, 1);
        }

        return .{};
    }

    /// Tries to bind to the `IOP` server `server`. The client is only valid until the
    /// `IOP` resets.
    pub fn bind(_: @This(), comptime server: Server) BindError!Client(server) {
        send(.bind, .{ .sid = @backingInt(server) });
        const end = complete(.rpc_bind);
        if (end.server == 0) return error.ServerNotFound;

        return .{ .server = end.server, .buf = end.buf };
    }
};

/// IDs of `IOP` RPC servers. The named ones are in ROM and registered at boot, others need
/// their modules loaded dynamically.
pub const Server = enum(u32) {
    /// Provides file access on the `IOP`'s devices (`host:`, `cdrom0:`, `rom0:`, ...)
    file_io = 0x8000_0001,
    /// Allocates and frees `IOP` memory from the `EE`
    iop_heap = 0x8000_0003,
    /// Loads and starts `IRX` modules on the `IOP` and `ELF`s on the `EE`
    load_file = 0x8000_0006,

    _,
};

/// RPC function associated with a given server
pub const Function = struct {
    /// `IOP` RPC server
    server: Server,
    /// Function ID
    id: u32,
    /// Arguments
    Args: type,
    /// Result type
    Result: type,
};

/// Client instance bound to a given `IOP` RPC server. Only valid until the `IOP` is reset.
pub fn Client(comptime id: Server) type {
    return struct {
        /// `IOP` address of the server's data
        server: u32,
        /// `IOP` address of the server's argument buffer where each call's arguments are
        /// copied to.
        buf: u32,

        /// Typed wrapper around `callRaw` to provide a convenient strongly-typed interface
        /// for RPC function calls.
        pub inline fn callBlocking(
            self: @This(),
            comptime func: Function,
            args: func.Args,
        ) func.Result {
            comptime {
                std.debug.assert(@sizeOf(func.Args) <= @sizeOf(@TypeOf(call_buf)));
                std.debug.assert(@sizeOf(func.Result) <= @sizeOf(@TypeOf(call_buf)));
            }

            if (func.server != id) @compileError(
                "function of server " ++ @tagName(func.server) ++ " called on a client of " ++ @tagName(id),
            );

            @as(*volatile func.Args, @ptrCast(uncached(&call_buf))).* = args;
            callRaw(self.server, self.buf, func.id, @sizeOf(func.Args), @sizeOf(func.Result));
            _ = complete(.rpc_call);
            return @as(*volatile func.Result, @ptrCast(uncached(&call_buf))).*;
        }
    };
}

// Factored out of `callBlocking` to reduce code duplication
fn callRaw(server: u32, buf: u32, func: u32, args_size: u32, result_size: u32) void {
    sendWith(.call, .{
        .func = func,
        .args_size = args_size,
        .result = @intFromPtr(&call_buf),
        .result_size = result_size,
        .server = server,
    }, .{
        .src = @intFromPtr(&call_buf),
        .dst = buf,
        .size = args_size,
    });
}

/// Sends a packet without an associated payload
inline fn send(comptime out: Out, body: out.Body()) void {
    sendWith(out, body, null);
}

/// Sends a packet with an associated payload
inline fn sendWith(comptime out: Out, body: out.Body(), payload: ?Payload) void {
    const P = Packet(out.Body());
    comptime std.debug.assert(@sizeOf(P) <= @sizeOf(@TypeOf(send_buf)));

    const packet: *volatile P = @ptrCast(uncached(&send_buf));
    packet.* = .{ .hdr = comptime out.header(), .body = body };
    submit(@sizeOf(P), payload);
}

/// Submits a packet and its associated payload to the kernel's `SIF` DMA queue
fn submit(size: u32, payload: ?Payload) void {
    const hdr: *volatile Header = @ptrCast(uncached(&send_buf));
    const list = uncached(&transfer_list);

    // If there's a payload associated with the packet, the payload is sent to the `IOP`
    // before the actual packet.
    var n: usize = 0;
    if (payload) |p| {
        hdr.size = .{ .whole = @intCast(size), .payload = @intCast(p.size) };
        hdr.payload_dst = p.dst;

        list[0] = .{
            .src = p.src,
            .dst = p.dst,
            .size = p.size,
            .attr = .{},
        };
        n = 1;
    } else {
        hdr.size = .{ .whole = @intCast(size) };
    }

    list[n] = .{
        .src = @intFromPtr(&send_buf),
        .dst = iop_recv_buf,
        .size = size,
        .attr = .{ .iop_int = true, .ert = true },
    };
    // Drain the store buffer so every uncached write is visible
    asm volatile ("sync" ::: .{ .memory = true });

    while (sif.queueDmaTransfers(transfer_list[0 .. n + 1]) == 0) {}
}

/// Waits for the next packet from the `IOP` and returns it unless it's a system
/// packet that can be handled internally.
fn receive() In {
    const in: *volatile In = @ptrCast(uncached(&recv_buf));
    while (true) {
        // Spin until the packet size gets written which means the DMA transfer for incoming
        // `IOP` packet is complete.
        while (in.hdr.size.whole == 0) {}

        const packet = in.*;

        // Mark the buffer free by setting the packet size to `0` and unblock the `IOP`
        in.hdr.size = .{};
        sif.unblockReceive();

        switch (packet.hdr.cmd) {
            .change_saddr => iop_recv_buf = packet.change_saddr.body.buf,
            .rpc_rdata => sendData(packet.rdata.body),

            else => return packet,
        }
    }
}

/// Waits for an `.rpc_end` packet that completes `request`
fn complete(request: Cmd) EndBody {
    while (true) {
        const packet = receive();
        if (packet.hdr.cmd == .rpc_end and packet.end.body.request == request)
            return packet.end.body;
    }
}

/// Answers an `IOP` request for `EE` memory
fn sendData(request: RdataBody) void {
    // Write back any dirty lines belonging to the request so the DMA controller picks them up
    std.os.ps2.writeBackDCache(request.src, request.size);
    sendWith(.end, .{
        .rpc = .{ .packet_addr = request.rpc.packet_addr, .client = request.rpc.client },
        .request = .rpc_rdata,
    }, .{ .src = request.src, .dst = request.dst, .size = request.size });
}
