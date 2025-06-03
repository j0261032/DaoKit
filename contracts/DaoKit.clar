(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_VOTING_ENDED (err u102))
(define-constant ERR_VOTING_ACTIVE (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INSUFFICIENT_TOKENS (err u105))
(define-constant ERR_INVALID_DURATION (err u106))
(define-constant ERR_MODULE_NOT_FOUND (err u107))
(define-constant ERR_MODULE_ALREADY_EXISTS (err u108))

(define-data-var proposal-counter uint u0)
(define-data-var dao-name (string-ascii 50) "")
(define-data-var min-proposal-threshold uint u1000)
(define-data-var voting-duration uint u1440)

(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool,
    module: (string-ascii 50)
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, power: uint }
)

(define-map member-tokens
  principal
  uint
)

(define-map dao-modules
  (string-ascii 50)
  {
    contract: principal,
    active: bool,
    admin: principal
  }
)

(define-map module-permissions
  { module: (string-ascii 50), permission: (string-ascii 50) }
  bool
)

(define-public (initialize-dao (name (string-ascii 50)) (threshold uint) (duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> duration u0) ERR_INVALID_DURATION)
    (var-set dao-name name)
    (var-set min-proposal-threshold threshold)
    (var-set voting-duration duration)
    (ok true)
  )
)

(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set member-tokens recipient 
      (+ (default-to u0 (map-get? member-tokens recipient)) amount))
    (ok true)
  )
)

(define-public (register-module (name (string-ascii 50)) (contract principal) (admin principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? dao-modules name)) ERR_MODULE_ALREADY_EXISTS)
    (map-set dao-modules name {
      contract: contract,
      active: true,
      admin: admin
    })
    (ok true)
  )
)

(define-public (toggle-module (name (string-ascii 50)))
  (let ((module-data (unwrap! (map-get? dao-modules name) ERR_MODULE_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get admin module-data))) ERR_UNAUTHORIZED)
    (map-set dao-modules name (merge module-data { active: (not (get active module-data)) }))
    (ok true)
  )
)

(define-public (set-module-permission (module (string-ascii 50)) (permission (string-ascii 50)) (allowed bool))
  (let ((module-data (unwrap! (map-get? dao-modules module) ERR_MODULE_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER)
                  (is-eq tx-sender (get admin module-data))) ERR_UNAUTHORIZED)
    (map-set module-permissions { module: module, permission: permission } allowed)
    (ok true)
  )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (module (string-ascii 50)))
  (let ((proposal-id (+ (var-get proposal-counter) u1))
        (member-balance (default-to u0 (map-get? member-tokens tx-sender))))
    (asserts! (>= member-balance (var-get min-proposal-threshold)) ERR_INSUFFICIENT_TOKENS)
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: title,
      description: description,
      start-block: stacks-block-height,
      end-block: (+ stacks-block-height (var-get voting-duration)),
      yes-votes: u0,
      no-votes: u0,
      executed: false,
      module: module
    })
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote (proposal-id uint) (support bool))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (voter-tokens (default-to u0 (map-get? member-tokens tx-sender))))
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get end-block proposal)) ERR_VOTING_ENDED)
    (asserts! (> voter-tokens u0) ERR_INSUFFICIENT_TOKENS)
    
    (map-set votes { proposal-id: proposal-id, voter: tx-sender } 
      { vote: support, power: voter-tokens })
    
    (if support
      (map-set proposals proposal-id 
        (merge proposal { yes-votes: (+ (get yes-votes proposal) voter-tokens) }))
      (map-set proposals proposal-id 
        (merge proposal { no-votes: (+ (get no-votes proposal) voter-tokens) })))
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND)))
    (asserts! (> stacks-block-height (get end-block proposal)) ERR_VOTING_ACTIVE)
    (asserts! (not (get executed proposal)) ERR_VOTING_ACTIVE)
    (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR_UNAUTHORIZED)
    
    (map-set proposals proposal-id (merge proposal { executed: true }))
    (ok true)
  )
)

(define-public (delegate-tokens (to principal) (amount uint))
  (let ((sender-balance (default-to u0 (map-get? member-tokens tx-sender))))
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_TOKENS)
    (map-set member-tokens tx-sender (- sender-balance amount))
    (map-set member-tokens to 
      (+ (default-to u0 (map-get? member-tokens to)) amount))
    (ok true)
  )
)

(define-read-only (get-dao-info)
  {
    name: (var-get dao-name),
    proposal-threshold: (var-get min-proposal-threshold),
    voting-duration: (var-get voting-duration),
    total-proposals: (var-get proposal-counter)
  }
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-member-tokens (member principal))
  (default-to u0 (map-get? member-tokens member))
)

(define-read-only (get-module (name (string-ascii 50)))
  (map-get? dao-modules name)
)

(define-read-only (has-module-permission (module (string-ascii 50)) (permission (string-ascii 50)))
  (default-to false (map-get? module-permissions { module: module, permission: permission }))
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
    (let ((current-block stacks-block-height))
      {
        active: (<= current-block (get end-block proposal)),
        passed: (> (get yes-votes proposal) (get no-votes proposal)),
        executed: (get executed proposal),
        total-votes: (+ (get yes-votes proposal) (get no-votes proposal))
      }
    )
    {
      active: false,
      passed: false,
      executed: false,
      total-votes: u0
    }
  )
)

(define-read-only (can-vote (proposal-id uint) (voter principal))
  (match (map-get? proposals proposal-id)
    proposal
    (and 
      (<= stacks-block-height (get end-block proposal))
      (is-none (map-get? votes { proposal-id: proposal-id, voter: voter }))
      (> (default-to u0 (map-get? member-tokens voter)) u0)
    )
    false
  )
)