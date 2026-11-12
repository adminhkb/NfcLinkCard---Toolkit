"""Generate NLC Toolkit icon masters from the Hkbisn ERP logo.

Composites `assets/erp-logo-source.png` (the ERP monogram, black shapes with a
light outline on transparency) onto the dark rounded-square background used
across platforms, then writes the PNG masters consumed by
flutter_launcher_icons and the small Linux/web fallbacks.

Run this to refresh the masters, then `dart run flutter_launcher_icons`.
Requires Pillow (`python -m pip install pillow`).
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SOURCE = ASSETS / "erp-logo-source.png"
CANVAS = 1024
DARK = (0x0E, 0x14, 0x20, 255)
BORDER = (0x30, 0x44, 0x5A, 255)


def _logo(scale: float, *, white: bool = False) -> Image.Image:
    """The ERP logo resized to [scale] of the canvas, optionally as a white
    silhouette (for the Android monochrome / tinted icons)."""
    logo = Image.open(SOURCE).convert("RGBA")
    target = int(CANVAS * scale)
    logo = logo.resize((target, target), Image.Resampling.LANCZOS)
    if white:
        alpha = logo.getchannel("A")
        logo = Image.new("RGBA", logo.size, (255, 255, 255, 0))
        logo.putalpha(alpha)
    return logo


def render(
    background: bool = True, *, monochrome: bool = False, scale: float = 0.72
) -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), DARK if background else (0, 0, 0, 0))
    if background:
        ImageDraw.Draw(image).rounded_rectangle(
            (56, 56, 968, 968), radius=198, outline=BORDER, width=18
        )
    logo = _logo(scale, white=monochrome)
    image.alpha_composite(
        logo, ((CANVAS - logo.width) // 2, (CANVAS - logo.height) // 2)
    )
    return image


def save_png(image: Image.Image, path: Path, size: int = CANVAS) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    image.save(path, "PNG", optimize=True)


def main() -> None:
    icon = render()
    foreground = render(False, scale=0.60)
    monochrome = render(False, monochrome=True, scale=0.60)
    grayscale = render(monochrome=True)
    background = Image.new("RGB", (CANVAS, CANVAS), DARK[:3])

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
