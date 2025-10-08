## Helium Examples

| # | File                                                 | Description                                                                                             |
|---|------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| 1 | [e1_simple_example.zig](e1_simple_example.zig)       | A simple web application made with Helium                                                               |
| 2 | [e2_error_handling.zig](e2_error_handling.zig)       | This example shows custom error handling with different error types                                     |
| 3 | [e3_route_groups.zig](e3_route_groups.zig)           | This example shows route grouping and group-level middleware usage                                      |
| 4 | [e4_json_api.zig](e4_json_api.zig)                   | This example shows a complete REST API implementation with JSON request/response handling               |
| 5 | [e5_query_and_headers.zig](e5_query_and_headers.zig) | This example shows how to work with query parameters, request/response headers, and content negotiation |
| 6 | [e6_custom_middleware.zig](e6_custom_middleware.zig) | A custom middleware example that shows timing, authentication, request counting, and security headers   |
| 7 | [e7_file_upload.zig](e7_file_upload.zig)             | A file upload and download functionality example                                                        |
| 8 | [e8_sessions_cookies.zig](e8_sessions_cookies.zig)   | An example for session management and cookie handling for user authentication                           |
| 9 | [e9_server_modes.zig](e9_server_modes.zig)           | This example demonstrates different server modes (thread pool vs async event loop)                      |

### Running Examples

1. First, build the examples:

```sh
make build

# Or

zig build
```

2. Then run an example using:

```sh
# Run example file `examples/e1_simple_example.zig`
make run EXAMPLE=e1_simple_example

# Or

zig build run-e1_simple_example
```

Replace `e1_simple_example` with the name of the example you want to run from [the table above](#helium-examples)
without the `.zig` extension in the name.
