## Helium Web Framework Roadmap

This document outlines the development roadmap for Helium, a lightweight, configurable micro web framework for Zig.

> [!IMPORTANT]
> This roadmap is a living document and may change based on community feedback and evolving needs.

### Philosophy & Design Goals

Helium is designed as a **micro-framework** with these core principles:
- **Configurability First**: Nothing is hardcoded; everything is opt-in and customizable
- **Minimal Core**: Keep the core API small and focused
- **Composability**: Features should be independent and composable
- **Zero Magic**: Explicit, predictable behavior without hidden abstractions
- **Performance**: Efficient use of resources with multiple concurrency models

---

### ✅ Implemented Features

#### Core Framework
- [x] Generic `App` type with custom context support
- [x] Type-safe request handlers and middleware
- [x] Configurable memory allocator per application
- [x] Custom error handler support
- [x] Multi-mode server (thread pool and event-driven I/O)

#### Routing System
- [x] Express.js-like routing API
- [x] HTTP method support (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
- [x] Dynamic route parameters (e.g., `/users/:id`)
- [x] Query parameter parsing
- [x] Route grouping with shared path prefixes
- [x] Tree-based router for efficient path matching

#### Middleware System
- [x] Global middleware (applied to all routes)
- [x] Group-scoped middleware (applied to route groups)
- [x] Route-specific middleware chains
- [x] Middleware composition with `next()` pattern
- [x] Type-safe middleware signatures

#### Built-in Utilities
- [x] CORS middleware (allow-all origins)
- [x] Static file server with path traversal protection
- [x] Common log format middleware with timing
- [x] JSON response helpers

#### Request/Response
- [x] Request parameter access (path params, query params)
- [x] Request body string access
- [x] Response status code setting
- [x] Response header management
- [x] JSON response serialization
- [x] Plain text responses

---

### 📋 Planned Features

#### 1. Enhanced Routing
- [ ] Route wildcards (e.g., `/files/*`)
- [ ] Route matching with regular expressions
- [ ] Route priority/ordering control
- [ ] Nested route groups
- [ ] Route metadata and tagging
- [ ] Automatic OPTIONS handling per route

#### 2. Request Handling
- [ ] Multipart form data parsing
- [ ] File upload handling
- [ ] Request body size limits (configurable)
- [ ] Content negotiation helpers
- [ ] Cookie parsing and setting
- [ ] Request validation helpers
- [ ] Custom body parsers (pluggable)

#### 3. Response Enhancements
- [ ] Response streaming API for large payloads
- [ ] Request body streaming for file uploads
- [ ] Template rendering support (pluggable)
- [ ] Response compression (gzip, deflate, brotli)
- [ ] ETag support for caching
- [ ] Conditional requests (If-None-Match, If-Modified-Since)
- [ ] Server-Sent Events (SSE) support
- [ ] Chunked transfer encoding

#### 4. Middleware Ecosystem
- [ ] Configurable CORS middleware (custom origins, methods, headers)
- [ ] Rate limiting middleware
- [ ] Authentication middleware (JWT, Bearer, Basic Auth)
- [ ] Session management middleware
- [ ] Cookie parsing and management
- [ ] Request ID tracking
- [ ] Body parser middleware (JSON, form-urlencoded, multipart)
- [ ] CSRF protection
- [ ] Security headers middleware (helmet-style)
- [ ] Request timeout middleware
- [ ] Circuit breaker pattern

#### 5. Performance & Scaling
- [ ] Connection pooling
- [ ] Request/response pooling
- [ ] Zero-copy optimizations
- [ ] HTTP keep-alive connection management
- [ ] Graceful shutdown support
- [ ] Health check endpoints
- [ ] Metrics and monitoring hooks

#### 6. Error Handling
- [ ] Error recovery middleware
- [ ] Detailed error responses (development mode)
- [ ] Error logging integration points
- [ ] Panic recovery
- [ ] Structured error types

#### 7. Testing & Development
- [ ] Test client for integration testing
- [ ] Mock request/response builders
- [ ] Development mode with hot reload (external tool integration)
- [ ] Request/response logging levels
- [ ] Debug middleware

#### 8. Security
- [ ] HTTPS/TLS support
- [ ] Certificate management helpers
- [ ] Input sanitization helpers
- [ ] SQL injection prevention utilities
- [ ] XSS prevention utilities
- [ ] Rate limiting by IP/user
- [ ] Request size limits

#### 9. Documentation & Examples
- [x] Basic examples (simple server, error handling)
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

#### 10. Ecosystem Integration
- [ ] Database connection pooling patterns
- [ ] ORM integration examples
- [ ] Message queue integration patterns
- [ ] Cache integration (Redis, Memcached)
- [ ] Logging framework integration
- [ ] OpenTelemetry/tracing support

---

### 🎯 Future Considerations

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

---

### Contributing

Want to help implement a feature? Check our [CONTRIBUTING.md](CONTRIBUTING.md) guide!

### Feedback

Have suggestions for the roadmap? Open an issue or discussion on our [GitHub repository](https://github.com/CogitatorTech/helium).
