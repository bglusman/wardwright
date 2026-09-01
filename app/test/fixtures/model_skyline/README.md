# ModelSkyline golden fixtures

`selection-a.json` and `selection-b.json` are synthetic cross-language contract
fixtures. They do not describe private traffic or make benchmark, price, or
quality claims about real models. Their synthetic choice records exercise
full offering identity, ordering, decimal axis values, RFC 8785 hashing, and
UTF-16 object-key ordering.

They were normalized and hashed with ModelSkyline 0.9.0 at commit
`51640fc70183fda801cdf42145116cb05036c16d`. From a Wardwright checkout next to
a ModelSkyline checkout at that commit, verify or regenerate them with:

```console
uv run --project ../model_skyline python scripts/regenerate-model-skyline-fixtures.py
uv run --project ../model_skyline python scripts/regenerate-model-skyline-fixtures.py --write
```

The first command is read-only and fails if normalization would change either
fixture. Review any `--write` diff in both repositories' canonicalization tests
before accepting it; regeneration is not an instruction to update a golden
digest blindly.
