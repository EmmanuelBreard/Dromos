#!/usr/bin/env python3
"""Generate Dromos app icon PNGs from SVG logo."""

import cairosvg
from PIL import Image
import io
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ICON_DIR = os.path.join(PROJECT_ROOT, "Dromos", "Dromos", "Assets.xcassets", "AppIcon.appiconset")
LOGO_DIR = os.path.join(PROJECT_ROOT, "Dromos", "Dromos", "Assets.xcassets", "DromosLogo.imageset")

# Logo SVG paths (no fill, we apply color via the background/composite approach)
LOGO_PATHS = """<svg width="500" height="300" viewBox="0 0 500 300" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M260.25 45.44L198.08 107.61L166.99 76.52C157.64 67.17 142.47 67.17 133.12 76.52L91.25 118.39C81.9 127.74 81.9 142.91 91.25 152.26L112.44 173.45L184.54 101.35C193.89 92 209.06 92 218.41 101.35L249.5 132.44L311.67 70.27C321.02 60.92 321.02 45.75 311.67 36.4L290.48 15.21C281.13 5.86 265.96 5.86 256.61 15.21L225.52 46.3L260.25 45.44Z" fill="{fill}"/>
<path d="M294.12 79.31L231.95 141.48L200.86 110.39C191.51 101.04 176.34 101.04 166.99 110.39L125.12 152.26C115.77 161.61 115.77 176.78 125.12 186.13L146.31 207.32L218.41 135.22C227.76 125.87 242.93 125.87 252.28 135.22L283.37 166.31L345.54 104.14C354.89 94.79 354.89 79.62 345.54 70.27L324.35 49.08C315 39.73 299.83 39.73 290.48 49.08L259.39 80.17L294.12 79.31Z" fill="{fill}"/>
<path d="M327.99 113.18L265.82 175.35L234.73 144.26C225.38 134.91 210.21 134.91 200.86 144.26L158.99 186.13C149.64 195.48 149.64 210.65 158.99 220L180.18 241.19L252.28 169.09C261.63 159.74 276.8 159.74 286.15 169.09L317.24 200.18L379.41 138.01C388.76 128.66 388.76 113.49 379.41 104.14L358.22 82.95C348.87 73.6 333.7 73.6 324.35 82.95L293.26 114.04L327.99 113.18Z" fill="{fill}"/>
</svg>"""

SIZE = 1024
LOGO_RENDER_HEIGHT = 500  # Render logo at this height, then center in 1024x1024


def render_logo(fill_color: str) -> Image.Image:
    """Render the logo SVG with a given fill color to a PIL Image."""
    svg = LOGO_PATHS.format(fill=fill_color)
    # Render at high resolution
    png_data = cairosvg.svg2png(bytestring=svg.encode(), output_height=LOGO_RENDER_HEIGHT)
    return Image.open(io.BytesIO(png_data)).convert("RGBA")


def create_app_icon(bg_color: tuple, fill_color: str, output_path: str):
    """Create a 1024x1024 app icon with colored background and centered logo."""
    canvas = Image.new("RGBA", (SIZE, SIZE), bg_color)
    logo = render_logo(fill_color)

    # Center the logo on the canvas
    x = (SIZE - logo.width) // 2
    y = (SIZE - logo.height) // 2
    canvas.paste(logo, (x, y), logo)

    # App icons must be RGB (no alpha) for light/dark
    if bg_color[3] == 255:
        canvas = canvas.convert("RGB")
    canvas.save(output_path)
    print(f"  Created: {output_path} ({canvas.size})")


def create_tinted_icon(output_path: str):
    """Create tinted variant: grayscale logo on transparent background."""
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    logo = render_logo("black")

    x = (SIZE - logo.width) // 2
    y = (SIZE - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    canvas.save(output_path)
    print(f"  Created: {output_path} ({canvas.size})")


def create_template_logo(output_path: str):
    """Create a template-mode logo for in-app use (black on transparent)."""
    svg = LOGO_PATHS.format(fill="black")
    png_data = cairosvg.svg2png(bytestring=svg.encode(), output_height=300)
    img = Image.open(io.BytesIO(png_data)).convert("RGBA")
    img.save(output_path)
    print(f"  Created: {output_path} ({img.size})")


if __name__ == "__main__":
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(LOGO_DIR, exist_ok=True)

    print("Generating app icons...")
    # Light: white logo on brand green
    create_app_icon((0, 155, 119, 255), "white", os.path.join(ICON_DIR, "AppIcon-light.png"))
    # Dark: white logo on black
    create_app_icon((0, 0, 0, 255), "white", os.path.join(ICON_DIR, "AppIcon-dark.png"))
    # Tinted: black logo on transparent
    create_tinted_icon(os.path.join(ICON_DIR, "AppIcon-tinted.png"))

    print("\nGenerating in-app logo...")
    create_template_logo(os.path.join(LOGO_DIR, "DromosLogo.png"))

    print("\nDone!")
