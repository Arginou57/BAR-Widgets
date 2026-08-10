# Zombie Wreck Timers

## Introduction
In Zombie mode every wreck is a threat on a timer. This widget shows that timer: a countdown floats over each corpse telling you exactly when it will rise again, so you can decide what to reclaim, what to defend and what to run from.

## What it shows
- A **countdown** over every wreck that will reanimate (`2:45`, `1:10`, `43`, ...).
- Colors escalate as the rise nears: **white** with more than 2 minutes, **light purple** under 2 minutes, **deep purple** under 1 minute, and a **pulsing purple** in the final 15 seconds.
- **Reclaim resets are picked up instantly** when someone nibbles a corpse and the game restarts its timer, the display follows.
- A purple **?** marks wrecks that slipped into the fog: their timer may have been reset unseen, so the widget is honest about not knowing instead of showing a stale number.
- Timers fade slightly for wrecks outside your line of sight but still readable on radar-known ground.

## Fair play
The widget reads only the public `zombie_rez_frame` feature rules param that the game itself publishes since the Zombie Mode Update ([PR #8582](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8582)). Spawn timing was deliberately made transparent to all players there and this widget just puts that number on screen. No hidden information, no unit control, spectator-safe, display only.

## Credits
Created by Egzothicki together with SethDGamre, the author of Zombie mode. The spawn-timing rework that made this widget possible grew out of the same collaboration.