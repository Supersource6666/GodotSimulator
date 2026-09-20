"""Image-derived profiles from calibrated Godot structured-light captures.

Inputs are synthetic rendered images. Multi-line correspondence uses separately
exported simulated laser IDs; XYZ ground truth is NEVER used as reconstructed XYZ.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import sys
import traceback
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
from scipy.spatial import cKDTree
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def write_csv(path, columns, values):
    with path.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(columns)
        writer.writerows(values)


def ridges(image):
    """Gaussian/Hessian subpixel ridge detector; not HALCON lines_gauss."""
    a = np.asarray(image, dtype=np.float64)
    sigma = 1.4
    gx = ndimage.gaussian_filter(a, sigma, order=(0, 1))
    gy = ndimage.gaussian_filter(a, sigma, order=(1, 0))
    xx = ndimage.gaussian_filter(a, sigma, order=(0, 2))
    yy = ndimage.gaussian_filter(a, sigma, order=(2, 0))
    xy = ndimage.gaussian_filter(a, sigma, order=(1, 1))
    eigenvalue = (xx + yy - np.hypot(xx - yy, 2 * xy)) / 2
    angle = np.arctan2(2 * xy, xx - yy) / 2
    nx, ny = -np.sin(angle), np.cos(angle)
    shift = np.divide(-(gx * nx + gy * ny), eigenvalue,
                      out=np.zeros_like(a), where=eigenvalue < -1e-8)
    dx, dy = shift * nx, shift * ny
    other_eigenvalue = (xx + yy + np.hypot(xx - yy, 2 * xy)) / 2
    elongated = np.abs(other_eigenvalue) < .3 * np.abs(eigenvalue)
    candidate = elongated & (eigenvalue < -0.8) & (np.abs(dx) <= .5) & (np.abs(dy) <= .5) & (a > 12)
    candidate[:5] = candidate[-5:] = False
    candidate[:, :5] = candidate[:, -5:] = False
    labels, count = ndimage.label(candidate, np.ones((3, 3)))
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    strong = np.unique(labels[candidate & (eigenvalue < -2)])
    keep = strong[(strong != 0) & (sizes[strong] >= 8)]
    mask = np.isin(labels, keep)
    v, u = np.nonzero(mask)
    return mask, np.column_stack((u + dx[v, u], v + dy[v, u]))


def triangulate(uv, ids, calibration):
    K = np.asarray(calibration['K'], float)
    R = np.asarray(calibration['R_camera_to_world'], float)
    t = np.asarray(calibration['t_camera_to_world_m'], float)
    if not np.allclose(R.T @ R, np.eye(3), atol=1e-5) or not np.isclose(np.linalg.det(R), 1, atol=1e-5):
        raise ValueError('Camera rotation is not a proper rigid rotation')
    rays = np.column_stack((uv, np.ones(len(uv)))) @ np.linalg.inv(K).T @ R.T
    points = np.full_like(rays, np.nan)
    valid = np.zeros(len(uv), dtype=bool)
    for plane in calibration['planes_world']:
        use = np.flatnonzero(ids == plane['laser_id'])
        normal = np.asarray(plane['normal'], float)
        den = rays[use] @ normal
        depth = np.divide(-(normal @ t + plane['d']), den,
                          out=np.full(len(use), np.nan), where=np.abs(den) > 1e-5)
        good = np.isfinite(depth) & (depth > 0) & (depth < 4)
        points[use[good]] = t + rays[use[good]] * depth[good, None]
        valid[use[good]] = True
    return points, valid


def associate(uv, projected):
    """Simulation-assisted plane identity only, never replace measured pixels."""
    if not len(uv) or not len(projected):
        return np.zeros(len(uv), bool), np.zeros(len(uv), int)
    distance, nearest = cKDTree(projected[:, :2]).query(uv, k=min(8, len(projected)))
    if distance.ndim == 1:
        distance, nearest = distance[:, None], nearest[:, None]
    ids = projected[nearest, 2].astype(int)
    different = ids != ids[:, :1]
    rival = np.min(np.where(different, distance, np.inf), axis=1)
    accepted = (distance[:, 0] < 5) & ((rival - distance[:, 0]) > .8)
    return accepted, ids[:, 0]


def distance_to_profile(points, reference):
    best = np.full(len(points), np.inf)
    for p, q in zip(reference[:-1], reference[1:]):
        delta = q - p
        fraction = np.clip((points - p) @ delta / max(float(delta @ delta), 1e-12), 0, 1)
        best = np.minimum(best, np.linalg.norm(points - (p + fraction[:, None] * delta), axis=1))
    return best


def synthesize(sensor, seed, mode):
    """Explicit, reproducible image-space augmentation, not optical physics."""
    rng = np.random.default_rng(seed)
    clean = np.asarray(sensor.filter(ImageFilter.GaussianBlur(1.1)), float) * .88
    yy, xx = np.indices(clean.shape)
    if mode == 'single':
        brightness = .22 + .78 * (.5 + .5 * np.sin(xx / 110 + yy / 230))
    else:
        brightness = .66 + .34 * (.5 + .5 * np.sin(xx / 200 + yy / 190))
    original = clean * brightness
    label = np.zeros(clean.shape, np.uint8)
    support = np.argwhere(clean > 70)
    if len(support):
        for _ in range(3):
            y, x = support[rng.integers(len(support))]
            hole = ((xx - x) / 13)**2 + ((yy - y) / 10)**2 < 1
            label[hole & (clean > 5)] = 2
            original[hole] = 0
        for _ in range(2):
            y, x = support[rng.integers(len(support))]
            blob = 255 * np.exp(-.5 * (((xx-x)/17)**2 + ((yy-y)/10)**2))
            area = (blob > 12) & (label != 2)
            original[area] += blob[area]
            label[area] = 1
    original += rng.normal(0, .7, clean.shape)
    return np.clip(original, 0, 255).astype(np.uint8), np.clip(clean, 0, 255).astype(np.uint8), label


def analyze_record(root, record):
    name = record['id']
    calibration = json.loads((root/'calibration'/f'{name}.json').read_text())
    geometry = json.loads((root/'geometry'/f'{name}.json').read_text())
    projected = np.asarray(geometry['samples'], float).reshape(-1, 6)
    sensor = Image.open(root/'sensor'/f'{name}.png').convert('L')
    if sensor.size != (800, 672):
        raise ValueError(f'{name}: incorrect crop dimensions')
    full = Image.open(root/'raw_1280'/f'{name}.png').convert('L')
    if full.size != (1280, 1024) or not np.array_equal(np.asarray(full.crop((240,176,1040,848))), np.asarray(sensor)):
        raise ValueError('Stored cropped image differs from raw capture')
    seed = int.from_bytes(hashlib.sha256(name.encode()).digest()[:4], 'little')
    original, clean, label = synthesize(sensor, seed, record['mode'])
    Image.fromarray(original).save(root/'origin'/f'{name}.png')
    Image.fromarray(clean).save(root/'inpainted'/f'{name}.png')
    Image.fromarray(label).save(root/'label'/f'{name}.png')
    clean_mask, clean_uv = ridges(clean)
    origin_mask, origin_uv = ridges(original)
    # WLI-style masks use values 0/1; provide separate visible 0/255 previews.
    Image.fromarray(clean_mask.astype(np.uint8)).save(root/'centerline'/f'{name}.png')
    Image.fromarray(origin_mask.astype(np.uint8)).save(root/'centerline_origin'/f'{name}.png')
    Image.fromarray(clean_mask.astype(np.uint8)*255).save(root/'centerline_show'/f'{name}.png')
    rgb = np.repeat(original[:, :, None], 3, axis=2)
    rgb[label == 1] = [255, 60, 50]
    rgb[label == 2] = [40, 255, 80]
    rgb[origin_mask & (label == 0)] = [80, 200, 255]
    Image.fromarray(rgb).save(root/'overlay'/f'{name}.png')
    # Independent geometry round-trip validates K, crop, sign and units.
    truth_points, truth_valid = triangulate(projected[:, :2], projected[:, 2].astype(int), calibration)
    geometric_error = np.linalg.norm(truth_points[truth_valid] - projected[truth_valid, 3:], axis=1) * 1000
    roundtrip = float(np.sqrt(np.mean(geometric_error**2))) if len(geometric_error) else float('inf')
    if roundtrip > .03:
        raise ValueError(f'{name}: geometry round-trip error {roundtrip:.4f} mm')
    outputs = {}
    for variant, uv in [('origin', origin_uv), ('inpainted', clean_uv)]:
        accepted, ids = associate(uv, projected)
        points, good = triangulate(uv[accepted], ids[accepted], calibration)
        uv, ids = uv[accepted][good], ids[accepted][good]
        points = points[good]
        relative = points - np.asarray(calibration['wheel_center_m'])
        axial = relative[:, 0] * calibration['axial_sign'] * 1000
        radius = np.hypot(relative[:, 1], relative[:, 2]) * 1000
        roi = (np.abs(axial) < 130) & (radius > 400) & (radius < 530)
        data = np.column_stack((ids, uv, points*1000, axial, radius))[roi]
        write_csv(root/'profiles'/f'{name}_{variant}.csv',
                  ['laser_id','u_px','v_px','world_x_mm','world_y_mm','world_z_mm','axial_mm','radius_mm'],data)
        residual = distance_to_profile(data[:, -2:], np.asarray(geometry['reference_profile_xr_mm']))
        outputs[variant] = {'extracted_pixels': len(origin_uv) if variant=='origin' else len(clean_uv),
                            'reconstructed_points': len(data),
                            'axial_span_mm': float(np.ptp(data[:, -2])) if len(data) else 0,
                            'profile_distance_rmse_mm': float(np.sqrt(np.mean(residual**2))) if len(data) else None,
                            'profile_distance_p95_mm': float(np.percentile(residual,95)) if len(data) else None,
                            'data': data}
    return {'id': name, 'mode': record['mode'], 'channel': record['channel'],
            'seed': seed, 'geometry_roundtrip_rmse_mm': roundtrip,
            'bright_pixels': int((np.asarray(sensor)>20).sum()),
            'origin': outputs['origin'], 'inpainted': outputs['inpainted']}, geometry


def make_figures(root, manifest, results, reference):
    chosen = [r for r in manifest['records'] if r['mode']=='multi' and '_01_' in r['id']]
    if not chosen: chosen = manifest['records'][:4]
    fig, axes = plt.subplots(len(chosen), 4, figsize=(13, 3*len(chosen)), squeeze=False)
    for row, record in enumerate(chosen):
        for col, folder in enumerate(['origin','inpainted','centerline_show','overlay']):
            axes[row,col].imshow(Image.open(root/folder/(record['id']+'.png')), cmap='gray',vmin=0,vmax=255)
            axes[row,col].axis('off')
            axes[row,col].set_title(folder + '\n' + record['channel'],fontsize=9)
    fig.suptitle('SYNTHETIC / rendered wheel stripes, image-space defects and extracted centerlines',fontsize=12)
    fig.tight_layout()
    fig.savefig(root/'image_comparison.png',dpi=130)
    plt.close(fig)
    fig, axes = plt.subplots(1,2,figsize=(12,4.5))
    reference = np.asarray(reference)
    for ax, mode in zip(axes, ['single','multi']):
        ax.plot(reference[:,0],reference[:,1]-460,color='black',lw=1.2,label='Model section (evaluation only)')
        for channel in ['LeftInnerSensor','LeftOuterSensor','RightInnerSensor','RightOuterSensor']:
            arrays = [r['origin']['data'] for r in results if r['mode']==mode and r['channel']==channel]
            if not arrays: continue
            points = np.concatenate(arrays)
            ax.scatter(points[:, -2],points[:, -1]-460,s=1.2,alpha=.45,label=channel)
        ax.set(xlim=(-105,105),ylim=(-65,40),xlabel='Axial position (mm)',ylabel='Radius minus 460 mm (mm)',title=mode+' / image-derived profiles')
        ax.grid(alpha=.25)
        ax.legend(fontsize=7,loc='lower center')
    fig.suptitle('Known simulation calibration; laser identities from simulation annotations')
    fig.tight_layout()
    fig.savefig(root/'wheel_profiles.png',dpi=160)
    plt.close(fig)


def main(root):
    manifest = json.loads((root/'manifest.json').read_text())
    if manifest.get('provenance')!='GODOT_SYNTHETIC_NOT_REAL_WLI_SET':
        raise ValueError('This tool accepts only track_side synthetic captures, not original WLI archives')
    folders = ['origin','inpainted','label','centerline','centerline_origin','centerline_show','overlay','profiles']
    if (root/'processing_result.json').exists():
        raise FileExistsError('Dataset has already been processed; select a new capture directory')
    for folder in folders: (root/folder).mkdir(exist_ok=True)
    results=[]
    reference=None
    for record in manifest['records']:
        result, geometry = analyze_record(root,record)
        results.append(result)
        reference=geometry['reference_profile_xr_mm']
    for mode in ['single','multi']:
        for side in ['Left','Right']:
            pieces=[r['origin']['data'] for r in results if r['mode']==mode and r['channel'].startswith(side)]
            if not pieces: continue
            data=np.concatenate(pieces)
            write_csv(root/'profiles'/f'{mode}_{side}_merged_points.csv',
                      ['laser_id','u_px','v_px','world_x_mm','world_y_mm','world_z_mm','axial_mm','radius_mm'],data)
            # Preserve every measured point above; this secondary envelope is binned.
            bins=np.floor(data[:,-2]/.5).astype(int)
            rows=[]
            for b in np.unique(bins):
                p=data[bins==b,-2:]
                rows.append([float(np.median(p[:,0])),float(np.percentile(p[:,1],90)),len(p)])
            write_csv(root/'profiles'/f'{mode}_{side}_envelope.csv',['axial_mm','radius_p90_mm','samples'],rows)
    make_figures(root,manifest,results,reference)
    for record in results:
        record['origin'].pop('data'); record['inpainted'].pop('data')
    success=bool(results) and all(r['origin']['reconstructed_points']>=40 and r['inpainted']['reconstructed_points']>=40 for r in results)
    report={'success':success,'record_count':len(results),'provenance':manifest['provenance'],
            'method':'Gaussian-Hessian image ridges -> simulated laser-ID association -> calibrated ray/plane intersections',
            'not_implemented':'HALCON, learned inpainting, physical reflection/exposure simulation, real-world metric accuracy',
            'records':results}
    (root/'processing_result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if success:
        (root.parent/'latest_successful.json').write_text(json.dumps({'directory':str(root.resolve()),'records':len(results)},indent=2),encoding='utf-8')
    (root/'README.md').write_text('''# Synthetic wheel laser images

Generated from Godot track_side, inspired by Sensors 2018 (doi:10.3390/s18124296) and WLI-Set 2024 (doi:10.1038/s41597-024-03288-y). These are not the papers' original images or measured data.

- raw_1280: unmodified monochrome viewport captures, 1280 x 1024.
- sensor: exact 800 x 672 crop at (240,176); the crop origin is a local simulation choice.
- origin: deterministic uneven brightness, noise, synthetic spots and fractures applied in image space.
- inpainted: ideal rendered reference plus Gaussian PSF; not a learned repair or manual annotation.
- label: exact synthetic defect masks (0 background, 1 spot, 2 fracture), lossless PNG.
- centerline: Gaussian-Hessian centerlines from inpainted (0/1); centerline_origin is independently extracted from origin.
- centerline_show and overlay: human-readable previews.
- calibration: actual scene camera intrinsics/extrinsics and each light plane, in metres.
- geometry: model truth for evaluation and simulated laser identity association, kept separate from predictions.
- profiles: points triangulated from image-extracted pixels, plus merged points and a secondary axial envelope. Gaps are not interpolated. The envelope loses vertical-side detail; use full points for the complete section.
- image_comparison.png, wheel_profiles.png and processing_result.json: visual checks and computed numerical diagnostics.

Multi-line physical correspondence is supplied by projected simulation annotations (5 px maximum association distance); this is not a solution to unknown laser identity in real WLI images. The XYZ truth is not used to generate reconstructed XYZ. Reported errors compare a synthetic mesh and ideal scene calibration; they are not real-world measurement accuracy. 13 planes, angular spacing, crop offset, camera poses and perturbations are local settings, not calibration values published by either paper.
''',encoding='utf-8')
    return 0 if success else 2


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--dataset',type=Path,required=True)
    args=parser.parse_args()
    try:
        code=main(args.dataset)
    except Exception:
        text=traceback.format_exc()
        (args.dataset/'processing_error.txt').write_text(text,encoding='utf-8')
        print(text,file=sys.stderr)
        code=1
    sys.exit(code)
