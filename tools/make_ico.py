"""Turns icon.png (256x256) into icon.ico with the sizes Windows uses.
Needs Pillow:  pip install pillow
Run from the project folder:  python tools/make_ico.py
"""
from PIL import Image

img = Image.open("icon.png").convert("RGBA")
img.save("icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icon.ico saved")
