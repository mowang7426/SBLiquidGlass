# SBLiquidGlass V1.0.0 Alpha 1

SBLiquidGlass is a new project built from the GPL-licensed LiquidAss source architecture. The separate Liquidify binary supplied for reference is not bundled or copied into this project.

## Alpha 1

- Dock is the only surface enabled by default.
- Other existing LiquidAss surface hooks remain as an inactive foundation and require explicit per-surface preferences.
- The Backboardd renderer remains a separate subproject.
- Preferences use the `dylv.sbliquidglassprefs` namespace.
- No Backboardd retry loop is introduced in Alpha 1.

## Safety goals

1. Never hide a stock material before a replacement glass view exists.
2. Do not repeatedly bootstrap Backboardd after a failed registration.
3. Keep one registration path per material host.
4. Add additional surfaces only after Dock stability is confirmed.

## First test

Build with RootHide Theos and install only the `roothide` package on the test device. Confirm SpringBoard starts normally and Dock remains functional before enabling additional surfaces.
