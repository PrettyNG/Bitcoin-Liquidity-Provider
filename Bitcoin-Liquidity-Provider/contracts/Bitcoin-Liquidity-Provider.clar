
;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var protocol-fee uint u500) ;; 5% in basis points (100 = 1%)
(define-data-var min-fee uint u50) ;; 0.5% minimum fee
(define-data-var max-fee uint u1000) ;; 10% maximum fee
(define-data-var volatility-multiplier uint u2) ;; Multiplier for fee adjustments based on volatility
(define-data-var oracle-price-stale-threshold uint u3600) ;; 1 hour in seconds
(define-data-var rebalance-threshold uint u500) ;; 5% threshold for rebalancing
(define-data-var il-protection-ratio uint u7000) ;; 70% of impermanent loss covered
(define-data-var minimum-liquidity uint u1000000) ;; Minimum liquidity required (in micro units)
(define-data-var emergency-shutdown bool false)

;; Maps
(define-map pools-map
  { pool-id: uint }
  {
    dex-contract: principal,
    token-x: principal,
    token-y: principal,
    token-x-reserve: uint,
    token-y-reserve: uint,
    fee-rate: uint,
    last-price-x: uint,
    last-price-y: uint,
    last-rebalance: uint,
    total-shares: uint,
    active: bool
  }
)

(define-map user-positions
  { user: principal, pool-id: uint }
  {
    shares: uint,
    token-x-deposited: uint,
    token-y-deposited: uint,
    entry-price-ratio: uint,
    last-harvest: uint,
    il-protection-eligible: bool
  }
)

(define-map oracle-providers
  { token: principal }
  {
    provider: principal,
    last-update: uint,
    price: uint
  }
)

(define-map volatility-tracking
  { token: principal }
  {
    price-samples: (list 20 uint),
    last-sample-time: uint,
    calculated-volatility: uint
  }
)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POOL-EXISTS (err u101))
(define-constant ERR-POOL-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-ZERO-AMOUNTS (err u104))
(define-constant ERR-ORACLE-NOT-FOUND (err u105))
(define-constant ERR-STALE-ORACLE (err u106))
(define-constant ERR-EMERGENCY-SHUTDOWN (err u107))
(define-constant ERR-SLIPPAGE-TOO-HIGH (err u108))
(define-constant ERR-MIN-LIQUIDITY (err u109))
(define-constant ERR-INVALID-PARAMS (err u110))
(define-constant ERR-POSITION-NOT-FOUND (err u111))

;; Read-only functions


(define-read-only (get-pool (pool-id uint))
  (map-get? pools-map { pool-id: pool-id })
)


(define-read-only (get-user-position (user principal) (pool-id uint))
  (map-get? user-positions { user: user, pool-id: pool-id })
)

(define-read-only (get-volatility (token principal))
  (default-to u0
    (match (map-get? volatility-tracking { token: token })
      volatility-data (some (get calculated-volatility volatility-data))
      none
    )
  )
)

(define-public (enable-il-protection (pool-id uint))
  (let ((position (unwrap! (map-get? user-positions { user: tx-sender, pool-id: pool-id }) ERR-POSITION-NOT-FOUND)))
   
    ;; Check minimum liquidity requirement (must have significant stake to enable protection)
    (asserts! (> (get shares position) (var-get minimum-liquidity)) ERR-MIN-LIQUIDITY)
   
    ;; Check if position has been held for minimum time (30 days in blocks ~4320 blocks)
    (asserts! (> (- stacks-block-height (get last-harvest position)) u4320) ERR-INVALID-PARAMS)
   
    ;; Enable protection
    (map-set user-positions
      { user: tx-sender, pool-id: pool-id }
      (merge position { il-protection-eligible: true })
    )
   
    (ok true)
  )
)

(define-public (toggle-emergency-shutdown (shutdown bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set emergency-shutdown shutdown)
    (ok shutdown)
  )
)

(define-public (set-pool-active (pool-id uint) (active bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
   
    (let ((pool (unwrap! (map-get? pools-map { pool-id: pool-id }) ERR-POOL-NOT-FOUND)))
      (map-set pools-map
        { pool-id: pool-id }
        (merge pool { active: active })
      )
     
      (ok active)
    )
  )
)

(define-public (update-protocol-parameters
  (new-protocol-fee (optional uint))
  (new-min-fee (optional uint))
  (new-max-fee (optional uint))
  (new-volatility-multiplier (optional uint))
  (new-oracle-stale-threshold (optional uint))
  (new-rebalance-threshold (optional uint))
  (new-il-protection-ratio (optional uint))
  (new-minimum-liquidity (optional uint))
)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
   
    ;; Update each parameter if provided
    (match new-protocol-fee fee (var-set protocol-fee fee) false)
    (match new-min-fee fee (var-set min-fee fee) false)
    (match new-max-fee fee (var-set max-fee fee) false)
    (match new-volatility-multiplier mult (var-set volatility-multiplier mult) false)
    (match new-oracle-stale-threshold threshold (var-set oracle-price-stale-threshold threshold) false)
    (match new-rebalance-threshold threshold (var-set rebalance-threshold threshold) false)
    (match new-il-protection-ratio ratio (var-set il-protection-ratio ratio) false)
    (match new-minimum-liquidity min (var-set minimum-liquidity min) false)
   
    (ok true)
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)


(define-private (max-diff (a uint) (b uint))
  (if (> a b) a b)
)

;; New Data Variables
(define-data-var governance-token principal .governance-token) ;; Added governance token
(define-data-var staking-rewards-rate uint u100) ;; 1% rewards rate
(define-data-var fee-rebate-rate uint u2000) ;; 20% fee rebate for stakers
(define-data-var min-stake-time uint u4320) ;; Minimum staking period (30 days in blocks)
(define-data-var auto-compound-enabled bool true) ;; Enable auto-compounding by default
(define-data-var referral-reward-rate uint u1000) ;; 10% referral rewards

;; Added new maps
(define-map staking-positions
  { user: principal }
  {
    amount: uint,
    start-time: uint,
    last-claim: uint,
    locked-until: uint
  }
)

(define-map pool-performance
  { pool-id: uint }
  {
    total-volume: uint,
    fees-collected: uint,
    all-time-apy: uint,
    weekly-apy: uint,
    daily-apy: uint
  }
)

(define-map user-preferences
  { user: principal }
  {
    slippage-tolerance: uint,
    auto-stake-rewards: bool,
    use-referral: (optional principal)
  }
)

;; New error constants
(define-constant ERR-LOCKED-POSITION (err u112))
(define-constant ERR-INVALID-STRATEGY (err u113))
(define-constant ERR-INVALID-RANGE (err u114))
(define-constant ERR-NO-REWARDS (err u115))
(define-constant ERR-INVALID-REFERRAL (err u116))

;; New read-only functions
(define-read-only (get-staking-position (user principal))
  (map-get? staking-positions { user: user })
)

(define-read-only (get-user-preferences (user principal))
  (default-to 
    { slippage-tolerance: u100, auto-stake-rewards: false, use-referral: none }
    (map-get? user-preferences { user: user })
  )
)

(define-read-only (calculate-apy (pool-id uint) (time-period uint))
  (match (map-get? pool-performance { pool-id: pool-id })
    performance
    (if (is-eq time-period u1) ;; daily
      (get daily-apy performance)
      (if (is-eq time-period u7) ;; weekly
        (get weekly-apy performance)
        (get all-time-apy performance) ;; all-time
      )
    )
    u0
  )
)

(define-public (set-user-preferences
  (slippage-tolerance (optional uint))
  (auto-stake-rewards (optional bool))
  (use-referral (optional principal))
)
  (let (
    (current-prefs (get-user-preferences tx-sender))
  )
    (map-set user-preferences
      { user: tx-sender }
      {
        slippage-tolerance: (default-to (get slippage-tolerance current-prefs) slippage-tolerance),
        auto-stake-rewards: (default-to (get auto-stake-rewards current-prefs) auto-stake-rewards),
        use-referral: (match use-referral
                        ref (some ref)
                        (get use-referral current-prefs))
      }
    )
    
    (ok true)
  )
)

;; Liquidity gauges for weighted rewards
(define-map liquidity-gauges
  { pool-id: uint }
  {
    weight: uint,
    emissions-rate: uint,
    total-staked: uint
  }
)

;; NFT boost system
(define-map nft-boost-multipliers
  { nft-id: uint }
  {
    boost: uint,
    expiry: uint
  }
)

;; Farm positions tracking
(define-map user-farm-positions
  { user: principal, farm-id: uint }
  {
    staked-amount: uint,
    rewards-claimed: uint,
    entry-block: uint
  }
)

;; Insurance fund rate
(define-data-var insurance-fund-rate uint u1000) ;; 10% of fees go to insurance fund

;; Daily volume cap for manipulation prevention
(define-data-var daily-volume-cap uint u1000000000000) ;; Cap on daily volume

;; Insurance claims system
(define-map insurance-claims
  { claim-id: uint }
  {
    user: principal,
    pool-id: uint,
    amount: uint,
    reason: (string-ascii 100),
    status: (string-ascii 20),
    created-at: uint
  }
)

;; Related error constant
(define-constant ERR-DAILY-CAP-REACHED (err u134))
(define-constant ERR-CLAIM-NOT-FOUND (err u135))

;; Strategy templates system
(define-map strategy-templates
  { strategy-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 100),
    risk-level: uint,
    leverage: uint,
    rebalance-frequency: uint,
    target-ratio: uint
  }
)

;; User strategies implementation
(define-map user-strategies
  { user: principal, pool-id: uint }
  {
    strategy-id: uint,
    custom-params: (optional {
      custom-ratio: uint,
      custom-rebalance: uint,
      min-profit-threshold: uint
    }),
    active: bool,
    last-execution: uint
  }
)

;; Governance parameters
(define-data-var dao-voting-threshold uint u5100) ;; 51% of governance tokens needed
(define-data-var time-lock-duration uint u14400) ;; Default 100 days time lock

;; Proposal system
(define-map dao-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    action: (string-ascii 50),
    param-name: (string-ascii 50),
    param-value: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20),
    deadline: uint
  }
)

;; Voting system
(define-map user-votes
  { user: principal, proposal-id: uint }
  {
    vote: bool,
    power: uint
  }
)

;; Error constants for governance
(define-constant ERR-PROPOSAL-NOT-FOUND (err u119))
(define-constant ERR-VOTING-ENDED (err u120))
(define-constant ERR-ALREADY-VOTED (err u121))
(define-constant ERR-TIMELOCK-ACTIVE (err u132))

;; Lending pools
(define-map lending-pools
  { token: principal }
  {
    total-supply: uint,
    total-borrowed: uint,
    interest-rate: uint,
    collateral-ratio: uint,
    max-utilization: uint
  }
)

;; Flash loans
(define-data-var flash-loan-fee uint u900) ;; 9% fee for flash loans
(define-map flash-loans
  { loan-id: uint }
  {
    borrower: principal,
    token: principal,
    amount: uint,
    fee: uint,
    timestamp: uint
  }
)

;; Farm pools for yield farming
(define-map farm-pools
  { farm-id: uint }
  {
    reward-token: principal,
    pool-id: uint,
    rewards-per-block: uint,
    total-staked: uint,
    start-block: uint,
    end-block: uint
  }
)

;; User borrowing positions
(define-map user-borrows
  { user: principal, token: principal }
  {
    amount: uint,
    collateral: uint,
    collateral-token: principal,
    timestamp: uint,
    liquidation-price: uint
  }
)

;; Whitelist system
(define-data-var whitelist-only bool false) ;; Flag to restrict to whitelisted users
(define-map whitelisted-users
  { user: principal }
  { status: bool }
)

;; Fee discount tiers
(define-map fee-discounts
  { tier: uint }
  {
    min-stake: uint,
    discount-rate: uint
  }
)

;; Vesting schedules
(define-map vesting-schedules
  { user: principal }
  {
    total-amount: uint,
    claimed-amount: uint,
    start-block: uint,
    cliff-block: uint,
    end-block: uint,
    revocable: bool
  }
)

;; Historical performance tracking
(define-map historical-performance
  { pool-id: uint, timestamp: uint }
  {
    price-ratio: uint,
    tvl: uint,
    volume: uint,
    fees: uint
  }
)
