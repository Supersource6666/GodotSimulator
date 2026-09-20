# Track-side wheel-profile acquisition

The scene provides a visual measurement installation and a reproducible **synthetic** image-to-profile workflow. Existing real WLI-Set ZIP archives are never inputs to the exporter and are not overwritten.

## Paper basis

- Pan, Liu and Zhang, *Reliable and Accurate Wheel Size Measurement under Highly Reflective Conditions*, Sensors 2018, 18, 4296, DOI: 10.3390/s18124296. Pages 3-5 / Figs. 2-4 motivate the paired inner/outer sensors, a common central light plane through the nominal axle, complementary flange/tread views and black-background stripes. This implementation does not reproduce the paper's full MSR enhancement algorithm.
- Song et al., *A comprehensive laser image dataset for real-time measurement of wheelset geometric parameters*, Scientific Data 2024, 11:462, DOI: 10.1038/s41597-024-03288-y. Pages 2-6 / Figs. 2-8 motivate multi-line acquisition, 1280 x 1024 captures, 800 x 672 crops, origin/inpainted/label/centerline folders and labels 0/1/2. The paper uses HALCON; this implementation uses an explicitly identified Gaussian-Hessian approximation.

Both PDFs were read from `C:/DoctorDegreeWork/LY/wli_profile`. Neither supplies the numeric camera/laser calibration used here. The 13-plane count, 0.042 rad angular spacing, crop origin (240,176), sensor poses, line width and image perturbations are local simulation parameters. The 2024 inpainted references are not a source of real metric calibration.

## Scene and acquisition

Four camera units see the lower wheel rim, flange and tread. Laser planes extend along axle X. Inner/outer central planes are coplanar and pass through the axle at nominal trigger z=0. The multi-line mode fans 13 planes from each real scene aperture. First-hit ray queries use the same mesh as the wheel and respect rails/housings; each sampled plane has an exported equation. Blue airborne fan helpers are visible only in the overview.

Filtered cameras render white surface stripes on black, with black depth occluders at the wheel/rail geometry. Each channel uses an isolated optical render layer so laser identities do not mix between sensor units. This is an ideal optical-filter abstraction, not a physical exposure/reflection simulation. Capture resolution is 1280 x 1024; live view uses 640 x 512. The saved 800 x 672 images are exact crops. Pixel centers, crop-adjusted K, OpenCV camera axes, camera-to-world rigid transforms, wheel pose and every light-plane equation are saved in metres.

Default output: `C:/DoctorDegreeWork/LY/WLI-set/track_side_sim/<timestamp>/`. Change the path in the scene panel or use `--wli-root=<directory>`. Every capture creates a new run; `latest_successful.json` points to the newest completed run.

| Control | Action |
| --- | --- |
| P / Capture | Capture current pattern/pose from all four cameras, then extract profiles |
| B / Batch | Both patterns x three longitudinal positions x four cameras = 24 samples |
| G / pattern menu | Single-plane / multi-plane acquisition |
| L | Laser emission on/off |
| C / F1 | Camera monitor panel / all interface |
| 1 / 2 / R | Installation / wheel view / reset |
| Space / W / T | Wheel motion / wheel visibility / labels |
| RMB drag / scroll / Esc | Orbit / zoom / scene menu |

Capture freezes wheel movement and takes synchronized camera images after physics/render updates. The original pose and movement are restored afterward. During capture, state-changing input is disabled. Python processing runs without a console window. The default interpreter is the local Miniconda Python, with `--wli-python=<executable>` override.

## Outputs and reconstruction

Each run contains raw captures, cropped sensor images, synthetic defective `origin`, ideal Gaussian-PSF `inpainted`, exact defect `label` masks, image-extracted `centerline` / `centerline_origin`, visible previews, calibration and separately stored geometric truth. Masks use lossless PNG: defects 0 background / 1 spot / 2 fracture; centerlines 0/1. `inpainted` is a same-pose ideal reference, not an AI-repaired image.

`tools/track_side_reconstruct.py` extracts subpixel image ridges, associates them with the known simulated laser identity, intersects camera rays with calibrated planes, and transforms the result into axial position / radius. Reconstructed XYZ is calculated from the extracted pixels, not copied from model truth. Multi-line association uses separately exported projected annotations; solving unknown real-world stripe identity is outside this synthetic workflow. Blob-like Hessian responses and ambiguous plane matches are rejected.

`profiles/*_origin.csv` and `*_inpainted.csv` preserve measured pixel coordinates, laser IDs, world XYZ and axial/radius values. Per-wheel merged point CSVs retain full side-face information; optional 0.5 mm axial envelopes are secondary summaries and cannot represent vertical faces completely. Gaps are not filled. `wheel_profiles.png` compares image-derived sections with model truth; `image_comparison.png` shows stripe images and extracted centerlines. `processing_result.json` records all counts, exact geometry round-trip checks and observed reconstruction errors. These errors describe only the simulation, not metrology performance on a real wheel.

## Run and verify

```powershell
./run-preview.ps1 -LocalScene track_side -SkipDispatch -GodotPath <Godot executable>
# Append these user arguments when launching Godot directly:
# -- --wli-batch                 24-sample capture, processing, then exit
# -- --wli-preview               4-sample capture, processing, then exit
# -- --demo-smoke-test           headless optical/scene checks
python tools/test_track_side_reconstruct.py
python tools/track_side_reconstruct.py --dataset <unprocessed capture directory>
```

Python dependencies: NumPy, SciPy, Pillow, Matplotlib. The standalone processor refuses to overwrite a completed result. On failure, captures remain available and `processing_error.txt` or `processing_result.json` identifies the issue. Original WLI-Set images cannot be passed to this calibrated simulation processor without their own real calibration and verified laser correspondences.
