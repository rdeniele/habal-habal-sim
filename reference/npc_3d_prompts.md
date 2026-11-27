# NPC 3D models: prompts and steps

## Local TripoSR workflow (current)

The library now contains 20 GLBs: the existing vendor pair plus all 18 remaining NPCs.
The current first-pass lineup is `reference/npc_library_next18.png`; per-role images
also show walking and sitting. Triangle counts and file hashes are recorded in
`reference/npc_asset_inventory.json`.

The vendor pair is already complete. The other nine types use the same downloaded
TripoSR model and Windows-compatible environment in `tools/triposr_tmp/`. That folder
is intentionally ignored by Git; keep it locally to regenerate assets without downloads.
The source crops are in `reference/npc_crops/`.

From the project root:

```powershell
python tools/npc_batch.py prepare
python tools/npc_batch.py generate
python tools/npc_batch.py build
```

All steps accept `--types enforcer customer` (or any of the other nine types). They
exclude the completed vendors. Generation uses the installed GPU environment, cached
weights in offline mode, resolution 128 and baked 1024px textures. Completed meshes
are reused when resuming. `build` accepts `--blender <path>` if Blender moves.

`tools/blender/npc_heads.py` supplies each role's hair/headwear, including police caps,
office glasses, ponytails, delivery caps and the older characters' straw hat/gray bun.
`triposr_to_npc.py` replaces the blurry generated head, closes the neckline, and rigs
the body to the game's bone names. Assets include editable `.blend` files and `.glb`
files with embedded textures.

These remain single-image reconstructions: clothing/back details are approximate and
the textures can look blotchy up close. Fused arms, carried helmets, bags and phones
retain the source pose. Walking and sitting drive the legs/spine; these meshes are
not suitable for independently animated hands, pointing or handlebar grips. The
vendor assets are preserved by the batch workflow.

Import in Godot, then run `res://tests/npc_library_test.tscn` to validate all 18 assets
and save standing/walking/seated screenshots under `reference/npc_previews/`.
The rendered check also tests deformed edges for long stretching triangles; source
ground/shadow bridges between the feet are removed before rigging.
`python tools/npc_preview_board.py` assembles those into
`reference/npc_library_next18.png`. Headless mode validates without screenshots.

## Alternative: external image-to-3D service

How to turn the NPC sheet into game-ready 3D models with any image-to-3D site that has a free
tier (for example Meshy, Tripo, or the Hunyuan3D demo). The game picks the files up by name.

## Steps (per character)

1. Upload the picture from `reference/npc_crops/<name>.png` (cut from the sheet, 3x bigger).
   If the site has "remove background", turn it on (some cut-outs show a sliver of the
   character next to it).
2. Settings:
   - **Pose:** A-pose (arms 40 degrees down). Turn **rigging / auto-rig ON** (humanoid).
   - **Polygons:** 8,000-15,000 triangles ("low" or "medium").
   - **Texture:** on. PBR is fine but not needed.
   - Height (if asked): 1.70 m for men, 1.60 m for women, 1.50 m for the student girl.
   - If there's a "texture prompt" box, paste the prompt from the table below.
3. Download as **GLB**.
4. Save it as `assets/characters/npc/<name>.glb` (same name as the picture, e.g. `student_f.glb`).
   Then open the project in Godot once (or run the import command) so it imports the file.
   The game uses it automatically for that kind of person, with all animations.

Which game NPCs use which file:

| File | Used for |
| --- | --- |
| `vendor_*` | street / market vendors |
| `student_*` | students |
| `office_worker_*` | office and call-center workers |
| `technician_*` | workers |
| `pedestrian_*`, `customer_*`, `delivery_*`, `misc_*` | everyday people on the street (picked at random) |
| `enforcer_*`, `fellow_rider_*` | available by explicit `CharacterModel.random_look` role; police units and traffic rider spawning still use their existing looks |

Kids and elders keep the simple style (no sheet for them yet).

## Prompts

Use one as a text-to-3D prompt, a texture prompt, or a prompt to make a clean single-character
picture with an image generator first (then use that picture for image-to-3D).

Add this to the end of every prompt:

> , full body, A-pose, standing straight, arms 40 degrees down, facing forward, plain light
> background, anime game character, soft cel shading, clean shapes, Filipino city setting,
> single character, no props on the ground

| Name | Prompt |
| --- | --- |
| `vendor_m` | Filipino street food vendor man, short messy black hair, white headband, dark gray t-shirt, long brown apron with front pockets, cream towel over one shoulder, knee-length khaki shorts, rubber slippers |
| `vendor_f` | Filipino market vendor woman, black hair in a low bun under a pink kerchief, pink t-shirt, long brown apron with pockets, dark capri pants, brown flat shoes |
| `enforcer_m` | Filipino barangay tanod or police officer man, navy police cap, light blue short-sleeve uniform shirt with shoulder patch and badge, dark tie, radio on the chest, black duty belt with holster and pouches, navy cargo trousers, black boots |
| `enforcer_f` | Filipino police officer woman, ponytail, navy cap, light blue uniform shirt, black tactical vest with radio, duty belt, black gloves, navy trousers, black boots |
| `customer_m` | young Filipino man, short black hair, plain white t-shirt, black backpack, holding a smartphone, dark cargo shorts, white sneakers |
| `customer_f` | young Filipino woman, black hair in a bun, cream t-shirt, brown tote bag on the shoulder, rolled-up blue jeans, white sneakers |
| `pedestrian_m` | Filipino commuter man, dark navy cap, headphones around the neck, dark gray hoodie, baggy charcoal cargo pants, gray sneakers |
| `pedestrian_f` | Filipino commuter woman, long black hair, beige cap, oversized beige hoodie, denim shorts, white socks, gray sneakers, backpack |
| `fellow_rider_m` | Filipino motorcycle rider man, messy black hair, olive green bomber jacket with a reflective stripe and Philippine flag patch, dark hoodie under it, backpack, baggy charcoal cargo pants, sneakers, holding a white half-face helmet |
| `fellow_rider_f` | Filipino motorcycle rider woman, high ponytail, olive green rider jacket with a reflective stripe, backpack, baggy charcoal cargo pants, sneakers, holding a white helmet |
| `office_worker_m` | Filipino office employee man, neat black hair, glasses, light lavender short-sleeve button shirt, ID lanyard, dark gray slacks, brown belt, black leather shoes, messenger bag |
| `office_worker_f` | Filipino office employee woman, ponytail, glasses, white blouse, ID lanyard, dark gray trousers, black flats, brown shoulder bag |
| `student_m` | Filipino high school student boy, short black hair, white polo uniform with school ID, navy backpack, black shorts, white socks, black school shoes |
| `student_f` | Filipino high school student girl, long ponytail, white blouse uniform with a red ribbon, school ID, navy pleated skirt, white socks, black school shoes, brown backpack |
| `technician_m` | Filipino mechanic man, navy cap, navy coveralls with pockets and a name patch, black work gloves, black work boots |
| `technician_f` | Filipino maintenance worker woman, ponytail, navy cap, navy coveralls with a reflective stripe, work gloves, black boots |
| `delivery_m` | Filipino delivery courier man, navy cap, bright orange rain jacket, black messenger bag, dark cargo pants, black and white sneakers |
| `delivery_f` | Filipino delivery courier woman, ponytail, pink cap, coral pink hoodie jacket, big insulated delivery backpack, black shorts, white socks, sneakers |
| `misc_m` | older Filipino farmer man, straw hat, white sleeveless tank top, towel on the shoulder, brown knee-length shorts, rubber slippers |
| `misc_f` | Filipino lola grandmother, gray hair in a bun, pink t-shirt, brown shoulder bag, dark long skirt, slippers |
