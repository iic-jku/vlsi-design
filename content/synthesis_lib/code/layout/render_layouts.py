# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
"""Renders standard cells of SG13CMOS5L (IHP) and EZ130 (ETH Zurich) with
KLayout, all at the same scale, and composes the two layout figures of the
chapter. Run in the container: python3 render_layouts.py [<outdir>]

NWell is drawn as an outline and pSD with coarse dots, so the transistors
under them stay visible. All other layers keep the colors and patterns of
the PDK's layer properties.
"""
import os
import sys
import tempfile

import klayout.db as db
import klayout.lay as lay
import matplotlib

matplotlib.use('Agg')
import matplotlib.image as mpimg  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

PDK = os.environ['PDK_ROOT']
IHP = f'{PDK}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/gds/sg13cmos5l_stdcell.gds'
ETH = f'{PDK}/ihp-sg13g2/libs.ref/ez130_8t/gds/ez130_8t.gds'
LYP = f'{PDK}/ihp-sg13cmos5l/libs.tech/klayout/tech/sg13cmos5l.lyp'
PPU = 150       # pixels per um, the same for every cell
MARGIN = 0.2    # um around the bounding box of a cell
DPI = 300
DITHER = {(31, 0): 1, (14, 0): 3}      # NWell hollow, pSD coarse dots
LEGEND = [((31, 0), 'NWell'), ((14, 0), 'pSD'), ((1, 0), 'Activ'),
          ((5, 0), 'GatPoly'), ((6, 0), 'Cont'), ((8, 0), 'Metal1'),
          ((189, 4), 'cell boundary')]
MONO = 'DejaVu Sans Mono'


def open_view(gds):
    lv = lay.LayoutView()
    lv.set_config('background-color', '#ffffff')
    lv.set_config('grid-visible', 'false')
    lv.set_config('text-visible', 'true')
    cv = lv.cellview(lv.load_layout(gds, False))
    lv.load_layer_props(LYP, False)    # only the layers of the PDK
    it = lv.begin_layers()
    while not it.at_end():
        lp = it.current()
        ld = (lp.source_layer, lp.source_datatype)
        if ld in DITHER:
            lp.dither_pattern = DITHER[ld]
            lp.width = 2
        it.next()
    return lv, cv


def render(lv, cv, cell, png):
    """Renders one cell, returns its image box and its boundary in um."""
    cv.cell_name = cell
    lv.max_hier()
    c = cv.layout().cell(cell)
    box = c.dbbox().enlarged(MARGIN)
    bnd = db.Region(c.begin_shapes_rec(cv.layout().layer(189, 4))).bbox()
    bnd = bnd.to_dtype(cv.layout().dbu)
    s = PPU / 50                        # looks like a screen at 50 px per um
    lv.save_image_with_options(png, round(box.width() * PPU),
                               round(box.height() * PPU), round(s), 1, 1 / s,
                               box, False)
    return box, bnd


def legend_images(tmp):
    """Renders one swatch per layer of LEGEND."""
    ly = db.Layout()
    ly.dbu = 0.001
    for i, (ld, _) in enumerate(LEGEND):
        ly.create_cell(f'L{i}').shapes(ly.layer(*ld)).insert(
            db.DBox(0, 0, 0.9, 0.6))
    gds = os.path.join(tmp, 'legend.gds')
    ly.write(gds)
    lv, cv = open_view(gds)
    return [render(lv, cv, f'L{i}', os.path.join(tmp, f'L{i}.png'))[0]
            for i in range(len(LEGEND))]


def place(ax, png, box, x, y):
    """Draws an image so that the point (0, 0) of its layout lies at (x, y)."""
    ax.imshow(mpimg.imread(png), interpolation='antialiased',
              extent=(x + box.left, x + box.right, y + box.bottom, y + box.top))


def draw_legend(ax, tmp, boxes, x, y, step, fs):
    """Two rows of swatches, four in the first, starting at (x, y)."""
    for i, ((_, name), box) in enumerate(zip(LEGEND, boxes)):
        xi, yi = x + (i % 4) * step, y - (i // 4) * 1.0
        place(ax, os.path.join(tmp, f'L{i}.png'), box, xi, yi)
        ax.text(xi + 1.1, yi + 0.3, name, va='center', fontsize=fs)


def scale_bar(ax, x, y, fs):
    ax.plot([x, x + 1], [y, y], color='black', lw=2.5, solid_capstyle='butt')
    ax.text(x + 0.5, y - 0.15, '1 µm', ha='center', va='top', fontsize=fs)


def save(fig, ax, xlim, ylim, png):
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    ax.set_aspect('equal')
    ax.axis('off')
    fig.savefig(png, dpi=DPI, facecolor='white')
    plt.close(fig)
    print(png)


def new_figure(xlim, ylim):
    w = (xlim[1] - xlim[0]) * PPU / DPI
    h = (ylim[1] - ylim[0]) * PPU / DPI
    fig = plt.figure(figsize=(w, h))
    return fig, fig.add_axes((0, 0, 1, 1))


def figure_ihp(tmp, out, swatches):
    """inv_1 and inv_16 in the top row, mux2_1 and dfrbpq_1 below."""
    lv, cv = open_view(IHP)
    cells = ['inv_1', 'inv_16', 'mux2_1', 'dfrbpq_1']
    r = {c: render(lv, cv, f'sg13cmos5l_{c}', os.path.join(tmp, f'{c}.png'))
         for c in cells}
    col2 = max(r['inv_1'][0].right, r['mux2_1'][0].right) + 1.2
    row = r['inv_1'][0].top - r['inv_1'][0].bottom + 1.9
    pos = {'inv_1': (0, row), 'inv_16': (col2, row),
           'mux2_1': (0, 0), 'dfrbpq_1': (col2, 0)}
    xlim = (-0.6, col2 + r['dfrbpq_1'][0].right + 0.3)
    ylim = (-3.1, row + r['inv_1'][0].top + 1.5)
    fig, ax = new_figure(xlim, ylim)
    for c in cells:
        box, bnd = r[c]
        x, y = pos[c]
        place(ax, os.path.join(tmp, f'{c}.png'), box, x, y)
        ax.text(x + box.left, y + box.top + 0.7, c, fontsize=17,
                family=MONO, va='bottom')
        ax.text(x + box.left, y + box.top + 0.12,
                f'{bnd.width():.2f} µm × {bnd.height():.2f} µm', fontsize=16,
                va='bottom')
    draw_legend(ax, tmp, swatches, 0, -1.6, 3.2, 16)
    scale_bar(ax, xlim[1] - 1.6, row + 2.0, 16)
    save(fig, ax, xlim, ylim, os.path.join(out, 'layouts_ihp.png'))


def figure_9t_8t(tmp, out, swatches):
    """The IHP inverter against two ETH inverters and the ETH tap cell."""
    lv, cv = open_view(IHP)
    r = [('sg13cmos5l_inv_1', render(lv, cv, 'sg13cmos5l_inv_1',
                                     os.path.join(tmp, 'i_inv_1.png')),
          os.path.join(tmp, 'i_inv_1.png'))]
    lv, cv = open_view(ETH)
    for c in ['INVX1', 'INVX3', 'WELLTAP']:
        png = os.path.join(tmp, f'e_{c}.png')
        r.append((c, render(lv, cv, c, png), png))
    x, pos = 0.0, []
    for i, (_, (box, _), _) in enumerate(r):
        pos.append(x - box.left)
        x += box.width() + (1.6 if i == 0 else 0.7)
    top = max(b.top for _, (b, _), _ in r)
    xlim = (-1.9, x + 1.0)
    ylim = (-2.9, top + 1.3)
    fig, ax = new_figure(xlim, ylim)
    for (name, (box, bnd), png), xp in zip(r, pos):
        place(ax, png, box, xp, 0)
        ax.text(xp + bnd.center().x, top + 0.12, name, ha='center',
                va='bottom', fontsize=14, family=MONO)
    for (name, (box, bnd), _), xp, side in ((r[0], pos[0], -1), (r[-1], pos[-1], 1)):
        xa = xp + (box.left - 0.25 if side < 0 else box.right + 0.25)
        ax.annotate('', (xa, bnd.top), (xa, bnd.bottom),
                    arrowprops=dict(arrowstyle='<->', lw=1.5, shrinkA=0, shrinkB=0))
        ax.text(xa + side * 0.12, bnd.height() / 2, f'{bnd.height():.2f} µm',
                rotation=90, ha='center', va='center', fontsize=13,
                bbox=dict(fc='white', ec='none', pad=1))
    ax.text(pos[0] + r[0][1][1].center().x, top + 0.75, 'IHP LV, 9 tracks',
            ha='center', fontsize=14, weight='bold')
    eth_mid = (pos[1] + r[1][1][1].left + pos[3] + r[3][1][1].right) / 2
    ax.text(eth_mid, top + 0.75, 'ETH LV, 8 tracks', ha='center',
            fontsize=14, weight='bold')
    for k, (i, box) in enumerate(enumerate(swatches)):
        xi = xlim[0] + 0.4 + (k % 4) * 2.75
        yi = -1.4 if k < 4 else -2.4
        place(ax, os.path.join(tmp, f'L{i}.png'), box, xi, yi)
        ax.text(xi + 1.1, yi + 0.3, LEGEND[i][1], va='center', fontsize=13)
    scale_bar(ax, xlim[1] - 1.7, -0.55, 13)
    save(fig, ax, xlim, ylim, os.path.join(out, 'layouts_9t_8t.png'))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        swatches = legend_images(tmp)
        figure_ihp(tmp, out, swatches)
        figure_9t_8t(tmp, out, swatches)


if __name__ == '__main__':
    main()
