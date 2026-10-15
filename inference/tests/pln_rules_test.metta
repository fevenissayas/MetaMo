!(import! &self ../../core/helper)
!(import! &self "../../core/helpers.py")
!(import! &self ../pln_rules)

(PlnTermPrior a (stv 0.4 0.9))
(PlnTermPrior b (stv 0.4 0.9))
(PlnTermPrior c (stv 0.4 0.9))

;; Deduction truth function matches PeTTa's lib_pln reference value.
!(test
    (plnTruthDeduction (plnTermTV a) (plnTermTV b) (plnTermTV c) (stv 0.9 0.9) (stv 0.8 0.9))
    (stv 0.7333333333333334 0.9)
)

;; Inconsistent premises yield a zero-confidence deduction.
!(test
    (plnTruthDeduction (stv 0.9 0.9) (stv 0.1 0.9) (stv 0.5 0.9) (stv 0.9 0.9) (stv 0.5 0.9))
    (stv 1.0 0.0)
)

;; Modus ponens multiplies strengths and confidences.
!(test
    (plnTruthModusPonens (stv 1.0 0.9) (stv 0.8 0.9))
    (stv 0.8 0.81)
)

;; Revision of two equally weighted beliefs averages strength and raises confidence.
!(test
    (plnTruthRevision (stv 1.0 0.5) (stv 0.0 0.5))
    (stv 0.5 0.6666666666666666)
)

;; Unknown terms fall back to the default prior.
!(test (plnTermTV unknownTerm) (stv 0.5 0.9))

;; Rule application: deduction over an Inheritance chain.
!(test
    (collapse (plnApplyRule ((Inheritance a b) (stv 0.9 0.9)) ((Inheritance b c) (stv 0.8 0.9))))
    ((deduction ((Inheritance a c) (stv 0.7333333333333334 0.9))))
)

;; Rule application: modus ponens.
!(test
    (collapse (plnApplyRule (a (stv 1.0 0.9)) ((Implication a b) (stv 0.8 0.9))))
    ((modusPonens (b (stv 0.8 0.81))))
)

;; Rule application: shared subject gives induction, shared predicate abduction.
!(test
    (let $r (collapse (plnApplyRule ((Inheritance c a) (stv 0.8 0.9)) ((Inheritance c b) (stv 0.7 0.9))))
        (let (($rule ($term $tv))) $r ($rule $term)))
    (induction (Inheritance a b))
)

!(test
    (let $r (collapse (plnApplyRule ((Inheritance a c) (stv 0.8 0.9)) ((Inheritance b c) (stv 0.7 0.9))))
        (let (($rule ($term $tv))) $r ($rule $term)))
    (abduction (Inheritance a b))
)

;; Syllogistic rules do not apply to other link types.
!(test
    (collapse (plnApplyRule ((Similarity a b) (stv 0.9 0.9)) ((Similarity b c) (stv 0.8 0.9))))
    ()
)

;; Stamps
!(test (plnStampDisjoint (1 2) (3 4)) True)
!(test (plnStampDisjoint (1 2) (2 3)) False)
!(test (plnStampMerge (3 1) (2)) (1 2 3))

;; Beliefs
!(test
    (plnMakeBeliefs (((Inheritance a b) (stv 0.9 0.9)) (a (stv 1.0 0.8))) 5)
    ((belief (Inheritance a b) (stv 0.9 0.9) (5)) (belief a (stv 1.0 0.8) (6)))
)

!(test
    (plnBestBelief a ((belief a (stv 0.9 0.4) (1)) (belief b (stv 0.9 0.9) (2)) (belief a (stv 0.7 0.8) (3))))
    (belief a (stv 0.7 0.8) (3))
)

!(test (plnKnownConfidence c ((belief a (stv 0.9 0.4) (1)))) 0.0)
