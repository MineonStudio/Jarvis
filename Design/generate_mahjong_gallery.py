from pathlib import Path
from html import escape
import math

W = H = 1400
TILE_W, TILE_H = 104, 148
XS = [98 + 132 * i for i in range(9)]
ROWS = [174, 472, 770, 1068]
GREEN, RED, BLUE = '#218a45', '#c72f3e', '#2455a2'
IVORY = '#fffdf7'
svg = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <filter id="tableShadow" x="-30%" y="-30%" width="180%" height="190%"><feGaussianBlur stdDeviation="3"/></filter>
  <linearGradient id="face" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#fffef9"/><stop offset="1" stop-color="#f2eee3"/></linearGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d2ad69"/><stop offset="1" stop-color="#a97a3b"/></linearGradient>
  <linearGradient id="felt" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#21964b"/><stop offset="1" stop-color="#147c39"/></linearGradient>
</defs>
<rect width="1400" height="1400" fill="url(#felt)"/>
<text x="98" y="72" fill="#ffffff" font-family="-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif" font-size="29" font-weight="700">國標麻將・牌面設計稿</text>
<text x="1300" y="70" text-anchor="end" fill="#e3f4e7" font-family="-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif" font-size="14">34 張牌・SVG 向量稿・可繼續迭代</text>''']

def label_text(x, y, text, *, size=12, color='#f0f8f1', weight=600, anchor='middle'):
    svg.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{color}" font-family="-apple-system,BlinkMacSystemFont,\'PingFang SC\',sans-serif" font-size="{size}" font-weight="{weight}">{escape(text)}</text>')

def section(title, y, subtitle):
    label_text(98, y, title, size=17, color='#eff8f0', weight=700, anchor='start')
    label_text(1300, y, subtitle, size=12, color='#d9eedf', weight=500, anchor='end')

def tile(x, y, name, draw=None):
    svg.append('<g class="tile">')
    svg.append(f'<rect x="{x+8}" y="{y+4}" width="{TILE_W}" height="{TILE_H}" rx="13" fill="#062f18" opacity=".36" filter="url(#tableShadow)"/>')
    svg.append(f'<rect x="{x+5}" y="{y-5}" width="{TILE_W}" height="{TILE_H}" rx="13" fill="url(#edge)"/>')
    svg.append(f'<rect x="{x+3}" y="{y-3}" width="{TILE_W}" height="{TILE_H}" rx="13" fill="#e6d1a4" opacity=".8"/>')
    svg.append(f'<rect x="{x}" y="{y}" width="{TILE_W}" height="{TILE_H}" rx="13" fill="url(#face)" stroke="#4f453b" stroke-width="1.8"/>')
    if draw:
        draw(x, y)
    label_text(x + TILE_W/2, y + TILE_H + 27, name, size=13, weight=650)
    svg.append('</g>')

def ring(cx, cy, r, color):
    svg.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{color}"/>')
    svg.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r*.70:.2f}" fill="{IVORY}"/>')
    svg.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r*.47:.2f}" fill="{color}"/>')
    svg.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r*.18:.2f}" fill="{IVORY}"/>')

def flower(cx, cy):
    # Bold, centered medallion sized to fill the single-dot tile.
    for i in range(16):
        a = 2*math.pi*i/16
        px, py = cx+20*math.cos(a), cy+20*math.sin(a)
        svg.append(f'<ellipse cx="{px:.1f}" cy="{py:.1f}" rx="5.0" ry="7.2" transform="rotate({i*22.5:.1f} {px:.1f} {py:.1f})" fill="{GREEN}"/>')
    svg.append(f'<circle cx="{cx}" cy="{cy}" r="31" fill="none" stroke="{BLUE}" stroke-width="3.8"/>')
    svg.append(f'<circle cx="{cx}" cy="{cy}" r="16" fill="{RED}" stroke="white" stroke-width="2.5"/>')
    svg.append(f'<path d="M{cx} {cy-10}v20M{cx-10} {cy}h20" stroke="white" stroke-width="2.8" stroke-linecap="round"/>')

def dot_draw(rank, layout):
    def draw(x,y):
        if rank == 1:
            flower(x+TILE_W/2,y+TILE_H/2)
            return
        points=[(px,py,c) for px,py,c in layout]
        for px,py,c in points:
            nearest=min(math.hypot((px-qx)*TILE_W,(py-qy)*TILE_H) for qx,qy,_ in points if (px,py)!=(qx,qy))
            r=min(12.0,nearest*.43)
            ring(x+px*TILE_W,y+py*TILE_H,r,c)
    return draw

# Reference-inspired continuous double-node, pinched-waist bamboo stem.
def bamboo(cx, cy, color=GREEN, hw=8.0, hh=18.0, sw=3.0):
    d=(f'M{cx} {cy-hh} '
       f'C{cx+hw*1.08} {cy-hh*1.04} {cx+hw*1.02} {cy-hh*.70} {cx+hw*.66} {cy-hh*.56} '
       f'C{cx+hw*.45} {cy-hh*.42} {cx+hw*.52} {cy-hh*.26} {cx+hw*.48} {cy-hh*.12} '
       f'C{cx+hw*.46} {cy-hh*.02} {cx+hw*.46} {cy+hh*.02} {cx+hw*.48} {cy+hh*.12} '
       f'C{cx+hw*.52} {cy+hh*.26} {cx+hw*.45} {cy+hh*.42} {cx+hw*.66} {cy+hh*.56} '
       f'C{cx+hw*1.02} {cy+hh*.70} {cx+hw*1.08} {cy+hh*1.04} {cx} {cy+hh} '
       f'C{cx-hw*1.08} {cy+hh*1.04} {cx-hw*1.02} {cy+hh*.70} {cx-hw*.66} {cy+hh*.56} '
       f'C{cx-hw*.45} {cy+hh*.42} {cx-hw*.52} {cy+hh*.26} {cx-hw*.48} {cy+hh*.12} '
       f'C{cx-hw*.46} {cy+hh*.02} {cx-hw*.46} {cy-hh*.02} {cx-hw*.48} {cy-hh*.12} '
       f'C{cx-hw*.52} {cy-hh*.26} {cx-hw*.45} {cy-hh*.42} {cx-hw*.66} {cy-hh*.56} '
       f'C{cx-hw*1.02} {cy-hh*.70} {cx-hw*1.08} {cy-hh*1.04} {cx} {cy-hh}Z')
    svg.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>')
    svg.append(f'<path d="M{cx-hw*.48} {cy} Q{cx} {cy+1} {cx+hw*.48} {cy}" fill="none" stroke="{color}" stroke-width="{sw*.58}" stroke-linecap="round"/>')

def eight_wave(cx, cy, invert=False):
    s=-1 if invert else 1
    hw, hh = 28, 11
    outer=(f'M{cx-hw} {cy+s*hh} '
           f'C{cx-hw*.82} {cy+s*hh} {cx-hw*.78} {cy-s*hh} {cx-hw*.58} {cy-s*hh} '
           f'C{cx-hw*.38} {cy-s*hh} {cx-hw*.42} {cy+s*hh*.72} {cx-hw*.2} {cy+s*hh*.72} '
           f'C{cx} {cy+s*hh*.72} {cx-hw*.05} {cy-s*hh*.65} {cx} {cy-s*hh*.65} '
           f'C{cx+hw*.05} {cy-s*hh*.65} {cx+hw*.0} {cy+s*hh*.72} {cx+hw*.2} {cy+s*hh*.72} '
           f'C{cx+hw*.42} {cy+s*hh*.72} {cx+hw*.38} {cy-s*hh} {cx+hw*.58} {cy-s*hh} '
           f'C{cx+hw*.78} {cy-s*hh} {cx+hw*.82} {cy+s*hh} {cx+hw} {cy+s*hh}')
    inner=(f'M{cx-hw*.9} {cy+s*hh*.60} '
           f'C{cx-hw*.75} {cy+s*hh*.60} {cx-hw*.70} {cy-s*hh*.56} {cx-hw*.57} {cy-s*hh*.56} '
           f'C{cx-hw*.42} {cy-s*hh*.56} {cx-hw*.34} {cy+s*hh*.43} {cx-hw*.2} {cy+s*hh*.43} '
           f'C{cx-hw*.07} {cy+s*hh*.43} {cx-hw*.08} {cy-s*hh*.25} {cx} {cy-s*hh*.25} '
           f'C{cx+hw*.08} {cy-s*hh*.25} {cx+hw*.07} {cy+s*hh*.43} {cx+hw*.2} {cy+s*hh*.43} '
           f'C{cx+hw*.34} {cy+s*hh*.43} {cx+hw*.42} {cy-s*hh*.56} {cx+hw*.57} {cy-s*hh*.56} '
           f'C{cx+hw*.70} {cy-s*hh*.56} {cx+hw*.75} {cy+s*hh*.60} {cx+hw*.9} {cy+s*hh*.60}')
    svg.append(f'<path d="{outer}" fill="none" stroke="{GREEN}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>')
    svg.append(f'<path d="{inner}" fill="none" stroke="{GREEN}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')

def bird_draw(x,y):
    cx,cy=x+TILE_W/2,y+TILE_H/2
    # Minimal side-profile bird with a distinct head, beak, wing and tail.
    svg.append(f'<path d="M{cx-34} {cy+42} Q{cx-17} {cy+12} {cx+9} {cy-9} M{cx-25} {cy+31} Q{cx-38} {cy+18} {cx-35} {cy+7}" fill="none" stroke="{GREEN}" stroke-width="3.5" stroke-linecap="round"/>')
    svg.append(f'<path d="M{cx-24} {cy+10} C{cx-20} {cy-2} {cx-8} {cy-9} {cx+5} {cy-5} C{cx+18} {cy-1} {cx+24} {cy+11} {cx+18} {cy+23} C{cx+11} {cy+38} {cx-8} {cy+39} {cx-22} {cy+27} Z" fill="#fffdf7" stroke="{BLUE}" stroke-width="3.5" stroke-linejoin="round"/>')
    svg.append(f'<circle cx="{cx+13}" cy="{cy-13}" r="15" fill="#fffdf7" stroke="{BLUE}" stroke-width="3.5"/>')
    svg.append(f'<path d="M{cx+2} {cy-25} Q{cx-1} {cy-37} {cx+7} {cy-34} Q{cx+11} {cy-43} {cx+17} {cy-34} Q{cx+27} {cy-36} {cx+23} {cy-24}" fill="none" stroke="{RED}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>')
    svg.append(f'<path d="M{cx+27} {cy-15} L{cx+42} {cy-9} L{cx+27} {cy-5} Z" fill="{RED}"/>')
    svg.append(f'<circle cx="{cx+18}" cy="{cy-17}" r="2.4" fill="{BLUE}"/>')
    svg.append(f'<path d="M{cx-15} {cy+10} Q{cx+1} {cy-1} {cx+14} {cy+12} Q{cx+5} {cy+29} {cx-13} {cy+24} Z" fill="none" stroke="{BLUE}" stroke-width="3" stroke-linejoin="round"/>')
    svg.append(f'<path d="M{cx-18} {cy+28} Q{cx-4} {cy+40} {cx+2} {cy+57}" fill="none" stroke="{RED}" stroke-width="4.2" stroke-linecap="round"/>')

def bamboo_draw(rank, layout=None):
    def draw(x,y):
        if rank==1:
            bird_draw(x,y)
        elif rank==8:
            for py in (.23,.5,.77):
                for px in (.22,.78): bamboo(x+px*TILE_W,y+py*TILE_H,hw=8.2,hh=17.5,sw=3.1)
            eight_wave(x+TILE_W/2,y+TILE_H*.36,False)
            eight_wave(x+TILE_W/2,y+TILE_H*.64,True)
        else:
            for px,py,color in layout: bamboo(x+px*TILE_W,y+py*TILE_H,color,hw=8.0,hh=18.0,sw=3.0)
    return draw

def char_draw(rank, top, bottom, color_top=BLUE):
    def draw(x,y):
        cx=x+TILE_W/2
        svg.append(f'<text x="{cx}" y="{y+70}" text-anchor="middle" fill="{color_top}" font-family="Kaiti SC,STKaiti,serif" font-size="48" font-weight="700">{top}</text>')
        svg.append(f'<text x="{cx}" y="{y+128}" text-anchor="middle" fill="{RED}" font-family="Kaiti SC,STKaiti,serif" font-size="44" font-weight="700">{bottom}</text>')
    return draw

# Dots, ranks 1–9.
section('筒子', 142, '一至九・同心圓點')
dot_layouts={
2:[(.5,.32,BLUE),(.5,.68,GREEN)],
3:[(.27,.25,BLUE),(.5,.5,RED),(.73,.75,GREEN)],
4:[(.29,.29,GREEN),(.71,.29,BLUE),(.29,.71,BLUE),(.71,.71,GREEN)],
5:[(.29,.27,GREEN),(.71,.27,BLUE),(.5,.5,RED),(.29,.73,BLUE),(.71,.73,GREEN)],
6:[(.3,.24,GREEN),(.7,.24,GREEN),(.3,.5,RED),(.7,.5,RED),(.3,.76,RED),(.7,.76,RED)],
7:[(.25,.22,GREEN),(.5,.34,GREEN),(.75,.46,GREEN),(.3,.64,RED),(.7,.64,RED),(.3,.82,RED),(.7,.82,RED)],
8:[(.3,.16,BLUE),(.7,.16,BLUE),(.3,.39,BLUE),(.7,.39,BLUE),(.3,.61,BLUE),(.7,.61,BLUE),(.3,.84,BLUE),(.7,.84,BLUE)],
9:[(.23,.23,BLUE),(.5,.23,BLUE),(.77,.23,BLUE),(.23,.5,RED),(.5,.5,RED),(.77,.5,RED),(.23,.77,GREEN),(.5,.77,GREEN),(.77,.77,GREEN)]}
for rank in range(1,10): tile(XS[rank-1],ROWS[0],f'{rank}筒',dot_draw(rank,dot_layouts.get(rank,[])))

# Bamboo, ranks 1–9.
section('條子', 440, '雙節竹形・七條配色・八條曲節重繪')
layouts={
2:[(.5,.32,GREEN),(.5,.68,GREEN)],
3:[(.5,.26,GREEN),(.28,.72,GREEN),(.72,.72,GREEN)],
4:[(.3,.34,GREEN),(.7,.34,GREEN),(.3,.66,GREEN),(.7,.66,GREEN)],
5:[(.28,.28,GREEN),(.72,.28,GREEN),(.5,.5,RED),(.28,.72,GREEN),(.72,.72,GREEN)],
6:[(.25,.3,GREEN),(.5,.3,GREEN),(.75,.3,GREEN),(.25,.7,GREEN),(.5,.7,GREEN),(.75,.7,GREEN)],
7:[(.5,.22,RED),(.25,.48,GREEN),(.5,.48,BLUE),(.75,.48,GREEN),(.25,.76,GREEN),(.5,.76,BLUE),(.75,.76,GREEN)],
9:[(.25,.22,GREEN),(.5,.22,RED),(.75,.22,GREEN),(.25,.5,GREEN),(.5,.5,RED),(.75,.5,GREEN),(.25,.78,GREEN),(.5,.78,RED),(.75,.78,GREEN)]}
tile(XS[0],ROWS[1],'1條',bamboo_draw(1))
for rank in range(2,10): tile(XS[rank-1],ROWS[1],f'{rank}條',bamboo_draw(rank,layouts.get(rank)))

# Characters use traditional 萬 while the Chinese numerals remain shared forms.
section('萬子', 738, '一至九・繁體牌面字樣')
nums='一二三四五六七八九'
for rank,n in enumerate(nums,1): tile(XS[rank-1],ROWS[2],f'{rank}萬',char_draw(rank,n,'萬'))

# Honors, centered as a seven-tile group.
section('字牌', 1036, '東、南、西、北、中、發、白')
honors=[('東',BLUE),('南',BLUE),('西',BLUE),('北',BLUE),('中',RED),('發',GREEN)]
for i,(glyph,color) in enumerate(honors):
    def draw_honor(x,y,g=glyph,c=color):
        svg.append(f'<text x="{x+TILE_W/2}" y="{y+99}" text-anchor="middle" fill="{c}" font-family="Kaiti SC,STKaiti,serif" font-size="61" font-weight="700">{g}</text>')
    tile(XS[i+1],ROWS[3],glyph,draw_honor)

def white_dragon(x,y):
    cx,cy=x+TILE_W/2,y+TILE_H/2
    svg.append(f'<rect x="{cx-34}" y="{cy-61}" width="68" height="122" rx="8" fill="none" stroke="{BLUE}" stroke-width="3.3"/>')
    svg.append(f'<rect x="{cx-24}" y="{cy-51}" width="48" height="102" rx="5" fill="none" stroke="{BLUE}" stroke-width="2"/>')
tile(XS[7],ROWS[3],'白',white_dragon)
label_text(98, 1360, '設計檢查點：牌面飽滿度、圖案置中、間距、配色、實體厚邊方向', size=12, color='#d7ecdc', weight=500, anchor='start')
svg.append('</svg>')
Path('Design/MahjongTileGallery.svg').write_text('\n'.join(svg),encoding='utf-8')
