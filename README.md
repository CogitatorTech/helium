<div align="center">
  <picture>
    <img alt="Helium Logo" src="logo.svg" height="25%" width="25%">
  </picture>
<br>

<h2>Helium</h2>

[![Tests](https://img.shields.io/github/actions/workflow/status/CogitatorTech/helium/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/actions/workflows/tests.yml)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/CogitatorTech/helium?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/CogitatorTech/helium)
[![Zig Version](https://img.shields.io/badge/Zig-0.15.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Docs](https://img.shields.io/github/v/tag/CogitatorTech/helium?label=docs&color=blue&style=flat&labelColor=282c34&logo=read-the-docs)](https://habedi.github.io/helium/)
[![Examples](https://img.shields.io/github/v/tag/CogitatorTech/helium?label=examples&color=green&style=flat&labelColor=282c34&logo=zig)](https://github.com/CogitatorTech/helium/tree/main/examples)
[![Release](https://img.shields.io/github/release/CogitatorTech/helium.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/CogitatorTech/helium/blob/main/LICENSE)

A lightweight, fast web framework for Zig

</div>

---

Helium is a small, configurable web framework for Zig programming language.
It provides the essential building blocks for creating fast and efficient web applications and services in Zig by
composing a set of reusable components.
Helium follows a micro-framework design philosophy with a small core feature set that could be extended via optional
middleware and utilities.

### Features

- Fully configurable and extensible components
- Build your application from small, reusable components
- Use what you need, ignore what you don't
- A small, focused API that doesn't get in your way
- Explicit and predictable behavior with minimal hidden states

### Core Features

**Routing & Request Handling**

- Express.js-like routing with HTTP method support (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
- Dynamic route parameters (e.g., `/users/:id`)
- Query parameter parsing
- Route grouping with shared prefixes
- Request body parsing

**Middleware System**

- Global middleware applied to all routes
- Group-scoped middleware for route collections
- Route-specific middleware chains
- Custom middleware support with simple function signatures

**Server Modes**

- Thread pool mode for high concurrency
- Minimal thread pool with event-driven I/O
- Configurable worker thread counts

**Built-in Utilities** (all optional)

- **CORS middleware**: Cross-origin resource sharing (allow-all)
- **Static file serving**: Secure file server with path traversal protection
- **Logging middleware**: Common log format with timing information
- **JSON responses**: Built-in JSON serialization support

**Flexibility**

- Generic context type for application state
- Custom error handlers per application
- Memory allocator control
- Type-safe handler functions

See the [ROADMAP.md](ROADMAP.md) for the list of implemented and planned features.

> [!IMPORTANT]
> Helium is in early development, so bugs and breaking changes are expected.
> Please use the [issues page](https://github.com/CogitatorTech/Helium/issues) to report bugs or request features.

---

### Getting Started

To be added.

---

### Documentation

You can find the full API documentation for the latest release of Helium [here](https://habedi.github.io/helium/).

Alternatively, you can use the `make docs` command to generate the API documentation for the current version of Helium
from the source code.
This will generate HTML documentation in the `docs/api` directory, which you can serve locally with `make serve-docs`
and view in your web browser at [http://localhost:8000](http://localhost:8000).

### Examples

Check out the [examples](examples/) directory for examples of how Helium can be used to build a variety of web
applications and services.

---

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### License

Helium is licensed under the MIT License (see [LICENSE](LICENSE)).

### Acknowledgements

* The logo is from [SVG Repo](https://www.svgrepo.com/svg/206807/atom) with some modifications.
