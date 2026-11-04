# Photo Restore model files: sources and licenses

These Core ML files are redistributed, unmodified except where noted, under their upstream
licenses. The conversions to Core ML are by john-rocky
(https://github.com/john-rocky/CoreML-Models, https://github.com/john-rocky/CoreML-Face-Parsing),
whose models follow the licenses of the original projects.

| File | Model | Upstream | License |
|---|---|---|---|
| `RealESRGAN4x.mlmodel` | Real-ESRGAN x4plus | https://github.com/xinntao/Real-ESRGAN | BSD-3-Clause |
| `GFPGAN-ANE.mlmodel` | GFPGAN v1.4 | https://github.com/TencentARC/GFPGAN | Apache-2.0 (see its LICENSE for third-party components) |
| `FaceParsing.mlmodel` | BiSeNet face parsing | https://github.com/zllrunning/face-parsing.PyTorch | MIT |

**Modification notice (Apache-2.0 §4b):** `GFPGAN-ANE.mlmodel` is modified from john-rocky's
`GFPGAN.mlmodel`. Its modulated convolutions are rewritten into an equivalent form that runs on the
Apple Neural Engine, and its weights are stored as 16-bit floats. The script that does this is
`tools/models/rewrite_gfpgan_ane.py` in https://github.com/alecf/photo-restore-mac.

Full license texts (GFPGAN's is also attached to this release as `GFPGAN-LICENSE.txt`):
- Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN/blob/master/LICENSE
- GFPGAN: https://github.com/TencentARC/GFPGAN/blob/master/LICENSE
- face-parsing.PyTorch: https://github.com/zllrunning/face-parsing.PyTorch/blob/master/LICENSE
