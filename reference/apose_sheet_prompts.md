# A-pose sheets for the NPCs (image generator, e.g. Codex)

Nanay shows what a good sheet does: separate arms (full rig) and clean art all around.
Make one sheet per character, attach the NPC library image as a style reference, and paste:

> Use the attached NPC library image as a STYLE REFERENCE ONLY. Create a single-character
> turnaround sheet for: **<description from the table in npc_3d_prompts.md>**.
> Landscape 3:2, high resolution, plain warm cream background, no cast shadows.
> Four full-body views of the SAME person, same scale and foot line, with wide empty space
> between them, in this order: straight FRONT A-POSE (arms 35 degrees away from the body,
> hands clear of the hips, legs slightly apart, nothing overlapping, nothing held in the hands),
> three-quarter view, true SIDE view facing right, straight BACK view. Label them
> "Front / A-pose", "Three-quarter", "Side", "Back". Same outfit in every view; bags worn on
> the back or shoulder, never held. Clean dark linework, soft cel shading. No other characters.

Save each as `reference/sheets/<name>.png` (for example `student_f.png`), then ask Claude to
"build the A-pose sheets".
