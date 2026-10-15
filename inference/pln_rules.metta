;; PLN rules for inference control, ported from PeTTa's lib_pln.metta.
;; Belief: (belief $term (stv $s $c) $stamp)
;; Entry: (plnApplyRule $p1 $p2) -> ($rule ($conclusion $tv))

;; Numeric helpers

(= (plnClamp $v $lo $hi)
    (min $hi (max $v $lo))
)

;; Division with no result when the denominator is not positive.
(= (plnSafeDiv $a $b)
    (if (> $b 0.0) (/ $a $b) (empty))
)

(= (plnC2W $c) (plnSafeDiv $c (- 1.0 $c)))
(= (plnW2C $w) (plnSafeDiv $w (+ $w 1.0)))

;; Term priors

(= (PLN_DEFAULT_PRIOR) (stv 0.5 0.9))

;; Prior from (PlnTermPrior $term $tv), else the default.
(= (plnTermTV $term)
    (let $found (collapse (match &self (PlnTermPrior $term $tv) $tv))
        (if (== $found ()) (PLN_DEFAULT_PRIOR) (car-atom $found))
    )
)

;; Consistency conditions: PLN book 5.2.2.2, page 74

(= (plnSmallestIntersection $As $Bs)
    (plnClamp (/ (- (+ $As $Bs) 1.0) $As) 0.0 1.0)
)

(= (plnLargestIntersection $As $Bs)
    (plnClamp (/ $Bs $As) 0.0 1.0)
)

(= (plnConditionalConsistency $As $Bs $ABs)
    (if (> $As 0.0)
        (and (<= (plnSmallestIntersection $As $Bs) $ABs)
             (<= $ABs (plnLargestIntersection $As $Bs)))
        False
    )
)

;; Truth functions

;; Deduction: PLN book 1.4, page 15.
(= (plnTruthDeduction (stv $Ps $Pc) (stv $Qs $Qc) (stv $Rs $Rc) (stv $PQs $PQc) (stv $QRs $QRc))
    (if (and (plnConditionalConsistency $Ps $Qs $PQs)
             (plnConditionalConsistency $Qs $Rs $QRs))
        (stv (if (< 0.9999 $Qs)
                 $Rs
                 (+ (* $PQs $QRs) (plnSafeDiv (* (- 1.0 $PQs) (- $Rs (* $Qs $QRs))) (- 1.0 $Qs))))
             (min $Pc (min $Qc (min $Rc (min $PQc $QRc)))))
        (stv 1.0 0.0)
    )
)

;; Induction: PLN book Appendix A, page 307.
(= (plnTruthInduction (stv $sA $cA) (stv $sB $cB) (stv $sC $cC) (stv $sBA $cBA) (stv $sBC $cBC))
    (stv (plnClamp
             (+ (plnSafeDiv (* (* $sBA $sBC) $sB) $sA)
                (* (- 1.0 (plnSafeDiv (* $sBA $sB) $sA))
                   (plnSafeDiv (- $sC (* $sB $sBC)) (- 1.0 $sB))))
             0.0 1.0)
         (plnW2C (min $cBA $cBC)))
)

;; Abduction: PLN book Appendix A, page 307.
(= (plnTruthAbduction (stv $sA $cA) (stv $sB $cB) (stv $sC $cC) (stv $sAB $cAB) (stv $sCB $cCB))
    (stv (plnClamp
             (+ (plnSafeDiv (* (* $sAB $sCB) $sC) $sB)
                (plnSafeDiv (* $sC (* (- 1.0 $sAB) (- 1.0 $sCB))) (- 1.0 $sB)))
             0.0 1.0)
         (plnW2C (min $cAB $cCB)))
)

;; Modus ponens: PLN book 5.7.1, page 111.
(= (plnTruthModusPonens (stv $f1 $c1) (stv $f2 $c2))
    (stv (+ (* $f1 $f2) (* 0.02 (- 1.0 $f1)))
         (* $c1 $c2))
)

;; Revision: PLN book 5.10.2, page 116.
(= (plnTruthRevision (stv $f1 $c1) (stv $f2 $c2))
    (let* (
        ($w1 (plnC2W $c1))
        ($w2 (plnC2W $c2))
        ($w (+ $w1 $w2))
        ($f (plnSafeDiv (+ (* $w1 $f1) (* $w2 $f2)) $w))
        ($c (plnW2C $w))
    )
        (stv (min 1.0 $f) (min 1.0 (max (max $c $c1) $c2)))
    )
)

;; Rules

(= (plnSyllogisticLink Inheritance) True)
(= (plnSyllogisticLink Implication) True)

(= (plnIsSyllogisticLink $link)
    (== (collapse (plnSyllogisticLink $link)) (True))
)

;; Revision: two independent beliefs about the same term.
(= (plnApplyRule ($term $T1) ($term $T2))
    (revision ($term (plnTruthRevision $T1 $T2)))
)

;; Modus ponens: A, A => B  |-  B
(= (plnApplyRule ($A $T1) ((Implication $A $B) $T2))
    (modusPonens ($B (plnTruthModusPonens $T1 $T2)))
)

;; Deduction: A -> B, B -> C  |-  A -> C
(= (plnApplyRule (($Link $A $B) $T1) (($Link $B $C) $T2))
    (if (and (plnIsSyllogisticLink $Link) (not (== $A $C)))
        (deduction (($Link $A $C)
            (plnTruthDeduction (plnTermTV $A) (plnTermTV $B) (plnTermTV $C) $T1 $T2)))
        (empty)
    )
)

;; Induction: C -> A, C -> B  |-  A -> B
(= (plnApplyRule (($Link $C $A) $T1) (($Link $C $B) $T2))
    (if (and (plnIsSyllogisticLink $Link) (not (== $A $B)))
        (induction (($Link $A $B)
            (plnTruthInduction (plnTermTV $A) (plnTermTV $B) (plnTermTV $C) $T1 $T2)))
        (empty)
    )
)

;; Abduction: A -> C, B -> C  |-  A -> B
(= (plnApplyRule (($Link $A $C) $T1) (($Link $B $C) $T2))
    (if (and (plnIsSyllogisticLink $Link) (not (== $A $B)))
        (abduction (($Link $A $B)
            (plnTruthAbduction (plnTermTV $A) (plnTermTV $B) (plnTermTV $C) $T1 $T2)))
        (empty)
    )
)

;; Stamps (evidential bases)

(= (plnStampDisjoint $stamp1 $stamp2)
    (if (== $stamp1 ())
        True
        (let ($head $tail) (decons $stamp1)
            (if (is-member $head $stamp2)
                False
                (plnStampDisjoint $tail $stamp2)
            )
        )
    )
)

;; Sorted union of two stamps.
(= (plnStampMerge $stamp1 $stamp2)
    (sort-atom (union-atom $stamp1 $stamp2))
)

;; Beliefs

(= (beliefTerm (belief $term $tv $stamp)) $term)
(= (beliefTV (belief $term $tv $stamp)) $tv)
(= (beliefStamp (belief $term $tv $stamp)) $stamp)
(= (beliefStrength (belief $term (stv $s $c) $stamp)) $s)
(= (beliefConfidence (belief $term (stv $s $c) $stamp)) $c)

;; (term tv) pairs -> beliefs with fresh stamps starting at $nextId.
(= (plnMakeBeliefs $facts $nextId)
    (if (== $facts ())
        ()
        (let* (
            ((($term $tv) $rest) (decons $facts))
            ($tail (plnMakeBeliefs $rest (+ $nextId 1)))
        )
            (cons-atom (belief $term $tv ($nextId)) $tail)
        )
    )
)

;; Highest-confidence belief about $term, or ().
(= (plnBestBelief $term $beliefs)
    (plnBestBeliefLoop $term $beliefs ())
)

(= (plnBestBeliefLoop $term $beliefs $best)
    (if (== $beliefs ())
        $best
        (let* (
            (($head $rest) (decons $beliefs))
            ($better (if (== (beliefTerm $head) $term)
                         (if (== $best ())
                             $head
                             (if (> (beliefConfidence $head) (beliefConfidence $best)) $head $best))
                         $best))
        )
            (plnBestBeliefLoop $term $rest $better)
        )
    )
)

;; 0.0 when unknown.
(= (plnKnownConfidence $term $beliefs)
    (let $best (plnBestBelief $term $beliefs)
        (if (== $best ()) 0.0 (beliefConfidence $best))
    )
)
