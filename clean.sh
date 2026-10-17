#!/bin/bash
# -------------------------------------------------
# Clean all auxiliary files from the render process
# -------------------------------------------------
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# Johannes Kepler University, Institute for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0

rm -rf _freeze
rm -rf _manuscript
rm -rf _site
rm -rf .quarto
rm -rf *.html
rm -f vlsi.tex
rm -f vlsi.fdb_latexmk
rm -rf vlsi_files
rm -rf index_files
rm -rf content/**/*_files
rm -rf content/**/*.html
