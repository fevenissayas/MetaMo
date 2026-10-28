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
(InferenceRiskTag safe -0.5)

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

;; Neutral except for one goal.
(= (highIndState) (motivation (0.9 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5)))
(= (lowIndState) (motivation (0.1 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5)))
(= (highTransState) (motivation (0.5 0.9 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5)))
(= (lowTransState) (motivation (0.5 0.1 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5)))

;; gInd just above THETA_SAFE, so the state is near the safe-region boundary.
(= (nearBoundaryState) (motivation (0.35 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5)))

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

(= (relevanceOf (inferenceCandidate $rule $term $tv $stamp $premises))
    (inferenceRelevance $term (testTargets))
)

(= (featuresOf $candidate)
    (inferenceFeatures $candidate (relevanceOf $candidate) (testBeliefs))
)

(= (stimulusValue $candidate $idx)
    (index-atom (stimulusValues (inferenceStimulus (featuresOf $candidate))) $idx)
)

(= (appraisedIn $state $candidate)
    (inferenceAppraise $state (featuresOf $candidate))
)

(= (scoredIn $state $candidate)
    (scoreInference $state $candidate (relevanceOf $candidate) (testBeliefs) 1.0)
)

(= (scoreIn $state $candidate) (scoredScore (scoredIn $state $candidate)))

(= (deltaGoal $candidate $goal)
    (index-atom (scoredDeltaG (scoredIn (neutralState) $candidate))
                (match &self (GoalIndex $goal $idx) $idx))
)

(= (relevantConclusion)
    (inferenceCandidate deduction (Inheritance a d) (stv 0.6 0.9) (1 2) ())
)

(= (unrelatedConclusion)
    (inferenceCandidate deduction (Inheritance x y) (stv 0.6 0.9) (1 2) ())
)

(= (riskyConclusion)
    (inferenceCandidate deduction (Inheritance a unsafe) (stv 0.6 0.9) (1 2) ())
)

(= (safeConclusion)
    (inferenceCandidate deduction (Inheritance a safe) (stv 0.6 0.9) (1 2) ())
)

;; A novel, low-confidence proof on the task.
(= (tentativeProof)
    (inferenceCandidate induction (Inheritance d a) (stv 0.6 0.2) (1 2) ())
)

;; A confident proof that the task is safe.
(= (safetyProof)
    (inferenceCandidate deduction (Inheritance a safe) (stv 0.9 0.9) (1 2) ())
)

(= (stepSummary $state)
    (let (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation $shift)
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

;; Step 1, appraisal: each (r, H) is a stimulus (novelty conduciveness risk cost).

;; Unknown conclusions are more novel than ones already believed.
!(test
    (> (stimulusValue (unrelatedConclusion) 0)
       (stimulusValue (inferenceCandidate revision (Inheritance a c) (stv 0.6 0.9) (1 2) ()) 0))
    True
)

;; Task-relevant conclusions are more conducive.
!(test (> (stimulusValue (relevantConclusion) 1) (stimulusValue (unrelatedConclusion) 1)) True)

;; Risk tags raise the risk; a confident safety proof enters as negative risk.
!(test (> (stimulusValue (riskyConclusion) 2) (stimulusValue (unrelatedConclusion) 2)) True)
!(test (< (stimulusValue (safetyProof) 2) 0.0) True)

;; Uncertainty a proof resolves on the task counts against its risk.
!(test (< (stimulusValue (relevantConclusion) 2) (stimulusValue (unrelatedConclusion) 2)) True)

;; Appraisal changes modulators only.
!(test
    (motivationGoals (appraisedIn (cautiousState) (riskyConclusion)))
    (0.9 0.2 0.6 0.3 0.3 0.4 0.9 0.4)
)

;; A novel low-confidence proof raises arousal and threshold.
!(test (> (getModulator (appraisedIn (neutralState) (tentativeProof)) arousal) 0.5) True)
!(test (> (getModulator (appraisedIn (neutralState) (tentativeProof)) threshold) 0.5) True)

;; A successful safety proof lowers threshold and securing.
!(test (< (getModulator (appraisedIn (neutralState) (safetyProof)) threshold) 0.5) True)
!(test (< (getModulator (appraisedIn (neutralState) (safetyProof)) securing) 0.5) True)

;; Reassurance keeps modulators inside [0, 1].
!(test
    (let $mods (motivationModulators
                  (appraisedIn (motivation (0.1 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.01 0.01))
                               (safetyProof)))
        (and (>= (min-atom $mods) 0.0) (<= (max-atom $mods) 1.0)))
    True
)

;; gInd amplifies the threshold and securing response to risk.
!(test
    (> (getModulator (appraisedIn (highIndState) (riskyConclusion)) securing)
       (getModulator (appraisedIn (lowIndState) (riskyConclusion)) securing))
    True
)

;; gTrans amplifies the arousal and approach response to novelty.
!(test
    (> (getModulator (appraisedIn (highTransState) (unrelatedConclusion)) arousal)
       (getModulator (appraisedIn (lowTransState) (unrelatedConclusion)) arousal))
    True
)

;; Step 2, decision: score = sum_i g_i m'_i rel_i - lambdaInd gInd risk + lambdaTrans gTrans

;; With no task relevance only the overgoal terms remain.
(= (offTaskRisky) (inferenceCandidate deduction (Inheritance x unsafe) (stv 0.6 0.9) (1 2) ()))

!(test
    (roundNum (scoreIn (cautiousState) (offTaskRisky)) 6)
    (roundNum (+ (- 0.0 (* (* (LAMBDA_IND) 0.9) (stimulusValue (offTaskRisky) 2)))
                 (* (LAMBDA_TRANS) 0.2)) 6)
)

;; A conclusion that answers the task outranks an unrelated one.
!(test (> (scoreIn (neutralState) (relevantConclusion)) (scoreIn (neutralState) (unrelatedConclusion))) True)

;; Risky conclusions are penalised, and more so under strong individuation.
!(test (> (scoreIn (neutralState) (safeConclusion)) (scoreIn (neutralState) (riskyConclusion))) True)

!(test
    (> (- (scoreIn (highIndState) (safeConclusion)) (scoreIn (highIndState) (riskyConclusion)))
       (- (scoreIn (lowIndState) (safeConclusion)) (scoreIn (lowIndState) (riskyConclusion))))
    True
)

;; Near limits gInd raises the effective penalty and gTrans softens it.
!(test (roundNum (inferencePenaltyScale (cautiousState) 1.0) 3) 1.7)
!(test (roundNum (inferencePenaltyScale (exploratoryState) 1.0) 3) 0.45)
!(test (inferencePenaltyScale (cautiousState) 0.0) 1.0)

;; Proposed goal changes: unsafe findings raise gInd, safety proofs lower it
;; and raise gEthic.
!(test (> (deltaGoal (riskyConclusion) gInd) 0.0) True)
!(test (< (deltaGoal (safetyProof) gInd) 0.0) True)
!(test (> (deltaGoal (safetyProof) gEthic) 0.0) True)

;; Step 3, allocation and pruning

!(test (computeInferenceAllocation (neutralState)) (inferenceAllocation 2 0.2 0.25))

;; Curiosity, gSelf and transcendence widen the search; threshold, ethics and
;; individuation tighten the confidence cutoff.
!(test
    (> (allocationBreadth (computeInferenceAllocation (exploratoryState)))
       (allocationBreadth (computeInferenceAllocation (cautiousState))))
    True
)

!(test
    (> (allocationBreadth (computeInferenceAllocation (motivation (0.5 0.9 0.5 0.5 0.5 0.9 0.5 0.5) (0.5 0.9 0.5 0.5 0.5 0.5))))
       (allocationBreadth (computeInferenceAllocation (motivation (0.5 0.9 0.5 0.5 0.5 0.1 0.5 0.5) (0.5 0.9 0.5 0.5 0.5 0.5)))))
    True
)

!(test
    (> (allocationCutoff (computeInferenceAllocation (cautiousState)))
       (allocationCutoff (computeInferenceAllocation (exploratoryState))))
    True
)

;; d_max(h): proofs go deeper only on relevant subgraphs.
!(test (inferenceMaxDepth (inferenceAllocation 2 0.2 0.5) 1.0) 4)
!(test (inferenceMaxDepth (inferenceAllocation 2 0.2 0.5) 0.0) 2)

;; Checks made before appraisal.
!(test (inferencePrePruneReason (inferenceCandidate deduction x (stv 0.9 0.1) (1 2) ()) 1.0 (inferenceAllocation 2 0.2 0.5)) lowConfidence)
!(test (inferencePrePruneReason (inferenceCandidate deduction x (stv 0.9 0.9) (1 2 3) ()) 0.0 (inferenceAllocation 2 0.2 0.5)) tooDeep)
!(test (inferencePrePruneReason (inferenceCandidate deduction x (stv 0.9 0.9) (1 2 3) ()) 1.0 (inferenceAllocation 2 0.2 0.5)) ok)

;; Pre-pruned candidates are reported as candidates, without a score.
!(test
    (let (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation $shift)
         (inferenceControlStep (cautiousState) (testBeliefs) (testTargets) 0)
        (let (pruned $reason $item) (car-atom $pruned) (car-atom $item)))
    inferenceCandidate
)

;; Counts are (executed deferred pruned).
!(test (stepSummary (cautiousState)) (0 0 7))
!(test (stepSummary (exploratoryState)) (5 2 0))
!(test (stepSummary (neutralState)) (2 5 0))

;; Executed inferences are ranked by score.
!(test
    (let (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation $shift)
         (inferenceControlStep (neutralState) (testBeliefs) (testTargets) 0)
        (>= (scoredScore (car-atom $executed)) (scoredScore (car-atom $deferred))))
    True
)

;; Step 4, incremental coherence

(= (blendWith $state $previousShift)
    (inferenceBlend $state (motivation (motivationGoals $state) (0.9 0.9 0.9 0.9 0.9 0.9)) $previousShift)
)

(= (shiftOf $state $previousShift)
    (let (blendStep $next $shift) (blendWith $state $previousShift) $shift)
)

;; The blended state lies between the current state and the target.
!(test
    (let (blendStep $next $shift) (blendWith (neutralState) 0.25)
        (let $valence (getModulator $next valence) (and (> $valence 0.5) (< $valence 0.9))))
    True
)

;; Individuation slows the step, transcendence speeds it.
!(test (< (shiftOf (highIndState) 0.25) (shiftOf (lowIndState) 0.25)) True)
!(test (> (shiftOf (highTransState) 0.25) (shiftOf (lowTransState) 0.25)) True)

;; Near the boundary the shift is contractive: shift <= 0.9 previous + 0.01.
!(test (> (boundaryPressure (nearBoundaryState)) 0.0) True)
!(test (<= (shiftOf (nearBoundaryState) 0.05) (+ (* 0.9 0.05) 0.01)) True)

;; Away from the boundary the step is not capped.
!(test (> (shiftOf (neutralState) 0.05) (+ (* 0.9 0.05) 0.01)) True)

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

;; The final state stays in the safe region.
!(test (isInSafeRegion (inferenceRunState (chainRun))) True)
