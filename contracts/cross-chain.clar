;; Cross-Chain Messaging Contract
;; Handles cross-chain communication and bridge integrations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-MESSAGE (err u402))
(define-constant ERR-MESSAGE-EXPIRED (err u403))
(define-constant ERR-DUPLICATE-MESSAGE (err u404))
(define-constant ERR-INVALID-CHAIN (err u405))
(define-constant ERR-BRIDGE-NOT-FOUND (err u406))
(define-constant ERR-INSUFFICIENT-FEE (err u407))

;; Data Variables
(define-data-var message-nonce uint u1)
(define-data-var paused bool false)

;; Cross-chain message structure
(define-map cross-chain-messages
  { message-id: uint }
  {
    sender: principal,
    target-chain: (string-ascii 32),
    target-contract: (string-ascii 64),
    payload: (buff 1024),
    fee: uint,
    timestamp: uint,
    processed: bool,
    bridge-id: uint
  }
)

;; Bridge configurations
(define-map bridges
  { bridge-id: uint }
  {
    name: (string-ascii 32),
    supported-chains: (list 10 (string-ascii 32)),
    fee-rate: uint,
    min-fee: uint,
    active: bool,
    validator: principal
  }
)

;; Message validation records
(define-map message-validations
  { message-id: uint, validator: principal }
  { validated: bool, timestamp: uint }
)

;; Chain configurations
(define-map chain-configs
  { chain-name: (string-ascii 32) }
  {
    target-chain-id: uint,
    confirmation-blocks: uint,
    max-gas: uint,
    bridge-contract: (string-ascii 64),
    active: bool
  }
)

;; Admin Functions
(define-public (set-paused (new-paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set paused new-paused)
    (print { event: "cross-chain-paused", paused: new-paused })
    (ok true)
  )
)

(define-public (add-bridge 
  (bridge-id uint)
  (name (string-ascii 32))
  (supported-chains (list 10 (string-ascii 32)))
  (fee-rate uint)
  (min-fee uint)
  (validator principal)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? bridges { bridge-id: bridge-id })) ERR-DUPLICATE-MESSAGE)
    
    (map-set bridges { bridge-id: bridge-id }
      {
        name: name,
        supported-chains: supported-chains,
        fee-rate: fee-rate,
        min-fee: min-fee,
        active: true,
        validator: validator
      }
    )
    
    (print {
      event: "bridge-added",
      bridge-id: bridge-id,
      name: name,
      validator: validator
    })
    
    (ok true)
  )
)

(define-public (add-chain-config
  (chain-name (string-ascii 32))
  (target-chain-id uint)
  (confirmation-blocks uint)
  (max-gas uint)
  (bridge-contract (string-ascii 64))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (map-set chain-configs { chain-name: chain-name }
      {
        target-chain-id: target-chain-id,
        confirmation-blocks: confirmation-blocks,
        max-gas: max-gas,
        bridge-contract: bridge-contract,
        active: true
      }
    )
    
    (print {
      event: "chain-config-added",
      chain-name: chain-name,
      target-chain-id: target-chain-id
    })
    
    (ok true)
  )
)

;; Message Functions
(define-public (send-cross-chain-message
  (target-chain (string-ascii 32))
  (target-contract (string-ascii 64))
  (payload (buff 1024))
  (bridge-id uint)
)
  (let (
    (message-id (var-get message-nonce))
    (bridge-info (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-BRIDGE-NOT-FOUND))
    (chain-config (unwrap! (map-get? chain-configs { chain-name: target-chain }) ERR-INVALID-CHAIN))
  )
    (asserts! (not (var-get paused)) ERR-UNAUTHORIZED)
    (asserts! (get active bridge-info) ERR-BRIDGE-NOT-FOUND)
    (asserts! (get active chain-config) ERR-INVALID-CHAIN)
    (asserts! (is-some (index-of (get supported-chains bridge-info) target-chain)) ERR-INVALID-CHAIN)
    
    (let (
      (calculated-fee (calculate-bridge-fee (len payload) bridge-id target-chain))
    )
      (asserts! (>= calculated-fee (get min-fee bridge-info)) ERR-INSUFFICIENT-FEE)
      
      ;; Store message
      (map-set cross-chain-messages { message-id: message-id }
        {
          sender: tx-sender,
          target-chain: target-chain,
          target-contract: target-contract,
          payload: payload,
          fee: calculated-fee,
          timestamp: stacks-block-height,
          processed: false,
          bridge-id: bridge-id
        }
      )
      
      ;; Increment nonce
      (var-set message-nonce (+ message-id u1))
      
      (print {
        event: "cross-chain-message-sent",
        message-id: message-id,
        sender: tx-sender,
        target-chain: target-chain,
        target-contract: target-contract,
        fee: calculated-fee,
        bridge-id: bridge-id
      })
      
      (ok message-id)
    )
  )
)

(define-public (validate-message 
  (message-id uint)
  (validator-signature (buff 65))
)
  (let (
    (message-info (unwrap! (map-get? cross-chain-messages { message-id: message-id }) ERR-INVALID-MESSAGE))
    (bridge-info (unwrap! (map-get? bridges { bridge-id: (get bridge-id message-info) }) ERR-BRIDGE-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get validator bridge-info)) ERR-UNAUTHORIZED)
    (asserts! (not (get processed message-info)) ERR-DUPLICATE-MESSAGE)
    
    ;; Record validation
    (map-set message-validations 
      { message-id: message-id, validator: tx-sender }
      { validated: true, timestamp: stacks-block-height }
    )
    
    (print {
      event: "message-validated",
      message-id: message-id,
      validator: tx-sender,
      timestamp: stacks-block-height
    })
    
    (ok true)
  )
)

(define-public (process-message (message-id uint))
  (let (
    (message-info (unwrap! (map-get? cross-chain-messages { message-id: message-id }) ERR-INVALID-MESSAGE))
    (bridge-info (unwrap! (map-get? bridges { bridge-id: (get bridge-id message-info) }) ERR-BRIDGE-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get validator bridge-info)) ERR-UNAUTHORIZED)
    (asserts! (not (get processed message-info)) ERR-DUPLICATE-MESSAGE)
    
    ;; Check if message is validated
    (asserts! (is-some (map-get? message-validations { message-id: message-id, validator: tx-sender })) ERR-INVALID-MESSAGE)
    
    ;; Mark as processed
    (map-set cross-chain-messages { message-id: message-id }
      (merge message-info { processed: true })
    )
    
    (print {
      event: "message-processed",
      message-id: message-id,
      target-chain: (get target-chain message-info),
      target-contract: (get target-contract message-info)
    })
    
    (ok true)
  )
)

;; Queue management for batched processing
(define-public (batch-process-messages (message-ids (list 50 uint)))
  (let (
    (results (map process-single-message message-ids))
  )
    (print {
      event: "batch-processed",
      count: (len message-ids),
      timestamp: stacks-block-height
    })
    (ok results)
  )
)

;; Read-Only Functions
(define-read-only (get-message (message-id uint))
  (map-get? cross-chain-messages { message-id: message-id })
)

(define-read-only (get-bridge (bridge-id uint))
  (map-get? bridges { bridge-id: bridge-id })
)

(define-read-only (get-chain-config (chain-name (string-ascii 32)))
  (map-get? chain-configs { chain-name: chain-name })
)

(define-read-only (get-message-validation (message-id uint) (validator principal))
  (map-get? message-validations { message-id: message-id, validator: validator })
)

(define-read-only (calculate-bridge-fee (payload-size uint) (bridge-id uint) (target-chain (string-ascii 32)))
  (let (
    (bridge-info (unwrap! (map-get? bridges { bridge-id: bridge-id }) u0))
    (base-fee (get min-fee bridge-info))
    (variable-fee (/ (* payload-size (get fee-rate bridge-info)) u1000))
  )
    (+ base-fee variable-fee)
  )
)

(define-read-only (get-supported-chains (bridge-id uint))
  (match (map-get? bridges { bridge-id: bridge-id })
    bridge-info (get supported-chains bridge-info)
    (list)
  )
)

(define-read-only (is-chain-supported (bridge-id uint) (chain-name (string-ascii 32)))
  (match (map-get? bridges { bridge-id: bridge-id })
    bridge-info (is-some (index-of (get supported-chains bridge-info) chain-name))
    false
  )
)

(define-read-only (get-next-message-id)
  (var-get message-nonce)
)

(define-read-only (is-paused)
  (var-get paused)
)

;; Private helper functions
(define-private (process-single-message (message-id uint))
  (match (process-message message-id)
    success true
    error false
  )
)

(define-private (is-message-expired (message-id uint) (expiry-blocks uint))
  (let (
    (message-info (unwrap! (map-get? cross-chain-messages { message-id: message-id }) true))
    (message-timestamp (get timestamp message-info))
  )
    (> stacks-block-height (+ message-timestamp expiry-blocks))
  )
)