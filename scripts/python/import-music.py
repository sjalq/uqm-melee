"""Render the original MOD files once for browser playback. Requires openmpt123 and ffmpeg."""
from pathlib import Path
import subprocess, concurrent.futures, urllib.request
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT.parent/"uqm/sc2/content/base"
OUT=ROOT/"public/music"
OUT.mkdir(exist_ok=True)
files=[(SOURCE/"battle/battle.mod", "battle")]+[(p,p.parent.name) for p in (SOURCE/"ships").glob("*/*.mod") if p.parent.name not in ["flagship","drone","lastbat"]]
def render(item):
    source,name=item
    wav=Path("/tmp/uqm-music-"+name+".wav")
    subprocess.run(["openmpt123","--batch","--quiet","--force","--samplerate","48000","--channels","2","-o",str(wav),str(source)],check=True)
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(wav),"-c:a","aac","-b:a","160k",str(OUT/(name+".m4a"))],check=True)
    wav.unlink()
    return name
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    print("Rendered",list(pool.map(render,files)))
