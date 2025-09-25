;; Cross-Chain sBTC Liquidity Router
;; A decentralized liquidity routing protocol for sBTC with MEV protection

;; SIP-010 Trait Definition
(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u403))
(define-constant ERR-POOL-NOT-FOUND (err u404))
(define-constant ERR-POOL-ALREADY-EXISTS (err u405))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u406))
(define-constant ERR-PAUSED (err u407))
(define-constant ERR-INVALID-CHAIN (err u408))

;; Data Variables
(define-data-var paused bool false)
(define-data-var fee-rate uint u300) ;; 3% default fee (30/1000)
(define-data-var next-pool-id uint u1)

;; Pool Structure
(define-map pools 
  { pool-id: uint }
  {
    token-a: principal,
    token-b: principal,
    reserve-a: uint,
    reserve-b: uint,
    total-supply: uint,
    chain: (string-ascii 32),
    active: bool
  }
)

;; Pool ID mapping for easy lookup
(define-map pool-lookup
  { token-a: principal, token-b: principal, chain: (string-ascii 32) }
  { pool-id: uint }
)

;; Liquidity provider balances
(define-map lp-balances
  { pool-id: uint, provider: principal }
  { balance: uint }
)

;; Cross-chain routing data
(define-map chain-routes
  { from-chain: (string-ascii 32), to-chain: (string-ascii 32) }
  { 
    fee-multiplier: uint,
    min-amount: uint,
    max-amount: uint,
    active: bool
  }
)

;; Events
(define-data-var last-event-id uint u0)

;; Admin Functions
(define-public (set-paused (new-paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set paused new-paused)
    (print { event: "paused-changed", paused: new-paused })
    (ok true)
  )
)

(define-public (set-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT) ;; Max 100%
    (var-set fee-rate new-rate)
    (print { event: "fee-rate-changed", rate: new-rate })
    (ok true)
  )
)

;; Pool Management Functions
(define-public (create-pool 
  (token-a <sip-010-trait>) 
  (token-b <sip-010-trait>) 
  (initial-a uint) 
  (initial-b uint)
  (chain (string-ascii 32))
)
  (let (
    (pool-id (var-get next-pool-id))
    (token-a-principal (contract-of token-a))
    (token-b-principal (contract-of token-b))
  )
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (> initial-a u0) ERR-INVALID-AMOUNT)
    (asserts! (> initial-b u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq token-a-principal token-b-principal)) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? pool-lookup { token-a: token-a-principal, token-b: token-b-principal, chain: chain })) ERR-POOL-ALREADY-EXISTS)
    
    ;; Transfer tokens to contract
    (try! (contract-call? token-a transfer initial-a tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-b transfer initial-b tx-sender (as-contract tx-sender) none))
    
    ;; Calculate initial liquidity (simple geometric mean approximation)
    (let ((initial-liquidity (/ (+ initial-a initial-b) u2)))
      ;; Create pool
      (map-set pools 
        { pool-id: pool-id }
        {
          token-a: token-a-principal,
          token-b: token-b-principal,
          reserve-a: initial-a,
          reserve-b: initial-b,
          total-supply: initial-liquidity,
          chain: chain,
          active: true
        }
      )
      
      ;; Set pool lookup
      (map-set pool-lookup
        { token-a: token-a-principal, token-b: token-b-principal, chain: chain }
        { pool-id: pool-id }
      )
      
      ;; Set LP balance
      (map-set lp-balances
        { pool-id: pool-id, provider: tx-sender }
        { balance: initial-liquidity }
      )
      
      ;; Increment pool ID counter
      (var-set next-pool-id (+ pool-id u1))
      
      (print { 
        event: "pool-created", 
        pool-id: pool-id, 
        token-a: token-a-principal, 
        token-b: token-b-principal,
        chain: chain,
        liquidity: initial-liquidity
      })
      
      (ok pool-id)
    )
  )
)

;; Swap Functions
(define-public (swap-exact-tokens-for-tokens
  (token-in <sip-010-trait>)
  (token-out <sip-010-trait>)
  (amount-in uint)
  (amount-out-min uint)
  (chain (string-ascii 32))
)
  (let (
    (token-in-principal (contract-of token-in))
    (token-out-principal (contract-of token-out))
    (pool-data (unwrap! (get-pool-by-tokens token-in-principal token-out-principal chain) ERR-POOL-NOT-FOUND))
    (pool-id (get pool-id pool-data))
    (pool-info (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
  )
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (> amount-in u0) ERR-INVALID-AMOUNT)
    (asserts! (get active pool-info) ERR-POOL-NOT-FOUND)
    
    (let (
      (is-token-a-in (is-eq token-in-principal (get token-a pool-info)))
      (reserve-in (if is-token-a-in (get reserve-a pool-info) (get reserve-b pool-info)))
      (reserve-out (if is-token-a-in (get reserve-b pool-info) (get reserve-a pool-info)))
      (amount-out (calculate-amount-out amount-in reserve-in reserve-out))
    )
      (asserts! (>= amount-out amount-out-min) ERR-SLIPPAGE-EXCEEDED)
      (asserts! (> reserve-out amount-out) ERR-INSUFFICIENT-LIQUIDITY)
      
      ;; Transfer tokens
      (try! (contract-call? token-in transfer amount-in tx-sender (as-contract tx-sender) none))
      (try! (as-contract (contract-call? token-out transfer amount-out tx-sender tx-sender none)))
      
      ;; Update pool reserves
      (map-set pools { pool-id: pool-id }
        (merge pool-info {
          reserve-a: (if is-token-a-in (+ (get reserve-a pool-info) amount-in) (- (get reserve-a pool-info) amount-out)),
          reserve-b: (if is-token-a-in (- (get reserve-b pool-info) amount-out) (+ (get reserve-b pool-info) amount-in))
        })
      )
      
      (print {
        event: "swap",
        pool-id: pool-id,
        amount-in: amount-in,
        amount-out: amount-out,
        chain: chain,
        trader: tx-sender
      })
      
      (ok amount-out)
    )
  )
)

;; Add Liquidity
(define-public (add-liquidity
  (token-a <sip-010-trait>)
  (token-b <sip-010-trait>)
  (amount-a uint)
  (amount-b uint)
  (chain (string-ascii 32))
)
  (let (
    (token-a-principal (contract-of token-a))
    (token-b-principal (contract-of token-b))
    (pool-data (unwrap! (get-pool-by-tokens token-a-principal token-b-principal chain) ERR-POOL-NOT-FOUND))
    (pool-id (get pool-id pool-data))
    (pool-info (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
  )
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (> amount-a u0) ERR-INVALID-AMOUNT)
    (asserts! (> amount-b u0) ERR-INVALID-AMOUNT)
    (asserts! (get active pool-info) ERR-POOL-NOT-FOUND)
    
    (let (
      (reserve-a (get reserve-a pool-info))
      (reserve-b (get reserve-b pool-info))
      (total-supply (get total-supply pool-info))
      (liquidity (min 
        (/ (* amount-a total-supply) reserve-a)
        (/ (* amount-b total-supply) reserve-b)
      ))
    )
      (asserts! (> liquidity u0) ERR-INVALID-AMOUNT)
      
      ;; Transfer tokens
      (try! (contract-call? token-a transfer amount-a tx-sender (as-contract tx-sender) none))
      (try! (contract-call? token-b transfer amount-b tx-sender (as-contract tx-sender) none))
      
      ;; Update pool
      (map-set pools { pool-id: pool-id }
        (merge pool-info {
          reserve-a: (+ reserve-a amount-a),
          reserve-b: (+ reserve-b amount-b),
          total-supply: (+ total-supply liquidity)
        })
      )
      
      ;; Update LP balance
      (let ((current-balance (default-to u0 (get balance (map-get? lp-balances { pool-id: pool-id, provider: tx-sender })))))
        (map-set lp-balances
          { pool-id: pool-id, provider: tx-sender }
          { balance: (+ current-balance liquidity) }
        )
      )
      
      (print {
        event: "liquidity-added",
        pool-id: pool-id,
        amount-a: amount-a,
        amount-b: amount-b,
        liquidity: liquidity,
        provider: tx-sender
      })
      
      (ok liquidity)
    )
  )
)

;; Cross-Chain Route Management
(define-public (add-chain-route
  (from-chain (string-ascii 32))
  (to-chain (string-ascii 32))
  (fee-multiplier uint)
  (min-amount uint)
  (max-amount uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (not (is-eq from-chain to-chain)) ERR-INVALID-CHAIN)
    
    (map-set chain-routes
      { from-chain: from-chain, to-chain: to-chain }
      {
        fee-multiplier: fee-multiplier,
        min-amount: min-amount,
        max-amount: max-amount,
        active: true
      }
    )
    
    (print {
      event: "chain-route-added",
      from-chain: from-chain,
      to-chain: to-chain,
      fee-multiplier: fee-multiplier
    })
    
    (ok true)
  )
)

;; Read-Only Functions
(define-read-only (get-pool (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

(define-read-only (get-pool-by-tokens (token-a principal) (token-b principal) (chain (string-ascii 32)))
  (map-get? pool-lookup { token-a: token-a, token-b: token-b, chain: chain })
)

(define-read-only (get-lp-balance (pool-id uint) (provider principal))
  (default-to u0 (get balance (map-get? lp-balances { pool-id: pool-id, provider: provider })))
)

(define-read-only (get-chain-route (from-chain (string-ascii 32)) (to-chain (string-ascii 32)))
  (map-get? chain-routes { from-chain: from-chain, to-chain: to-chain })
)

(define-read-only (calculate-amount-out (amount-in uint) (reserve-in uint) (reserve-out uint))
  (let (
    (fee (var-get fee-rate))
    (amount-in-with-fee (- amount-in (/ (* amount-in fee) u1000)))
    (numerator (* amount-in-with-fee reserve-out))
    (denominator (+ reserve-in amount-in-with-fee))
  )
    (/ numerator denominator)
  )
)

(define-read-only (get-optimal-route 
  (amount uint) 
  (from-chain (string-ascii 32)) 
  (to-chain (string-ascii 32))
)
  (let (
    (route (map-get? chain-routes { from-chain: from-chain, to-chain: to-chain }))
  )
    (match route
      route-data {
        fee-multiplier: (get fee-multiplier route-data),
        estimated-fee: (/ (* amount (get fee-multiplier route-data)) u1000),
        min-amount: (get min-amount route-data),
        max-amount: (get max-amount route-data),
        active: (get active route-data)
      }
      { fee-multiplier: u0, estimated-fee: u0, min-amount: u0, max-amount: u0, active: false }
    )
  )
)

(define-read-only (is-paused)
  (var-get paused)
)

(define-read-only (get-fee-rate)
  (var-get fee-rate)
)

;; Private helper functions
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

