import numpy as np
from PIL import Image, ImageDraw, ImageFont

BAYER8 = np.array([
    [0,32,8,40,2,34,10,42],[48,16,56,24,50,18,58,26],[12,44,4,36,14,46,6,38],[60,28,52,20,62,30,54,22],
    [3,35,11,43,1,33,9,41],[51,19,59,27,49,17,57,25],[15,47,7,39,13,45,5,37],[63,31,55,23,61,29,53,21]
], dtype=np.float32) / 64.0

# Palette Strate (grimdark): noirs, gris acier, rouille, accent orange
DARK   = np.array([10, 10, 12], np.float32)
MID    = np.array([74, 70, 72], np.float32)
LIGHT  = np.array([150, 142, 136], np.float32)
ACCENT = np.array([255, 120, 40], np.float32)

def load(p):
    return np.asarray(Image.open(p).convert("RGB"), np.float32) / 255.0

def crop_focus(img):
    # zone utile de la capture (le couloir en haut à droite)
    h, w, _ = img.shape
    return img[0:480, 380:1280]

def lum(img):
    return img[..., 0]*0.299 + img[..., 1]*0.587 + img[..., 2]*0.114

def saturation(img):
    mx = img.max(-1); mn = img.min(-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)

def accent_mask(img):
    # tout ce qui est chaud et saturé (orange joueur, rouge windup, jaune aggro) garde sa couleur
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    return (saturation(img) > 0.35) & (r > g) & (r > b * 1.5)

def bayer(h, w, scale=1):
    t = np.tile(BAYER8, (h // 8 + 1, w // 8 + 1))[:h, :w]
    if scale > 1:
        t = np.kron(t[: h // scale + 1, : w // scale + 1], np.ones((scale, scale)))[:h, :w]
    return t

def downscale(img, f):
    h, w, _ = img.shape
    small = Image.fromarray((img * 255).astype(np.uint8)).resize((w // f, h // f), Image.NEAREST)
    return np.asarray(small, np.float32) / 255.0

def upscale(img, f, size):
    return np.asarray(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize(size, Image.NEAREST), np.float32) / 255.0

def quantize(img, levels):
    return np.round(img * (levels - 1)) / (levels - 1)

# ---------- A. Pixel dense ----------
# rampe de gris acier légèrement froide (8 tons) + rampe accent (4 tons) : la palette du jeu
STEEL = np.array([[8,8,10],[22,22,26],[40,40,46],[62,60,66],[88,84,88],[118,112,112],[150,142,136],[190,182,172]], np.float32)/255.0
ACC   = np.array([[90,36,10],[170,70,20],[255,120,40],[255,200,120]], np.float32)/255.0

def nearest(img, pal):
    d = ((img[..., None, :] - pal[None, None, :, :])**2).sum(-1)
    return pal[d.argmin(-1)]

def pixel_dense(img, f=3):
    h, w, _ = img.shape
    s = downscale(img, f)
    m = accent_mask(s)[..., None]
    out = np.where(m, nearest(s, ACC), nearest(s, STEEL))
    return upscale(out, f, (w, h))

# ---------- B. Dither bichrome gris + accent ----------
def dither_bichrome(img, f=2):
    h, w, _ = img.shape
    s = downscale(img, f)
    sh, sw, _ = s.shape
    l = lum(s)
    t = bayer(sh, sw)
    # trois tons sur deux seuils dithered: dark / mid / light
    lvl = l * 2.0
    base = np.floor(lvl)
    frac = lvl - base
    up = (frac > t).astype(np.float32)
    idx = np.clip(base + up, 0, 2)
    pal = np.stack([DARK, MID, LIGHT]) / 255.0
    out = pal[idx.astype(int)]
    # accent: dither entre accent et dark selon la luminance, pour garder du volume
    m = accent_mask(s)
    acc_lvl = np.clip(l * 1.6, 0, 1)
    acc = np.where((acc_lvl > t)[..., None], ACCENT / 255.0, DARK / 255.0 * 1.0 + ACCENT / 255.0 * 0.35)
    out = np.where(m[..., None], acc, out)
    return upscale(out, f, (w, h))

# ---------- C. Mélange : pixel dense + dither doux sur les dégradés + scanlines ----------
def blend(img, f=3):
    h, w, _ = img.shape
    s = downscale(img, f)
    sh, sw, _ = s.shape
    t = (bayer(sh, sw) - 0.5) * 0.09
    l = lum(s)
    # dither seulement sur les tons moyens (les dégradés), le noir reste noir, les accents restent nets
    mid = ((l > 0.06) & (l < 0.75))[..., None]
    jit = np.where(mid, s + t[..., None], s)
    m = accent_mask(s)[..., None]
    q = np.where(m, nearest(s, ACC), nearest(np.clip(jit, 0, 1), STEEL))
    big = upscale(q, f, (w, h))
    # scanlines légères (identité écran cathodique)
    scan = np.ones((h, 1, 1), np.float32)
    scan[::3] = 0.86
    return big * scan

def label(img_u8, text):
    im = Image.fromarray(img_u8)
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    d.rectangle([0, 0, 900, 36], fill=(0, 0, 0))
    d.text((12, 6), text, fill=(240, 240, 240), font=font)
    return im

def to_u8(a):
    return (np.clip(a, 0, 1) * 255).astype(np.uint8)

if __name__ == "__main__":
    import sys
    src = crop_focus(load(sys.argv[1]))
    tag = sys.argv[2]
    outs = [
        ("0_original", src, "0 · Original (greybox)"),
        ("1_pixel_dense", pixel_dense(src), "1 · Pixel dense"),
        ("2_dither_bichrome", dither_bichrome(src), "2 · Dither bichrome gris + accent"),
        ("3_melange", blend(src), "3 · Mélange : pixel dense + dither doux + scanlines"),
    ]
    tiles = []
    for name, a, title in outs:
        im = label(to_u8(a), title)
        im.save(f"/tmp/render/{tag}_{name}.png")
        tiles.append(im)
    w, h = tiles[0].size
    sheet = Image.new("RGB", (w * 2 + 8, h * 2 + 8), (30, 30, 30))
    for i, im in enumerate(tiles):
        sheet.paste(im, ((i % 2) * (w + 8), (i // 2) * (h + 8)))
    sheet.save(f"/tmp/render/{tag}_sheet.png")
    print("ok")
