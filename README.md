<div align="center">
  <picture>
    <img alt="Helium Logo" src="logo.svg" height="25%" width="25%">
  </picture>
<br>

<h2>Helium</h2>

[![Tests](https://img.shields.io/github/actions/workflow/status/CogitatorTech/helium/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/actions/workflows/tests.yml)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/CogitatorTech/helium?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/CogitatorTech/helium)
[![Zig Version](https://img.shields.io/badge/Zig-0.15.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Examples](https://img.shields.io/badge/examples-view-green?style=flat&labelColor=282c34&logo=zig)](https://github.com/CogitatorTech/helium/tree/main/examples)
[![Docs](https://img.shields.io/badge/docs-read-blue?style=flat&labelColor=282c34&logo=read-the-docs)](https://github.com/CogitatorTech/helium/tree/main/docs)
[![Release](https://img.shields.io/github/release/CogitatorTech/helium.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/CogitatorTech/helium/blob/main/LICENSE)

A micro web framework for Zig

</div>

---

Helium is a small, configurable web framework for the Zig programming language.
It aims to provide the essential building blocks needed for creating fast web applications and services in
Zig without getting in the way of your application's logic.

Helium follows a micro-framework design philosophy with a small core feature set that can be extended via optional
middleware and utilities.
It aims to be lightweight and easy to use but still be able to provide the necessary building blocks for building
complex web applications by allowing users to compose their applications from reusable components.

### Features

-   Supports application type with custom context
-   Supports Type-safe request handlers and middleware
-   Supports configurable memory allocator and error handlers
-   Provides routing API with dynamic parameters and query parsing
-   Supports route groups with shared path prefixes
-   Provides middleware for global, group, and route-specific logic
-   Supports JSON and plain text response serialization
-   Supports static file serving with path traversal protection

See the [ROADMAP.md](ROADMAP.md) for the full list of implemented and planned features.

> [!IMPORTANT]
> Helium is in early development, so bugs and breaking changes are expected.
> Please use the [issues page](https://github.com/CogitatorTech/Helium/issues) to report bugs or request features.

---

### Getting Started

To be added.

---

### Documentation

Check out the [docs](docs) directory for Helium documentation, including the API reference.

### Examples

Check out the [examples](examples) directory for example usages for various Helium features.

---

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### License

Helium is licensed under the MIT License (see [LICENSE](LICENSE)).

### Acknowledgements

* The logo is from [SVG Repo](https://www.svgrepo.com/svg/206807/atom) with some modifications.
