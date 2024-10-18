;; Advanced Secure Escrow Smart Contract

;; Constants for validation
(define-constant MIN-TIMEOUT-BLOCKS u144)  ;; Minimum 1 day (assuming ~10min per block)
(define-constant MAX-TIMEOUT-BLOCKS u14400)  ;; Maximum 100 days
(define-constant MIN-AMOUNT u1000)  ;; Minimum transaction amount
(define-constant MAX-AMOUNT u100000000000)  ;; Maximum transaction amount

;; Core Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-UNAUTHORIZED (err u101))
(define-constant ERR-ALREADY-INITIALIZED (err u102))
(define-constant ERR-NOT-INITIALIZED (err u103))
(define-constant ERR-ALREADY-FUNDED (err u104))
(define-constant ERR-NOT-FUNDED (err u105))
(define-constant ERR-ALREADY-COMPLETED (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-FEE-TOO-HIGH (err u108))
(define-constant ERR-NOT-DISPUTED (err u109))
(define-constant ERR-TIMEOUT-NOT-REACHED (err u110))
(define-constant ERR-INVALID-STATUS-FOR-RATING (err u111))
(define-constant ERR-INVALID-RATING (err u112))
(define-constant ERR-LIST-FULL (err u113))
(define-constant ERR-INVALID-TIMEOUT (err u114))
(define-constant ERR-INVALID-PRINCIPALS (err u115))
(define-constant ERR-AMOUNT-OUT-OF-RANGE (err u116))
(define-constant ERR-INVALID-ID (err u117))

;; Data Variables
(define-data-var fee-percentage uint u10) ;; 1% fee
(define-data-var next-id uint u0)
(define-data-var timeout-blocks uint u1440) ;; Default timeout of 1440 blocks

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

;; Validation Functions
(define-private (is-valid-timeout (blocks uint))
  (and (>= blocks MIN-TIMEOUT-BLOCKS)
       (<= blocks MAX-TIMEOUT-BLOCKS))
)

(define-private (is-valid-amount (amount uint))
  (and (>= amount MIN-AMOUNT)
       (<= amount MAX-AMOUNT))
)

(define-private (are-valid-principals (seller principal) (buyer principal) (arbiter principal))
  (and
    (not (is-eq seller buyer))
    (not (is-eq seller arbiter))
    (not (is-eq buyer arbiter))
  )
)

(define-private (is-valid-escrow-id (id uint))
  (< id (var-get next-id))
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

(define-private (add-escrow-to-user (user principal) (id uint))
  (let
    (
      (user-escrow-list (default-to (list) (map-get? user-escrows user)))
    )
    (if (< (len user-escrow-list) u100)
      (ok (map-set user-escrows 
                   user 
                   (unwrap! (as-max-len? (concat user-escrow-list (list id)) u100) ERR-LIST-FULL)))
      ERR-LIST-FULL
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
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (asserts! (< new-fee u1000) ERR-FEE-TOO-HIGH)
    (ok (var-set fee-percentage new-fee))
  )
)

(define-public (set-timeout (new-timeout uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (asserts! (is-valid-timeout new-timeout) ERR-INVALID-TIMEOUT)
    (ok (var-set timeout-blocks new-timeout))
  )
)

(define-public (create-escrow (seller principal) (buyer principal) (arbiter principal) (amount uint))
  (begin
    (asserts! (are-valid-principals seller buyer arbiter) ERR-INVALID-PRINCIPALS)
    (asserts! (is-valid-amount amount) ERR-AMOUNT-OUT-OF-RANGE)
    (let
      (
        (id (var-get next-id))
        (fee (calculate-fee amount))
        (total-amount (+ amount fee))
      )
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      (asserts! (is-eq tx-sender buyer) ERR-UNAUTHORIZED)
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
)

(define-public (release-to-seller (id uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get arbiter escrow))) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "funded") ERR-NOT-FUNDED)
      (try! (as-contract (transfer-tokens (get seller escrow) (get amount escrow))))
      (try! (as-contract (transfer-tokens contract-owner (get fee escrow))))
      (map-set escrows
        { id: id }
        (merge escrow { status: "completed" })
      )
      (ok true)
    )
  )
)

(define-public (refund-to-buyer (id uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (or (is-eq tx-sender (get seller escrow)) (is-eq tx-sender (get arbiter escrow))) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "funded") ERR-NOT-FUNDED)
      (try! (as-contract (transfer-tokens (get buyer escrow) (+ (get amount escrow) (get fee escrow)))))
      (map-set escrows
        { id: id }
        (merge escrow { status: "refunded" })
      )
      (ok true)
    )
  )
)

(define-public (dispute (id uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "funded") ERR-NOT-FUNDED)
      (map-set escrows
        { id: id }
        (merge escrow { status: "disputed" })
      )
      (ok true)
    )
  )
)

(define-public (resolve-dispute (id uint) (to-seller bool))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (is-eq tx-sender (get arbiter escrow)) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "disputed") ERR-NOT-DISPUTED)
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
)

(define-public (cancel-escrow (id uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
        (created-at (get created-at escrow))
      )
      (asserts! (is-eq tx-sender (get buyer escrow)) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "funded") ERR-NOT-FUNDED)
      (asserts! (> block-height (+ created-at (var-get timeout-blocks))) ERR-TIMEOUT-NOT-REACHED)
      (try! (as-contract (transfer-tokens (get buyer escrow) (+ (get amount escrow) (get fee escrow)))))
      (map-set escrows
        { id: id }
        (merge escrow { status: "cancelled" })
      )
      (ok true)
    )
  )
)

(define-public (extend-timeout (id uint) (extension uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) ERR-UNAUTHORIZED)
      (asserts! (is-eq status "funded") ERR-NOT-FUNDED)
      (map-set escrows
        { id: id }
        (merge escrow { created-at: (+ block-height extension) })
      )
      (ok true)
    )
  )
)

(define-public (rate-transaction (id uint) (rating uint))
  (begin
    (asserts! (is-valid-escrow-id id) ERR-INVALID-ID)
    (let
      (
        (escrow (unwrap! (map-get? escrows { id: id }) ERR-NOT-INITIALIZED))
        (status (get status escrow))
      )
      (asserts! (or (is-eq tx-sender (get buyer escrow)) (is-eq tx-sender (get seller escrow))) ERR-UNAUTHORIZED)
      (asserts! (or (is-eq status "completed") (is-eq status "refunded") (is-eq status "resolved")) ERR-INVALID-STATUS-FOR-RATING)
      (asserts! (<= rating u5) ERR-INVALID-RATING)
      (map-set escrows
        { id: id }
        (merge escrow { rating: (some rating) })
      )
      (ok true)
    )
  )
)