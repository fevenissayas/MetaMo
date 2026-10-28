!(import! &self ../../core/helper)
!(import! &self "../../core/helpers.py")
!(import! &self ../../core/state)
!(import! &self ../../core/state_accessors)
!(import! &self ../../core/config)
!(import! &self ../../openpsi/config)
!(import! &self ../../category/functors)
!(import! &self ../../openpsi/appraisal)
!(import! &self ../../openpsi/appraisal_helpers)
!(import! &self ../../magus/decision)
!(import! &self ../../dynamics/stability)
!(import! &self ../../dynamics/coherence)
!(import! &self (library lib_pln))
!(import! &self ../pln_adapter)
!(import! &self ../config)
!(import! &self ../control)

(InferenceRiskTag unsafe 0.9)

;; Shared motivational states.
;; Goals: (gInd gTrans gHelp gCurio gNovel gSelf gEthic gSoc)
;; Modulators: (valence arousal approach resolution threshold securing)
(= (neutralState)
    (motivation (0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5))
)

(= (cautiousState)
    (motivation (0.9 0.2 0.6 0.3 0.3 0.4 0.9 0.4) (0.5 0.3 0.4 0.5 0.8 0.8))
)

(= (exploratoryState)
    (motivation (0.35 0.9 0.5 0.9 0.9 0.6 0.4 0.5) (0.6 0.8 0.8 0.5 0.3 0.3))
)

;; Knowledge base with deductive, inductive and abductive openings, one weak
;; link (c -> d) and one risky concept.
(= (testBeliefs)
    (plnMakeBeliefs (
        ((Inheritance a c) (stv 0.8 0.9))
        ((Inheritance b c) (stv 0.7 0.9))
        ((Inheritance c d) (stv 0.9 0.4))
        ((Inheritance a unsafe) (stv 0.6 0.9))
        ((Inheritance d e) (stv 0.8 0.8))
    ) 1)
)

(= (testTargets) ((Inheritance a d)))

(= (featuresOf $candidate)
    (inferenceFeatures $candidate (testBeliefs) (testTargets))
)

(= (stimulusOf $candidate)
    (inferenceStimulus $candidate (featuresOf $candidate))
)

(= (scoreIn $state $candidate)
    (scoredScore (scoreInference $state $candidate (testBeliefs) (testTargets) 0.0))
)

(= (safeConclusion)
    (inferenceCandidate deduction (Inheritance b d) (stv 0.6 0.9) (1 2) ())
)

(= (riskyConclusion)
    (inferenceCandidate deduction (Inheritance b unsafe) (stv 0.6 0.9) (1 2) ())
)

(= (stepSummary $state)
    (let (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation)
         (inferenceControlStep $state (testBeliefs) (testTargets) 0)
        ((size-atom $executed) (size-atom $deferred) (size-atom $pruned))
    )
)

;; Term structure and relevance

!(test (inferenceTermSymbols (Inheritance a (Implication b c))) (a b c))
!(test (inferenceTermRelevance (Inheritance a d) (Inheritance a d)) 1.0)
!(test (inferenceTermRelevance (Inheritance a b) (Inheritance a d)) 0.4)
!(test (inferenceRelevance (Inheritance x y) ((Inheritance a d) (Inheritance x y))) 1.0)

;; Candidate generation: every rule application with disjoint evidence,
;; minus conclusions already held with the same evidence.
!(test (size-atom (inferenceCandidates (testBeliefs))) 7)
!(test
    (inferenceCandidates (plnMakeBeliefs (((Inheritance a b) (stv 0.9 0.9)) ((Inheritance b c) (stv 0.8 0.9))) 1))
    ((inferenceCandidate deduction (Inheritance a c) (stv 0.7400000000000001 0.9) (1 2)
        ((Inheritance a b) (Inheritance b c))))
)

;; Appraisal (Psi): candidate -> stimulus

;; Unknown conclusions are more novel than ones already believed.
!(test
    (> (index-atom (stimulusValues (stimulusOf (inferenceCandidate deduction (Inheritance x y) (stv 0.6 0.9) (1 2) ()))) 0)
       (index-atom (stimulusValues (stimulusOf (inferenceCandidate revision (Inheritance a c) (stv 0.6 0.9) (1 2) ()))) 0))
    True
)

;; Concepts tagged as risky raise the stimulus risk.
!(test
    (> (index-atom (stimulusValues (stimulusOf (riskyConclusion))) 2)
       (index-atom (stimulusValues (stimulusOf (safeConclusion))) 2))
    True
)

;; Target-relevant conclusions are more conducive.
!(test
    (> (index-atom (stimulusValues (stimulusOf (inferenceCandidate deduction (Inheritance a d) (stv 0.6 0.9) (1 2) ()))) 1)
       (index-atom (stimulusValues (stimulusOf (safeConclusion))) 1))
    True
)

;; Appraisal leaves goals untouched and raises securing more for risky inferences.
!(test
    (motivationGoals (inferenceAppraise (cautiousState) (riskyConclusion) (featuresOf (riskyConclusion))))
    (0.9 0.2 0.6 0.3 0.3 0.4 0.9 0.4)
)

!(test
    (> (getModulator (inferenceAppraise (neutralState) (riskyConclusion) (featuresOf (riskyConclusion))) securing)
       (getModulator (inferenceAppraise (neutralState) (safeConclusion) (featuresOf (safeConclusion))) securing))
    True
)

;; Decision (D): MAGUS scoring

;; A conclusion that answers the target outranks an unrelated one.
!(test
    (> (scoreIn (neutralState) (inferenceCandidate deduction (Inheritance a d) (stv 0.6 0.9) (1 2) ()))
       (scoreIn (neutralState) (safeConclusion)))
    True
)

;; Risky conclusions are penalised, and more so under strong individuation.
!(test
    (> (scoreIn (neutralState) (safeConclusion)) (scoreIn (neutralState) (riskyConclusion)))
    True
)

!(test
    (> (- (scoreIn (cautiousState) (safeConclusion)) (scoreIn (cautiousState) (riskyConclusion)))
       (- (scoreIn (exploratoryState) (safeConclusion)) (scoreIn (exploratoryState) (riskyConclusion))))
    True
)

;; Dynamic allocation and pruning

!(test (computeInferenceAllocation (neutralState)) (inferenceAllocation 2 0.2 3))

;; Transcendence and curiosity widen the search, individuation and ethics
;; tighten the confidence cutoff.
!(test
    (> (allocationBreadth (computeInferenceAllocation (exploratoryState)))
       (allocationBreadth (computeInferenceAllocation (cautiousState))))
    True
)

!(test
    (> (allocationCutoff (computeInferenceAllocation (cautiousState)))
       (allocationCutoff (computeInferenceAllocation (exploratoryState))))
    True
)

;; Near limits a high gInd throttles inference while a high gTrans softens it.
!(test (roundNum (inferenceThrottle (cautiousState) 1.0) 3) 0.37)
!(test (inferenceThrottle (exploratoryState) 1.0) 0.0)
!(test (inferenceThrottle (cautiousState) 0.0) 0.0)

;; Prune reasons.
!(test
    (inferencePruneReason
        (scoredInference 1.0 (inferenceCandidate deduction x (stv 0.9 0.1) (1 2) ()) () ())
        (inferenceAllocation 2 0.2 3))
    lowConfidence
)

!(test
    (inferencePruneReason
        (scoredInference 1.0 (inferenceCandidate deduction x (stv 0.9 0.9) (1 2 3 4) ()) () ())
        (inferenceAllocation 2 0.2 3))
    tooDeep
)

!(test
    (inferencePruneReason
        (scoredInference -0.5 (inferenceCandidate deduction x (stv 0.9 0.9) (1 2) ()) () ())
        (inferenceAllocation 2 0.2 3))
    lowScore
)

!(test
    (inferencePruneReason
        (scoredInference 0.5 (inferenceCandidate deduction x (stv 0.9 0.9) (1 2) ()) () ())
        (inferenceAllocation 2 0.2 3))
    ok
)

;; A cautious controller prunes every weak inference; an exploratory one
;; runs its top-k and defers the rest. Counts are (executed deferred pruned).
!(test (stepSummary (cautiousState)) (0 0 7))
!(test (stepSummary (exploratoryState)) (6 1 0))
!(test (stepSummary (neutralState)) (2 5 0))

;; Executed inferences are ranked by score.
!(test
    (let (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation)
         (inferenceControlStep (neutralState) (testBeliefs) (testTargets) 0)
        (>= (scoredScore (car-atom $executed)) (scoredScore (car-atom $deferred))))
    True
)

;; Incremental self-model coherence

!(test (roundNum (inferenceBlendFactor (cautiousState)) 3) 0.11)
!(test (roundNum (inferenceBlendFactor (exploratoryState)) 3) 0.555)

;; The blended state lies between the current state and the target.
!(test
    (let* (
        ($state (neutralState))
        ($target (motivation (0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.9 0.9 0.9 0.9 0.9 0.9)))
        ($valence (getModulator (inferenceBlend $state $target) valence))
    )
        (and (> $valence 0.5) (< $valence 0.9)))
    True
)

;; Full run: the controller reaches the target conclusion over a deduction chain.
(= (chainRun)
    (runInferenceControl
        (neutralState)
        (((Inheritance a b) (stv 0.9 0.9))
         ((Inheritance b c) (stv 0.8 0.9))
         ((Inheritance c d) (stv 0.7 0.9)))
        ((Inheritance a d))
        3)
)

!(test
    (let (belief $term (stv $s $c) $stamp) (inferenceRunAnswer (chainRun) (Inheritance a d))
        ($term $stamp))
    ((Inheritance a d) (1 2 3))
)

;; The run stops once nothing new can be derived.
!(test (size-atom (inferenceRunTrace (chainRun))) 3)

;; The final state stays in the safe region.
!(test (isInSafeRegion (inferenceRunState (chainRun))) True)
