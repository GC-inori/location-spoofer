# Third-party proxy module snapshots

The files under `Resources/ThirdPartyProxyModules/` are bundled configuration
snapshots from [Yu9191/wloc](https://github.com/Yu9191/wloc). They are retained
in the App bundle for release provenance and offline inspection. The setup UI
copies the official subscription URL instead of exporting these files.

- Upstream commit: `eec07a8dc8de6dbaee8eac1fb376e4d03020154a`
- Snapshot date: 2026-08-06
- Source directory: `modules/`

| Bundled file | Client |
|---|---|
| `wloc.module` | Shadowrocket |
| `wloc.sgmodule` | Surge and Egern |
| `wloc.conf` | Quantumult X |
| `wloc.lpx` | Loon |
| `wloc.stoverride` | Stash |

SHA-256:

```text
bb5e17b60027704971660b0ea2df3560ceff973c27d43e7f2c2c18b48d368ac6  wloc.conf
1fb451616fb17242849f72490f016afcdb8aa81a0b086f6dd5f94e1af3d58ee1  wloc.lpx
97cab104056428aa0e90521c3bf2646e9739b0b4c83272b31790f99584bca89e  wloc.module
5d6b82c31316f4a7be65e3b8d2335f4338e01af98e262948118eefe63abf7034  wloc.sgmodule
cb06593752db8b223dfa5cd1cbd089115fe3a541f5c8532491615923e83df2cb  wloc.stoverride
```

The official subscription URLs are the setup UI's import path. Egern reuses the
Surge module. Stash imports `.stoverride` directly.
