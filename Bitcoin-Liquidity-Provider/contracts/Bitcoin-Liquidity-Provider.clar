
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

