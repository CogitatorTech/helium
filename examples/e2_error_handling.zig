const std = @import("std");
const helium = @import("helium");

const AppContext = struct {
    name: []const u8,
};

// Custom error types
const AppError = error{
    Unauthorized,
    NotFound,
    ValidationFailed,
    DatabaseError,
};

// Custom error handler that provides detailed error responses
fn customErrorHandler(err: anyerror, req: *helium.Request, res: *helium.Response, ctx: *AppContext) !void {
    _ = ctx; // Context available if needed

    std.log.warn("Error occurred: {} on path: {s}", .{ err, req.raw_request.head.target });

    // Match on different error types and provide custom responses
    switch (err) {
        AppError.Unauthorized => {
            res.setStatus(.unauthorized);
            const json_response =
                \\{"error": "Unauthorized", "message": "You need to be logged in to access this resource", "code": 401}
            ;
            try res.headers.append(res.allocator, .{ .name = "content-type", .value = "application/json" });
            res.body = json_response;
        },
        AppError.NotFound => {
            res.setStatus(.not_found);
            const json_response =
                \\{"error": "Not Found", "message": "The requested resource was not found", "code": 404}
            ;
            try res.headers.append(res.allocator, .{ .name = "content-type", .value = "application/json" });
            res.body = json_response;
        },
        AppError.ValidationFailed => {
            res.setStatus(.bad_request);
            const json_response =
                \\{"error": "Validation Failed", "message": "The request data is invalid", "code": 400}
            ;
            try res.headers.append(res.allocator, .{ .name = "content-type", .value = "application/json" });
            res.body = json_response;
        },
        AppError.DatabaseError => {
            res.setStatus(.internal_server_error);
            const json_response =
                \\{"error": "Database Error", "message": "A database error occurred", "code": 500}
            ;
            try res.headers.append(res.allocator, .{ .name = "content-type", .value = "application/json" });
            res.body = json_response;
        },
        else => {
            // Default fallback for any other error
            res.setStatus(.internal_server_error);
            const json_response =
                \\{"error": "Internal Server Error", "message": "An unexpected error occurred", "code": 500}
            ;
            try res.headers.append(res.allocator, .{ .name = "content-type", .value = "application/json" });
            res.body = json_response;
        },
    }
}

// Route handlers that return various errors
fn homeHandler(_: *AppContext, _: *helium.Request, res: *helium.Response) !void {
    _ = try res.send("Welcome! Try visiting /error routes to see custom error handling in action.");
}

fn unauthorizedHandler(_: *AppContext, _: *helium.Request, _: *helium.Response) !void {
    return AppError.Unauthorized;
}

fn notFoundHandler(_: *AppContext, _: *helium.Request, _: *helium.Response) !void {
    return AppError.NotFound;
}

fn validationHandler(_: *AppContext, _: *helium.Request, _: *helium.Response) !void {
    return AppError.ValidationFailed;
}

fn databaseHandler(_: *AppContext, _: *helium.Request, _: *helium.Response) !void {
    return AppError.DatabaseError;
}

fn unexpectedHandler(_: *AppContext, _: *helium.Request, _: *helium.Response) !void {
    return error.SomethingWentWrong;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = AppContext{
        .name = "ErrorHandlingDemo",
    };

    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();

    // Register the custom error handler
    app.setErrorHandler(customErrorHandler);

    // Register routes that demonstrate different error types
    try app.get("/", homeHandler);
    try app.get("/error/unauthorized", unauthorizedHandler);
    try app.get("/error/notfound", notFoundHandler);
    try app.get("/error/validation", validationHandler);
    try app.get("/error/database", databaseHandler);
    try app.get("/error/unexpected", unexpectedHandler);

    std.log.info("Server starting on http://127.0.0.1:3000", .{});
    std.log.info("Try these endpoints:", .{});
    std.log.info("  GET http://127.0.0.1:3000/", .{});
    std.log.info("  GET http://127.0.0.1:3000/error/unauthorized", .{});
    std.log.info("  GET http://127.0.0.1:3000/error/notfound", .{});
    std.log.info("  GET http://127.0.0.1:3000/error/validation", .{});
    std.log.info("  GET http://127.0.0.1:3000/error/database", .{});
    std.log.info("  GET http://127.0.0.1:3000/error/unexpected", .{});

    try app.listen(3000);
}
