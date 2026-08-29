# Offline science runtime notices

This directory contains pinned, bundled dependencies used only by the optional PHY111 interactive learning activities. Runtime views are configured for local files with network access disabled.

## JavaScript and WebAssembly runtimes

- Pyodide 314.0.2 — Mozilla Public License 2.0. The complete license is bundled at `pyodide/LICENSE.txt`.
- MathJax 4.0.0 and MathJax NewCM Font 4.0.0 — Apache License 2.0. The complete license is bundled at `mathjax/LICENSE.txt`.
- MathLive 0.110.0 — MIT License. The complete license is bundled at `mathlive/LICENSE.txt`.
- Cortex Compute Engine 0.92.1 — MIT License. The complete license is bundled at `compute-engine/LICENSE.txt`.

## Python packages

The bundled wheel files retain their own distribution metadata and license material. The pinned set is NumPy 2.4.3, Matplotlib 3.10.8, contourpy 1.3.3, Cycler 0.12.1, FontTools 4.62.1, kiwisolver 1.5.0, packaging 26.1, Pillow 12.2.0, pyparsing 3.3.2, python-dateutil 2.9.0.post0, pytz 2026.1.post1, and six 1.17.0.

Exact file hashes and runtime limits are recorded in `runtime-manifest.json`. This bundled runtime is a formative offline learning tool; it is not a trusted server-side grader or a secure examination environment.
