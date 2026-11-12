# MoonRainflow

[中文说明](README.zh-CN.md) · [API](pkg.generated.mbti)

MoonRainflow counts rainflow cycles in a single load history. It reports the range, mean, weight and original endpoints of each excursion, and can accumulate a range-by-mean spectrum as samples arrive. The library is MoonBit with no third-party runtime dependencies; the file/pipe CLI calls the same compiled library.

## Replay a published example

```sh
moon run cmd/demo --target wasm-gc
```

Nine reversals arrive in three blocks. Samples 4 and 5 enclose a full cycle from −1 to 3 (range 4, mean 1). The seven records comprise one full and six half cycles, or four equivalent cycles. With range edges `[0,4,8]` and mean edges `[-1,0,1]`, the half-unit matrix is `[[1,0],[1,5]]`, with one more half unit outside the grid.

## Process a file

From this directory, with MoonBit (tested with moonc 0.10.19) and Node 22.12+:

```sh
moon build --target js --release cmd/bridge
node cmd/rainflow.mjs examples/mathworks-nine.txt
node cmd/rainflow.mjs measurements.txt > cycles.csv
```

Input is one decimal number per UTF-8 line, including scientific notation. Blank lines are ignored. With no path or with `-`, the CLI reads stdin. CSV columns are `start_index,end_index,range,mean,half_units`. The last field is 1 for a half cycle and 2 for a full cycle; range is the full peak-to-valley distance, not amplitude. A failing stream returns nonzero and reports the physical line for a bad sample; any rows already emitted remain in the output.

## Library

See the [executable MoonBit example](cmd/demo/main.mbt) and [package import](cmd/demo/moon.pkg). For a batch, call `@rain.extract(samples)`. For streaming, use one `Counter::new()` per continuous signal, collect the arrays returned by every `push(value)` or `push_chunk(values)`, then append `finish()` once at the end. The chunk layout does not affect the results; finishing each chunk separately does. Invalid chunks are rejected atomically. A second finish returns no cycles; appending to a finished counter raises an error.

Indices are zero-based Int64 sample indices. Flat runs use the first occurrence, including the trailing plateau. A constant history has no cycles. The three-point rule closes equal as well as larger incoming ranges. Inner pairs are full cycles; boundary pairs and the final unclosed adjacent excursions count as halves. Records are emitted in settlement order. Inputs must be finite and within ±1e300. The library does not infer timestamps, periodically wrap the signal, apply a noise filter, or predict fatigue life.

Feed returned cycles to `Spectrum::new(range_edges, mean_edges).add(c)`. Both axes must be finite and strictly increasing, range edges nonnegative. Each bin includes its lower edge; only the last also includes its upper edge. A cycle outside either axis contributes just once to `outside_units()`. `matrix()` returns an independent snapshot in half-cycle units, indexed by range then mean. Its sum plus outside units equals `total_units()`. The grid limit is one million cells.

Counting is amortized O(n) in samples. The stream does not retain all measurements or settled cycles; the unresolved reversal stack can still grow to O(n). Binning takes O(log R + log M) time per record.

## Verification and provenance

```sh
moon fmt --check
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon build --target js --release cmd/bridge --deny-warn
node --test scripts/cli.test.mjs
```

Checks include the [MathWorks nine-reversal table](https://www.mathworks.com/help/signal/ref/rainflow.html), all 256 partitions of that input, all 3,280 ternary histories up to length seven (total variation, plateau anchors and endpoints), bin conservation and streaming CLI behavior. For an optional external check, install `rainflow==3.2.0` in an isolated Python environment, build the JS bridge, and run `python scripts/check_reference.py`. It compares 100 deterministic histories and 3,540 cycle records with [Python rainflow](https://github.com/iamlikeme/rainflow), including order and indices. Adjacent ties are tested separately because plateau index conventions differ.

Independent implementation of a published counting method, licensed under [Apache-2.0](LICENSE). Python rainflow (MIT) is an optional test oracle. No standards certification is claimed.
