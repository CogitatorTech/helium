const std = @import("std");
const net = std.net;
const posix = std.posix;

/// Event-driven I/O loop using epoll (Linux) or kqueue (BSD/macOS)
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    epoll_fd: i32,
    running: bool,
    connections: std.AutoHashMap(i32, *Connection),

    pub const Connection = struct {
        fd: i32,
        stream: net.Stream,
        address: net.Address,
        state: ConnectionState,
        read_buffer: std.ArrayList(u8),
        write_buffer: std.ArrayList(u8),

        pub const ConnectionState = enum {
            reading_request,
            processing,
            writing_response,
            closing,
        };
    };

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        const epoll_fd = try posix.epoll_create1(0);

        return EventLoop{
            .allocator = allocator,
            .epoll_fd = epoll_fd,
            .running = false,
            .connections = std.AutoHashMap(i32, *Connection).init(allocator),
        };
    }

    pub fn deinit(self: *EventLoop) void {
        posix.close(self.epoll_fd);

        var it = self.connections.valueIterator();
        while (it.next()) |conn| {
            conn.*.read_buffer.deinit();
            conn.*.write_buffer.deinit();
            conn.*.stream.close();
            self.allocator.destroy(conn.*);
        }
        self.connections.deinit();
    }

    /// Register a new connection to be monitored
    pub fn registerConnection(self: *EventLoop, stream: net.Stream, address: net.Address) !void {
        const fd = stream.handle;

        // Set socket to non-blocking mode
        const flags = try posix.fcntl(fd, posix.F.GETFL, 0);
        _ = try posix.fcntl(fd, posix.F.SETFL, flags | @as(u32, posix.O.NONBLOCK));

        // Create connection tracking structure
        const conn = try self.allocator.create(Connection);
        conn.* = Connection{
            .fd = fd,
            .stream = stream,
            .address = address,
            .state = .reading_request,
            .read_buffer = std.ArrayList(u8).init(self.allocator),
            .write_buffer = std.ArrayList(u8).init(self.allocator),
        };

        try self.connections.put(fd, conn);

        // Register with epoll for read events
        var event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET, // Edge-triggered
            .data = .{ .fd = fd },
        };

        try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);
    }

    /// Unregister and close a connection
    pub fn unregisterConnection(self: *EventLoop, fd: i32) void {
        if (self.connections.fetchRemove(fd)) |kv| {
            const conn = kv.value;
            _ = posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
            conn.read_buffer.deinit();
            conn.write_buffer.deinit();
            conn.stream.close();
            self.allocator.destroy(conn);
        }
    }

    /// Modify epoll events for a connection (e.g., switch to write monitoring)
    pub fn modifyConnection(self: *EventLoop, fd: i32, events: u32) !void {
        var event = std.os.linux.epoll_event{
            .events = events,
            .data = .{ .fd = fd },
        };
        try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
    }

    /// Main event loop - processes events as they arrive
    pub fn run(self: *EventLoop) !void {
        self.running = true;
        var events: [128]std.os.linux.epoll_event = undefined;

        while (self.running) {
            const num_events = posix.epoll_wait(self.epoll_fd, &events, -1);

            for (events[0..num_events]) |event| {
                const fd = event.data.fd;

                if (event.events & std.os.linux.EPOLL.IN != 0) {
                    // Ready to read
                    self.handleRead(fd) catch |err| {
                        std.log.err("Read error on fd {d}: {}", .{ fd, err });
                        self.unregisterConnection(fd);
                    };
                }

                if (event.events & std.os.linux.EPOLL.OUT != 0) {
                    // Ready to write
                    self.handleWrite(fd) catch |err| {
                        std.log.err("Write error on fd {d}: {}", .{ fd, err });
                        self.unregisterConnection(fd);
                    };
                }

                if (event.events & (std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP) != 0) {
                    // Error or hangup
                    self.unregisterConnection(fd);
                }
            }
        }
    }

    fn handleRead(self: *EventLoop, fd: i32) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        var buffer: [4096]u8 = undefined;
        const bytes_read = conn.stream.read(&buffer) catch |err| switch (err) {
            error.WouldBlock => return, // No data available right now, will be notified later
            else => return err,
        };

        if (bytes_read == 0) {
            // Connection closed by peer
            self.unregisterConnection(fd);
            return;
        }

        try conn.read_buffer.appendSlice(buffer[0..bytes_read]);
    }

    fn handleWrite(self: *EventLoop, fd: i32) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        if (conn.write_buffer.items.len == 0) {
            // Nothing to write, switch back to read mode
            try self.modifyConnection(fd, std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET);
            return;
        }

        const bytes_written = conn.stream.write(conn.write_buffer.items) catch |err| switch (err) {
            error.WouldBlock => return, // Can't write right now, will be notified later
            else => return err,
        };

        // Remove written bytes from buffer
        std.mem.copyForwards(u8, conn.write_buffer.items, conn.write_buffer.items[bytes_written..]);
        conn.write_buffer.shrinkRetainingCapacity(conn.write_buffer.items.len - bytes_written);
    }

    pub fn stop(self: *EventLoop) void {
        self.running = false;
    }
};

