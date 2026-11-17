#!/bin/bash
# Prints the UDID of the simulator to use: $SIM_UDID if set, else the available device named $SIM
# (default "iPhone 17") on the newest iOS runtime.
if [ -n "$SIM_UDID" ]; then echo "$SIM_UDID"; exit 0; fi
xcrun simctl list devices available -j | python3 -c "
import json,sys,os
name=os.environ.get('SIM','iPhone 17')
d=json.load(sys.stdin)['devices']
cands=[(rt,dev) for rt,devs in d.items() for dev in devs if dev['name']==name and 'iOS' in rt]
if not cands: sys.exit('no available simulator named '+name)
rt,dev=sorted(cands,key=lambda x:[int(p) for p in x[0].split('iOS-')[-1].split('-')])[-1]
print(dev['udid'])"
