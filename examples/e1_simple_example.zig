const std = @import("std");
const helium = @import("helium");

const User = struct { id: u32, name: []const u8 };

const UserStore = std.HashMap(u32, User, std.hash_map.AutoContext(u32), 80);

const AppContext = struct {
    start_time: i64,
    file_server: helium.static.FileServer,
    user_db: UserStore,
    user_db_mutex: std.Thread.Mutex,
};

const Request = helium.Request;
const Response = helium.Response;

fn staticFileServer(ctx: *AppContext, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
    if (try ctx.file_server.handle(req, res)) {
        return;
    }

    const Next = helium.App(AppContext).Next;
    const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));
    try next.call(ctx, req, res);
}

fn getUser(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id").?;
    const id = try std.fmt.parseInt(u32, id_str, 10);

    ctx.user_db_mutex.lock();
    defer ctx.user_db_mutex.unlock();

    if (ctx.user_db.get(id)) |user| {
        const user_copy = User{
            .id = user.id,
            .name = try req.allocator.dupe(u8, user.name),
        };
        try res.sendJson(user_copy);
    } else {
        res.setStatus(.not_found);
        try res.send("User not found");
    }
}

fn updateUser(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id").?;
    const id = try std.fmt.parseInt(u32, id_str, 10);

    // Read body with streaming API (limited to 1MB by default)
    const body = req.readBodyAlloc() catch |err| {
        res.setStatus(.bad_request);
        if (err == error.BodyTooLarge) {
            try res.send("Request body too large (max 1MB)");
        } else {
            try res.send("Failed to read request body");
        }
        return;
    };
    defer req.allocator.free(body);

    if (body.len == 0) {
        res.setStatus(.bad_request);
        try res.send("Missing request body");
        return;
    }

    var parsed_json = try std.json.parseFromSlice(User, req.allocator, body, .{});
    defer parsed_json.deinit();

    const persistent_name = try ctx.user_db.allocator.dupe(u8, parsed_json.value.name);
    errdefer ctx.user_db.allocator.free(persistent_name);

    ctx.user_db_mutex.lock();
    defer ctx.user_db_mutex.unlock();

    if (ctx.user_db.get(id)) |old_user| {
        ctx.user_db.allocator.free(old_user.name);
    }

    try ctx.user_db.put(id, .{
        .id = id,
        .name = persistent_name,
    });

    const updated_user = ctx.user_db.get(id).?;
    const user_copy = User{
        .id = updated_user.id,
        .name = try req.allocator.dupe(u8, updated_user.name),
    };

    try res.sendJson(user_copy);
}

fn setupStaticFiles() !void {
    const public_dir_path = "public";
    const html_file_path = "public/index.html";
    const html_content = "<h1>Hello from a static file created by Zig!</h1>";
    const dir = std.fs.cwd();

    dir.makeDir(public_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const file = try dir.createFile(html_file_path, .{});
    defer file.close();
    try file.writeAll(html_content);
}

pub fn main() !void {
    const gpa_unprotected = std.heap.page_allocator;
    var thread_safe_gpa_state = std.heap.ThreadSafeAllocator{ .child_allocator = gpa_unprotected };
    const gpa = thread_safe_gpa_state.allocator();

    try setupStaticFiles();

    var app_context = AppContext{
        .start_time = std.time.timestamp(),
        .file_server = try helium.static.FileServer.init(gpa, "./public"),
        .user_db = UserStore.init(gpa),
        .user_db_mutex = .{},
    };
    defer app_context.file_server.deinit();
    defer app_context.user_db.deinit();

    var app = helium.App(AppContext).init(gpa, app_context);
    defer app.deinit();

    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.use(staticFileServer);

    try app.get("/user/:id", getUser);
    try app.put("/user/:id", updateUser);

    try app.listen(3000);
}
