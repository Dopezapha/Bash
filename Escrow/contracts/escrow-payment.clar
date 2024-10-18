;; Complete Escrow Smart Contract with All Functions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant error-owner-only (err u100))
(define-constant error-unauthorized (err u101))
(define-constant error-already-initialized (err u102))
(define-constant error-not-initialized (err u103))
(define-constant error-already-funded (err u104))
(define-constant error-not-funded (err u105))
(define-constant error-already-completed (err u106))
(define-constant error-invalid-amount (err u107))
(define-constant error-fee-too-high (err u108))
(define-constant error-not-disputed (err u109))
(define-constant error-timeout-not-reached (err u110))
(define-constant error-invalid-status-for-rating (err u111))
(define-constant error-invalid-rating (err u112))
(define-constant error-list-full (err u113))

;; Data Variables
(define-data-var fee-percentage uint u10) ;; 1% fee
(define-data-var next-id uint u0)
(define-data-var timeout-blocks uint u1440) ;; Default timeout of 1440 blocks (approx. 10 days)

;; Data Maps
(define-map escrows
  { id: uint }
  {
    seller: principal,
    buyer: principal,
    arbiter: principal,
    amount: uint,
    fee: uint,
    status: (string-ascii 20),
    created-at: uint,
    rating: (optional uint)
  }
)

(define-map user-escrows
  principal
  (list 100 uint)
)

;; Private Functions

(define-private (calculate-fee (amount uint))
  (/ (* amount (var-get fee-percentage)) u1000)
)

(define-private (transfer-tokens (recipient principal) (amount uint))
  (if (> amount u0)
    (stx-transfer? amount tx-sender recipient)
    (ok true)
  )
)

;; Updated Private Function

(define-private (add-escrow-to-user (user principal) (id uint))
  (let
    (
      (user-escrow-list (default-to (list) (map-get? user-escrows user)))
    )
    (if (< (len user-escrow-list) u99)  ;; Check if there's room for one more item
      (ok (map-set user-escrows user (append user-escrow-list id)))
      error-list-full
    )
  )
)

;; Read-only Functions

(define-read-only (get-escrow (id uint))
  (match (map-get? escrows { id: id })
    entry (ok entry)
    (err u404)
  )
)

(define-read-only (get-escrow-status (id uint))
  (match (map-get? escrows { id: id })
    entry (ok (get status entry))
    (err u404)
  )
)

(define-read-only (get-user-escrows (user principal))
  (default-to (list) (map-get? user-escrows user))
)

(define-read-only (get-timeout)
  (ok (var-get timeout-blocks))
)

;; Public Functions

(define-public (set-fee-percentage (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) error-owner-only)
    (asserts! (< new-fee u1000) error-fee-too-high)
    (ok (var-set fee-percentage new-fee))
  )
)

(define-public (set-timeout (new-timeout uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) error-owner-only)
    (ok (var-set timeout-blocks new-timeout))
  )
)

(define-public (create-escrow (seller principal) (buyer principal) (arbiter principal) (amount uint))
  (let
    (
      (id (var-get next-id))
      (fee (calculate-fee amount))
      (total-amount (+ amount fee))
    )
    (asserts! (> amount u0) error-invalid-amount)
    (asserts! (is-eq tx-sender buyer) error-unauthorized)
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    (map-set escrows
      { id: id }
      {
        seller: seller,
        buyer: buyer,
        arbiter: arbiter,
        amount: amount,
        fee: fee,
        status: "funded",
        created-at: block-height,
        rating: none
      }
    )
    (var-set next-id (+ id u1))
    (try! (add-escrow-to-user seller id))
    (try! (add-escrow-to-user buyer id))
    (try! (add-escrow-to-user arbiter id))
    (ok id)
  )
)

(define-public (release-to-seller (id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get arbiter escrow))) error-unauthorized)
    (asserts! (is-eq status "funded") error-not-funded)
    (try! (as-contract (transfer-tokens (get seller escrow) (get amount escrow))))
    (try! (as-contract (transfer-tokens contract-owner (get fee escrow))))
    (map-set escrows
      { id: id }
      (merge escrow { status: "completed" })
    )
    (ok true)
  )
)

(define-public (refund-to-buyer (id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (or (is-eq tx-sender (get seller escrow)) (is-eq tx-sender (get arbiter escrow))) error-unauthorized)
    (asserts! (is-eq status "funded") error-not-funded)
    (try! (as-contract (transfer-tokens (get buyer escrow) (+ (get amount escrow) (get fee escrow)))))
    (map-set escrows
      { id: id }
      (merge escrow { status: "refunded" })
    )
    (ok true)
  )
)

(define-public (dispute (id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) error-unauthorized)
    (asserts! (is-eq status "funded") error-not-funded)
    (map-set escrows
      { id: id }
      (merge escrow { status: "disputed" })
    )
    (ok true)
  )
)

(define-public (resolve-dispute (id uint) (to-seller bool))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (is-eq tx-sender (get arbiter escrow)) error-unauthorized)
    (asserts! (is-eq status "disputed") error-not-disputed)
    (if to-seller
      (begin
        (try! (as-contract (transfer-tokens (get seller escrow) (get amount escrow))))
        (try! (as-contract (transfer-tokens contract-owner (get fee escrow))))
      )
      (try! (as-contract (transfer-tokens (get buyer escrow) (+ (get amount escrow) (get fee escrow)))))
    )
    (map-set escrows
      { id: id }
      (merge escrow { status: "resolved" })
    )
    (ok true)
  )
)

(define-public (cancel-escrow (id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
      (created-at (get created-at escrow))
    )
    (asserts! (is-eq tx-sender (get buyer escrow)) error-unauthorized)
    (asserts! (is-eq status "funded") error-not-funded)
    (asserts! (> block-height (+ created-at (var-get timeout-blocks))) error-timeout-not-reached)
    (try! (as-contract (transfer-tokens (get buyer escrow) (+ (get amount escrow) (get fee escrow)))))
    (map-set escrows
      { id: id }
      (merge escrow { status: "cancelled" })
    )
    (ok true)
  )
)

(define-public (extend-timeout (id uint) (extension uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) error-unauthorized)
    (asserts! (is-eq status "funded") error-not-funded)
    (map-set escrows
      { id: id }
      (merge escrow { created-at: (+ block-height extension) })
    )
    (ok true)
  )
)

(define-public (rate-transaction (id uint) (rating uint))
  (let
    (
      (escrow (unwrap! (map-get? escrows { id: id }) error-not-initialized))
      (status (get status escrow))
    )
    (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) error-unauthorized)
    (asserts! (or (is-eq status "completed") (is-eq status "refunded") (is-eq status "resolved")) error-invalid-status-for-rating)
    (asserts! (<= rating u5) error-invalid-rating)
    (map-set escrows
      { id: id }
      (merge escrow { rating: (some rating) })
    )
    (ok true)
  )
)