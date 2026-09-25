//! Handles a single connection lifecycle.

const std = @import("../std.zig");
const http = std.http;
const mem = std.mem;
const Uri = std.Uri;
const assert = std.debug.assert;
const testing = std.testing;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const Server = @This();

/// Data from the HTTP server to the HTTP client.
out: *Writer,
reader: http.Reader,

/// Initialize an HTTP server that can respond to multiple requests on the same
/// connection.
///
/// The buffer of `in` must be large enough to store the client's entire HTTP
/// header, otherwise `receiveHead` returns `error.HttpHeadersOversize`.
///
/// The returned `Server` is ready for `receiveHead` to be called.
pub fn init(in: *Reader, out: *Writer) Server {
    return .{
        .reader = .{
            .in = in,
            .state = .ready,
            // Populated when `http.Reader.bodyReader` is called.
            .interface = undefined,
            .max_head_len = in.buffer.len,
        },
        .out = out,
    };
}

pub const ReceiveHeadError = http.Reader.HeadError || error{
    /// Client sent headers that did not conform to the HTTP protocol.
    ///
    /// To find out more detailed diagnostics, `Request.head_buffer` can be
    /// passed directly to `Request.Head.parse`.
    HttpHeadersInvalid,
};

pub fn receiveHead(s: *Server) ReceiveHeadError!Request {
    const head_buffer = try s.reader.receiveHead();
    return .{
        .server = s,
        .head_buffer = head_buffer,
        // No need to track the returned error here since users can repeat the
        // parse with the header buffer to get detailed diagnostics.
        .head = Request.Head.parse(head_buffer) catch return error.HttpHeadersInvalid,
    };
}

pub const Request = struct {
    server: *Server,
    /// Pointers in this struct are invalidated when the request body stream is
    /// initialized.
    head: Head,
    head_buffer: []const u8,
    respond_err: ?RespondError = null,

    pub const RespondError = error{
        /// The request contained an `expect` header with an unrecognized value.
        HttpExpectationFailed,
    };

    pub const Head = struct {
        method: http.Method,
        target: []const u8,
        version: http.Version,
        expect: ?[]const u8,
        content_type: ?[]const u8,
        content_length: ?u64,
        transfer_encoding: http.TransferEncoding,
        transfer_compression: http.ContentEncoding,
        keep_alive: bool,

        pub const ParseError = error{
            UnknownHttpMethod,
            HttpHeadersInvalid,
            HttpHeaderContinuationsUnsupported,
            HttpTransferEncodingUnsupported,
            HttpConnectionHeaderUnsupported,
            InvalidContentLength,
            CompressionUnsupported,
            MissingFinalNewline,
        };

        pub fn parse(bytes: []const u8) ParseError!Head {
            var it = mem.splitSequence(u8, bytes, "\r\n");

            const first_line = it.next().?;
            if (first_line.len < 10)
                return error.HttpHeadersInvalid;

            const method_end = mem.findScalar(u8, first_line, ' ') orelse
                return error.HttpHeadersInvalid;

            const method = std.meta.stringToEnum(http.Method, first_line[0..method_end]) orelse
                return error.UnknownHttpMethod;

            const version_start = mem.findScalarLast(u8, first_line, ' ') orelse
                return error.HttpHeadersInvalid;
            if (version_start == method_end) return error.HttpHeadersInvalid;

            const version_str = first_line[version_start + 1 ..];
            if (version_str.len != 8) return error.HttpHeadersInvalid;
            const version: http.Version = switch (int64(version_str[0..8])) {
                int64("HTTP/1.0") => .@"HTTP/1.0",
                int64("HTTP/1.1") => .@"HTTP/1.1",
                else => return error.HttpHeadersInvalid,
            };

            const target = first_line[method_end + 1 .. version_start];

            var head: Head = .{
                .method = method,
                .target = target,
                .version = version,
                .expect = null,
                .content_type = null,
                .content_length = null,
                .transfer_encoding = .none,
                .transfer_compression = .identity,
                .keep_alive = switch (version) {
                    .@"HTTP/1.0" => false,
                    .@"HTTP/1.1" => true,
                },
            };

            while (it.next()) |line| {
                if (line.len == 0) return head;
                switch (line[0]) {
                    ' ', '\t' => return error.HttpHeaderContinuationsUnsupported,
                    else => {},
                }

                var line_it = mem.splitScalar(u8, line, ':');
                const header_name = line_it.next().?;
                const header_value = mem.trim(u8, line_it.rest(), " \t");
                if (header_name.len == 0) return error.HttpHeadersInvalid;

                if (std.ascii.eqlIgnoreCase(header_name, "connection")) {
                    head.keep_alive = !std.ascii.eqlIgnoreCase(header_value, "close");
                } else if (std.ascii.eqlIgnoreCase(header_name, "expect")) {
                    head.expect = header_value;
                } else if (std.ascii.eqlIgnoreCase(header_name, "content-type")) {
                    head.content_type = header_value;
                } else if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
                    if (head.content_length != null) return error.HttpHeadersInvalid;
                    head.content_length = std.fmt.parseInt(u64, header_value, 10) catch
                        return error.InvalidContentLength;
                } else if (std.ascii.eqlIgnoreCase(header_name, "content-encoding")) {
                    if (head.transfer_compression != .identity) return error.HttpHeadersInvalid;

                    const trimmed = mem.trim(u8, header_value, " ");

                    if (http.ContentEncoding.fromString(trimmed)) |ce| {
                        head.transfer_compression = ce;
                    } else {
                        return error.HttpTransferEncodingUnsupported;
                    }
                } else if (std.ascii.eqlIgnoreCase(header_name, "transfer-encoding")) {
                    // Transfer-Encoding: second, first
                    // Transfer-Encoding: deflate, chunked
                    var iter = mem.splitBackwardsScalar(u8, header_value, ',');

                    const first = iter.first();
                    const trimmed_first = mem.trim(u8, first, " ");

                    var next: ?[]const u8 = first;
                    if (std.meta.stringToEnum(http.TransferEncoding, trimmed_first)) |transfer| {
                        if (head.transfer_encoding != .none)
                            return error.HttpHeadersInvalid; // we already have a transfer encoding
                        head.transfer_encoding = transfer;

                        next = iter.next();
                    }

                    if (next) |second| {
                        const trimmed_second = mem.trim(u8, second, " ");

                        if (http.ContentEncoding.fromString(trimmed_second)) |transfer| {
                            if (head.transfer_compression != .identity)
                                return error.HttpHeadersInvalid; // double compression is not supported
                            head.transfer_compression = transfer;
                        } else {
                            return error.HttpTransferEncodingUnsupported;
                        }
                    }

                    if (iter.next()) |_| return error.HttpTransferEncodingUnsupported;
                }
            }
            return error.MissingFinalNewline;
        }

        test parse {
            const request_bytes = "GET /hi HTTP/1.0\r\n" ++
                "content-tYpe: text/plain\r\n" ++
                "content-Length:10\r\n" ++
                "expeCt:   100-continue \r\n" ++
                "TRansfer-encoding:\tdeflate, chunked \r\n" ++
                "connectioN:\t keep-alive \r\n\r\n";

            const req = try parse(request_bytes);

            try testing.expectEqual(.GET, req.method);
            try testing.expectEqual(.@"HTTP/1.0", req.version);
            try testing.expectEqualStrings("/hi", req.target);

            try testing.expectEqualStrings("text/plain", req.content_type.?);
            try testing.expectEqualStrings("100-continue", req.expect.?);

            try testing.expectEqual(true, req.keep_alive);
            try testing.expectEqual(10, req.content_length.?);
            try testing.expectEqual(.chunked, req.transfer_encoding);
            try testing.expectEqual(.deflate, req.transfer_compression);
        }

        inline fn int64(array: *const [8]u8) u64 {
            return @bitCast(array.*);
        }

        /// Help the programmer avoid bugs by calling this when the string
        /// memory of `Head` becomes invalidated.
        fn invalidateStrings(h: *Head) void {
            h.target = undefined;
            if (h.expect) |*s| s.* = undefined;
            if (h.content_type) |*s| s.* = undefined;
        }
    };

    pub fn iterateHeaders(r: *const Request) http.HeaderIterator {
        assert(r.server.reader.state == .received_head);
        return http.HeaderIterator.init(r.head_buffer);
    }

    test iterateHeaders {
        const request_bytes = "GET /hi HTTP/1.0\r\n" ++
            "content-tYpe: text/plain\r\n" ++
            "content-Length:10\r\n" ++
            "expeCt:   100-continue \r\n" ++
            "TRansfer-encoding:\tdeflate, chunked \r\n" ++
            "connectioN:\t keep-alive \r\n\r\n";

        var server: Server = .{
            .reader = .{
                .in = undefined,
                .state = .received_head,
                .interface = undefined,
                .max_head_len = 4096,
            },
            .out = undefined,
        };

        var request: Request = .{
            .server = &server,
            .head = undefined,
            .head_buffer = @constCast(request_bytes),
        };

        var it = request.iterateHeaders();
        {
            const header = it.next().?;
            try testing.expectEqualStrings("content-tYpe", header.name);
            try testing.expectEqualStrings("text/plain", header.value);
            try testing.expect(!it.is_trailer);
        }
        {
            const header = it.next().?;
            try testing.expectEqualStrings("content-Length", header.name);
            try testing.expectEqualStrings("10", header.value);
            try testing.expect(!it.is_trailer);
        }
        {
            const header = it.next().?;
            try testing.expectEqualStrings("expeCt", header.name);
            try testing.expectEqualStrings("100-continue", header.value);
            try testing.expect(!it.is_trailer);
        }
        {
            const header = it.next().?;
            try testing.expectEqualStrings("TRansfer-encoding", header.name);
            try testing.expectEqualStrings("deflate, chunked", header.value);
            try testing.expect(!it.is_trailer);
        }
        {
            const header = it.next().?;
            try testing.expectEqualStrings("connectioN", header.name);
            try testing.expectEqualStrings("keep-alive", header.value);
            try testing.expect(!it.is_trailer);
        }
        try testing.expectEqual(null, it.next());
    }

    pub const RespondOptions = struct {
        version: http.Version = .@"HTTP/1.1",
        status: http.Status = .ok,
        reason: ?[]const u8 = null,
        keep_alive: bool = true,
        extra_headers: []const http.Header = &.{},
        transfer_encoding: ?http.TransferEncoding = null,
    };

    /// Send an entire HTTP response to the client, including headers and body.
    ///
    /// Automatically handles HEAD requests by omitting the body.
    ///
    /// Unless `transfer_encoding` is specified, uses the "content-length"
    /// header.
    ///
    /// If the request contains a body and the connection is to be reused,
    /// discards the request body, leaving the Server in the `ready` state. If
    /// this discarding fails, the connection is marked as not to be reused and
    /// no error is surfaced.
    ///
    /// Asserts status is not `continue`.
    /// Asserts that "\r\n" does not occur in any header name or value.
    pub fn respond(
        request: *Request,
        content: []const u8,
        options: RespondOptions,
    ) ExpectContinueError!void {
        try respondUnflushed(request, content, options);
        try request.server.out.flush();
    }

    pub fn respondUnflushed(
        request: *Request,
        content: []const u8,
        options: RespondOptions,
    ) ExpectContinueError!void {
        assert(options.status != .@"continue");
        if (std.debug.runtime_safety) {
            for (options.extra_headers) |header| {
                assert(header.name.len != 0);
                assert(std.mem.findScalar(u8, header.name, ':') == null);
                assert(std.mem.findPosLinear(u8, header.name, 0, "\r\n") == null);
                assert(std.mem.findPosLinear(u8, header.value, 0, "\r\n") == null);
            }
        }
        try writeExpectContinue(request);

        const transfer_encoding_none = (options.transfer_encoding orelse .chunked) == .none;
        const server_keep_alive = !transfer_encoding_none and options.keep_alive;
        const keep_alive = request.discardBody(server_keep_alive);

        const phrase = options.reason orelse options.status.phrase() orelse "";

        const out = request.server.out;
        try out.print("{s} {d} {s}\r\n", .{
            @tagName(options.version), @backingInt(options.status), phrase,
        });

        switch (options.version) {
            .@"HTTP/1.0" => if (keep_alive) try out.writeAll("connection: keep-alive\r\n"),
            .@"HTTP/1.1" => if (!keep_alive) try out.writeAll("connection: close\r\n"),
        }

        if (options.transfer_encoding) |transfer_encoding| switch (transfer_encoding) {
            .none => {},
            .chunked => try out.writeAll("transfer-encoding: chunked\r\n"),
        } else {
            try out.print("content-length: {d}\r\n", .{content.len});
        }

        for (options.extra_headers) |header| {
            var vecs: [4][]const u8 = .{ header.name, ": ", header.value, "\r\n" };
            try out.writeVecAll(&vecs);
        }

        try out.writeAll("\r\n");

        if (request.head.method != .HEAD) {
            const is_chunked = (options.transfer_encoding orelse .none) == .chunked;
            if (is_chunked) {
                if (content.len > 0) try out.print("{x}\r\n{s}\r\n", .{ content.len, content });
                try out.writeAll("0\r\n\r\n");
            } else if (content.len > 0) {
                try out.writeAll(content);
            }
        }
    }

    pub const RespondStreamingOptions = struct {
        /// If provided, the response will use the content-length header;
        /// otherwise it will use transfer-encoding: chunked.
        content_length: ?u64 = null,
        /// Options that are shared with the `respond` method.
        respond_options: RespondOptions = .{},
    };

    /// The header is not guaranteed to be sent until `BodyWriter.flush` or
    /// `BodyWriter.end` is called.
    ///
    /// If the request contains a body and the connection is to be reused,
    /// discards the request body, leaving the Server in the `ready` state. If
    /// this discarding fails, the connection is marked as not to be reused and
    /// no error is surfaced.
    ///
    /// HEAD requests are handled transparently by setting the
    /// `BodyWriter.elide` flag on the returned `BodyWriter`, causing
    /// the response stream to omit the body. However, it may be worth noticing
    /// that flag and skipping any expensive work that would otherwise need to
    /// be done to satisfy the request.
    ///
    /// Asserts status is not `continue`.
    pub fn respondStreaming(
        request: *Request,
        buffer: []u8,
        options: RespondStreamingOptions,
    ) ExpectContinueError!http.BodyWriter {
        try writeExpectContinue(request);
        const o = options.respond_options;
        assert(o.status != .@"continue");
        const transfer_encoding_none = (o.transfer_encoding orelse .chunked) == .none;
        const server_keep_alive = !transfer_encoding_none and o.keep_alive;
        const keep_alive = request.discardBody(server_keep_alive);
        const phrase = o.reason orelse o.status.phrase() orelse "";
        const out = request.server.out;

        try out.print("{s} {d} {s}\r\n", .{
            @tagName(o.version), @backingInt(o.status), phrase,
        });

        switch (o.version) {
            .@"HTTP/1.0" => if (keep_alive) try out.writeAll("connection: keep-alive\r\n"),
            .@"HTTP/1.1" => if (!keep_alive) try out.writeAll("connection: close\r\n"),
        }

        if (o.transfer_encoding) |transfer_encoding| switch (transfer_encoding) {
            .chunked => try out.writeAll("transfer-encoding: chunked\r\n"),
            .none => {},
        } else if (options.content_length) |len| {
            try out.print("content-length: {d}\r\n", .{len});
        } else {
            try out.writeAll("transfer-encoding: chunked\r\n");
        }

        for (o.extra_headers) |header| {
            assert(header.name.len != 0);
            var bufs: [4][]const u8 = .{ header.name, ": ", header.value, "\r\n" };
            try out.writeVecAll(&bufs);
        }

        try out.writeAll("\r\n");
        const elide_body = request.head.method == .HEAD;
        const state: http.BodyWriter.State = if (o.transfer_encoding) |te| switch (te) {
            .chunked => .init_chunked,
            .none => .none,
        } else if (options.content_length) |len| .{
            .content_length = len,
        } else .init_chunked;

        return if (elide_body) .{
            .http_protocol_output = request.server.out,
            .state = state,
            .writer = .{
                .buffer = buffer,
                .vtable = &.{
                    .drain = http.BodyWriter.elidingDrain,
                    .sendFile = http.BodyWriter.elidingSendFile,
                },
            },
        } else .{
            .http_protocol_output = request.server.out,
            .state = state,
            .writer = .{
                .buffer = buffer,
                .vtable = switch (state) {
                    .none => &.{
                        .drain = http.BodyWriter.noneDrain,
                        .sendFile = http.BodyWriter.noneSendFile,
                    },
                    .content_length => &.{
                        .drain = http.BodyWriter.contentLengthDrain,
                        .sendFile = http.BodyWriter.contentLengthSendFile,
                    },
                    .chunk_len => &.{
                        .drain = http.BodyWriter.chunkedDrain,
                        .sendFile = http.BodyWriter.chunkedSendFile,
                    },
                    .end => unreachable,
                },
            },
        };
    }

    pub const WebSocketOptions = struct {
        reason: ?[]const u8 = null,
        extra_headers: []const http.Header = &.{},
    };

    const RespondWebSocketError = ExpectContinueError || error{ WebSocketProtocolViolation, UnknownWebSocketVersion };

    pub const supported_websocket_version = "13";

    /// Requires `request.head` to still be valid.
    ///
    /// If `error.HttpExpectationFailed`, `error.WebSocketProtocolViolation`,
    /// or `error.UnknownWebSocketVersion` are returned, does not invalidate
    /// `request.head`.
    ///
    /// The spec requires servers to respond with supported websocket
    /// versions if this returns `error.UnknownWebSocketVersion`.  However
    /// it has been 15 years with only one valid version, so this is unlikely
    /// to ever matter.
    pub fn respondWebSocket(request: *Request, io: std.Io, options: WebSocketOptions) RespondWebSocketError!WebSocket {
        if (request.head.expect != null) return error.HttpExpectationFailed;

        switch (request.head.version) {
            .@"HTTP/1.0" => return error.WebSocketProtocolViolation,
            .@"HTTP/1.1" => if (request.head.method != .GET) return error.WebSocketProtocolViolation,
        }

        const key = blk: {
            var sec_websocket_key: ?[]const u8 = null;
            var upgrade = false;
            var connection = false;
            var sec_websocket_version = false;

            var it = request.iterateHeaders();
            while (it.next()) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "sec-websocket-key")) {
                    if (std.base64.standard.Decoder.calcSizeForSlice(header.value) catch 0 != 16) return error.WebSocketProtocolViolation;
                    sec_websocket_key = header.value;
                } else if (std.ascii.eqlIgnoreCase(header.name, "upgrade")) {
                    if (std.ascii.findIgnoreCase(header.value, "websocket")) |_| upgrade = true;
                } else if (std.ascii.eqlIgnoreCase(header.name, "connection")) {
                    if (std.ascii.findIgnoreCase(header.value, "upgrade")) |_| connection = true;
                } else if (std.ascii.eqlIgnoreCase(header.name, "sec-websocket-version")) {
                    if (!std.mem.eql(u8, header.value, supported_websocket_version)) return error.UnknownWebSocketVersion;
                    sec_websocket_version = true;
                }
            }
            if (!(upgrade and connection and sec_websocket_version)) return error.WebSocketProtocolViolation;

            break :blk (sec_websocket_key orelse return error.WebSocketProtocolViolation);
        };

        const out = request.server.out;
        const version: http.Version = .@"HTTP/1.1";
        const status: http.Status = .switching_protocols;
        const phrase = options.reason orelse status.phrase() orelse "";

        assert(request.head.version == version);
        assert(request.head.method == .GET);

        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(key);
        sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
        var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
        sha1.final(&digest);
        try out.print("{s} {d} {s}\r\n", .{ @tagName(version), @backingInt(status), phrase });
        try out.writeAll("connection: upgrade\r\nupgrade: websocket\r\nsec-websocket-accept: ");
        const base64_digest = try out.writableArray(28);
        assert(std.base64.standard.Encoder.encode(base64_digest, &digest).len == base64_digest.len);
        try out.writeAll("\r\n");

        for (options.extra_headers) |header| {
            assert(header.name.len != 0);
            var bufs: [4][]const u8 = .{ header.name, ": ", header.value, "\r\n" };
            try out.writeVecAll(&bufs);
        }

        try out.writeAll("\r\n");
        try out.flush();

        assert(request.server.reader.in.buffer.len >= WebSocket.control_frame_max_payload_len);

        return .{
            .io = io,
            .write_lock = .init,
            .input = request.server.reader.in,
            .output = request.server.out,
            .closed = false,
            .reader = undefined,
            .writer = undefined,
            .reader_frame = null,
            .writer_frame = null,
            .reader_err = null,
            .writer_err = null,
            .close_status_code = 0,
            .close_reason = "",
        };
    }

    /// In the case that the request contains "expect: 100-continue", this
    /// function writes the continuation header, which means it can fail with a
    /// write error. After sending the continuation header, it sets the
    /// request's expect field to `null`.
    ///
    /// Asserts that this function is only called once.
    ///
    /// See `readerExpectNone` for an infallible alternative that cannot write
    /// to the server output stream.
    pub fn readerExpectContinue(request: *Request, buffer: []u8) ExpectContinueError!*Reader {
        const flush = request.head.expect != null;
        try writeExpectContinue(request);
        if (flush) try request.server.out.flush();
        return readerExpectNone(request, buffer);
    }

    /// Asserts the expect header is `null`. The caller must handle the
    /// expectation manually and then set the value to `null` prior to calling
    /// this function.
    ///
    /// Asserts that this function is only called once.
    ///
    /// Invalidates the string memory inside `Head`.
    pub fn readerExpectNone(request: *Request, buffer: []u8) *Reader {
        assert(request.server.reader.state == .received_head);
        assert(request.head.expect == null);
        request.head.invalidateStrings();
        if (!request.head.method.requestHasBody()) return .ending;
        return request.server.reader.bodyReader(buffer, request.head.transfer_encoding, request.head.content_length);
    }

    pub const ExpectContinueError = error{
        /// Failed to write "HTTP/1.1 100 Continue\r\n\r\n" to the stream.
        WriteFailed,
        /// The client sent an expect HTTP header value other than
        /// "100-continue".
        HttpExpectationFailed,
    };

    pub fn writeExpectContinue(request: *Request) ExpectContinueError!void {
        const expect = request.head.expect orelse return;
        if (!mem.eql(u8, expect, "100-continue")) return error.HttpExpectationFailed;
        try request.server.out.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
        request.head.expect = null;
    }

    /// Returns whether the connection should remain persistent.
    ///
    /// If it would fail, it instead sets the Server state to receiving body
    /// and returns false.
    fn discardBody(request: *Request, keep_alive: bool) bool {
        // Prepare to receive another request on the same connection.
        // There are two factors to consider:
        // * Any body the client sent must be discarded.
        // * The Server's read_buffer may already have some bytes in it from
        //   whatever came after the head, which may be the next HTTP request
        //   or the request body.
        // If the connection won't be kept alive, then none of this matters
        // because the connection will be severed after the response is sent.
        const r = &request.server.reader;
        if (keep_alive and request.head.keep_alive) switch (r.state) {
            .received_head => {
                if (request.head.method.requestHasBody()) {
                    assert(request.head.transfer_encoding != .none or request.head.content_length != null);
                    const reader_interface = request.readerExpectContinue(&.{}) catch return false;
                    _ = reader_interface.discardRemaining() catch return false;
                    assert(r.state == .ready);
                } else {
                    r.state = .ready;
                }
                return true;
            },
            .body_remaining_content_length, .body_remaining_chunk_len, .body_none, .ready => return true,
            else => unreachable,
        };

        // Avoid clobbering the state in case a reading stream already exists.
        switch (r.state) {
            .received_head => r.state = .closing,
            else => {},
        }
        return false;
    }
};

/// See https://tools.ietf.org/html/rfc6455
pub const WebSocket = struct {
    // Changes to WebSocket should be tested with the autobahn testsuite, which
    // isn't worth being added as a dependency to run in the ci.  See
    // https://codeberg.org/ScottRedig/websocket_test/ for an example test setup.

    // A Note for future improvement:  This type (with a few small field changes)
    // would be equally capable of being used as a WebSocket client.  However
    // that requires entirely different reader.stream and writer.drain
    // implementations to account for masking always being from client to server.
    // That, along with an appropriate code to initiate the connection / upgrade
    // the request are left as an exercise for a future contributor.

    // Shared
    io: std.Io,
    write_lock: std.Io.Mutex,
    closed: bool, // guarded by write_lock
    output: *std.Io.Writer, // guarded by write_lock

    // Read thread
    input: *std.Io.Reader,
    reader: std.Io.Reader,
    reader_frame: ?struct {
        finish: bool,
        mask: [4]u8,
        mask_pos: u2,
        bytes_remaining: u64,
    },
    reader_err: ?ReadError,
    /// Populated after an attempted read recieves a close message.
    close_status_code: u16,
    /// if populated, is a view into input's buffer, invalidated by changes to input.
    close_reason: []u8,

    // Write thread
    writer: std.Io.Writer,
    writer_frame: ?struct {
        op_code: Header.OpCode,
    },
    writer_err: ?WriteError,

    pub const control_frame_max_payload_len = 125;

    pub const ReadError = error{
        WebSocketProtocolViolation,
        WebSocketClosed,
        ReadFailed,
        WriteFailed,
        Canceled,
    };

    pub const WriteError = error{
        WriteFailed,
        Canceled,
        WebSocketClosed,
    };

    const MessageKind = enum {
        binary,
        text,
    };

    /// Begins reading a new message. Invalidates previously returned readers and discards any unread
    /// bytes in the last message.
    ///
    /// In a departure from WebSocket's spec, this does not perform utf8 validation when MessageKind
    /// is text.  Clients which care should validate it themselves, eg with `std.unicode.utf8ValidateSlice`.
    pub fn messageReader(ws: *WebSocket, buffer: []u8) ReadError!struct { MessageKind, *std.Io.Reader } {
        ws.reader = .{
            .vtable = &.{
                .stream = readerStream,
            },
            .buffer = buffer,
            .seek = 0,
            .end = 0,
        };
        if (ws.reader_frame) |frame| {
            _ = ws.reader.discardRemaining() catch |err| switch (err) {
                error.ReadFailed => return ws.reader_err.?,
            };
            assert(frame.finish);
            assert(frame.bytes_remaining == 0);
            ws.reader_frame = null;
        }

        const kind: MessageKind = switch (try ws.beginDataFrame()) {
            .continuation => return error.WebSocketProtocolViolation,
            .text => .text,
            .binary => .binary,
            else => unreachable,
        };
        return .{ kind, &ws.reader };
    }

    /// Begins writing a new message.  Caller must call `endWriter` to finalize this message before
    /// calling messageWriter again.
    pub fn messageWriter(ws: *WebSocket, buffer: []u8, kind: MessageKind) *std.Io.Writer {
        assert(ws.writer_frame == null);
        ws.writer_frame = .{
            .op_code = switch (kind) {
                .text => .text,
                .binary => .binary,
            },
        };
        ws.writer = .{
            .vtable = &.{
                .drain = drain,
            },
            .buffer = buffer,
            .end = 0,
        };
        return &ws.writer;
    }

    /// Marks the message initiated by `messageWriter` as complete, and flushes any buffered bytes.
    /// It is unnecessary to directly call flush on the writer returned from messageWriter, and will
    /// likely result in a few extra bytes being sent.
    pub fn endWriter(ws: *WebSocket) WriteError!void {
        assert(ws.writer_err == null);
        // Can't use flush, since it may be sending a zero byte message.
        _ = ws.writeFrame(ws.writer_frame.?.op_code, true, ws.writer.buffer[0..ws.writer.end], &.{}, 0) catch |err| {
            ws.writer_err = err;
            return err;
        };
        ws.writer = undefined;
        ws.writer_frame = null;
    }

    /// Tells the client the connection is closing, and no further messages will be sent.  The client is supposed to
    /// finish sending the current message and then respond with a close itself.  So the server can still fully process
    /// any incoming messages after it wants to close the connection.  Does not close any underlying sockets.
    ///
    /// For the connection to be considered properly closed, the server should call messageReader until getting an
    /// error, such as error.WebSocketClosed.
    pub fn sendClose(ws: *WebSocket) error{ Canceled, WriteFailed }!void {
        // Could take close status code and reason parameters.  Do that when there's literally any reason whatsoever to do so.
        const normal_closure_code: u16 = 1000;
        var body: [2]u8 = undefined;
        std.mem.writeInt(u16, &body, normal_closure_code, .big);
        _ = ws.writeFrame(.close, true, &body, &.{}, 0) catch |err| return switch (err) {
            error.Canceled => error.Canceled,
            error.WriteFailed => error.WriteFailed,
            error.WebSocketClosed => {},
        };
    }

    fn beginDataFrame(ws: *WebSocket) ReadError!Header.OpCode {
        while (true) {
            const header = Header.read(ws.input) catch |err| return switch (err) {
                error.EndOfStream, error.WebSocketProtocolViolation => error.WebSocketProtocolViolation,
                error.ReadFailed => error.ReadFailed,
            };
            switch (header.op_code) {
                .continuation, .text, .binary => {
                    const mask = header.mask orelse return error.WebSocketProtocolViolation;

                    ws.reader_frame = .{
                        .finish = header.finish,
                        .mask = mask,
                        .mask_pos = 0,
                        .bytes_remaining = header.payload_len,
                    };

                    return header.op_code;
                },
                .close => {
                    if (!header.finish) return error.WebSocketProtocolViolation;
                    const payload = try ws.controlFramePayload(header);

                    const no_status_code = 1005;
                    ws.close_status_code = if (payload.len >= 2) std.mem.readInt(u16, payload[0..2], .big) else no_status_code;

                    if (payload.len > 2) {
                        ws.close_reason = payload[2..];
                    }
                    _ = ws.writeFrame(.close, true, "", &.{}, 0) catch |err| return switch (err) {
                        error.Canceled => error.Canceled,
                        // Close previously sent.  Either both closed at same time, or this is the response to close being sent.
                        error.WebSocketClosed => error.WebSocketClosed,
                        // A failed write is still an error here.  If the remote wanted to shut down in a spec complaint way,
                        // it should have waited for the close echo before closing sockets.  The source Writer may also have
                        // encountered an error.Canceled.
                        error.WriteFailed => error.WriteFailed,
                    };
                    return error.WebSocketClosed;
                },
                .ping => {
                    if (!header.finish) return error.WebSocketProtocolViolation;
                    const payload = try ws.controlFramePayload(header);
                    _ = ws.writeFrame(.pong, true, payload, &.{}, 0) catch |err| switch (err) {
                        error.WebSocketClosed => {}, // Even if writing is closed, should continue processing reads.
                        else => return err,
                    };
                    continue;
                },
                .pong => {
                    // Though this API doesn't support sending pings, remote connections are allowed
                    // to send unsolicited pongs.
                    if (!header.finish) return error.WebSocketProtocolViolation;
                    _ = try ws.controlFramePayload(header);
                    continue;
                },
            }
        }
    }

    fn controlFramePayload(ws: *WebSocket, header: Header) ![]u8 {
        if (header.payload_len > control_frame_max_payload_len) {
            return error.WebSocketProtocolViolation;
        }
        const result = ws.input.take(header.payload_len) catch |err| return switch (err) {
            error.EndOfStream => error.WebSocketProtocolViolation,
            error.ReadFailed => error.ReadFailed,
        };
        var mask_pos: u2 = 0;
        if (header.mask) |mask| maskedCopy(result, result, mask, &mask_pos);
        return result;
    }

    fn readerStream(i: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const ws: *WebSocket = @fieldParentPtr("reader", i);
        if (ws.reader_err) |_| return error.ReadFailed;

        const frame = &ws.reader_frame.?;
        while (frame.bytes_remaining == 0) {
            if (frame.finish) {
                return error.EndOfStream;
            }
            const op_code = ws.beginDataFrame() catch |err| {
                ws.reader_err = err;
                return error.ReadFailed;
            };
            if (op_code != .continuation) {
                ws.reader_err = error.WebSocketProtocolViolation;
                return error.ReadFailed;
            }
        }

        if (ws.input.bufferedLen() == 0) {
            try ws.input.fillMore();
        }
        const src_buffer = ws.input.buffered();

        const dst_buffer = try w.writableSliceGreedy(1);
        const copy_len: usize = limit.minInt(@min(dst_buffer.len, src_buffer.len, frame.bytes_remaining));

        maskedCopy(dst_buffer[0..copy_len], src_buffer[0..copy_len], frame.mask, &frame.mask_pos);

        w.advance(copy_len);
        ws.input.toss(copy_len);
        frame.bytes_remaining -= copy_len;
        return copy_len;
    }

    fn drain(i: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const ws: *WebSocket = @fieldParentPtr("writer", i);

        const written = ws.writeFrame(ws.writer_frame.?.op_code, false, i.buffer[0..i.end], data, splat) catch |err| {
            ws.writer_err = err;
            return error.WriteFailed;
        };
        ws.writer_frame.?.op_code = .continuation;
        i.end = 0;
        return written;
    }

    // Returns the length of bytes written from data (with splat), does not include length from buffer.
    fn writeFrame(ws: *WebSocket, op_code: Header.OpCode, finish: bool, buffer: []const u8, data: []const []const u8, splat: usize) !usize {
        ws.write_lock.lock(ws.io) catch |err| return err;
        defer ws.write_lock.unlock(ws.io);

        if (ws.closed) {
            return error.WebSocketClosed;
        }
        ws.closed = op_code == .close;

        const data_len = if (data.len > 0) std.Io.Writer.countSplat(data, splat) else 0;
        const payload_len = buffer.len + data_len;
        const header: Header = .{
            .finish = finish,
            .op_code = op_code,
            .payload_len = payload_len,
            .mask = null,
        };

        try header.write(ws.output);
        try ws.output.writeAll(buffer);
        if (data.len > 0) try writeSplatAllConst(ws.output, data, splat);
        if (finish) {
            try ws.output.flush();
        }
        return data_len;
    }

    // Io.Writer has this method, except that it requires data be mutable, which has its place but is unnessary and
    // it makes it incompatible with calling from a drain function. Having to occasionally call writeAll on a single
    // element of data instead of always using writeSplat is the tradeoff.
    fn writeSplatAllConst(w: *std.Io.Writer, const_data: []const []const u8, const_splat: usize) std.Io.Writer.Error!void {
        assert(const_data.len > 0);
        var data = const_data;
        var splat = const_splat;
        var truncate: usize = 0;
        while (data.len >= 2) {
            truncate += try w.writeSplat(data, splat);
            while (data.len >= 2 and truncate >= data[0].len) {
                truncate -= data[0].len;
                data = data[1..];
            }
            if (data.len >= 2 and truncate > 0) {
                try w.writeAll(data[0][truncate..]);
                data = data[1..];
            }
        }

        assert(data.len == 1);
        if (data[0].len == 0) return;

        while (true) {
            splat -= truncate / data[0].len;
            if (splat == 0) {
                return;
            }
            truncate %= data[0].len;
            truncate += try w.writeSplat(&.{ data[0][truncate..], data[0] }, splat - 1);
        }
    }
    // dst and src must be equal, or not alias.
    fn maskedCopy(dst: []u8, src: []const u8, mask: [4]u8, mask_pos: *u2) void {
        assert(dst.len == src.len);
        var i: usize = 0;

        if (std.simd.suggestVectorLength(u8)) |lanes| {
            while (i < dst.len and mask_pos.* != 0) {
                dst[i] = src[i] ^ mask[mask_pos.*];
                mask_pos.* +%= 1;
                i += 1;
            }

            const repetition: [@divExact(lanes, 4)][4]u8 = @splat(mask);
            const array: [lanes]u8 = @bitCast(repetition);
            const simd_mask: @Vector(lanes, u8) = array;
            while (i + lanes <= dst.len) : (i += lanes) {
                const bytes: @Vector(lanes, u8) = src[i..][0..lanes].*;
                dst[i..][0..lanes].* = bytes ^ simd_mask;
            }
        }
        while (i < dst.len) {
            dst[i] = src[i] ^ mask[mask_pos.*];
            mask_pos.* +%= 1;
            i += 1;
        }
    }

    test maskedCopy {
        var mask_pos: u2 = 1;
        const mask: [4]u8 = .{ 3, 1, 2, 3 };

        const src: [120]u8 = @bitCast(@as([40][3]u8, @splat(.{ 0, 100, 200 })));
        const expected: [120]u8 = @bitCast(@as([10][12]u8, @splat(.{
            1, 102, 203,
            3, 101, 202,
            3, 103, 201,
            2, 103, 203,
        })));

        {
            var dst: [120]u8 = undefined;
            maskedCopy(&dst, &src, mask, &mask_pos);
            try testing.expectEqualSlices(u8, &expected, &dst);
            try testing.expectEqual(mask_pos, 1);
        }

        {
            var dst = src;
            maskedCopy(&dst, &dst, mask, &mask_pos);
            try testing.expectEqualSlices(u8, &expected, &dst);
            try testing.expectEqual(mask_pos, 1);
        }

        var dst: [1]u8 = undefined;
        maskedCopy(&dst, (&src)[0..1], mask, &mask_pos);
        try testing.expectEqual(mask_pos, 2);
    }

    const Header = struct {
        finish: bool,
        op_code: OpCode,
        payload_len: u64,
        mask: ?[4]u8,

        const OpCode = enum(u4) {
            continuation = 0,
            text = 1,
            binary = 2,
            close = 8,
            ping = 9,
            pong = 10,
        };

        const PayloadLen = enum(u7) {
            u16_len = 126,
            u64_len = 127,
            _,
        };

        const Partial = packed struct(u16) {
            payload_len: PayloadLen,
            masked: bool,
            op_code: u4,
            reserved: u3,
            fin: bool,
        };
        fn read(reader: *std.Io.Reader) !Header {
            const partial: Partial = @bitCast(try reader.takeInt(u16, .big));
            if (partial.reserved != 0) {
                @branchHint(.cold);
                return error.WebSocketProtocolViolation;
            }

            var r: Header = undefined;
            r.finish = partial.fin;
            r.op_code = std.enums.fromInt(OpCode, partial.op_code) orelse return error.WebSocketProtocolViolation;
            r.payload_len = switch (partial.payload_len) {
                .u16_len => try reader.takeInt(u16, .big),
                .u64_len => try reader.takeInt(u64, .big),
                else => |v| @backingInt(v),
            };
            r.mask = if (partial.masked) (try reader.takeArray(4)).* else null;
            return r;
        }

        fn write(h: Header, writer: *std.Io.Writer) !void {
            const payload_len: PayloadLen = if (h.payload_len < 126) @fromBackingInt(@intCast(h.payload_len)) else if (h.payload_len <= std.math.maxInt(u16)) .u16_len else .u64_len;
            const p: Partial = .{
                .payload_len = payload_len,
                .masked = if (h.mask) |_| true else false,
                .op_code = @backingInt(h.op_code),
                .reserved = 0,
                .fin = h.finish,
            };
            try writer.writeInt(u16, @bitCast(p), .big);

            switch (payload_len) {
                .u16_len => try writer.writeInt(u16, @intCast(h.payload_len), .big),
                .u64_len => try writer.writeInt(u64, h.payload_len, .big),
                else => {},
            }
            if (h.mask) |mask| {
                try writer.writeAll(&mask);
            }
        }
    };

    fn testHeader(header_truth: Header, buffer_truth: []const u8) !void {
        {
            var reader: std.Io.Reader = .fixed(buffer_truth);
            const header_result = Header.read(&reader);
            try std.testing.expectEqualDeep(header_truth, header_result);
            try std.testing.expectEqual(buffer_truth.len, reader.seek); // consumed whole header
        }
        {
            var b: [20]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&b);
            try header_truth.write(&writer);
            try std.testing.expectEqualSlices(u8, buffer_truth, writer.buffered());
        }
    }

    test Header {
        // Finish
        try testHeader(.{ .finish = true, .op_code = .continuation, .payload_len = 0, .mask = null }, &[_]u8{ 1 << 7, 0 });
        // Op code
        try testHeader(.{ .finish = false, .op_code = .text, .payload_len = 0, .mask = null }, &[_]u8{ 1, 0 });
        // Payload len
        try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 125, .mask = null }, &[_]u8{ 0, 125 });
        try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 126, .mask = null }, &[_]u8{ 0, 126, 0, 126 });
        try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 65_535, .mask = null }, &[_]u8{ 0, 126, 255, 255 });
        try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 65_536, .mask = null }, &[_]u8{ 0, 127, 0, 0, 0, 0, 0, 1, 0, 0 });
        // Mask
        try testHeader(.{ .finish = false, .op_code = .continuation, .payload_len = 0, .mask = .{ 1, 2, 3, 4 } }, &[_]u8{ 0, 1 << 7, 1, 2, 3, 4 });
        // Bit of everthing
        try testHeader(.{ .finish = true, .op_code = .binary, .payload_len = 126, .mask = .{ 1, 2, 3, 4 } }, &[_]u8{ (1 << 7) | 2, 1 << 7 | 126, 0, 126, 1, 2, 3, 4 });
    }
};

test {
    _ = WebSocket;
}
