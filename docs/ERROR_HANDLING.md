## Centralized Error Handling in Helium

### Overview

Helium provides a centralized error handling mechanism that allows you to define custom error handlers to control
responses for different types of errors.
Instead of returning generic "Internal Server Error" messages, you can provide detailed, context-aware error responses.

### Features

- **Custom Error Handlers**: Define your own error handling logic
- **Error Type Matching**: Handle different errors differently (e.g., validation errors vs database errors)
- **Full Request/Response Access**: Access the request and response objects in your error handler
- **Context Awareness**: Access your application context within the error handler
- **Fallback Behavior**: If no custom handler is set, the framework falls back to default behavior

### Usage

#### Basic Setup

```zig
const std = @import("std");
const helium = @import("helium");

const AppContext = struct {
    name: []const u8,
};

// Define your custom error handler
fn customErrorHandler(err: anyerror, req: *helium.Request, res: *helium.Response, ctx: *AppContext) !void {
    std.log.warn("Error occurred: {} on path: {s}", .{ err, req.path() });

    // Set appropriate status and response based on error type
    res.setStatus(.internal_server_error);
    _ = res.send("An error occurred") catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = AppContext{ .name = "MyApp" };
    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();

    // Register the custom error handler
    app.setErrorHandler(customErrorHandler);

    // ... register routes ...

    try app.listen(3000);
}
```

#### Advanced Error Handling

You can match on specific error types and provide tailored responses:

```zig
const AppError = error{
Unauthorized,
NotFound,
ValidationFailed,
DatabaseError,
};

fn advancedErrorHandler(err: anyerror, req: *helium.Request, res: *helium.Response, ctx: *AppContext) !void {
    _ = ctx;

    switch (err) {
        AppError.Unauthorized => {
            res.setStatus(.unauthorized);
            const json_response =
                \\{"error": "Unauthorized", "message": "Authentication required", "code": 401}
            ;
            res.setHeader("Content-Type", "application/json") catch {};
            _ = res.send(json_response) catch {};
        },
        AppError.NotFound => {
            res.setStatus(.not_found);
            const json_response =
                \\{"error": "Not Found", "message": "Resource not found", "code": 404}
            ;
            res.setHeader("Content-Type", "application/json") catch {};
            _ = res.send(json_response) catch {};
        },
        AppError.ValidationFailed => {
            res.setStatus(.bad_request);
            const json_response =
                \\{"error": "Validation Failed", "message": "Invalid request data", "code": 400}
            ;
            res.setHeader("Content-Type", "application/json") catch {};
            _ = res.send(json_response) catch {};
        },
        else => {
            // Default fallback for unexpected errors
            res.setStatus(.internal_server_error);
            const json_response =
                \\{"error": "Internal Server Error", "message": "An unexpected error occurred", "code": 500}
            ;
            res.setHeader("Content-Type", "application/json") catch {};
            _ = res.send(json_response) catch {};
        },
    }
}
```

#### Route Handlers That Return Errors

Your route handlers can simply return errors, and they will be caught and processed by your custom error handler:

```zig
fn protectedHandler(ctx: *AppContext, req: *helium.Request, res: *helium.Response) !void {
    // Check authentication
    if (!isAuthenticated(req)) {
        return AppError.Unauthorized;
    }

    // ... normal handler logic ...
    _ = try res.send("Protected resource");
}

fn createUserHandler(ctx: *AppContext, req: *helium.Request, res: *helium.Response) !void {
    // Validate input
    const body = req.body() orelse return AppError.ValidationFailed;

    // ... validation logic ...
    if (!isValidEmail(body)) {
        return AppError.ValidationFailed;
    }

    // ... normal handler logic ...
    _ = try res.send("User created");
}
```

### API Reference

#### `app.setErrorHandler(handler)`

Registers a custom error handler for the application.

**Signature:**

```zig
pub fn setErrorHandler(
self: *Self,
handler: *const fn (err: anyerror, *Request, *Response, *ContextType) anyerror!void
) void
```

**Parameters:**

- `handler`: A function that takes:
    - `err: anyerror` - The error that occurred
    - `req: *Request` - The current request
    - `res: *Response` - The response to send
    - `ctx: *ContextType` - Your application context

**Example:**

```zig
app.setErrorHandler(myCustomErrorHandler);
```

#### Error Handler Function Signature

```zig
fn errorHandler(
    err: anyerror,
    req: *helium.Request,
    res: *helium.Response,
    ctx: *YourContextType
) !void {
    // Your error handling logic
}
```

### Best Practices

1. **Log Errors**: Always log errors for debugging purposes
   ```zig
   std.log.err("Handler error: {} on path: {s}", .{ err, req.path() });
   ```

2. **Provide Meaningful Messages**: Give users helpful error messages
   ```zig
   _ = res.send("Invalid email format. Please provide a valid email address.") catch {};
   ```

3. **Use Appropriate HTTP Status Codes**: Match status codes to error types
    - `400 Bad Request` - Validation errors
    - `401 Unauthorized` - Authentication required
    - `403 Forbidden` - Permission denied
    - `404 Not Found` - Resource not found
    - `500 Internal Server Error` - Unexpected errors

4. **Return JSON for APIs**: For REST APIs, return structured JSON error responses
   ```zig
   const json = try std.fmt.allocPrint(req.allocator,
       \\{{"error": "{s}", "message": "{s}", "code": {}}}
   , .{ error_type, error_message, status_code });
   res.setHeader("Content-Type", "application/json") catch {};
   _ = res.send(json) catch {};
   ```

5. **Don't Expose Sensitive Information**: Be careful not to leak stack traces or internal details in production

6. **Handle Error Handler Failures**: Your error handler can also fail. The framework will catch this and fall back to a
   default response.

### Example Project

See the complete example in [`examples/e2_error_handling.zig`](../examples/e2_error_handling.zig) which demonstrates:

- Custom error types
- JSON error responses
- Different error handling strategies
- Logging and debugging

Run the example with:

```bash
zig build
./zig-out/bin/e2_error_handling
```

Then test it:

```bash
## Test different error types
curl http://127.0.0.1:3000/error/unauthorized
curl http://127.0.0.1:3000/error/validation
curl http://127.0.0.1:3000/error/database
```

### Migration Guide

If you're upgrading from a version without centralized error handling:

**Before:**

```zig
fn handler(ctx: *Context, req: *Request, res: *Response) !void {
    doSomething() catch |err| {
        std.log.err("Error: {}", .{err});
        res.setStatus(.internal_server_error);
        _ = res.send("Error occurred") catch {};
        return;
    };
}
```

**After:**

```zig
// Set up error handler once
app.setErrorHandler(myErrorHandler);

// Handlers can simply return errors
fn handler(ctx: *Context, req: *Request, res: *Response) !void {
try doSomething(); // Errors propagate to error handler
}
```

### Future Improvements

Potential future improvements to the error handling system:

- Error middleware chain
- Multiple error handlers for different route groups
- Built-in error recovery strategies
- Automatic retry mechanisms
- Circuit breaker patterns
