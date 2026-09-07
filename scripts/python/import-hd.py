"""Import unmodified UQM MegaMod HD battle art, retaining upstream sprite anchors."""
import concurrent.futures, json, urllib.request
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
REPO = "https://raw.githubusercontent.com/JHGuitarFreak/UQM-MegaMod-Content/master/"
tree = json.load(urllib.request.urlopen("https://api.github.com/repos/JHGuitarFreak/UQM-MegaMod-Content/git/trees/master?recursive=1"))["tree"]
paths = [x["path"] for x in tree if x["type"] == "blob" and x["path"].startswith("addons/mm-hd/ships/") and ("-big-" in x["path"] or x["path"].endswith("-big.ani"))]
def fetch(path):
    dest = ROOT / "public/hd" / path.removeprefix("addons/mm-hd/")
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        for attempt in range(3):
            try:
                data = urllib.request.urlopen(REPO + path, timeout=30).read()
                dest.write_bytes(data)
                break
            except Exception:
                if attempt == 2: raise
    return dest
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    files = list(pool.map(fetch, paths))
entries=[]
for ani in files:
    if ani.suffix != ".ani": continue
    for line in ani.read_text().splitlines():
        fields=line.split()
        if len(fields)<5:continue
        target=ani.parent/fields[0]
        if not target.exists(): fetch("addons/mm-hd/ships/"+ani.parent.name+"/"+fields[0])
        w,h=Image.open(target).size
        x,y=map(int,fields[-2:])
        original="/ships/"+ani.parent.name+"/"+target.name
        entries.append(f'( "{original}", Sprite "/hd{original}" {w} {h} ({x}) ({y}) )')
code="""module Melee.Hires exposing (Sprite, get)

import Dict

type alias Sprite = { path : String, width : Int, height : Int, x : Int, y : Int }

get : String -> Maybe Sprite
get path = Dict.get path sprites

sprites : Dict.Dict String Sprite
sprites = Dict.fromList
    [ """ + "\n    , ".join(entries) + "\n    ]\n"
(ROOT/"src/Melee/Hires.elm").write_text(code)
(ROOT/"public/HD-CREDITS.txt").write_text("UQM HD and MegaMod artwork by Damon Czanik, the UQM HD team, Kruzen, and JHGuitarFreak (Kohr-Ah Death).\nSource: https://github.com/JHGuitarFreak/UQM-MegaMod-Content\nUnderlying Star Control II content: Toys for Bob and respective creators. CC BY-NC-SA 2.5, see UQM-COPYING.txt.\nImages are copied without alteration; only their display size changes.\n")
print(f"Imported {len(entries)} HD sprites")
