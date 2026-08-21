# Third-party proxy modules

The files under `Resources/ThirdPartyProxyModules/` are project-owned module
definitions used by the App's default domestic-mirror subscription path. Their
executable scripts are built from `ThirdParty/WlocScripts/src/` and checked in
under the versioned `ThirdParty/WlocScripts/dist/v1/` directory.

The direct GitHub Raw variants are stored under
`ThirdParty/WlocScripts/modules/direct/`. The Settings switch selects which
module URL the App copies:

- enabled by default: `gh-proxy.org` in front of GitHub Raw;
- disabled: GitHub Raw directly.

The App appends the module version as a query parameter, such as `?v=1.0.0`.
Increment this value whenever an existing module path changes so proxy clients
do not reuse a previously cached subscription body.

| Module file | Client |
|---|---|
| `wloc.module` | Shadowrocket |
| `wloc.sgmodule` | Surge and Egern |
| `wloc.conf` | Quantumult X |
| `wloc.lpx` | Loon |
| `wloc.stoverride` | Stash |

Egern reuses the Surge module. Stash imports `.stoverride` directly.

Both script entry points are owned by this repository:

- `wloc.js` patches Apple WLOC response bodies;
- `wloc-settings.js` implements `/wloc-settings/save` and
  `/wloc-settings/version`.

The generated scripts target ES2017 and avoid hard dependencies on `BigInt`,
optional chaining, nullish coalescing, `globalThis`, `URLSearchParams`, and
`Object.fromEntries`. This keeps them usable by older proxy-client releases
that still implement the established module syntax, binary response body,
`$done`, and persistent-storage APIs.

Already-installed legacy modules that point to another repository are not
silently migrated because their remote script URL is outside this project's
control. Those users must re-import the project-owned module before using the
versioned protocol and motion setting.

Current bundled module SHA-256 values:

```text
6c687eef3e47351873d4cf7545a851a473f0cee7eadc7417beff31d41e1f2ef7  wloc.conf
500bce45c3e5e0703408d5c9e29ddf1cbb1e1d976fceff3cb94260ac72fe7496  wloc.lpx
eea76b97ff01b4c242f8b497f4cc9941ace12fafac0842f45fbbb6b877177628  wloc.module
875adfc2a848e44b3109a663fb0780f6efb5feadf6c1a2b886a6d03103b71983  wloc.sgmodule
1286996b790fa19d3e840b4167b90fcf9396e6c0372356adb347ede4796d5f07  wloc.stoverride
```

The project acknowledges [Yu9191/wloc](https://github.com/Yu9191/wloc) as a
reference for earlier WLOC implementation ideas. That acknowledgement is not
an executable dependency or subscription source.
