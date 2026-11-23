.pragma library

// The size of a title in a theme's title font. ui.json "titleScale" scales it: a wide font is drawn larger
// than most at the same size. "titleGrid" snaps it to a whole number of the font's pixels: a pixel font drawn
// on an 8x8 grid is sharp only at 8, 16, 24 px.
function titleSize(px, ui) {
    const scaled = px * ((ui && ui.titleScale) || 1);
    const grid = ui && ui.titleGrid;
    return grid ? Math.max(grid, Math.round(scaled / grid) * grid) : Math.round(scaled);
}
