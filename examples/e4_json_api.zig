const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;
const Task = struct {
    id: u32,
    title: []const u8,
    description: []const u8,
    completed: bool,
    created_at: i64,
};
const CreateTaskRequest = struct {
    title: []const u8,
    description: []const u8,
};
const UpdateTaskRequest = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    completed: ?bool = null,
};
const AppContext = struct {
    tasks: std.AutoHashMap(u32, Task),
    next_id: u32,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
};
fn getAllTasks(ctx: *AppContext, _: *Request, res: *Response) !void {
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    var tasks_list: std.ArrayList(Task) = .{};
    defer tasks_list.deinit(res.allocator);
    var iter = ctx.tasks.valueIterator();
    while (iter.next()) |task| {
        const task_copy = Task{
            .id = task.id,
            .title = try res.allocator.dupe(u8, task.title),
            .description = try res.allocator.dupe(u8, task.description),
            .completed = task.completed,
            .created_at = task.created_at,
        };
        try tasks_list.append(res.allocator, task_copy);
    }
    try res.sendJson(.{
        .success = true,
        .count = tasks_list.items.len,
        .tasks = tasks_list.items,
    });
}
fn getTaskById(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id") orelse {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing task ID" });
        return;
    };
    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid task ID format" });
        return;
    };
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    if (ctx.tasks.get(id)) |task| {
        const task_copy = Task{
            .id = task.id,
            .title = try res.allocator.dupe(u8, task.title),
            .description = try res.allocator.dupe(u8, task.description),
            .completed = task.completed,
            .created_at = task.created_at,
        };
        try res.sendJson(.{ .success = true, .task = task_copy });
    } else {
        res.setStatus(.not_found);
        try res.sendJson(.{ .success = false, .message = "Task not found" });
    }
}
fn createTask(ctx: *AppContext, req: *Request, res: *Response) !void {
    const body = req.readBodyAlloc() catch |err| {
        res.setStatus(.bad_request);
        if (err == error.BodyTooLarge) {
            try res.sendJson(.{ .success = false, .message = "Request body too large (max 1MB)" });
        } else {
            try res.sendJson(.{ .success = false, .message = "Failed to read request body" });
        }
        return;
    };
    defer req.allocator.free(body);
    if (body.len == 0) {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing request body" });
        return;
    }
    var parsed = std.json.parseFromSlice(CreateTaskRequest, req.allocator, body, .{}) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid JSON format" });
        return;
    };
    defer parsed.deinit();
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    const task_id = ctx.next_id;
    ctx.next_id += 1;
    const title = try ctx.allocator.dupe(u8, parsed.value.title);
    errdefer ctx.allocator.free(title);
    const description = try ctx.allocator.dupe(u8, parsed.value.description);
    errdefer ctx.allocator.free(description);
    const task = Task{
        .id = task_id,
        .title = title,
        .description = description,
        .completed = false,
        .created_at = std.time.timestamp(),
    };
    try ctx.tasks.put(task_id, task);
    const task_copy = Task{
        .id = task.id,
        .title = try res.allocator.dupe(u8, task.title),
        .description = try res.allocator.dupe(u8, task.description),
        .completed = task.completed,
        .created_at = task.created_at,
    };
    res.setStatus(.created);
    try res.sendJson(.{ .success = true, .task = task_copy });
}
fn updateTask(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id") orelse {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing task ID" });
        return;
    };
    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid task ID format" });
        return;
    };
    const body = req.readBodyAlloc() catch |err| {
        res.setStatus(.bad_request);
        if (err == error.BodyTooLarge) {
            try res.sendJson(.{ .success = false, .message = "Request body too large" });
        } else {
            try res.sendJson(.{ .success = false, .message = "Failed to read request body" });
        }
        return;
    };
    defer req.allocator.free(body);
    if (body.len == 0) {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing request body" });
        return;
    }
    var parsed = std.json.parseFromSlice(UpdateTaskRequest, req.allocator, body, .{}) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid JSON format" });
        return;
    };
    defer parsed.deinit();
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    const existing_task = ctx.tasks.get(id) orelse {
        res.setStatus(.not_found);
        try res.sendJson(.{ .success = false, .message = "Task not found" });
        return;
    };
    var updated_task = existing_task;
    if (parsed.value.title) |new_title| {
        ctx.allocator.free(updated_task.title);
        updated_task.title = try ctx.allocator.dupe(u8, new_title);
    }
    if (parsed.value.description) |new_desc| {
        ctx.allocator.free(updated_task.description);
        updated_task.description = try ctx.allocator.dupe(u8, new_desc);
    }
    if (parsed.value.completed) |completed| {
        updated_task.completed = completed;
    }
    try ctx.tasks.put(id, updated_task);
    const task_copy = Task{
        .id = updated_task.id,
        .title = try res.allocator.dupe(u8, updated_task.title),
        .description = try res.allocator.dupe(u8, updated_task.description),
        .completed = updated_task.completed,
        .created_at = updated_task.created_at,
    };
    try res.sendJson(.{ .success = true, .message = "Task updated successfully", .task = task_copy });
}
fn deleteTask(ctx: *AppContext, req: *Request, res: *Response) !void {
    const id_str = req.params.get("id") orelse {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing task ID" });
        return;
    };
    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid task ID format" });
        return;
    };
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    if (ctx.tasks.fetchRemove(id)) |entry| {
        ctx.allocator.free(entry.value.title);
        ctx.allocator.free(entry.value.description);
        try res.sendJson(.{ .success = true, .message = "Task deleted successfully" });
    } else {
        res.setStatus(.not_found);
        try res.sendJson(.{ .success = false, .message = "Task not found" });
    }
}
fn healthCheck(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .status = "healthy",
        .service = "Task API",
        .version = "1.0.0",
        .timestamp = std.time.timestamp(),
    });
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var app_context = AppContext{
        .tasks = std.AutoHashMap(u32, Task).init(allocator),
        .next_id = 1,
        .mutex = .{},
        .allocator = allocator,
    };
    defer {
        var iter = app_context.tasks.valueIterator();
        while (iter.next()) |task| {
            allocator.free(task.title);
            allocator.free(task.description);
        }
        app_context.tasks.deinit();
    }
    var app = helium.App(AppContext).init(allocator, app_context);
    defer app.deinit();
    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.get("/health", healthCheck);
    try app.get("/tasks", getAllTasks);
    try app.get("/tasks/:id", getTaskById);
    try app.post("/tasks", createTask);
    try app.put("/tasks/:id", updateTask);
    try app.delete("/tasks/:id", deleteTask);
    std.log.info("Task API Server starting on http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("Available endpoints:", .{});
    std.log.info("  GET    /health           - Health check", .{});
    std.log.info("  GET    /tasks            - Get all tasks", .{});
    std.log.info("  GET    /tasks/:id        - Get task by ID", .{});
    std.log.info("  POST   /tasks            - Create a new task", .{});
    std.log.info("  PUT    /tasks/:id        - Update a task", .{});
    std.log.info("  DELETE /tasks/:id        - Delete a task", .{});
    try app.listen(3000);
}
