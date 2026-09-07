"""Regenerate collision silhouettes from the original UQM PNGs, never from HD art."""
from pathlib import Path
from PIL import Image
import subprocess
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT.parent/"uqm/sc2/content/base/ships"
module=ROOT/"src/Melee/Masks.elm"
existing=module.read_text()
header=existing[:existing.index("masks :")]
entries=[]
for ani in sorted(SOURCE.glob("*/*-big.ani")):
    for line in ani.read_text().splitlines():
        fields=line.split()
        if len(fields)<5: continue
        image=Image.open(ani.parent/fields[0]).convert("RGBA")
        width,height=image.size
        x,y=map(int,fields[-2:])
        pixels=image.load()
        rows=[]
        for row in range(height):
            runs=[]
            start=None
            for column in range(width+1):
                solid=column<width and pixels[column,row][3]>0
                if solid and start is None: start=column
                if not solid and start is not None:
                    runs.append((start,column-1))
                    start=None
            rows.append(runs)
        serialized="["+",".join("["+",".join(f"({a},{b})" for a,b in row)+"]" for row in rows)+"]"
        path="/ships/"+ani.parent.name+"/"+fields[0]
        entries.append(f'( "{path}", Mask {width} {height} ({x}) ({y}) (Array.fromList {serialized}) )')
module.write_text(header+"masks : Dict.Dict String Mask\nmasks = Dict.fromList\n    [ "+"\n    , ".join(entries)+"\n    ]\n")
subprocess.run(["elm-format",str(module),"--yes"],check=True)
print(f"Generated {len(entries)} original collision masks")
