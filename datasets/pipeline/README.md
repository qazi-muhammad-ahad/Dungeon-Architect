# End-to-end CLI fixtures

`teaching.json` is the small 24x16 complete walkthrough: two fixed rooms, four
packs, budget 3, score 14 and three actors. It is useful for readable map previews
and detailed allocation traces.

`irregular-fortress.json` is a 150x150 L-shaped building mask with an interior
14x14 courtyard hole. It requests 16 rooms and preserves a locked gatehouse,
boss hall and exit tower. The boss and exit have capacity overrides; encounter
packs include role/tag restrictions. There are 14 active packs and budget 24.
Verified seed 2 succeeds with score 74. The 30,000-attempt bound is explicit;
other seeds can exhaust the constructive search and are not promised to succeed.

```powershell
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli run datasets/pipeline/teaching.json --metrics
& $cli run datasets/pipeline/irregular-fortress.json --preview 95 100 55 50 --metrics
& $cli export datasets/pipeline/irregular-fortress.json output/app/fortress-result.json --events 0 --no-map
```

Use a new destination or `--force` to replace an earlier export. Every result
includes the entire map and all actors, regardless of preview crop. Output is
reproducible for a fixed source, engine version and trace configuration.
