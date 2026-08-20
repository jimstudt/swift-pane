# ``SwiftPane``

A dashboard renderer for embedded-minded Swift: an element tree in,
pixels (or a PNG) out.

## Overview

SwiftPane draws dashboards — fixed layouts of rectangles, gauges, and
single-line text — into caller-owned BGRA8888 buffers. You describe
the frame as a tree of value-type ``Element``s, and rendering follows
the Flutter contract: constraints flow down, sizes come up, parents
assign positions.

![A rendered example dashboard.](dashboard)

The design serves embedded targets and desktops with the same code:

- **No allocation in the library.** Pixel buffers, glyph scratch, and
  text storage are caller-owned; the tree itself is stack values.
  ``Pane/glyphScratchSize`` reports the exact scratch requirement, and
  ``TextBuffer`` formats readings into fixed-capacity UTF-8 without
  ever touching an allocator.
- **Per-frame trees, checked by the compiler.** ``Label`` borrows its
  text as a `UTF8Span`, which makes elements `~Escapable`: a tree is
  built, laid out, rendered, and discarded within the frame, and the
  lifetime rules hold you to it. Layout state caches inline in the
  nodes — there is no separate render tree, no ARC traffic, and no
  stale-layout bugs.
- **Banded rendering is the same code path as whole-frame.** A
  ``Canvas`` covers any horizontal band of the frame and clips
  everything else; render the tree once per band and a device that
  can't afford a full framebuffer never needs one. Banded and
  whole-frame output are byte-identical.
- **Crisp by construction.** Layout runs on whole pixels
  (``Point``, ``Size``, ``Rect``, ``Constraints``); the only
  anti-aliasing is rounded-rect corners and glyph coverage from
  [swift-glyph](https://github.com/jimstudt/swift-glyph), the
  package's one dependency.

### A frame, start to finish

```swift
var temp = TextBuffer<16>()
temp.append(reading, decimals: 1)
temp.append("°C")

var pane = Pane(size: Size(width: 320, height: 240), root:
    Padding(10, Column(spacing: 8,
        Row(spacing: 8, alignment: .center,
            Label("REACTOR 4", size: 26, color: .white),
            Spacer(),
            Label("ONLINE", size: 14, color: accent)),
        Box(fill: card, cornerRadius: 8, padding: EdgeInsets(8),
            Label(temp.span, size: 20, color: .white)))))

let env = Environment(fonts: fonts.span, textColor: .white)
pane.layout(env)
for band in bands {
    var canvas = Canvas(pixels: bandPixels, bandRect: band,
                        glyphScratch: scratch)
    pane.render(into: &canvas, env)
}
```

Rebuild the tree with fresh values each frame — it's cheap, and it is
the design, not a workaround.

### PNG output

``PNGStream`` is a trivial, allocation-free encoder: one fixed-Huffman
deflate stream whose distance-4 matches amount to run-length encoding,
which flat dashboard pixels compress well under. Paired with banded
rendering (``Pane/renderPNG(_:background:bandHeight:bandBuffer:glyphScratch:emit:)``),
an embedded target can stream a full-frame PNG over HTTP while owning
only a band buffer and a few KB of staging.

## Topics

### Building a dashboard

- ``Pane``
- ``Element``
- ``Environment``
- ``FontRef``

### Elements

- ``Label``
- ``Box``
- ``Row``
- ``Column``
- ``Overlay``
- ``Padding``
- ``Align``
- ``SizedBox``
- ``Spacer``
- ``Flexible``
- ``EmptyElement``

### Text

- ``TextBuffer``

### Geometry and color

- ``Point``
- ``Size``
- ``Rect``
- ``EdgeInsets``
- ``Constraints``
- ``Color``
- ``Alignment``
- ``HorizontalAlignment``
- ``VerticalAlignment``
- ``CrossAlignment``

### Rendering

- ``Canvas``
- ``PNGStream``

### Child lists

- ``ElementList``
- ``ElementPair``
- ``EmptyList``
- ``maxContainerChildren``
