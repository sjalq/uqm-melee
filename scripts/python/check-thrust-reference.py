import argparse
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description="Generate thrust cases by compiling the original UQM C routines")
parser.add_argument("--source", type=Path, default=Path.home() / "git/uqm/sc2/src/uqm")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
scratch = root / "scripts/temp/thrust-reference"
scratch.mkdir(parents=True, exist_ok=True)

def source(name):
    return re.sub(r'^#include.*$', '', (args.source / name).read_text(), flags=re.M)

ship = source("ship.c")
start = ship.index("inertial_thrust (ELEMENT")
end = ship.index("\nvoid\nship_preprocess", start)
header = r"""
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef int16_t SIZE;
typedef uint16_t COUNT;
typedef uint32_t DWORD;
typedef uint8_t BYTE;
typedef int8_t SBYTE;
typedef unsigned STATUS_FLAGS;
typedef struct { SIZE width, height; } EXTENT;
typedef struct { COUNT TravelAngle; EXTENT vector, fract, error, incr; } VELOCITY_DESC;
#define FULL_CIRCLE 64
#define HALF_CIRCLE 32
#define QUADRANT 16
#define CIRCLE_SHIFT 6
#define FACING_TO_ANGLE(f) ((f)*4)
#define NORMALIZE_FACING(f) ((f)&15)
#define NORMALIZE_ANGLE(a) ((a)&63)
#define SIN_SHIFT 14
#define SIN_SCALE (1<<SIN_SHIFT)
#define FLT_ADJUST(x) (SIZE)((x)*SIN_SCALE)
#define SINVAL(a) sinetab[NORMALIZE_ANGLE(a)]
#define SINE(a,m) ((SIZE)((((long)SINVAL(a))*(long)(m))>>SIN_SHIFT))
#define COSINE(a,m) SINE((a)+QUADRANT,m)
#define VELOCITY_SHIFT 5
#define VELOCITY_SCALE 32
#define WORLD_TO_VELOCITY(v) ((v)*32)
#define VELOCITY_TO_WORLD(v) ((v)>>5)
#define DISPLAY_TO_WORLD(v) ((v)*4)
#define HIBYTE(v) (((v)>>8)&255)
#define LOBYTE(v) ((v)&255)
#define MAKE_WORD(a,b) ((a)|((b)<<8))
#define ZeroVelocityComponents(v) memset(v,0,sizeof(*v))
#define GetVelocityTravelAngle(v) ((v)->TravelAngle)
#define SHIP_AT_MAX_SPEED 1
#define SHIP_BEYOND_MAX_SPEED 2
#define SHIP_IN_GRAVITY_WELL 4
typedef struct { struct { COUNT thrust_increment, max_thrust; } characteristics; } RACE_DESC;
typedef struct { COUNT ShipFacing; STATUS_FLAGS cur_status_flags; RACE_DESC *RaceDescPtr; } STARSHIP;
typedef struct { VELOCITY_DESC velocity; STARSHIP *ship; } ELEMENT;
#define GetElementStarShip(e,s) (*(s)=(e)->ship)
static DWORD VelocitySquared(SIZE x,SIZE y) { return (DWORD)((long)x*x+(long)y*y); }
"""
main = r"""
int main(void) {
 int maximum,increment,facing,x,y,flags;
 while(scanf("%d %d %d %d %d %d",&maximum,&increment,&facing,&x,&y,&flags)==6) {
  RACE_DESC race = {{increment,maximum}};
  STARSHIP ship = {facing,flags,&race};
  ELEMENT element = {.ship=&ship};
  SetVelocityComponents(&element.velocity,x,y);
  STATUS_FLAGS result = inertial_thrust(&element);
  SIZE dx,dy; GetCurrentVelocityComponents(&element.velocity,&dx,&dy);
  printf("%d %d %u\n",dx,dy,result);
 }
}
"""
cfile = scratch / "reference.c"
cfile.write_text(header + source("trans.c") + source("velocity.c") + "\nSTATUS_FLAGS\n" + ship[start:end] + main)
subprocess.run(["cc", "-O2", str(cfile), "-o", str(scratch / "reference")], check=True)
stock = (root / "src/Melee/Ship.elm").read_text().split("stock kind =",1)[1].split("mmrnmhrmYWing :",1)[0]
specs = re.findall(r'        (\w+) ->.*?maxThrust = (\d+).*?thrustIncrement = (\d+)',stock,re.S)
assert len(specs)==25, len(specs)
cases=[]
for kind,maximum,increment in specs:
 for facing in range(16):
  limit=int(maximum)*32
  for x,y,flags in [(0,0,0),(100,-70,0),(limit,0,1),(limit,0,5),(1800,-800,3),(-1800,800,7)]:
   cases.append((kind,int(maximum),int(increment),facing,x,y,flags))
request="".join(" ".join(map(str,c[1:]))+"\n" for c in cases)
result=subprocess.run([str(scratch/"reference")],input=request,text=True,capture_output=True,check=True)
outputs=[tuple(map(int,line.split())) for line in result.stdout.splitlines()]
assert len(outputs)==len(cases)
fixture=root/"tests/Fixtures/ThrustReference.elm"
fixture.parent.mkdir(exist_ok=True)
rows=[]
for (kind,maximum,increment,facing,x,y,flags),(dx,dy,status) in zip(cases,outputs):
 rows.append(f"( {kind}, ( {facing}, ( {x}, {y} ), {flags} ), ( {dx}, {dy}, {status} ) )")
fixture.write_text("module Fixtures.ThrustReference exposing (cases)\n\nimport Melee.Ship exposing (ShipKind(..))\n\ncases : List ( ShipKind, ( Int, ( Int, Int ), Int ), ( Int, Int, Int ) )\ncases =\n    [ " + "\n    , ".join(rows) + "\n    ]\n")
print(f"Generated {len(cases)} original-C cases across all 25 ship characteristics and 16 facings")
