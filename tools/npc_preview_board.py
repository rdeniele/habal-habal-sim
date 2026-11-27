"""Assemble the actual Godot character review screenshots into a labeled library board."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TYPES = ["enforcer", "customer", "pedestrian", "fellow_rider", "office_worker",
         "student", "technician", "delivery", "misc"]
NAMES = ["Enforcer", "Customer", "Pedestrian", "Fellow rider", "Office worker",
         "Student", "Technician", "Delivery staff", "Older NPCs"]


def main():
    font_path = Path("C:/Windows/Fonts/seguisb.ttf")
    title = ImageFont.truetype(str(font_path), 42)
    heading = ImageFont.truetype(str(font_path), 28)
    small = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 23)
    width, tile_h, top = 1800, 620, 120
    board = Image.new("RGB", (width, top+3*tile_h+50), "#efe9df")
    draw = ImageDraw.Draw(board)
    draw.text((32, 19), "Habal-Habal | The next 18 NPCs", font=title, fill="#302c29")
    draw.text((34, 77), "Local TripoSR bodies + custom heads | Actual Godot renders", font=small, fill="#71685e")
    for i, (kind, name) in enumerate(zip(TYPES, NAMES)):
        x, y = (i % 3)*600, top+(i//3)*tile_h
        im = Image.open(ROOT / "reference/npc_previews" / (kind+".png")).convert("RGB")
        # Camera is fixed for all pairs. Keep the two standing figures; full screenshots
        # also include a walking male and seated female for deformation review.
        w,h = im.size
        im = im.crop((0, round(h*0.09), w//2, round(h*0.94)))
        im.thumbnail((580, 550), Image.Resampling.LANCZOS)
        board.paste(im,(x+(600-im.width)//2,y+47))
        draw.text((x+25,y+6), f"{i+2:02d}  {name}", font=heading,fill="#39342e")
        draw.text((x+150,y+tile_h-35), "Male                 Female",font=small,fill="#71685e")
    dest = ROOT / "reference/npc_library_next18.png"
    board.save(dest)
    print(dest)


if __name__ == "__main__":
    main()
