# GFPGAN calibration faces

Aligned 512×512 face crops that `../rewrite_gfpgan_ane.py --calibrate` uses to pick its per-layer
fp16 scale factors (pinned in `../gfpgan_ane_scales.json`), and that every build uses to check its
output. Cropped from photos that are public domain or have no known
copyright restrictions, via Wikimedia Commons:

- `woolf-1927-f0.jpg`: Virginia Woolf, 1927.
- `bonnier-sons-f*.jpg`: Tor Bonnier's sons, by Jan de Meyere.

Changing these files changes the build's checks but not the model's bytes, unless you also re-run
`--calibrate` and the scale factors change.
