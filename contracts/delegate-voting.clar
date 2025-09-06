;; DaoKit Delegate Voting Module
;; Allows members to delegate their voting power to trusted representatives

(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_DELEGATE (err u201))
(define-constant ERR_DELEGATION_NOT_FOUND (err u202))
(define-constant ERR_SELF_DELEGATION (err u203))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u204))
(define-constant ERR_ALREADY_VOTED (err u205))
(define-constant ERR_INVALID_CATEGORY (err u206))
(define-constant ERR_DELEGATION_EXPIRED (err u207))

;; Data variables
(define-data-var delegation-counter uint u0)

;; Maps for delegation management
(define-map member-delegates
  { delegator: principal, category: (string-ascii 30) }
  { 
    delegate: principal,
    delegation-power: uint,
    expires-at: uint,
    active: bool,
    created-at: uint
  }
)

(define-map delegate-portfolio
  principal
  {
    total-delegated-power: uint,
    active-delegations: uint,
    categories: (list 10 (string-ascii 30)),
    reputation-score: uint
  }
)

(define-map delegation-votes
  { proposal-id: uint, delegate: principal }
  {
    vote-choice: bool,
    delegated-power: uint,
    voted-at: uint,
    delegators-count: uint
  }
)

(define-map proposal-delegation-stats
  uint
  {
    total-delegated-votes: uint,
    direct-votes: uint,
    delegate-participation: uint
  }
)

;; Create or update delegation
(define-public (delegate-voting-power 
  (delegate principal) 
  (category (string-ascii 30)) 
  (power-percentage uint) 
  (duration-blocks uint))
  (let (
    (member-tokens (contract-call? .DaoKit get-member-tokens tx-sender))
    (delegation-power (/ (* member-tokens power-percentage) u100))
    (expires-at (+ stacks-block-height duration-blocks))
  )
    ;; Validations
    (asserts! (not (is-eq tx-sender delegate)) ERR_SELF_DELEGATION)
    (asserts! (> member-tokens u0) ERR_UNAUTHORIZED)
    (asserts! (and (> power-percentage u0) (<= power-percentage u100)) ERR_INVALID_DELEGATE)
    (asserts! (> duration-blocks u144) ERR_INVALID_CATEGORY) ;; Min 1 day
    
    ;; Store delegation
    (map-set member-delegates 
      { delegator: tx-sender, category: category }
      {
        delegate: delegate,
        delegation-power: delegation-power,
        expires-at: expires-at,
        active: true,
        created-at: stacks-block-height
      })
    
    ;; Update delegate portfolio
    (match (map-get? delegate-portfolio delegate)
      existing-portfolio
      (map-set delegate-portfolio delegate
        (merge existing-portfolio {
          total-delegated-power: (+ (get total-delegated-power existing-portfolio) delegation-power),
          active-delegations: (+ (get active-delegations existing-portfolio) u1)
        }))
      (map-set delegate-portfolio delegate {
        total-delegated-power: delegation-power,
        active-delegations: u1,
        categories: (list category),
        reputation-score: u100
      })
    )
    
    (var-set delegation-counter (+ (var-get delegation-counter) u1))
    (ok true)
  )
)

;; Revoke delegation
(define-public (revoke-delegation (category (string-ascii 30)))
  (let (
    (delegation-info (unwrap! (map-get? member-delegates { delegator: tx-sender, category: category }) ERR_DELEGATION_NOT_FOUND))
    (delegate (get delegate delegation-info))
    (power (get delegation-power delegation-info))
  )
    ;; Deactivate delegation
    (map-set member-delegates 
      { delegator: tx-sender, category: category }
      (merge delegation-info { active: false }))
    
    ;; Update delegate portfolio
    (match (map-get? delegate-portfolio delegate)
      portfolio
      (map-set delegate-portfolio delegate
        (merge portfolio {
          total-delegated-power: (- (get total-delegated-power portfolio) power),
          active-delegations: (- (get active-delegations portfolio) u1)
        }))
      false ;; Portfolio should exist
    )
    (ok true)
  )
)

;; Delegate votes on behalf of delegators  
(define-public (cast-delegated-vote (proposal-id uint) (vote-choice bool))
  (let (
    (proposal (unwrap! (contract-call? .DaoKit get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
    (delegate-power u100) ;; Simplified - would calculate actual power from delegations
    (delegators-count u1) ;; Simplified count
  )
    ;; Check if delegate has already voted
    (asserts! (is-none (map-get? delegation-votes { proposal-id: proposal-id, delegate: tx-sender })) ERR_ALREADY_VOTED)
    (asserts! (> delegate-power u0) ERR_UNAUTHORIZED)
    
    ;; Record delegated vote
    (map-set delegation-votes 
      { proposal-id: proposal-id, delegate: tx-sender }
      {
        vote-choice: vote-choice,
        delegated-power: delegate-power,
        voted-at: stacks-block-height,
        delegators-count: delegators-count
      })
    
    ;; Update proposal stats
    (match (map-get? proposal-delegation-stats proposal-id)
      existing-stats
      (map-set proposal-delegation-stats proposal-id
        (merge existing-stats {
          total-delegated-votes: (+ (get total-delegated-votes existing-stats) delegate-power),
          delegate-participation: (+ (get delegate-participation existing-stats) u1)
        }))
      (map-set proposal-delegation-stats proposal-id {
        total-delegated-votes: delegate-power,
        direct-votes: u0,
        delegate-participation: u1
      })
    )
    
    (ok true)
  )
)

;; Update delegate reputation based on voting performance
(define-public (update-delegate-reputation (delegate principal) (score-change int))
  (let (
    (portfolio (unwrap! (map-get? delegate-portfolio delegate) ERR_INVALID_DELEGATE))
    (current-score (get reputation-score portfolio))
    (new-score (if (> score-change 0)
                 (+ current-score (to-uint score-change))
                 (if (>= current-score (to-uint (* score-change -1)))
                   (- current-score (to-uint (* score-change -1)))
                   u0)))
  )
    ;; Only delegate can update their own reputation
    (asserts! (is-eq tx-sender delegate) ERR_UNAUTHORIZED)
    
    (map-set delegate-portfolio delegate
      (merge portfolio { reputation-score: new-score }))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-delegation-info (delegator principal) (category (string-ascii 30)))
  (map-get? member-delegates { delegator: delegator, category: category })
)

(define-read-only (get-delegate-portfolio (delegate principal))
  (map-get? delegate-portfolio delegate)
)

(define-read-only (get-proposal-delegation-stats (proposal-id uint))
  (map-get? proposal-delegation-stats proposal-id)
)

(define-read-only (calculate-delegate-power (delegate principal) (category (string-ascii 50)))
  ;; Sum up all active delegations for this delegate in this category
  (fold calculate-delegation-power 
    (list tx-sender) ;; Simplified - in practice would iterate through all delegators
    u0)
)

(define-read-only (count-active-delegators (delegate principal) (category (string-ascii 50)))
  ;; Count active delegations for this delegate in this category
  ;; Simplified implementation - in practice would use external indexing
  u1
)

(define-read-only (is-delegation-active (delegator principal) (category (string-ascii 30)))
  (match (map-get? member-delegates { delegator: delegator, category: category })
    delegation
    (and (get active delegation) (> (get expires-at delegation) stacks-block-height))
    false
  )
)

;; Helper functions
(define-private (calculate-delegation-power (delegator principal) (current-total uint))
  ;; Helper to calculate total delegation power - simplified
  current-total
)

(define-read-only (get-delegation-summary)
  {
    total-delegations: (var-get delegation-counter),
    active-delegates: u0 ;; Would require external indexing for accurate count
  }
)
