
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

