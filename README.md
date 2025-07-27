<div align="center">
  <picture>
    <img alt="Helium Logo" src="logo.svg" height="25%" width="25%">
  </picture>
<br>

<h2>Helium</h2>

[![Tests](https://img.shields.io/github/actions/workflow/status/CogitatorTech/helium/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/actions/workflows/tests.yml)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/CogitatorTech/helium?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/CogitatorTech/helium)
[![Zig Version](https://img.shields.io/badge/Zig-0.14.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Docs](https://img.shields.io/github/v/tag/CogitatorTech/helium?label=docs&color=blue&style=flat&labelColor=282c34&logo=read-the-docs)](https://habedi.github.io/helium/)
[![Examples](https://img.shields.io/github/v/tag/CogitatorTech/helium?label=examples&color=green&style=flat&labelColor=282c34&logo=zig)](https://github.com/CogitatorTech/helium/tree/main/examples)
[![Release](https://img.shields.io/github/release/CogitatorTech/helium.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/CogitatorTech/helium/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/CogitatorTech/helium/blob/main/LICENSE)

A lightweight web framework for Zig

</div>

---

Helium is a small, asynchronous web framework for Zig programming language.
Its goal is to make it easy to build fast and efficient web applications and services in Zig.

### Features

- Full asynchronous operations support
- Cross-platform compatibility
- JSON and CBOR support
- Cookie management and optional session-based authentication mechanism
- Flexible middleware support (route-specific and global)
- Express.js-like routing mechanism

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
