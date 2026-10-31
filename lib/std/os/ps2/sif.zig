//! `SIF` is the name of the interface that sits between the `EE` and the `IOP`. It consists
//! of `2` `DMA` channels:
//! * `SIF0`, which is `IOP` -> `EE`
//! * `SIF1`, which is `EE` -> `IOP`
//!
//! The `SIF` `CMD` and RPC protocols are built on top of them.

const std = @import("std");
const ps2 = std.os.ps2;

/// `SIF` registers. The flag registers are used like semaphores to synchronize. The `sys_*`
/// registers are implemented by the kernel and not backed by hardware.
pub const Reg = enum(u32) {
    /// Address of the `EE`'s receive buffer, which is where the `IOP` writes packets to
    main_addr = 1,
    /// Address of the `IOP`'s receive buffer, where the `EE`'s packets are written to
    sub_addr = 2,
    /// Status flags for `EE` -> `IOP`
    ms_flag = 3,
    /// Status flags for `IOP` -> `EE`
    sm_flag = 4,

    /// Address of the `IOP`'s receive buffer as recorded by the first `SIF CMD` client
    sys_sub_addr = 0x8000_0000,
    /// Set to `1` after the RPC layer has been initialized
    sys_rpc_init = 0x8000_0002,
};

/// Single entry in a `DMA` transfer list
pub const DmaTransfer = extern struct {
    /// `EE` source address
    src: u32,
    /// `IOP` destination address
    dst: u32,
    /// Number of bytes to transfer
    size: u32,
    /// Transfer attributes
    attr: Attr,

    /// `DMA` transfer attributes
    pub const Attr = packed struct(u32) {
        _0: u1 = 0,
        /// Raise an interrupt on the `EE` when the transfer completes
        ee_int: bool = false,
        /// Raise an interrupt on the `IOP` when the transfer completes
        iop_int: bool = false,
        _3: u3 = 0,
        /// Marks the end of a `SIF` command packet chain
        ert: bool = false,
        _7: u25 = 0,
    };
};

/// Queues `transfers` on `SIF1` to `DMA` from `EE` -> `IOP`. Returns the transfer id or `0`
/// if the kernel's queue is full. The data referenced by each transfer's `src` must be
/// written back to the RAM since the `DMA` controller does not snoop `EE` caches.
pub fn queueDmaTransfers(transfers: []const DmaTransfer) u32 {
    return ps2.syscall2(.sif_set_dma, @intFromPtr(transfers.ptr), transfers.len);
}

/// `SIF0` (`IOP` -> `EE`) runs in so-called "chain mode" where the `IOP` pushes packets into
/// an `EE`-side receive buffer, but the `EE` needs to re-arm the channel after each packet.
pub fn unblockReceive() void {
    _ = ps2.syscall0(.sif_set_dchain);
}

/// Returns the value of the requested `SIF` register
pub fn getReg(reg: Reg) u32 {
    return ps2.syscall1(.sif_get_reg, @backingInt(reg));
}

/// Updates the value of the requested `SIF` register to `val`
pub fn setReg(reg: Reg, val: u32) void {
    _ = ps2.syscall2(.sif_set_reg, @backingInt(reg), val);
}
