const std = @import("std");
const helium = @import("helium");

const User = struct { id: u32, name: []const u8 };

// A simple in-memory "database" for storing users.
const UserStore = std.HashMap(u32, User, std.hash_map.AutoContext(u32), 80);

// The AppContext now holds all shared state for our application.
const AppContext = struct {
    start_time: i64,
    file_server: helium.static.FileServer,
    user_db: UserStore,
    user_db_mutex: std.Thread.Mutex,
};

const Request = helium.Request;
const Response = helium.Response;

// This is our middleware function for static files.
fn staticFileServer(ctx: *AppContext, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
    // If file_server.handle returns true, the request was handled and we can stop.
    if (try ctx.file_server.handle(req, res)) {
        return;
    }

    // Otherwise, the file was not found, so we must call the next handler.
    const Next = helium.App(AppContext).Next;
    const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));
    try next.call(ctx, req, res);
}

fn getUser(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id").?;
    const id = try std.fmt.parseInt(u32, id_str, 10);

    // Acquire the lock before accessing user_db
    ctx.user_db_mutex.lock();
    defer ctx.user_db_mutex.unlock();

    if (ctx.user_db.get(id)) |user| {
        // Copy the user data to memory owned by the request's allocator
        // before releasing the lock, to prevent holding a reference to data
        // that another thread could modify.
        const user_copy = User{
            .id = user.id,
            .name = try req.allocator.dupe(u8, user.name),
        };
        // Lock will be automatically released by defer
        try res.sendJson(user_copy);
    } else {
        res.setStatus(.not_found);
        try res.send("User not found");
    }
}

fn updateUser(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id").?;
    const id = try std.fmt.parseInt(u32, id_str, 10);

    const body = req.body_str orelse {
        res.setStatus(.bad_request);
        try res.send("Missing request body");
        return;
    };

    // Parse the JSON using the request's temporary allocator.
    var parsed_json = try std.json.parseFromSlice(User, req.allocator, body, .{});
    // Ensure the parsed data is freed when the function returns.
    defer parsed_json.deinit();

    // The parsed name is temporary. We must copy it to a persistent allocator
    // to store it in our database.
    const persistent_name = try ctx.user_db.allocator.dupe(u8, parsed_json.value.name);
    errdefer ctx.user_db.allocator.free(persistent_name);

    // Acquire the lock before accessing user_db
    ctx.user_db_mutex.lock();
    defer ctx.user_db_mutex.unlock();

    // If we are updating an existing user, we must free their old name to prevent a memory leak.
    if (ctx.user_db.get(id)) |old_user| {
        ctx.user_db.allocator.free(old_user.name);
    }

    // Store the new user data with the persistent name string.
    try ctx.user_db.put(id, .{
        .id = id,
        .name = persistent_name,
    });

    // Copy the user data before releasing the lock
    const updated_user = ctx.user_db.get(id).?;
    const user_copy = User{
        .id = updated_user.id,
        .name = try req.allocator.dupe(u8, updated_user.name),
    };

    // Lock will be automatically released by defer
    try res.sendJson(user_copy);
}

/// This function sets up the 'public' directory and a sample index.html.
fn setupStaticFiles() !void {
    const public_dir_path = "public";
    const html_file_path = "public/index.html";
    const html_content = "<h1>Hello from a static file created by Zig!</h1>";
    const dir = std.fs.cwd();

    // Create the directory, ignoring the error if it already exists.
    dir.makeDir(public_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create and write to the file, overwriting it if it exists.
    const file = try dir.createFile(html_file_path, .{});
    defer file.close();
    try file.writeAll(html_content);
}

pub fn main() !void {
    // Setup allocator
    const gpa_unprotected = std.heap.page_allocator;
    var thread_safe_gpa_state = std.heap.ThreadSafeAllocator{ .child_allocator = gpa_unprotected };
    const gpa = thread_safe_gpa_state.allocator();

    // Automatically create static files and directory
    try setupStaticFiles();

    // Initialize the application context with all its state.
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

    // Register middleware
    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.use(staticFileServer);

    // Register routes
    try app.get("/user/:id", getUser);
    try app.put("/user/:id", updateUser);

    try app.listen(3000);
}
