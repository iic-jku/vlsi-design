# VLSI Design

[![Quarto Publish](https://github.com/iic-jku/vlsi-design/actions/workflows/quarto-publish.yml/badge.svg?branch=main)](https://github.com/iic-jku/vlsi-design/actions/workflows/quarto-publish.yml)
[![Course Checks](https://github.com/iic-jku/vlsi-design/actions/workflows/course-checks.yml/badge.svg?branch=main)](https://github.com/iic-jku/vlsi-design/actions/workflows/course-checks.yml)
[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-online-brightgreen?logo=github)](https://iic-jku.github.io/vlsi-design/vlsi.html)
<!-- [![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.XXXXXXXX-blue)](https://doi.org/10.5281/zenodo.XXXXXXXX) -->

**(c) 2026 Simon Dorrer and co-authors, Department for Integrated Circuits (ICD), Johannes Kepler University, Linz (JKU)**

This is the material for a VLSI design course, held at JKU under course number 336.051 ("KV: VLSI Design"). Follow this [link to access the material](https://iic-jku.github.io/vlsi-design/vlsi.html).

The course makes heavy use of digital simulation, using **SystemVerilog**, [**cocotb**](https://github.com/cocotb/cocotb), [**GTKWave**](https://github.com/gtkwave/gtkwave) and [**Surfer**](https://gitlab.com/surfer-project/surfer).
Moreover, [**LibreLane**](https://github.com/librelane/librelane) is used for digital macro hardening, padframe generation and top-level assembly.
The 130 nm CMOS technology [**SG13CMOS5L**](https://github.com/IHP-GmbH/IHP-Open-PDK) from [IHP Microelectronics](https://www.ihp-microelectronics.com) is used.

Tools and PDK are integrated in the [**IIC-OSIC-TOOLS**](https://github.com/iic-jku/IIC-OSIC-TOOLS) Docker image, which will be used during the coursework.

Every tool result that a chapter quotes is reproduced in that image by `scripts/check_<chapter>.sh`, and `scripts/run_checks.sh` runs all chapters:

- `CHECK_MODE=book` (the default) fails on any value that differs from the book, on the image the book names.
- `CHECK_MODE=regression-full` fails only where an exercise would break: a tool or PDK file is missing, the course code no longer lints, synthesizes, or passes its testbenches, a seeded bug is not caught, or a LibreLane run does not finish clean. Values that a newer image changes are listed as drift.
- `CHECK_MODE=regression` does the same without the long runs of variants: four of the seven LibreLane runs of chapter `digital_flow` and two of the four ngspice runs of chapter `cdc`. Its log lists the skipped parts.

The workflow `course-checks` runs `regression-full` on `hpretl/iic-osic-tools:latest` for every push and pull request to `main` that changes the code or the scripts, and any mode on any image by hand. The nightly test 49 of IIC-OSIC-TOOLS runs `regression` on the branch `next_release`.

All course material is made publicly available and shared under the Apache-2.0 license.

**We happily accept [pull requests](https://github.com/iic-jku/vlsi-design/pulls) to fix typos or add content! If you want to discuss something that is not clear, please [open an issue](https://github.com/iic-jku/vlsi-design/issues/new)!**
