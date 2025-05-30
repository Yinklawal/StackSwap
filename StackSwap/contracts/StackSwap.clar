;; StackSwap Smart Contract

;; Define fungible token trait
(define-trait ft-trait
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

;; Define token types
(define-fungible-token primary-coin)
(define-fungible-token secondary-coin)
(define-fungible-token liquidity-shares)

;; Constants
(define-constant contract-deployer tx-sender)
(define-constant error-access-denied (err u100))
(define-constant error-balance-insufficient (err u101))
(define-constant error-pool-empty (err u102))
(define-constant error-zero-value (err u103))
(define-constant error-price-impact-high (err u104))
(define-constant error-invalid-amount (err u105))
(define-constant max-deposit-amount u1000000000000) ;; Maximum allowed deposit amount

;; Data variables
(define-data-var total-supply-tracked uint u0)
(define-data-var trading-fee-basis-points uint u30)

;; Input validation helper
(define-private (validate-deposit-amounts (primary-amount uint) (secondary-amount uint))
  (and 
    (> primary-amount u0)
    (> secondary-amount u0)
    (<= primary-amount max-deposit-amount)
    (<= secondary-amount max-deposit-amount)))

;; Private helper functions

(define-private (move-tokens-in (amount uint) (token-type (string-ascii 10)))
  (if (is-eq token-type "primary")
      (ft-transfer? primary-coin amount tx-sender (as-contract tx-sender))
      (ft-transfer? secondary-coin amount tx-sender (as-contract tx-sender))))

(define-private (move-tokens-out (amount uint) (recipient principal) (token-type (string-ascii 10)))
  (if (is-eq token-type "primary")
      (as-contract (ft-transfer? primary-coin amount tx-sender recipient))
      (as-contract (ft-transfer? secondary-coin amount tx-sender recipient))))

(define-private (mint-liquidity-shares (amount uint) (recipient principal))
  (ft-mint? liquidity-shares amount recipient))

(define-private (burn-liquidity-shares (amount uint) (sender principal))
  (ft-burn? liquidity-shares amount sender))

;; Simplified liquidity calculation - uses constant product formula without complex square root
(define-private (calculate-initial-liquidity (primary-amount uint) (secondary-amount uint))
  ;; For initial liquidity, use geometric mean approximation: sqrt(a*b) ~= (a+b)/2 for initial pools
  ;; This is simpler and avoids circular dependencies
  (/ (+ primary-amount secondary-amount) u2))

(define-private (calculate-proportional-shares (primary-amount uint) (secondary-amount uint))
  (let (
    (current-total-supply (ft-get-supply liquidity-shares))
    (primary-reserve (ft-get-balance primary-coin (as-contract tx-sender)))
    (secondary-reserve (ft-get-balance secondary-coin (as-contract tx-sender)))
    (shares-from-primary (/ (* primary-amount current-total-supply) primary-reserve))
    (shares-from-secondary (/ (* secondary-amount current-total-supply) secondary-reserve))
  )
    (if (< shares-from-primary shares-from-secondary)
        shares-from-primary
        shares-from-secondary)))

;; Read-only functions

(define-read-only (get-user-primary-balance)
  (ft-get-balance primary-coin contract-caller))

(define-read-only (get-user-secondary-balance)
  (ft-get-balance secondary-coin contract-caller))

(define-read-only (get-user-share-balance)
  (ft-get-balance liquidity-shares contract-caller))

(define-read-only (get-pool-reserves)
  (ok {
    primary-reserve: (ft-get-balance primary-coin (as-contract tx-sender)),
    secondary-reserve: (ft-get-balance secondary-coin (as-contract tx-sender))
  }))

(define-read-only (get-estimated-shares (primary-amount uint) (secondary-amount uint))
  (let ((current-total-supply (ft-get-supply liquidity-shares)))
    (if (is-eq current-total-supply u0)
        (ok (calculate-initial-liquidity primary-amount secondary-amount))
        (ok (calculate-proportional-shares primary-amount secondary-amount)))))

;; Public functions

(define-public (provide-liquidity (primary-deposit uint) (secondary-deposit uint) (minimum-shares uint))
  (let (
    (existing-primary (ft-get-balance primary-coin (as-contract tx-sender)))
    (existing-secondary (ft-get-balance secondary-coin (as-contract tx-sender)))
    (current-total-supply (ft-get-supply liquidity-shares))
    (validated-primary (if (and (> primary-deposit u0) (<= primary-deposit max-deposit-amount)) primary-deposit u0))
    (validated-secondary (if (and (> secondary-deposit u0) (<= secondary-deposit max-deposit-amount)) secondary-deposit u0))
    (shares-minted 
      (if (is-eq current-total-supply u0)
          (calculate-initial-liquidity validated-primary validated-secondary)
          (calculate-proportional-shares validated-primary validated-secondary)))
  )
    ;; Validate inputs
    (asserts! (validate-deposit-amounts primary-deposit secondary-deposit) error-invalid-amount)
    (asserts! (and (> validated-primary u0) (> validated-secondary u0)) error-zero-value)
    
    ;; For existing pools, ensure proportional deposits
    (if (> current-total-supply u0)
        (asserts! (is-eq (* validated-primary existing-secondary) (* validated-secondary existing-primary)) error-pool-empty)
        true)

    (try! (move-tokens-in validated-primary "primary"))
    (try! (move-tokens-in validated-secondary "secondary"))

    (asserts! (>= shares-minted minimum-shares) error-price-impact-high)

    (var-set total-supply-tracked (+ (var-get total-supply-tracked) shares-minted))
    (try! (mint-liquidity-shares shares-minted tx-sender))
    (ok shares-minted)))

(define-public (withdraw-liquidity (shares-to-burn uint) (min-primary uint) (min-secondary uint))
  (let (
    (total-shares-outstanding (ft-get-supply liquidity-shares))
    (primary-in-pool (ft-get-balance primary-coin (as-contract tx-sender)))
    (secondary-in-pool (ft-get-balance secondary-coin (as-contract tx-sender)))
    (primary-withdrawal (/ (* shares-to-burn primary-in-pool) total-shares-outstanding))
    (secondary-withdrawal (/ (* shares-to-burn secondary-in-pool) total-shares-outstanding))
  )
    (asserts! (> shares-to-burn u0) error-zero-value)
    (asserts! (and (>= primary-withdrawal min-primary) (>= secondary-withdrawal min-secondary)) error-price-impact-high)

    (try! (burn-liquidity-shares shares-to-burn tx-sender))
    (var-set total-supply-tracked (- (var-get total-supply-tracked) shares-to-burn))

    (try! (move-tokens-out primary-withdrawal tx-sender "primary"))
    (try! (move-tokens-out secondary-withdrawal tx-sender "secondary"))

    (ok {primary-withdrawal: primary-withdrawal, secondary-withdrawal: secondary-withdrawal})))

(define-public (trade-primary-for-secondary (input-amount uint) (minimum-output uint))
  (let (
    (primary-pool-balance (ft-get-balance primary-coin (as-contract tx-sender)))
    (secondary-pool-balance (ft-get-balance secondary-coin (as-contract tx-sender)))
    (fee-amount (/ (* input-amount (var-get trading-fee-basis-points)) u10000))
    (input-after-fee (- input-amount fee-amount))
    (output-amount (/ (* input-after-fee secondary-pool-balance) (+ primary-pool-balance input-after-fee)))
  )
    (asserts! (> input-amount u0) error-zero-value)
    (asserts! (>= output-amount minimum-output) error-price-impact-high)

    (try! (move-tokens-in input-amount "primary"))
    (try! (move-tokens-out output-amount tx-sender "secondary"))

    (ok output-amount)))

(define-public (trade-secondary-for-primary (input-amount uint) (minimum-output uint))
  (let (
    (primary-pool-balance (ft-get-balance primary-coin (as-contract tx-sender)))
    (secondary-pool-balance (ft-get-balance secondary-coin (as-contract tx-sender)))
    (fee-amount (/ (* input-amount (var-get trading-fee-basis-points)) u10000))
    (input-after-fee (- input-amount fee-amount))
    (output-amount (/ (* input-after-fee primary-pool-balance) (+ secondary-pool-balance input-after-fee)))
  )
    (asserts! (> input-amount u0) error-zero-value)
    (asserts! (>= output-amount minimum-output) error-price-impact-high)

    (try! (move-tokens-in input-amount "secondary"))
    (try! (move-tokens-out output-amount tx-sender "primary"))

    (ok output-amount)))

(define-public (claim-accumulated-fees)
  (let (
    (primary-pool-total (ft-get-balance primary-coin (as-contract tx-sender)))
    (secondary-pool-total (ft-get-balance secondary-coin (as-contract tx-sender)))
    (primary-fee-amount (/ (* primary-pool-total (var-get trading-fee-basis-points)) u10000))
    (secondary-fee-amount (/ (* secondary-pool-total (var-get trading-fee-basis-points)) u10000))
  )
    (asserts! (is-eq tx-sender contract-deployer) error-access-denied)
    (try! (move-tokens-out primary-fee-amount contract-deployer "primary"))
    (try! (move-tokens-out secondary-fee-amount contract-deployer "secondary"))
    (ok {primary-fee-amount: primary-fee-amount, secondary-fee-amount: secondary-fee-amount})))

(define-public (update-trading-fee (new-fee-basis-points uint))
  (begin
    (asserts! (is-eq tx-sender contract-deployer) error-access-denied)
    (asserts! (<= new-fee-basis-points u1000) (err u105))
    (ok (var-set trading-fee-basis-points new-fee-basis-points))))