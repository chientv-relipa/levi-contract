# Unit testing with test_scenario

Tests live in `tests/` as `#[test_only]` modules. The framework simulates multiple
transactions and multiple senders.

## Skeleton
```move
#[test_only]
module levi::action_flow_test;

use sui::test_scenario as ts;
use levi::config::Config;
// ...

const OPERATOR: address = @0xA;

#[test]
fun my_test() {
    let mut sc = ts::begin(OPERATOR);      // first tx, sender = OPERATOR
    // ... call entry functions with sc.ctx() ...

    sc.next_tx(OPERATOR);                   // start a new tx (commits the previous one)
    let cfg = sc.take_shared<Config>();     // pull a shared object created earlier
    // ... assert! on getters ...
    ts::return_shared(cfg);                 // must return every taken object

    ts::end(sc);                            // consumes the scenario
}
```

## Key calls
- `ts::begin(addr)` / `sc.next_tx(addr)` — start / advance a transaction (and switch sender).
- `sc.ctx()` — the `&mut TxContext` to pass into entry functions.
- `sc.take_shared<T>()` / `ts::return_shared(obj)` — borrow / return a shared object.
- `sc.take_from_sender<T>()` / `sc.return_to_sender(obj)` — borrow / return an owned object (e.g. a cap).
- `ts::take_shared_by_id<T>(&sc, id)` — when several `T` exist, pick one by `ID`.
- `let eff = sc.next_tx(addr); ts::created(&eff)` — IDs created by the previous tx.

## Asserting expected aborts
```move
#[test]
#[expected_failure(abort_code = levi::action_flow::ENotAgentWallet)]
fun submit_rejected_for_wrong_wallet() { /* ... triggers the abort ... */ }
```
The `abort_code` must name the constant in the module that actually aborts (errors are
module-private, so the location matters).

## Tips
- Every taken object must be returned or transferred before `ts::end`, or the test fails.
- You can call `public(package)` functions from a test in the same package (used here to
  unit-test reputation helpers directly).
- Run with `sui move test`; filter with `sui move test <name_substring>`.
