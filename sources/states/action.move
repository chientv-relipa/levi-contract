/// `Action` state — the encrypted intent plus verdict fields. The whole payload fits one
/// transaction, so it is stored in a single `vector<u8>` (no chunking needed).
///
/// This module owns the struct, the `ActionStatus` u8 codes, the state guards
/// (`assert_*`) and the package mutators. The flow handlers live in the per-instruction
/// modules `levi::submit_action`, `levi::verdict_action`, `levi::approve_action` and
/// `levi::reject_action`.
module levi::action;

// ActionStatus values. `Initialization (0)` is omitted because submit is single-shot;
// `decision` uses `PENDING` as the "undecided" sentinel.
const STATUS_PENDING: u8 = 1;
const STATUS_APPROVED: u8 = 2;
const STATUS_ESCALATED: u8 = 3;
const STATUS_BLOCKED: u8 = 4;
const STATUS_REJECTED: u8 = 5;

public struct Action has key {
    id: UID,
    agent: ID,
    action_id: u64,
    target_program: address,
    value: u64,
    commitment: vector<u8>,
    status: u8,
    decision: u8,
    raw_score: u32,
    reasoning_hash: vector<u8>,
    encrypted_payload: vector<u8>,
}

#[error]
const EActionAgentMismatch: vector<u8> = b"action does not belong to the given agent";

#[error]
const EActionNotPending: vector<u8> = b"action is not in pending state";

#[error]
const EActionNotEscalated: vector<u8> = b"action is not in escalated state";

// ----- Construction / mutation (driven by action_flow) -----

/// Create a new `PENDING` action, share it, and return its id.
public(package) fun create_and_share(
    agent: ID,
    action_id: u64,
    target_program: address,
    value: u64,
    commitment: vector<u8>,
    encrypted_payload: vector<u8>,
    ctx: &mut TxContext,
): ID {
    let action = Action {
        id: object::new(ctx),
        agent,
        action_id,
        target_program,
        value,
        commitment,
        status: STATUS_PENDING,
        decision: STATUS_PENDING,
        raw_score: 0,
        reasoning_hash: vector[],
        encrypted_payload,
    };
    let action_obj_id = object::id(&action);
    transfer::share_object(action);
    action_obj_id
}

/// Record the relayer verdict: write score + reasoning hash, then move both
/// `status` and `decision` to the resolved value.
public(package) fun record_verdict(
    action: &mut Action,
    raw_score: u32,
    reasoning_hash: vector<u8>,
    decision: u8,
) {
    action.raw_score = raw_score;
    action.reasoning_hash = reasoning_hash;
    action.decision = decision;
    action.status = decision;
}

/// Move the action's lifecycle `status` to `new_status`. The `decision` field is left
/// frozen at the value chosen at verdict — escalation resolution (`approve` / `reject`)
/// changes only `status`, not the recorded verdict `decision`.
public(package) fun set_status(action: &mut Action, new_status: u8) {
    action.status = new_status;
}

// ----- Guards -----

public(package) fun assert_belongs(action: &Action, agent: ID) {
    assert!(action.agent == agent, EActionAgentMismatch);
}

public(package) fun assert_pending(action: &Action) {
    assert!(action.status == STATUS_PENDING, EActionNotPending);
}

public(package) fun assert_escalated(action: &Action) {
    assert!(action.status == STATUS_ESCALATED, EActionNotEscalated);
}

// ----- Getters -----

public fun agent_id(action: &Action): ID { action.agent }

public fun action_id(action: &Action): u64 { action.action_id }

public fun target_program(action: &Action): address { action.target_program }

public fun value(action: &Action): u64 { action.value }

public fun status(action: &Action): u8 { action.status }

public fun decision(action: &Action): u8 { action.decision }

public fun raw_score(action: &Action): u32 { action.raw_score }

public fun commitment(action: &Action): vector<u8> { action.commitment }

public fun reasoning_hash(action: &Action): vector<u8> { action.reasoning_hash }

public fun encrypted_payload(action: &Action): vector<u8> { action.encrypted_payload }

// ----- Status constants (read-only views for handlers / tests / SDK parity) -----

public fun status_pending(): u8 { STATUS_PENDING }

public fun status_approved(): u8 { STATUS_APPROVED }

public fun status_escalated(): u8 { STATUS_ESCALATED }

public fun status_blocked(): u8 { STATUS_BLOCKED }

public fun status_rejected(): u8 { STATUS_REJECTED }
