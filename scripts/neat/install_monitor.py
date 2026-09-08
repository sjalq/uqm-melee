#!/usr/bin/env python3
"""Install the independent dashboard and equal-lane review timer on Snowball."""
from pathlib import Path
import shutil
import subprocess

root = Path('/home/schalk/git/uqm-melee')
release = root / 'artifacts/neat/releases/monitor-v1/scripts/neat'
units = Path.home() / '.config/systemd/user'
units.mkdir(parents=True, exist_ok=True)
backup = root / 'artifacts/neat/monitor-before-start.sh'
if not backup.exists():
    shutil.copy2(root / 'scripts/neat/start.sh', backup)
shutil.copy2(release / 'start.sh', root / 'scripts/neat/start.sh')
(units / 'uqm-monitor.service').write_text(f"""[Unit]
Description=Melee training dashboard and review evidence
[Service]
WorkingDirectory={root}
ExecStart=/usr/bin/python3 {release}/review_loop.py serve
Restart=on-failure
RestartSec=5
AllowedCPUs=6,7
MemoryMax=256M
MemorySwapMax=0
[Install]
WantedBy=default.target
""")
(units / 'uqm-review.service').write_text(f"""[Unit]
Description=Equal-budget research, creative and radical Melee trials
[Service]
Type=oneshot
WorkingDirectory={root}
ExecStart=/usr/bin/python3 {release}/review_loop.py review
AllowedCPUs=6,7
CPUQuota=200%
CPUWeight=10
MemoryMax=2G
MemorySwapMax=0
TimeoutStartSec=10800
KillMode=control-group
Environment=OPENBLAS_NUM_THREADS=1
Environment=OMP_NUM_THREADS=1
""")
(units / 'uqm-review.timer').write_text("""[Unit]
Description=Try a new Melee experiment every hour
[Timer]
OnActiveSec=5
OnUnitActiveSec=1h
AccuracySec=1s
Unit=uqm-review.service
[Install]
WantedBy=timers.target
""")
(units / 'uqm-health.service').write_text(f"""[Unit]
Description=Check Melee training progress and failures
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {release}/review_loop.py health
AllowedCPUs=6,7
CPUWeight=10
MemoryMax=256M
MemorySwapMax=0
""")
(units / 'uqm-health.timer').write_text("""[Unit]
Description=Check Melee training every 20 minutes
[Timer]
OnActiveSec=5
OnUnitActiveSec=20min
AccuracySec=1s
[Install]
WantedBy=timers.target
""")
subprocess.run(['systemctl','--user','daemon-reload'], check=True)
try:
    subprocess.run(['bash', str(root / 'scripts/neat/start.sh')], check=True, timeout=100)
    subprocess.run(['systemctl','--user','restart','uqm-monitor.service'], check=True)
    subprocess.run(['systemctl','--user','is-active','--quiet','uqm-neat.service'], check=True)
    subprocess.run(['systemctl','--user','enable','--now','uqm-monitor.service','uqm-review.timer','uqm-health.timer'], check=True)
except Exception:
    subprocess.run(['systemctl','--user','stop','uqm-monitor.service','uqm-review.timer','uqm-health.timer'])
    shutil.copy2(backup, root / 'scripts/neat/start.sh')
    subprocess.run(['bash', str(backup)], check=True, timeout=100)
    raise
