# GFPGAN calibration faces

Aligned 512×512 face crops that `../rewrite_gfpgan_ane.py` uses to pick its per-layer fp16 scale
factors, and to check its output. Cropped from photos that are public domain or have no known
copyright restrictions, via Wikimedia Commons:

- `woolf-1927-f0.jpg`: Virginia Woolf, 1927.
- `bonnier-sons-f*.jpg`: Tor Bonnier's sons, by Jan de Meyere.

Changing these files can change the scale factors, and so the rewritten model's bytes and its
pinned SHA-256 in `ModelRegistry.swift`.
