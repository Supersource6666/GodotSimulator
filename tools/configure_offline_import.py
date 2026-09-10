"""Configure generated Godot import metadata for the 4 GB target GPU."""
from pathlib import Path
import re
from PIL import Image

root = Path(__file__).resolve().parents[1] / "offline_data/models"
total = 0
count = 0
for path in root.glob("*.import"):
    text = path.read_text("utf-8")
    previous = text
    if path.name.endswith(".glb.import"):
        text = text.replace("meshes/generate_lods=true", "meshes/generate_lods=false")
        text = text.replace("meshes/light_baking=1", "meshes/light_baking=0")
    elif path.name.endswith((".jpg.import", ".png.import")):
        text = re.sub(r"(?m)^compress/mode=\d+$", "compress/mode=2", text)
        # Keep source atlases unchanged. Limit GPU atlas to 2048; document this
        # performance preset rather than claiming unchanged source resolution.
        text = re.sub(r"(?m)^process/size_limit=\d+$", "process/size_limit=2048", text)
        text = text.replace("mipmaps/generate=false", "mipmaps/generate=true")
        image_path = path.with_suffix("")
        with Image.open(image_path) as image:
            w, h = image.size
            scale = min(1.0, 2048/max(w, h))
            # Conservative BC3 1 byte/pixel including 4/3 mip overhead.
            total += int(w*scale)*int(h*scale)*4/3
            count += 1
    if text != previous:
        path.write_text(text, "utf-8")
print("OFFLINE_IMPORT_CONFIG images", count, "estimated_BC3_mip_MiB", round(total/1024**2, 1))
