# Capturing the frame art

/sab capture and tools/capture_art.py, for the gallery.

## /sab capture

`/sab capture` uses `Screenshot()` and the `screenshotFormat` CVar (TGA, put back after). The screenshot is the full
render resolution (an ultrawide 3440x1440 here), and the red "?" target portrait once fooled the marker search, which
now looks only at the top of the screen. The game's tooltip (bottom right, if the mouse rests on a mob) once landed in
the grid's last cell, the kill icon, so `capture_art.py` keeps only the portrait's area of that cell (`KEEP`).
