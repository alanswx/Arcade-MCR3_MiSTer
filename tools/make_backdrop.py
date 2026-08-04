#!/usr/bin/env python3
"""Convert the MAME Discs of Tron backdrop artwork into core-ready data.

WHY THIS EXISTS
    The Environmental (and upright) Discs of Tron cabinets put a backlit
    painted cityscape behind a half-silvered mirror; the monitor image is
    superimposed on it. The core reproduces that by showing the backdrop
    wherever the game pixel is black. This script turns the MAME artwork into
    the exact bytes the core wants.

GEOMETRY comes from the artwork's own default.lay, not from guesswork. Its
Upright_Artwork view places

    screen   at (890, 591) size 2196x1647      in a 4000x2950 canvas
    backdrop at (513,  97) size 2916x2186

so the part of the backdrop the screen covers is, in backdrop-image pixels,
(175, 230) size 1021x766 -- which is 4:3, as it must be.

OUTPUT FORMAT
    512 x 240, one 16-bit little-endian word per pixel carrying a 9-bit 3:3:3
    colour ({r[2:0], g[2:0], b[2:0]}). 512x240 is the core's DEFAULT active
    geometry (tv15Khz_mode=1); the Hi-Res option gives 480 lines and the core
    simply shows each backdrop line twice.

    9 bits is not a compromise: arcade_video is instantiated #(512,9), so the
    display path has 512 possible colours full stop. A palette cannot beat
    direct 3:3:3 here, it can only match it -- which is why this emits direct
    colour and no palette.

    Two bytes per pixel wastes 7 bits on the wire, but the MRA is text-encoded
    hex anyway and it keeps the core's download path trivial (assemble a word,
    write one 9-bit RAM location). The FPGA stores 9 bits, not 16.

DITHERING is applied before quantisation. The artwork is mostly a smooth dark
blue-to-purple gradient, which is exactly the content that bands worst at
3 bits per channel. Floyd-Steinberg costs nothing at runtime.

Usage:
    tools/make_backdrop.py dotron.zip [-o backdrop.bin] [--preview out.png]
"""
import argparse
import io
import sys
import zipfile

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow:  pip install pillow")

# From default.lay, Upright_Artwork view.
LAY_BACKDROP = (513, 97, 2916, 2186)     # x, y, w, h
LAY_SCREEN = (890, 591, 2196, 1647)
OUT_W, OUT_H = 512, 240


def screen_crop_box(img_w, img_h):
    """Map the screen rectangle into backdrop-image pixel coordinates."""
    bx, by, bw, bh = LAY_BACKDROP
    sx, sy, sw, sh = LAY_SCREEN
    x = (sx - bx) / bw * img_w
    y = (sy - by) / bh * img_h
    w = sw / bw * img_w
    h = sh / bh * img_h
    return (round(x), round(y), round(x + w), round(y + h))


def quantise_333(img):
    """Floyd-Steinberg dither to 3 bits per channel, returning a list of ints."""
    # Pillow's own quantize() targets a palette; we want a fixed 3:3:3 grid, so
    # do the error diffusion by hand.
    px = [list(p) for p in img.convert("RGB").getdata()]
    w, h = img.size
    out = []
    for y in range(h):
        for x in range(w):
            i = y * w + x
            old = px[i]
            new = []
            err = []
            for c in range(3):
                v = max(0, min(255, int(round(old[c]))))
                q = v >> 5                      # 8 -> 3 bits
                new.append(q)
                err.append(v - (q * 255 // 7))  # error against the reproduced level
            out.append((new[0] << 6) | (new[1] << 3) | new[2])
            # diffuse
            for dx, dy, f in ((1, 0, 7 / 16), (-1, 1, 3 / 16),
                              (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    for c in range(3):
                        px[j][c] += err[c] * f
    return out


def to_preview(words, w, h):
    im = Image.new("RGB", (w, h))
    im.putdata([(((v >> 6) & 7) * 255 // 7,
                 ((v >> 3) & 7) * 255 // 7,
                 (v & 7) * 255 // 7) for v in words])
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip", help="MAME artwork zip (contains dotron_backdrop.png)")
    ap.add_argument("-o", "--out", default="backdrop.bin")
    ap.add_argument("--preview", help="write a PNG of exactly what the core shows")
    ap.add_argument("--image", default="dotron_backdrop.png")
    ap.add_argument("--mra", help="write an MRA <rom> block with the data inline")
    ap.add_argument("--mra-index", type=int, default=2)
    args = ap.parse_args()

    with zipfile.ZipFile(args.zip) as z:
        raw = z.read(args.image)
    bd = Image.open(io.BytesIO(raw)).convert("RGB")

    box = screen_crop_box(*bd.size)
    print(f"backdrop {bd.size[0]}x{bd.size[1]} -> screen crop {box} "
          f"({box[2]-box[0]}x{box[3]-box[1]})")
    crop = bd.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS)

    words = quantise_333(crop)
    assert len(words) == OUT_W * OUT_H

    with open(args.out, "wb") as f:
        for v in words:
            f.write(bytes((v & 0xFF, (v >> 8) & 0xFF)))   # little-endian
    print(f"wrote {args.out}: {OUT_W}x{OUT_H} px, {OUT_W*OUT_H*2} bytes "
          f"(core stores {OUT_W*OUT_H*9} bits = "
          f"{(OUT_W*OUT_H*9 + 10239)//10240} M10K)")

    if args.mra:
        # Hardbaked into the MRA, so nothing extra ships alongside it. This is
        # an established MiSTer pattern, not an invention: Cosmic Alien.mra is
        # 3.4 MB of inline hex (its WAV samples), Space Panic 2.9 MB. Inline
        # entries carry md5="none" because there is no file to checksum.
        with open(args.mra, "w") as f:
            f.write(f'\t<!-- Backdrop artwork, {OUT_W}x{OUT_H}, 9-bit 3:3:3 in\n'
                    f'\t     16-bit LE words. Generated by tools/make_backdrop.py\n'
                    f'\t     from the MAME artwork; see that script for the geometry. -->\n')
            f.write(f'\t<rom index="{args.mra_index}" md5="none">\n\t\t<part>\n')
            for row in range(0, len(words), 16):
                chunk = words[row:row + 16]
                f.write("\t\t\t" + " ".join(f"{v & 0xFF:02X} {(v >> 8) & 0xFF:02X}"
                                              for v in chunk) + "\n")
            f.write('\t\t</part>\n\t</rom>\n')
        import os
        print(f"wrote {args.mra}: {os.path.getsize(args.mra)} bytes of MRA text")

    if args.preview:
        to_preview(words, OUT_W, OUT_H).resize(
            (OUT_W, OUT_H * 2), Image.NEAREST).save(args.preview)
        print(f"wrote {args.preview}")


if __name__ == "__main__":
    main()
