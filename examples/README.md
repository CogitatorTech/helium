## Helium Examples

| # | File                                                 | Description                                                                                                   |
|---|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| 1 | [e1_simple_example.zig](e1_simple_example.zig)       | A simple web application made with Helium                                                                     |
| 2 | [e2_error_handling.zig](e2_error_handling.zig)       | This example shows custom error handling with different error types                                           |
| 3 | [e3_route_groups.zig](e3_route_groups.zig)           | This example shows route grouping and group-level middleware usage                                            |
| 4 | [e4_json_api.zig](e4_json_api.zig)                   | This example shows a complete REST API with JSON request/response handling                                    |
| 5 | [e5_query_and_headers.zig](e5_query_and_headers.zig) | This example demonstrates working with query parameters, request/response headers, and content negotiation    |
| 6 | [e6_custom_middleware.zig](e6_custom_middleware.zig) | This is a custom middleware example that shows timing, authentication, request counting, and security headers |
| 7 | [e7_file_upload.zig](e7_file_upload.zig)             | File upload and download functionality example                                                                |
| 8 | [e8_sessions_cookies.zig](e8_sessions_cookies.zig)   | This example shows session management and cookie handling for user authentication                             |
| 9 | [e9_server_modes.zig](e9_server_modes.zig)           | This example demonstrates different server modes (thread pool vs async event loop)                            |

### Running Examples

1. To run examples, first build the project:

```sh
make build
```

Or

```sh
zig build
```

2. Then run an example (replace `e1_simple_example` with the name of the example
   from [the table above](#helium-examples) without the `.zig` extension):

```sh
# Run example file `examples/e1_simple_example.zig`
make run EXAMPLE=e1_simple_example
```

Or

```sh
zig build run-e1_simple_example
```
