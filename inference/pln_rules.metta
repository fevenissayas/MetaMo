;; Adapter between PeTTa's PLN library and the inference controller.
;; Truth functions, rules (|-) and stamps come from lib_pln; import it first:
;;   !(import! &self (library lib_pln))
;; Belief: (belief $term (stv $s $c) $stamp)
;; Entry: (plnApplyRule $p1 $p2) -> ($rule ($conclusion $tv))

;; Term priors

(= (PLN_DEFAULT_PRIOR) (stv 0.5 0.9))

;; Prior from (PlnTermPrior $term $tv), else the default.
(= (plnTermTV $term)
    (let $found (collapse (match &self (PlnTermPrior $term $tv) $tv))
        (if (== $found ()) (PLN_DEFAULT_PRIOR) (car-atom $found))
    )
)

;; lib_pln reads term priors through STV.
(= (STV $term) (plnTermTV $term))

;; Rule names

;; lib_pln's |- does not report which rule fired; recover it from the premise shapes.
(= (plnRuleName ($T $T1) ($T $T2) $T) revision)
(= (plnRuleName ($A $T1) ((Implication $A $B) $T2) $B) modusPonens)
(= (plnRuleName ($A $T1) (($Link $A $B) $T2) $B)
    (if (== $Link Implication) (empty) symmetricModusPonens))
(= (plnRuleName (($Link $A $B) $T1) (($Link $B $C) $T2) ($Link $A $C))
    (if (== $Link Similarity) transitiveSimilarity deduction))
(= (plnRuleName (($Link $C $A) $T1) (($Link $C $B) $T2) ($Link $A $B)) induction)
(= (plnRuleName (($Link $A $C) $T1) (($Link $B $C) $T2) ($Link $A $B)) abduction)
(= (plnRuleName ((Evaluation $P $Args) $T1) ((Inheritance $S $C) $T2) (Evaluation $P $NewArgs)) predicateInheritance)
(= (plnRuleName ((Evaluation $A $B) $T1) ((Implication $A $C) $T2) (Evaluation $C $B)) evaluationImplication)
(= (plnRuleName ((Member $A $B) $T1) ((Inheritance $B $C) $T2) (Member $A $C)) memberDeduction)

;; First matching name, or no result.
(= (plnRuleLabel $p1 $p2 $conclusion)
    (let $names (collapse (plnRuleName $p1 $p2 $conclusion))
        (if (== $names ()) (empty) (car-atom $names))
    )
)

;; Links from a term to itself carry no information.
(= (plnSelfLink $term)
    (case $term
        ((($Link $A $A) True)
         ($_ False)))
)

;; Every two-premise lib_pln conclusion, tagged with its rule.
(= (plnApplyRule $p1 $p2)
    (let ($term $tv) (|- $p1 $p2)
        (if (plnSelfLink $term)
            (empty)
            (let $rule (plnRuleLabel $p1 $p2 $term) ($rule ($term $tv)))
        )
    )
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
