# Store image tools

Python scripts (need Pillow: `pip install pillow`) used to make the store images.
Run them from the repo root.

- `make_icon.py` – launcher and store icons:
  `python store/tools/make_icon.py 70 resources/drawables/launcher_icon.png 512 store/icon-512.png`
- `crop_face.py` – cuts the round screen out of a simulator window screenshot:
  `python store/tools/crop_face.py simulator-window.png store/screenshot-0.png`
- `make_cover.py` – 500 x 500 cover image from the three screenshots:
  `python store/tools/make_cover.py store 500 store/cover-500.png`
- `make_hero.py` – hero banner from the three screenshots:
  `python store/tools/make_hero.py store 1440 720 store/hero-1440x720.png`

The screenshots are taken from the demo build (`demo.jungle`) in the simulator.
