# Chat history regression checks

On macOS with Swift 6:

```sh
python3 Tests/ChatHistory/run-tests.py /path/to/external-storage/history-checks
```

The production synchronization/adoption methods and five model files are compiled unchanged. A minimal observable owner records conversation assignments; sockets, logging and unused image extraction are stubbed. Every message, URL, file and metadata value is freshly invented. Build output and module caches stay outside the checkout.

The checks cover metadata preservation and replacement, missing nodes, inactive branches, empty histories, live-stream ownership, all role/streaming/whitespace combinations, initial load, and background replies added only to the history tree. The save path must apply its history update in one observable assignment.

For an optimized component benchmark:

```sh
python3 Tests/ChatHistory/run-tests.py --benchmark 6000 adopt /path/to/external-storage/history-benchmark
/path/to/external-storage/history-benchmark/checks --benchmark 6000 sync
```

`--source` can select the previous ViewModel implementation. Use alternating fresh processes and report medians after discarding warm-up pairs. Component CPU, wall time and peak RSS are not end-to-end app latency or memory measurements.
