"""Generate NLC Toolkit icon masters from one simple geometric mark.

The SVG is the editable vector reference. Run this script to refresh the PNG
masters used by flutter_launcher_icons and the small Linux/web fallbacks.
Requires Pillow (`python -m pip install pillow`).
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SIZE = 2048
DARK = "#0E1420"
BORDER = "#30445A"
CYAN = "#35D1F4"
VIOLET = "#A9A5F7"


def scaled(value: int) -> int:
    return value * 2


def draw_mark(image: Image.Image, *, monochrome: bool = False) -> None:
    draw = ImageDraw.Draw(image)
    stroke = "#FFFFFF" if monochrome else CYAN
    points = [
        (scaled(326), scaled(718)),
        (scaled(326), scaled(306)),
        (scaled(698), scaled(718)),
        (scaled(698), scaled(306)),
    ]
    width = scaled(88)
    radius = width // 2
    draw.line(points, fill=stroke, width=width, joint="curve")
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=stroke)

    # A single contrasting node suggests a precise NFC contact point.
    x, y = points[-1]
    node = scaled(49)
    draw.ellipse(
        (x - node, y - node, x + node, y + node),
        fill="#FFFFFF" if monochrome else VIOLET,
    )


def render(background: bool = True, *, monochrome: bool = False) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), DARK if background else (0, 0, 0, 0))
    if background:
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle(
            (scaled(56), scaled(56), scaled(968), scaled(968)),
            radius=scaled(198),
            outline=BORDER,
            width=scaled(18),
        )
    draw_mark(image, monochrome=monochrome)
    return image.resize((1024, 1024), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path, size: int = 1024) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    image.save(path, "PNG", optimize=True)


def main() -> None:
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="NLC Toolkit icon">
  <rect width="1024" height="1024" fill="{DARK}"/>
  <rect x="56" y="56" width="912" height="912" rx="198" fill="none" stroke="{BORDER}" stroke-width="18"/>
  <path d="M326 718V306L698 718V306" fill="none" stroke="{CYAN}" stroke-width="88" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="698" cy="306" r="49" fill="{VIOLET}"/>
</svg>
'''
    (ASSETS / "nlc-icon.svg").write_text(svg, encoding="utf-8")

    icon = render()
    foreground = render(False)
    monochrome = render(False, monochrome=True)
    background = Image.new("RGB", (1024, 1024), DARK)
    grayscale = render(monochrome=True)

    save_png(icon, ASSETS / "logo.png")
    save_png(icon, ASSETS / "logo-color-desktop.png")
    save_png(grayscale, ASSETS / "logo-bw.png")
    save_png(foreground, ASSETS / "foreground-color.png")
    save_png(monochrome, ASSETS / "foreground-bw.png")
    save_png(background, ASSETS / "background-color.png")
    save_png(background, ASSETS / "background-bw.png")

    save_png(icon, ROOT / "debian/gui/nlc-toolkit.png", 512)
    save_png(
        icon,
        ROOT / "macos/Runner/AppIcon.icon/Assets/logo-color-desktop.png",
    )
    save_png(icon, ROOT / "web/favicon.png", 48)
    save_png(icon, ROOT / "web/icons/Icon-192.png", 192)
    save_png(icon, ROOT / "web/icons/Icon-512.png", 512)
    save_png(icon, ROOT / "web/icons/Icon-maskable-192.png", 192)
    save_png(icon, ROOT / "web/icons/Icon-maskable-512.png", 512)

    launch_images = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for path in launch_images.glob("Icon-App-1024x1024@1x*.png"):
        save_png(icon, path)


if __name__ == "__main__":
    main()
