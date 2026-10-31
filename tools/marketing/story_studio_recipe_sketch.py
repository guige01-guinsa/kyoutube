"""Original offline line drawings; source text remains the only recipe authority."""
from PIL import Image, ImageDraw

PROFILE = 'recipe-sketch-v1'
BOX = (40, 220, 680, 650)
PAPER = '#fffaf0'
INK = '#534638'


class Pencil:
    def __init__(self, image, origin=(0, 0), scale=1):
        self.draw = ImageDraw.Draw(image)
        self.x, self.y = origin
        self.scale = scale

    def points(self, values):
        return [(round(self.x+x*self.scale), round(self.y+y*self.scale)) for x, y in values]

    def line(self, points, color=INK, width=3):
        values = self.points(points)
        # A second faint offset stroke gives a restrained pencil outline.
        self.draw.line([(x+1, y+2) for x, y in values], fill='#c5b9a7', width=max(1, round(width*self.scale)))
        self.draw.line(values, fill=color, width=max(1, round(width*self.scale)), joint='curve')

    def ellipse(self, box, fill=PAPER, color=INK, width=3):
        self.draw.ellipse(self.points([(box[0], box[1]), (box[2], box[3])]), fill=fill, outline=color, width=max(1, round(width*self.scale)))

    def polygon(self, points, fill, color=INK):
        self.draw.polygon(self.points(points), fill=fill)
        self.line([*points, points[0]], color)


def ingredient_kind(text):
    # Exact source words choose symbols, never infer quantities or extra ingredients.
    if '김칫국물' in text or '물' == text.split(' ')[0]: return 'cup'
    if any(word in text for word in ('참치액', '액젓', '간장')): return 'bottle'
    for word, kind in [('참치', 'can'), ('두부', 'tofu'), ('대파', 'scallion'),
                       ('양파', 'onion'), ('김치', 'kimchi'), ('고춧가루', 'spice'),
                       ('고추', 'pepper'), ('간장', 'bottle'), ('액젓', 'bottle'),
                       ('참치액', 'bottle'), ('고기', 'meat'), ('설탕', 'spoon'),
                       ('소금', 'spoon'), ('계량', 'spoon')]:
        if word in text: return kind
    return 'bowl'


def symbol(p, kind):
    """Symbols occupy a 180 x 180 canvas; no invented numerical markings."""
    if kind == 'onion':
        p.ellipse((34, 42, 146, 157), '#eadfbd')
        p.line([(90, 43), (78, 72), (74, 116), (90, 155)])
        p.line([(96, 46), (112, 80), (116, 120), (97, 154)])
        p.line([(78, 48), (72, 24), (92, 40), (105, 22), (102, 48)])
    elif kind == 'scallion':
        for dx in (0, 20, 40):
            p.polygon([(30+dx, 150), (40+dx, 155), (124+dx/2, 28), (108+dx/2, 30)], '#a7b88b')
            p.line([(43+dx, 137), (68+dx, 98)], '#f8f2d8', 5)
    elif kind == 'tofu':
        p.polygon([(30, 66), (108, 40), (154, 65), (74, 98)], '#fffdf2')
        p.polygon([(30, 66), (74, 98), (74, 150), (30, 119)], '#e3dbc7')
        p.polygon([(74, 98), (154, 65), (154, 117), (74, 150)], '#f3e9d4')
        for x, y in ((89, 109), (125, 92), (106, 127)): p.ellipse((x, y, x+3, y+3), INK, width=1)
    elif kind == 'can':
        p.polygon([(33, 53), (147, 53), (147, 136), (33, 136)], '#d9e0da')
        p.ellipse((33, 116, 147, 155), '#c7d2c8')
        p.ellipse((33, 35, 147, 74), '#eee6d4')
        p.ellipse((74, 43, 111, 59), '#eee6d4', width=2)
        p.ellipse((58, 91, 114, 119), '#fcf8e9', width=2)
        p.polygon([(111, 104), (134, 87), (133, 121)], '#fcf8e9')
    elif kind == 'cup':
        p.polygon([(41, 43), (130, 43), (121, 151), (51, 151)], '#dfebe7')
        p.line([(129, 65), (156, 65), (157, 114), (126, 114)])
        p.line([(50, 86), (124, 86)], '#83a69b')
        for y in (65, 94, 122): p.line([(56, y), (68, y)], width=2)
    elif kind == 'kimchi':
        for dx, dy in ((0, 0), (20, 26), (-20, 45)):
            p.polygon([(48+dx, 44+dy), (112+dx, 29+dy), (145+dx, 70+dy),
                       (105+dx, 106+dy), (37+dx, 84+dy)], '#d98664')
            p.line([(53+dx, 71+dy), (89+dx, 70+dy), (121+dx, 52+dy)], '#f6d3a8', 4)
    elif kind in ('bottle', 'spice'):
        p.polygon([(59, 51), (59, 24), (117, 24), (117, 51), (133, 65),
                   (133, 151), (43, 151), (43, 65)], '#c4a281' if kind == 'bottle' else '#d18c71')
        p.line([(58, 38), (118, 38)])
        p.polygon([(51, 84), (125, 84), (125, 123), (51, 123)], '#f4ead4')
    elif kind == 'spoon':
        p.ellipse((27, 34, 99, 92), '#e9ddbe')
        p.line([(88, 81), (147, 147)], width=10)
        p.line([(86, 77), (148, 142)], '#c3aa83', 5)
    elif kind == 'pepper':
        p.polygon([(34, 139), (63, 76), (110, 47), (135, 59), (123, 93), (78, 125)], '#b9896c')
        p.line([(119, 49), (128, 29), (148, 26)], '#7c956e', 6)
    elif kind == 'meat':
        p.polygon([(30, 84), (55, 49), (118, 41), (153, 76), (135, 129), (69, 151), (32, 122)], '#c68d7b')
        for y in (72, 94, 115): p.line([(49, y), (81, y+12), (128, y-10)], '#f5ddc5', 4)
    else:
        p.ellipse((20, 63, 160, 112), '#eee2c8')
        p.line([(20, 88), (38, 132), (68, 150), (114, 150), (144, 128), (160, 88)])
        p.line([(46, 106), (61, 131)], '#bbaa8e', 2)


def pot(image, text, ingredients):
    p = Pencil(image, (105, 66), 1.3)
    p.polygon([(40, 113), (51, 205), (76, 222), (252, 222), (281, 202), (292, 113)], '#d9cdb7')
    p.line([(40, 134), (14, 123), (1, 135), (6, 157), (44, 158)])
    p.line([(289, 135), (321, 124), (332, 139), (326, 157), (289, 159)])
    red = any('김치' in x or '고추' in x for x in ingredients)
    p.ellipse((40, 72, 292, 151), '#cf9675' if red else '#d6c6a3')
    if any('김치' in x for x in ingredients):
        for x, y in ((121, 107), (192, 121)):
            p.line([(x-14, y-5), (x+5, y-11), (x+14, y+2), (x-4, y+8), (x-14, y-5)], '#97563d', 2)
    if any('두부' in x for x in ingredients):
        for x, y in ((92, 99), (202, 104)):
            p.polygon([(x, y), (x+26, y-8), (x+44, y+7), (x+15, y+16)], '#f4ead0')
    if any('파' in x for x in ingredients):
        for x, y in ((80, 116), (167, 95), (229, 123)): p.ellipse((x, y, x+15, y+7), '#8ca27c')
    if '끓' in text or '김치찌개' in text:
        for x in (116, 162, 210):
            p.line([(x, 64), (x-9, 48), (x+5, 32), (x-3, 16)], '#ae9e85', 2)
    p.line([(69, 240), (259, 240)])


def dish(image, food, text, ingredients):
    if '찌개' in food or food.endswith(('탕', '국', '국밥')) or '끓' in text:
        pot(image, text+' '+food, ingredients)
        return
    p = Pencil(image)
    if any(word in food+' '+text for word in ('불고기', '볶음', '구이', '볶', '굽')) or food.endswith('전'):
        p.line([(475, 209), (591, 147)], INK, 22)
        p.line([(476, 205), (587, 145)], '#a1886b', 12)
        p.ellipse((70, 130, 508, 325), '#d6c5aa')
        p.ellipse((87, 143, 491, 301), '#eee3ce', width=2)
        if '불고기' in food or any('고기' in item for item in ingredients):
            for dx, dy in ((0, 0), (80, 7), (155, -5)):
                p.line([(143+dx, 216+dy), (168+dx, 191+dy), (193+dx, 220+dy), (178+dx, 249+dy)], '#9b775d', 14)
        elif food.endswith('전'):
            p.ellipse((139, 168, 438, 279), '#d6bd85')
    else:
        p.ellipse((72, 120, 568, 329), '#e5d9c0')
        p.ellipse((99, 139, 541, 301), PAPER, width=2)
        if '밥' in food:
            for x in range(187, 436, 31): p.line([(x, 235), (x+8, 227)], '#c4b596', 2)
        known = [ingredient_kind(item) for item in ingredients]
        known = [kind for kind in known if kind not in ('bowl', 'spoon', 'cup', 'bottle')][:3]
        for i, kind in enumerate(known):
            symbol(Pencil(image, (149+i*104, 153), .65), kind)


def sketch(plan, index):
    image = Image.new('RGB', (640, 430), PAPER)
    scene = plan['scenes'][index]
    text = scene['caption']
    if scene.get('role') == 'ingredients':
        parts = text.split(' / ')
        for i, part in enumerate(parts):
            x = (640-len(parts)*190)//2+i*190
            symbol(Pencil(image, (x, 105)), ingredient_kind(part))
    elif scene.get('role') == 'cooking' and '썰' in text:
        p = Pencil(image)
        p.polygon([(65, 112), (522, 112), (577, 319), (112, 319)], '#e7d9b9')
        for x in (105, 190): symbol(Pencil(image, (x, 126), .65), ingredient_kind('양파' if '양파' in text and x == 105 else text))
        p.polygon([(355, 144), (431, 172), (392, 232), (284, 190)], '#d7ddd7')
        p.line([(421, 164), (481, 118)], '#8d7460', 18)
    elif scene.get('role') == 'cooking' and any(w in text for w in ('간 조절', '간은', '신맛')):
        symbol(Pencil(image, (120, 110), 1.15), 'spoon')
        symbol(Pencil(image, (342, 110), 1.15), 'bowl')
    else:
        # Do not draw later additions (for example tofu) in an earlier step.
        ingredients = plan.get('recipe', {}).get('ingredients', [])
        if scene.get('role') == 'cooking':
            ingredients = [s['caption'] for s in plan['scenes'][:index+1] if s.get('role') == 'cooking']
        dish(image, plan.get('food', ''), text, ingredients)
    return image


def ink_fraction(image):
    hist = image.convert('L').histogram()
    return sum(hist[:150])/(image.width*image.height)


def verify_encoded_sketches(path, frames):
    """Decode the middle of every scene, including the last; never trust PNGs alone."""
    import imageio_ffmpeg
    import subprocess
    targets, start = [], 0
    for count in frames:
        targets.append(start+count//2)
        start += count
    # Only selected cropped frames cross the process boundary, not gigabytes of
    # full-size RGB frames. One bounded decode checks every scene.
    select = '+'.join(f'eq(n\\,{n})' for n in targets)
    raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
        '-nostdin', '-i', str(path), '-an', '-vf', f'select={select},crop=640:430:40:220',
        '-fps_mode', 'vfr', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=180).stdout
    frame_bytes = 640*430*3
    if len(raw) != frame_bytes*len(frames): raise ValueError('recipe_sketch_missing')
    ratios = []
    for i in range(len(frames)):
        crop = Image.frombytes('RGB', (640, 430), raw[i*frame_bytes:(i+1)*frame_bytes])
        ratio = ink_fraction(crop)
        if not .003 <= ratio <= .4: raise ValueError('recipe_sketch_missing')
        ratios.append(ratio)
    if len(ratios) != len(frames): raise ValueError('recipe_sketch_missing')
    return {'profile': PROFILE, 'scene_count': len(frames),
            'verified_frames': len(ratios), 'min_ink_fraction': min(ratios)}
