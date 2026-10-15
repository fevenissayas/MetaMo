;; Inference control demo: self-upgrade play-by-play.
;; Run: sh /path/to/PeTTa/run.sh applications/inference_control.metta

!(import! &self ../core/helper)
!(import! &self "../core/helpers.py")
!(import! &self ../core/state)
!(import! &self ../core/state_accessors)
!(import! &self ../core/config)
!(import! &self ../openpsi/config)
!(import! &self ../category/functors)
!(import! &self ../openpsi/appraisal)
!(import! &self ../openpsi/appraisal_helpers)
!(import! &self ../magus/decision)
!(import! &self ../dynamics/stability)
!(import! &self ../dynamics/coherence)
!(import! &self ../inference/pln_rules)
!(import! &self ../inference/config)
!(import! &self ../inference/control)
!(import! &self ../inference/self_upgrade)

(= (demoInitialState)
    (motivation (0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5))
)

(= (printFired $fired)
    (if (== $fired ())
        True
        (let* (
            (($head $tail) (decons $fired))
            ((fired $rule $term (stv $s $c) $score) $head)
            ($_ (println! (    $rule $term (stv (roundNum $s 3) (roundNum $c 3)) (score $score))))
        )
            (printFired $tail)
        )
    )
)

(= (printPhase (phaseRecord $phase $state $beliefs $fired $verdict))
    (let* (
        ($_ (println! (step $phase)))
        ($_ (println! (  goals (gInd gTrans gHelp gCurio gNovel gSelf gEthic gSoc)
                          (roundList (motivationGoals $state) 3))))
        ($_ (println! (  modulators (valence arousal approach resolution threshold securing)
                          (roundList (motivationModulators $state) 3))))
        ((inferenceAllocation $k $cutoff $depth) (computeInferenceAllocation $state))
        ($_ (println! (  allocation (breadth $k) (cutoff (roundNum $cutoff 3)) (depth $depth))))
        ($_ (printFired $fired))
        ($_ (println! (  verdict $verdict)))
    )
        True
    )
)

(= (printPhases $records)
    (if (== $records ())
        True
        (let ($head $tail) (decons $records)
            (let $_ (printPhase $head) (printPhases $tail))
        )
    )
)

!(println! (Self-upgrade play-by-play))
!(printPhases (runSelfUpgradeScenario (demoInitialState) 2))

;; Same evidence, different motivational states.
(= (allocationDemo $label $state)
    (let* (
        ($beliefs (plnMakeBeliefs (selfUpgradeEvidence discovery) 1))
        ((inferenceStepResult $next $nextBeliefs $executed $deferred $pruned $allocation)
         (inferenceControlStep $state $beliefs (selfUpgradeTargets) 0))
    )
        (println! ($label $allocation
                   (executed (size-atom $executed))
                   (deferred (size-atom $deferred))
                   (pruned (size-atom $pruned))))
    )
)

!(println! (Allocation on the discovery evidence))
!(allocationDemo cautious
    (motivation (0.9 0.2 0.6 0.3 0.3 0.4 0.9 0.4) (0.5 0.3 0.4 0.5 0.8 0.8)))
!(allocationDemo neutral (demoInitialState))
!(allocationDemo exploratory
    (motivation (0.35 0.9 0.5 0.9 0.9 0.6 0.4 0.5) (0.6 0.8 0.8 0.5 0.3 0.3)))
