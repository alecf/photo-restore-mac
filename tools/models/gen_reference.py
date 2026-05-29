#!/usr/bin/env python3
"""Generate PyTorch reference outputs for Core ML parity validation, using the existing
photo-restore pipeline's models (spandrel Real-ESRGAN + GFPGAN). Produces a fixed 512x512
input crop and each model's PyTorch output, so validate.py (in a coremltools env) can
compare the Core ML artifacts against them.

Run with the photo-restore venv:
  ../photo-restore/.venv/bin/python tools/models/gen_reference.py <input_image> <out_dir>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

from photo_restore.stages import faces, upscale


def aligned_face_512(arr: np.ndarray) -> np.ndarray | None:
    """Produce a facexlib-aligned 512x512 face crop (RGB) the way the real pipeline does,
    so GFPGAN parity is measured on a true aligned face rather than a squashed image
    (the model hallucinates on non-faces, making such a comparison meaningless)."""
    import cv2
    from facexlib.utils.face_restoration_helper import FaceRestoreHelper

    helper = FaceRestoreHelper(
        upscale_factor=1, face_size=512, crop_ratio=(1, 1),
        det_model="retinaface_resnet50", save_ext="png", use_parse=True, device="cpu",
    )
    helper.clean_all()
    helper.read_image(cv2.cvtColor(arr, cv2.COLOR_RGB2BGR))
    if helper.get_face_landmarks_5(only_center_face=True, eye_dist_threshold=5) == 0:
        return None
    helper.align_warp_face()
    if not helper.cropped_faces:
        return None
    return cv2.cvtColor(helper.cropped_faces[0], cv2.COLOR_BGR2RGB)


def main() -> int:
    inp = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    full = np.asarray(Image.open(inp).convert("RGB"), dtype=np.uint8)
    crop = aligned_face_512(full)
    if crop is None:
        print("no face detected — falling back to a 512 resize (GFPGAN parity will be unreliable)")
        crop = np.asarray(Image.open(inp).convert("RGB").resize((512, 512), Image.LANCZOS), dtype=np.uint8)
    else:
        print("using facexlib-aligned 512 face crop")
    arr = np.ascontiguousarray(crop)
    Image.fromarray(arr).save(out / "crop512.png")

    print("running Real-ESRGAN (PyTorch)…")
    up = upscale.upscale(arr, weight_name="realesrgan-x4plus", device="cpu")
    Image.fromarray(up).save(out / "realesrgan_ref.png")

    print("running GFPGAN (PyTorch)…")
    model = faces._load_model("gfpgan-v1.4", "cpu")
    t = torch.from_numpy(np.ascontiguousarray(arr)).permute(2, 0, 1).unsqueeze(0).float().div(255.0)
    with torch.no_grad():
        o = model(t)
    o = o.mul(255.0).round().clamp(0, 255).squeeze(0).permute(1, 2, 0).to(torch.uint8).numpy()
    Image.fromarray(o).save(out / "gfpgan_ref.png")

    print(f"references written to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
