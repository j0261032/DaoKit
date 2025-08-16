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
(define-constant ERR_BUDGET_NOT_FOUND (err u109))
(define-constant ERR_BUDGET_ALREADY_EXISTS (err u110))
(define-constant ERR_INSUFFICIENT_TREASURY (err u111))
(define-constant ERR_PAYMENT_NOT_FOUND (err u112))
(define-constant ERR_PAYMENT_ALREADY_EXECUTED (err u113))
(define-constant ERR_PAYMENT_NOT_DUE (err u114))
(define-constant ERR_INVALID_AMOUNT (err u115))
(define-constant ERR_BUDGET_EXCEEDED (err u116))
(define-constant ERR_ACHIEVEMENT_NOT_FOUND (err u117))
(define-constant ERR_ACHIEVEMENT_ALREADY_EXISTS (err u118))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u119))
(define-constant ERR_INVALID_MERIT_POINTS (err u120))
(define-constant ERR_MEMBER_NOT_FOUND (err u121))
(define-constant ERR_INVALID_CATEGORY (err u122))

(define-data-var proposal-counter uint u0)
(define-data-var dao-name (string-ascii 50) "")
(define-data-var min-proposal-threshold uint u1000)
(define-data-var voting-duration uint u1440)
(define-data-var treasury-balance uint u0)
(define-data-var budget-counter uint u0)
(define-data-var payment-counter uint u0)
(define-data-var achievement-counter uint u0)
(define-data-var reputation-multiplier uint u100)

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

(define-map treasury-budgets
  uint
  {
    name: (string-ascii 50),
    allocated-amount: uint,
    spent-amount: uint,
    period-start: uint,
    period-end: uint,
    category: (string-ascii 30),
    manager: principal,
    active: bool
  }
)

(define-map scheduled-payments
  uint
  {
    recipient: principal,
    amount: uint,
    due-block: uint,
    budget-id: uint,
    description: (string-ascii 100),
    executed: bool,
    recurring: bool,
    interval: uint
  }
)

(define-map treasury-transactions
  uint
  {
    transaction-type: (string-ascii 20),
    amount: uint,
    block-height: uint,
    related-entity: principal,
    description: (string-ascii 100),
    budget-id: (optional uint)
  }
)

(define-map member-reputation
  principal
  {
    total-points: uint,
    governance-points: uint,
    contribution-points: uint,
    achievement-count: uint,
    join-block: uint,
    last-activity: uint,
    reputation-level: uint
  }
)

(define-map achievements
  uint
  {
    name: (string-ascii 50),
    description: (string-ascii 100),
    category: (string-ascii 30),
    points-reward: uint,
    requirements: (string-ascii 100),
    active: bool,
    created-by: principal
  }
)

(define-map member-achievements
  { member: principal, achievement-id: uint }
  {
    earned-block: uint,
    points-earned: uint,
    verified: bool
  }
)

(define-map reputation-activities
  uint
  {
    member: principal,
    activity-type: (string-ascii 30),
    points-change: uint,
    block-height: uint,
    description: (string-ascii 100),
    related-proposal: (optional uint)
  }
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

(define-public (deposit-treasury (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (map-set treasury-transactions 
      (+ (var-get proposal-counter) u1)
      {
        transaction-type: "deposit",
        amount: amount,
        block-height: stacks-block-height,
        related-entity: tx-sender,
        description: "Treasury deposit",
        budget-id: none
      })
    (ok true)
  )
)

(define-public (create-budget (name (string-ascii 50)) (amount uint) (period-duration uint) (category (string-ascii 30)) (manager principal))
  (let ((budget-id (+ (var-get budget-counter) u1)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> period-duration u0) ERR_INVALID_DURATION)
    (asserts! (is-none (map-get? treasury-budgets budget-id)) ERR_BUDGET_ALREADY_EXISTS)
    (asserts! (>= (var-get treasury-balance) amount) ERR_INSUFFICIENT_TREASURY)
    
    (map-set treasury-budgets budget-id {
      name: name,
      allocated-amount: amount,
      spent-amount: u0,
      period-start: stacks-block-height,
      period-end: (+ stacks-block-height period-duration),
      category: category,
      manager: manager,
      active: true
    })
    (var-set budget-counter budget-id)
    (ok budget-id)
  )
)

(define-public (allocate-budget-funds (budget-id uint) (additional-amount uint))
  (let ((budget (unwrap! (map-get? treasury-budgets budget-id) ERR_BUDGET_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get manager budget))) ERR_UNAUTHORIZED)
    (asserts! (> additional-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get treasury-balance) additional-amount) ERR_INSUFFICIENT_TREASURY)
    
    (map-set treasury-budgets budget-id 
      (merge budget { allocated-amount: (+ (get allocated-amount budget) additional-amount) }))
    (ok true)
  )
)

(define-public (spend-from-budget (budget-id uint) (amount uint) (recipient principal) (description (string-ascii 100)))
  (let ((budget (unwrap! (map-get? treasury-budgets budget-id) ERR_BUDGET_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get manager budget))) ERR_UNAUTHORIZED)
    (asserts! (get active budget) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= (+ (get spent-amount budget) amount) (get allocated-amount budget)) ERR_BUDGET_EXCEEDED)
    (asserts! (>= (var-get treasury-balance) amount) ERR_INSUFFICIENT_TREASURY)
    
    (map-set treasury-budgets budget-id 
      (merge budget { spent-amount: (+ (get spent-amount budget) amount) }))
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    
    (map-set treasury-transactions 
      (+ (var-get proposal-counter) u1)
      {
        transaction-type: "spend",
        amount: amount,
        block-height: stacks-block-height,
        related-entity: recipient,
        description: description,
        budget-id: (some budget-id)
      })
    (ok true)
  )
)

(define-public (schedule-payment (recipient principal) (amount uint) (due-block uint) (budget-id uint) (description (string-ascii 100)) (recurring bool) (interval uint))
  (let ((payment-id (+ (var-get payment-counter) u1))
        (budget (unwrap! (map-get? treasury-budgets budget-id) ERR_BUDGET_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get manager budget))) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> due-block stacks-block-height) ERR_INVALID_DURATION)
    (asserts! (<= (+ (get spent-amount budget) amount) (get allocated-amount budget)) ERR_BUDGET_EXCEEDED)
    
    (map-set scheduled-payments payment-id {
      recipient: recipient,
      amount: amount,
      due-block: due-block,
      budget-id: budget-id,
      description: description,
      executed: false,
      recurring: recurring,
      interval: interval
    })
    (var-set payment-counter payment-id)
    (ok payment-id)
  )
)

(define-public (execute-scheduled-payment (payment-id uint))
  (let ((payment (unwrap! (map-get? scheduled-payments payment-id) ERR_PAYMENT_NOT_FOUND))
        (budget (unwrap! (map-get? treasury-budgets (get budget-id payment)) ERR_BUDGET_NOT_FOUND)))
    (asserts! (not (get executed payment)) ERR_PAYMENT_ALREADY_EXECUTED)
    (asserts! (>= stacks-block-height (get due-block payment)) ERR_PAYMENT_NOT_DUE)
    (asserts! (>= (var-get treasury-balance) (get amount payment)) ERR_INSUFFICIENT_TREASURY)
    
    (map-set treasury-budgets (get budget-id payment)
      (merge budget { spent-amount: (+ (get spent-amount budget) (get amount payment)) }))
    (var-set treasury-balance (- (var-get treasury-balance) (get amount payment)))
    
    (if (get recurring payment)
      (map-set scheduled-payments payment-id 
        (merge payment { 
          due-block: (+ (get due-block payment) (get interval payment)),
          executed: false
        }))
      (map-set scheduled-payments payment-id 
        (merge payment { executed: true })))
    
    (map-set treasury-transactions 
      (+ (var-get proposal-counter) u1)
      {
        transaction-type: "scheduled",
        amount: (get amount payment),
        block-height: stacks-block-height,
        related-entity: (get recipient payment),
        description: (get description payment),
        budget-id: (some (get budget-id payment))
      })
    (ok true)
  )
)

(define-public (toggle-budget-status (budget-id uint))
  (let ((budget (unwrap! (map-get? treasury-budgets budget-id) ERR_BUDGET_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get manager budget))) ERR_UNAUTHORIZED)
    (map-set treasury-budgets budget-id 
      (merge budget { active: (not (get active budget)) }))
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get treasury-balance) amount) ERR_INSUFFICIENT_TREASURY)
    
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    (map-set treasury-transactions 
      (+ (var-get proposal-counter) u1)
      {
        transaction-type: "emergency",
        amount: amount,
        block-height: stacks-block-height,
        related-entity: tx-sender,
        description: "Emergency withdrawal",
        budget-id: none
      })
    (ok true)
  )
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-budget (budget-id uint))
  (map-get? treasury-budgets budget-id)
)

(define-read-only (get-payment (payment-id uint))
  (map-get? scheduled-payments payment-id)
)

(define-read-only (get-budget-utilization (budget-id uint))
  (match (map-get? treasury-budgets budget-id)
    budget
    {
      allocated: (get allocated-amount budget),
      spent: (get spent-amount budget),
      remaining: (- (get allocated-amount budget) (get spent-amount budget)),
      utilization-rate: (if (> (get allocated-amount budget) u0)
                          (/ (* (get spent-amount budget) u100) (get allocated-amount budget))
                          u0)
    }
    {
      allocated: u0,
      spent: u0,
      remaining: u0,
      utilization-rate: u0
    }
  )
)

(define-read-only (get-treasury-summary)
  {
    total-balance: (var-get treasury-balance),
    total-budgets: (var-get budget-counter),
    total-payments: (var-get payment-counter)
  }
)

(define-read-only (get-budget-status (budget-id uint))
  (match (map-get? treasury-budgets budget-id)
    budget
    {
      active: (get active budget),
      expired: (> stacks-block-height (get period-end budget)),
      funds-available: (> (get allocated-amount budget) (get spent-amount budget)),
      manager: (get manager budget)
    }
    {
      active: false,
      expired: true,
      funds-available: false,
      manager: CONTRACT_OWNER
    }
  )
)

(define-public (register-member (member principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? member-reputation member)) ERR_MEMBER_NOT_FOUND)
    (map-set member-reputation member {
      total-points: u0,
      governance-points: u0,
      contribution-points: u0,
      achievement-count: u0,
      join-block: stacks-block-height,
      last-activity: stacks-block-height,
      reputation-level: u1
    })
    (ok true)
  )
)

(define-public (create-achievement (name (string-ascii 50)) (description (string-ascii 100)) (category (string-ascii 30)) (points-reward uint) (requirements (string-ascii 100)))
  (let ((achievement-id (+ (var-get achievement-counter) u1)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> points-reward u0) ERR_INVALID_MERIT_POINTS)
    (asserts! (is-none (map-get? achievements achievement-id)) ERR_ACHIEVEMENT_ALREADY_EXISTS)
    
    (map-set achievements achievement-id {
      name: name,
      description: description,
      category: category,
      points-reward: points-reward,
      requirements: requirements,
      active: true,
      created-by: tx-sender
    })
    (var-set achievement-counter achievement-id)
    (ok achievement-id)
  )
)

(define-public (award-achievement (member principal) (achievement-id uint))
  (let ((achievement (unwrap! (map-get? achievements achievement-id) ERR_ACHIEVEMENT_NOT_FOUND))
        (member-rep (unwrap! (map-get? member-reputation member) ERR_MEMBER_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (get active achievement) ERR_ACHIEVEMENT_NOT_FOUND)
    (asserts! (is-none (map-get? member-achievements { member: member, achievement-id: achievement-id })) ERR_ACHIEVEMENT_ALREADY_EXISTS)
    
    (map-set member-achievements { member: member, achievement-id: achievement-id } {
      earned-block: stacks-block-height,
      points-earned: (get points-reward achievement),
      verified: true
    })
    
    (map-set member-reputation member 
      (merge member-rep {
        total-points: (+ (get total-points member-rep) (get points-reward achievement)),
        achievement-count: (+ (get achievement-count member-rep) u1),
        last-activity: stacks-block-height,
        reputation-level: (calculate-reputation-level (+ (get total-points member-rep) (get points-reward achievement)))
      }))
    
    (map-set reputation-activities 
      (+ (var-get proposal-counter) u1)
      {
        member: member,
        activity-type: "achievement",
        points-change: (get points-reward achievement),
        block-height: stacks-block-height,
        description: (get name achievement),
        related-proposal: none
      })
    (ok true)
  )
)

(define-public (add-governance-points (member principal) (points uint) (proposal-id (optional uint)))
  (let ((member-rep (unwrap! (map-get? member-reputation member) ERR_MEMBER_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender member)) ERR_UNAUTHORIZED)
    (asserts! (> points u0) ERR_INVALID_MERIT_POINTS)
    
    (map-set member-reputation member 
      (merge member-rep {
        total-points: (+ (get total-points member-rep) points),
        governance-points: (+ (get governance-points member-rep) points),
        last-activity: stacks-block-height,
        reputation-level: (calculate-reputation-level (+ (get total-points member-rep) points))
      }))
    
    (map-set reputation-activities 
      (+ (var-get proposal-counter) u1)
      {
        member: member,
        activity-type: "governance",
        points-change: points,
        block-height: stacks-block-height,
        description: "Governance participation",
        related-proposal: proposal-id
      })
    (ok true)
  )
)

(define-public (add-contribution-points (member principal) (points uint) (description (string-ascii 100)))
  (let ((member-rep (unwrap! (map-get? member-reputation member) ERR_MEMBER_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> points u0) ERR_INVALID_MERIT_POINTS)
    
    (map-set member-reputation member 
      (merge member-rep {
        total-points: (+ (get total-points member-rep) points),
        contribution-points: (+ (get contribution-points member-rep) points),
        last-activity: stacks-block-height,
        reputation-level: (calculate-reputation-level (+ (get total-points member-rep) points))
      }))
    
    (map-set reputation-activities 
      (+ (var-get proposal-counter) u1)
      {
        member: member,
        activity-type: "contribution",
        points-change: points,
        block-height: stacks-block-height,
        description: description,
        related-proposal: none
      })
    (ok true)
  )
)

(define-public (penalize-member (member principal) (points uint) (reason (string-ascii 100)))
  (let ((member-rep (unwrap! (map-get? member-reputation member) ERR_MEMBER_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> points u0) ERR_INVALID_MERIT_POINTS)
    
    (let ((new-total (if (>= (get total-points member-rep) points)
                       (- (get total-points member-rep) points)
                       u0)))
      (map-set member-reputation member 
        (merge member-rep {
          total-points: new-total,
          last-activity: stacks-block-height,
          reputation-level: (calculate-reputation-level new-total)
        }))
      
      (map-set reputation-activities 
        (+ (var-get proposal-counter) u1)
        {
          member: member,
          activity-type: "penalty",
          points-change: points,
          block-height: stacks-block-height,
          description: reason,
          related-proposal: none
        })
      (ok true)
    )
  )
)

(define-public (toggle-achievement-status (achievement-id uint))
  (let ((achievement (unwrap! (map-get? achievements achievement-id) ERR_ACHIEVEMENT_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set achievements achievement-id 
      (merge achievement { active: (not (get active achievement)) }))
    (ok true)
  )
)

(define-public (update-reputation-multiplier (new-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-multiplier u0) ERR_INVALID_AMOUNT)
    (var-set reputation-multiplier new-multiplier)
    (ok true)
  )
)

(define-private (calculate-reputation-level (total-points uint))
  (if (<= total-points u100) u1
    (if (<= total-points u500) u2
      (if (<= total-points u1000) u3
        (if (<= total-points u2500) u4
          (if (<= total-points u5000) u5
            u6)))))
)

(define-read-only (get-member-reputation (member principal))
  (map-get? member-reputation member)
)

(define-read-only (get-achievement (achievement-id uint))
  (map-get? achievements achievement-id)
)

(define-read-only (get-member-achievement (member principal) (achievement-id uint))
  (map-get? member-achievements { member: member, achievement-id: achievement-id })
)

(define-read-only (calculate-voting-power (member principal))
  (match (map-get? member-reputation member)
    reputation
    (let ((base-tokens (default-to u0 (map-get? member-tokens member)))
          (reputation-bonus (/ (* (get total-points reputation) (var-get reputation-multiplier)) u100)))
      (+ base-tokens reputation-bonus))
    (default-to u0 (map-get? member-tokens member))
  )
)

(define-read-only (get-reputation-stats)
  {
    total-achievements: (var-get achievement-counter),
    reputation-multiplier: (var-get reputation-multiplier)
  }
)

(define-read-only (get-member-level-info (member principal))
  (match (map-get? member-reputation member)
    reputation
    {
      current-level: (get reputation-level reputation),
      total-points: (get total-points reputation),
      next-level-threshold: (get-level-threshold (+ (get reputation-level reputation) u1)),
      points-to-next: (if (< (get reputation-level reputation) u6)
                        (- (get-level-threshold (+ (get reputation-level reputation) u1)) (get total-points reputation))
                        u0)
    }
    {
      current-level: u0,
      total-points: u0,
      next-level-threshold: u100,
      points-to-next: u100
    }
  )
)

(define-read-only (get-level-threshold (level uint))
  (if (is-eq level u1) u0
    (if (is-eq level u2) u100
      (if (is-eq level u3) u500
        (if (is-eq level u4) u1000
          (if (is-eq level u5) u2500
            (if (is-eq level u6) u5000
              u10000))))))
)

(define-read-only (get-top-contributors (limit uint))
  {
    message: "Use external indexing for leaderboard queries",
    total-members: "Check member-reputation map"
  }
)


