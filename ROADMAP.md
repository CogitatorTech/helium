## Feature Roadmap

This document includes the roadmap for the Helium web framework.
It outlines features to be implemented and their current status.

> [!IMPORTANT]
> This roadmap is a work in progress and is subject to change.

---

### Features

The following features are currently being worked on or planned for future releases.

#### Core Framework

- [x] Generic `App` type with custom context support
- [x] Type-safe request handlers and middleware
- [x] Configurable memory allocator per application
- [x] Custom error handler support
- [x] Multi-mode server (thread pool and event-driven I/O)

#### Routing System

- [x] Express.js-like routing API
- [x] HTTP method support (GET, POST, PUT, DELETE, PATCH, HEAD, and OPTIONS)
- [x] Dynamic route parameters (like `/users/:id`)
- [x] Query parameter parsing
- [x] Route grouping with shared path prefixes
- [x] Tree-based router for efficient path matching
- [ ] Route wildcards (like `/files/*`)
- [ ] Route matching with regular expressions
- [ ] Route priority and ordering control
- [ ] Nested route groups
- [ ] Route metadata and tagging
- [ ] Automatic OPTIONS handling per route

#### Middleware System

- [x] Global middleware (applied to all routes)
- [x] Group-scoped middleware (applied to route groups)
- [x] Route-specific middleware chains
- [x] Middleware composition with `next()` pattern
- [x] Type-safe middleware signatures
- [x] CORS middleware (allow-all origins)
- [x] Common log format middleware with timing
- [ ] Configurable CORS middleware (custom origins, methods, and headers)
- [ ] Rate limiting middleware
- [ ] Authentication middleware (JWT, Bearer, and Basic Auth)
- [ ] Session management middleware
- [ ] Cookie parsing and management
- [ ] Request ID tracking
- [ ] Body parser middleware (JSON, form-urlencoded, and multipart)
- [ ] CSRF protection
- [ ] Security headers middleware (helmet-style)
- [ ] Request timeout middleware
- [ ] Circuit breaker pattern
- [ ] Error recovery middleware
- [ ] Panic recovery
- [ ] Debug middleware

#### Request Handling

- [x] Request parameter access (path and query parameters)
- [x] Request body string access
- [ ] Multipart form data parsing
- [ ] File upload handling
- [ ] Request body size limits (configurable)
- [ ] Content negotiation helpers
- [ ] Cookie parsing and setting
- [ ] Request validation helpers
- [ ] Custom body parsers (pluggable)

#### Response Handling

- [x] Response status code setting
- [x] Response header management
- [x] JSON response serialization
- [x] Plain text responses
- [ ] Response streaming API for large payloads
- [ ] Request body streaming for file uploads
- [ ] Template rendering support (pluggable)
- [ ] Response compression (gzip, deflate, or brotli)
- [ ] ETag support for caching
- [ ] Conditional requests (If-None-Match and If-Modified-Since)
- [ ] Server-Sent Events (SSE) support
- [ ] Chunked transfer encoding

#### Static File Serving

- [x] Static file server with path traversal protection
- [ ] ETag support for static files
- [ ] Range request support for partial content
- [ ] Directory listing (optional)

#### Error Handling

- [x] Custom error handler support
- [ ] Detailed error responses (development mode)
- [ ] Error logging integration points
- [ ] Structured error types

#### Performance & Scaling

- [ ] Connection pooling
- [ ] Request and response pooling
- [ ] Zero-copy optimizations
- [ ] HTTP keep-alive connection management
- [ ] Graceful shutdown support
- [ ] Health check endpoints
- [ ] Metrics and monitoring hooks

#### Testing & Development

- [ ] Test client for integration testing
- [ ] Mock request and response builders
- [ ] Development mode with hot reload (external tool integration)
- [ ] Request and response logging levels

#### Security

- [ ] HTTPS/TLS support
- [ ] Certificate management helpers
- [ ] Input sanitization helpers
- [ ] SQL injection prevention utilities
- [ ] XSS prevention utilities
- [ ] Rate limiting by IP/user
- [ ] Request size limits

#### Documentation & Examples

- [x] Basic examples (simple server and error handling)
- [x] Route grouping example
- [ ] REST API example
- [ ] WebSocket chat example
- [ ] File upload example
- [ ] Authentication example
- [ ] Microservices example
- [ ] Real-time SSE example
- [ ] Comprehensive API documentation
- [ ] Best practices guide
- [ ] Migration guide from other frameworks

#### Ecosystem Integration

- [ ] Database connection pooling patterns
- [ ] ORM integration examples
- [ ] Message queue integration patterns
- [ ] Cache integration (Redis and Memcached)
- [ ] Logging framework integration
- [ ] OpenTelemetry and tracing support

---

### Future Considerations

These features are being considered but not yet prioritized:

- WebSocket support
- HTTP/2 support
- HTTP/3 (QUIC) support
- GraphQL support
- gRPC support
- CBOR serialization support
- Built-in API documentation generation
- Load balancing support
- Service mesh integration
- Admin panel/dashboard
- Plugin system architecture
