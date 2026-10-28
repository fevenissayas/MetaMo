;; MetaMo-driven PLN inference control, in four steps:
;;   1. Appraisal (Psi): each candidate (r, H) is an OpenPsi stimulus.
;;   2. Decision (D): score = sum_i g_i m'_i rel_i - lambdaInd gInd risk + lambdaTrans gTrans
;;   3. Allocation: breadth, confidence cutoff and relevance-gated depth; top-k run.
;;   4. Coherence: the state blends toward x*, contractively near the boundary.
;; Entry point: (runInferenceControl $state $facts $targets $maxSteps)

;; Data
;; (inferenceCandidate $rule $conclusion $tv $stamp $premises)
;; (candidateFeatures $novelty $conduciveness $risk $signedRisk $effort $relevance $ruleNovelty $known $gain)
;; (inferenceAllocation $breadth $confidenceCutoff $deepen), $deepen = resolution * gHelp
;; (scoredInference $score $candidate $features $appraisedState $deltaG)
;; (inferenceRun $finalState $beliefs $trace)

(= (candidateBelief (inferenceCandidate $rule $term $tv $stamp $premises)) (belief $term $tv $stamp))

(= (allocationBreadth (inferenceAllocation $k $cutoff $deepen)) $k)
(= (allocationCutoff (inferenceAllocation $k $cutoff $deepen)) $cutoff)

(= (scoredScore (scoredInference $score $candidate $features $appraised $deltaG)) $score)
(= (scoredCandidate (scoredInference $score $candidate $features $appraised $deltaG)) $candidate)
(= (scoredAppraised (scoredInference $score $candidate $features $appraised $deltaG)) $appraised)
(= (scoredDeltaG (scoredInference $score $candidate $features $appraised $deltaG)) $deltaG)

(= (inferenceRunState (inferenceRun $state $beliefs $trace)) $state)
(= (inferenceRunBeliefs (inferenceRun $state $beliefs $trace)) $beliefs)
(= (inferenceRunTrace (inferenceRun $state $beliefs $trace)) $trace)

;; Best belief about $term, or ().
(= (inferenceRunAnswer (inferenceRun $state $beliefs $trace) $term)
    (plnBestBelief $term $beliefs)
)

;; List helpers

(= (inferenceAppend $list1 $list2) (append $list1 $list2))

;; ($f item) for each item, in order.
(= (inferenceMap $f $list) (collapse (let $x (superpose $list) ($f $x))))

(= (inferenceTake $list $n)
    (if (or (== $list ()) (<= $n 0))
        ()
        (let ($head $tail) (decons $list) (cons-atom $head (inferenceTake $tail (- $n 1)))))
)

(= (inferenceDrop $list $n)
    (if (or (== $list ()) (<= $n 0)) $list (inferenceDrop (cdr-atom $list) (- $n 1)))
)

;; Term structure

;; Concept symbols in a term, skipping link heads.
(= (inferenceTermSymbols $term)
    (case (get-metatype $term) (
        (Symbol ($term))
        (Expression (let $parts (cdr-atom $term)
                        (unique-atom (collapse (let* (($part (superpose $parts))
                                                      ($symbols (inferenceTermSymbols $part)))
                                                     (superpose $symbols))))))
        ($_ ())
    ))
)

;; 1.0 if equal, else scaled share of the target's concepts present.
(= (inferenceTermRelevance $term $target)
    (if (== $term $target)
        1.0
        (let $targetSymbols (inferenceTermSymbols $target)
            (if (== $targetSymbols ())
                0.0
                (* (INFERENCE_PARTIAL_RELEVANCE)
                   (/ (* 1.0 (size-atom (intersection-atom (inferenceTermSymbols $term) $targetSymbols)))
                      (size-atom $targetSymbols)))))
    )
)

;; rel(h, T): best relevance over all targets.
(= (inferenceRelevance $term $targets)
    (max-atom (cons-atom 0.0 (collapse (let $target (superpose $targets)
                                           (inferenceTermRelevance $term $target)))))
)

;; Domain annotations

;; Rule profile (novelty risk effort), neutral when missing.
(= (inferenceRuleProfile $rule)
    (let $found (collapse (match &self (InferenceRuleProfile $rule $n $r $e) ($n $r $e)))
        (if (== $found ()) (0.5 0.5 0.5) (car-atom $found)))
)

;; Summed InferenceRiskTag weights; negative means reassuring.
(= (inferenceTagRisk $symbols)
    (sum (collapse (let $symbol (superpose $symbols) (match &self (InferenceRiskTag $symbol $w) $w))))
)

;; Summed InferenceGoalTag weights for one goal.
(= (inferenceTagGoal $symbols $goal)
    (sum (collapse (let $symbol (superpose $symbols) (match &self (InferenceGoalTag $symbol $goal $w) $w))))
)

;; Goal names in GoalIndex order.
(= (inferenceGoalNames) (inferenceGoalNamesFrom 0))

(= (inferenceGoalNamesFrom $idx)
    (if (>= $idx (NUM_GOALS))
        ()
        (cons-atom (match &self (GoalIndex $name $idx) $name) (inferenceGoalNamesFrom (+ $idx 1))))
)

;; Goals in the score sum: those MAGUS maps to modulators.
(= (inferenceTaskGoals)
    (collapse (match &self (goalModulatorRelevance $goal $mods) $goal))
)

;; Candidate generation

;; Rule applications over belief pairs with disjoint stamps, minus known conclusions.
(= (inferenceCandidates $beliefs)
    (inferenceDedupe
        (collapse
            (let* (
                ((belief $t1 $tv1 $s1) (superpose $beliefs))
                ((belief $t2 $tv2 $s2) (superpose $beliefs))
            )
                (if (StampDisjoint $s1 $s2)
                    (let ($rule ($term $tv)) (plnApplyRule ($t1 $tv1) ($t2 $tv2))
                        (inferenceCandidate $rule $term $tv (StampConcat $s1 $s2) ($t1 $t2)))
                    (empty))))
        (collapse (let (belief $term $tv $stamp) (superpose $beliefs) ($term $stamp))))
)

;; Keeps the first candidate per (conclusion, stamp) not already in $seen.
(= (inferenceDedupe $candidates $seen)
    (if (== $candidates ())
        ()
        (let* (
            (($head $tail) (decons $candidates))
            ((inferenceCandidate $rule $term $tv $stamp $premises) $head)
        )
            (if (is-member ($term $stamp) $seen)
                (inferenceDedupe $tail $seen)
                (cons-atom $head (inferenceDedupe $tail (cons-atom ($term $stamp) $seen))))))
)

;; Step 1: appraisal (Psi)

;; Domain risk of a conclusion: risk tags scaled by strength; negative is reassuring.
(= (inferenceDomainRisk $term (stv $s $c))
    (npClip (* (INFERENCE_RISK_DOMAIN_WEIGHT) (* $s (inferenceTagRisk (inferenceTermSymbols $term)))) -1.0 1.0)
)

;; Features of (r, H); $relevance is rel(h, T), computed before appraisal.
(= (inferenceFeatures $candidate $relevance $beliefs)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        (($ruleNovelty $ruleRisk $ruleEffort) (inferenceRuleProfile $rule))
        ($known (plnKnownConfidence $term $beliefs))
        ($novelty (npClip
            (+ (* (INFERENCE_NOVELTY_UNKNOWN_WEIGHT) (- 1.0 $known))
               (* (INFERENCE_NOVELTY_RULE_WEIGHT) $ruleNovelty))
            0.0 1.0))
        ($gain (positivePart (- $c $known)))
        ;; Uncertainty left by the proof, minus uncertainty it resolves on the task.
        ($signedRisk (npClip
            (+ (+ (* (INFERENCE_RISK_RULE_WEIGHT) $ruleRisk)
                  (* (INFERENCE_RISK_UNCERTAINTY_WEIGHT) (- (- 1.0 $c) (* $relevance $gain))))
               (inferenceDomainRisk $term (stv $s $c)))
            -1.0 1.0))
        ($effort (npClip
            (+ (* (INFERENCE_EFFORT_RULE_WEIGHT) $ruleEffort)
               (* (- 1.0 (INFERENCE_EFFORT_RULE_WEIGHT))
                  (/ (size-atom $stamp) (INFERENCE_EFFORT_DEPTH_REF))))
            0.0 1.0))
    )
        (candidateFeatures $novelty (* $relevance $c) (positivePart $signedRisk) $signedRisk $effort
                           $relevance $ruleNovelty $known $gain)
    )
)

;; Stimulus (novelty conduciveness risk effort). Risk is signed: a reassuring
;; proof enters as negative risk, so OpenPsi lowers threshold and securing.
(= (inferenceStimulus (candidateFeatures $novelty $conduciveness $risk $signedRisk $effort $relevance $ruleNovelty $known $gain))
    (stimulus ($novelty $conduciveness $signedRisk $effort))
)

;; ((G, M), r, H) -> (G, M')
(= (inferenceAppraise $state $features)
    (appraise (inferenceAppraisalModule) $state (inferenceStimulus $features))
)

;; Step 2: decision (D)

;; rel_i(r, H) in [-1, 1]: alignment with goal i on the task, including domain goal tags.
(= (inferenceGoalRelevance $goal $term $strength
                           (candidateFeatures $novelty $conduciveness $risk $signedRisk $effort $relevance $ruleNovelty $known $gain))
    (npClip
        (* $relevance
           (+ (case $goal (
                  (gHelp 1.0)
                  (gCurio $novelty)
                  (gNovel (* $ruleNovelty (- 1.0 $known)))
                  (gSelf $gain)
                  (gEthic (- 1.0 (* 2.0 $risk)))
                  ($_ 0.0)
              ))
              (* $strength (inferenceTagGoal (inferenceTermSymbols $term) $goal))))
        -1.0 1.0)
)

;; max(budget spent, safety boundary pressure).
(= (inferencePressure $state $executedSoFar)
    (max (npClip (/ (* 1.0 $executedSoFar) (INFERENCE_BUDGET)) 0.0 1.0)
         (boundaryPressure $state))
)

;; Near limits gInd raises the effective risk penalty and gTrans softens it.
(= (inferencePenaltyScale $state $pressure)
    (positivePart (+ 1.0 (* $pressure (- (getGoal $state gInd) (getGoal $state gTrans)))))
)

;; score(r, H) = sum_i g_i m'_i rel_i - lambdaInd gInd risk + lambdaTrans gTrans
(= (inferenceScore $state $appraised $term $strength $features $penaltyScale)
    (let* (
        ((candidateFeatures $novelty $conduciveness $risk $signedRisk $effort $relevance $ruleNovelty $known $gain) $features)
        ($goals (inferenceTaskGoals))
        ($goalTerm (sum (collapse (let $goal (superpose $goals)
                     (* (* (getGoal $state $goal) (magusRelevantModulator $appraised $goal))
                        (inferenceGoalRelevance $goal $term $strength $features))))))
    )
        (+ (- $goalTerm (* $penaltyScale (* (* (LAMBDA_IND) (getGoal $state gInd)) $risk)))
           (* (LAMBDA_TRANS) (getGoal $state gTrans)))
    )
)

;; Goal change a proof proposes: served goals grow, domain risk moves gInd
;; (unsafe findings raise it, safety and ethics proofs lower it), safe novelty moves gTrans.
(= (inferenceGoalDelta $goal $term (stv $s $c) $features)
    (let (candidateFeatures $novelty $conduciveness $risk $signedRisk $effort $relevance $ruleNovelty $known $gain) $features
        (case $goal (
            (gInd (* (INFERENCE_IND_RATE) (* $c (inferenceDomainRisk $term (stv $s $c)))))
            (gTrans (* (INFERENCE_TRANS_RATE) (* $c (- $novelty $risk))))
            ($_ (* (INFERENCE_GOAL_RATE) (* $c (inferenceGoalRelevance $goal $term $s $features))))
        )))
)

;; Appraise and score one candidate.
(= (scoreInference $state $candidate $relevance $beliefs $penaltyScale)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        ($features (inferenceFeatures $candidate $relevance $beliefs))
        ($appraised (inferenceAppraise $state $features))
        ($goals (inferenceGoalNames))
    )
        (scoredInference (inferenceScore $state $appraised $term $s $features $penaltyScale)
                         $candidate $features $appraised
                         (collapse (let $goal (superpose $goals) (inferenceGoalDelta $goal $term (stv $s $c) $features))))
    )
)

;; Step 3: dynamic allocation and pruning

;; Breadth: arousal, gCurio, gSelf, gTrans. Cutoff: threshold, gEthic, gInd. Depth: resolution, gHelp.
(= (computeInferenceAllocation $state)
    (let* (
        ($widen (npClip
            (* (* (getModulator $state arousal)
                  (+ (* 0.5 (getGoal $state gCurio)) (* 0.5 (getGoal $state gSelf))))
               (+ 0.5 (getGoal $state gTrans)))
            0.0 1.0))
        ($cutoff (+ (INFERENCE_CUTOFF_MIN)
                    (* (INFERENCE_CUTOFF_SPAN)
                       (* (getModulator $state threshold)
                          (* (getGoal $state gEthic) (+ 0.5 (getGoal $state gInd)))))))
    )
        (inferenceAllocation
            (+ (INFERENCE_K_MIN) (floor-math (+ (* (- (INFERENCE_K_MAX) (INFERENCE_K_MIN)) $widen) 0.5)))
            (min (INFERENCE_CUTOFF_MAX) $cutoff)
            (* (getModulator $state resolution) (getGoal $state gHelp)))
    )
)

;; d_max(h): proofs go deeper on the most relevant subgraphs.
(= (inferenceMaxDepth (inferenceAllocation $k $cutoff $deepen) $relevance)
    (+ (INFERENCE_DEPTH_MIN) (floor-math (+ (* (INFERENCE_DEPTH_SPAN) (* $deepen $relevance)) 0.5)))
)

;; Checks that need no appraisal: lowConfidence, tooDeep or ok.
(= (inferencePrePruneReason (inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $relevance $allocation)
    (if (< $c (allocationCutoff $allocation))
        lowConfidence
        (if (> (size-atom $stamp) (inferenceMaxDepth $allocation $relevance)) tooDeep ok))
)

;; Descending by score; ties keep their order.
(= (inferenceSortByScore $scoredList)
    (if (== $scoredList ())
        ()
        (let ($head $tail) (decons $scoredList)
            (inferenceInsertByScore $head (inferenceSortByScore $tail))))
)

(= (inferenceInsertByScore $item $sorted)
    (if (== $sorted ())
        ($item)
        (let ($head $tail) (decons $sorted)
            (if (>= (scoredScore $item) (scoredScore $head))
                (cons-atom $item $sorted)
                (cons-atom $head (inferenceInsertByScore $item $tail)))))
)

;; Step 4: incremental self-model coherence

;; alpha = alpha0 (1 - gInd) + beta0 gTrans
(= (inferenceBlendFactor $state)
    (npClip
        (+ (* (INFERENCE_ALPHA_0) (- 1.0 (getGoal $state gInd)))
           (* (INFERENCE_BETA_0) (getGoal $state gTrans)))
        0.0 1.0)
)

;; Score-weighted mean of (score vector) pairs; plain mean if all scores are 0.
(= (inferenceWeightedMean $pairs)
    (let* (
        ($total (sum (collapse (let ($w $v) (superpose $pairs) $w))))
        ($n (size-atom $pairs))
    )
        (inferenceSumVectors (collapse (let ($w $v) (superpose $pairs)
                                           (scaleArray $v (if (> $total 0.0) (/ $w $total) (/ 1.0 $n)))))))
)

(= (inferenceSumVectors $vectors)
    (let ($head $tail) (decons $vectors)
        (if (== $tail ()) $head (vectorAdd $head (inferenceSumVectors $tail))))
)

;; x*: the executed proofs' goal changes (damped) and appraised modulators,
;; averaged with their scores as weights, kept in the safe region.
(= (inferenceTargetState $state $executed)
    (let* (
        ($deltaG (applyHomeostaticDamping $state
                    (inferenceWeightedMean (collapse (let $item (superpose $executed)
                                                         ((scoredScore $item) (scoredDeltaG $item)))))))
        ($goals (clipVector (vectorAdd (motivationGoals $state) $deltaG) 0.0 1.0))
        ($mods (inferenceWeightedMean (collapse (let $item (superpose $executed)
                                                    ((scoredScore $item) (motivationModulators (scoredAppraised $item)))))))
        ($target (raiseBoundaryCaution (motivation $goals $mods)))
    )
        (if (isInSafeRegion $target) $target (projectToSafeRegion $target))
    )
)

;; x_{t+1} = (1 - alpha) x_t + alpha x*. The shift is alpha d(x_t, x*), so near
;; the boundary alpha is capped to keep shift <= CONTRACTION * previous + EPSILON.
;; Returns (blendStep $next $shift).
(= (inferenceBlend $state $target $previousShift)
    (let* (
        ($distance (motivationStateDistance $state $target))
        ($alpha (inferenceBlendFactor $state))
        ($limit (+ (* (INFERENCE_CONTRACTION) $previousShift) (INFERENCE_CONTRACTION_EPSILON)))
        ($capped (if (and (> (boundaryPressure $state) 0.0) (> (* $alpha $distance) $limit))
                     (/ $limit $distance)
                     $alpha))
    )
        (blendStep (stateTowardTarget $state $target $capped) (* $capped $distance))
    )
)

;; Blend toward the step's x*. Returns (blendStep $state $shift).
(= (inferenceBlendProofs $state $executed $shift)
    (if (== $executed ())
        (blendStep $state $shift)
        (inferenceBlend $state (inferenceTargetState $state $executed) $shift))
)

;; Control step and loop

;; -> (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation $shift)
(= (inferenceControlStep $state $beliefs $targets $executedSoFar $shift)
    (let* (
        ($allocation (computeInferenceAllocation $state))
        ($penaltyScale (inferencePenaltyScale $state (inferencePressure $state $executedSoFar)))
        ($candidates (inferenceCandidates $beliefs))
        ($checked (collapse (let* (($candidate (superpose $candidates))
                                   ((inferenceCandidate $r $term $tv $st $p) $candidate)
                                   ($relevance (inferenceRelevance $term $targets)))
                                ((inferencePrePruneReason $candidate $relevance $allocation) $relevance $candidate))))
        ($scored (collapse (let ($reason $relevance $candidate) (superpose $checked)
                               (if (== $reason ok)
                                   (scoreInference $state $candidate $relevance $beliefs $penaltyScale)
                                   (empty)))))
        ($pruned (append
                    (collapse (let ($reason $relevance $candidate) (superpose $checked)
                                  (if (== $reason ok) (empty) (pruned $reason $candidate))))
                    (collapse (let $item (superpose $scored)
                                  (if (< (scoredScore $item) (INFERENCE_SCORE_FLOOR))
                                      (pruned lowScore (scoredCandidate $item))
                                      (empty))))))
        ($ranked (inferenceSortByScore (collapse (let $item (superpose $scored)
                                                     (if (< (scoredScore $item) (INFERENCE_SCORE_FLOOR)) (empty) $item)))))
        ($executed (inferenceTake $ranked (allocationBreadth $allocation)))
        ((blendStep $next $nextShift) (inferenceBlendProofs $state $executed $shift))
    )
        (inferenceStepResult
            $next
            (append $beliefs (inferenceMap candidateBelief (inferenceMap scoredCandidate $executed)))
            $executed
            (inferenceDrop $ranked (allocationBreadth $allocation))
            $pruned
            $allocation
            $nextShift)
    )
)

;; First step of a run.
(= (inferenceControlStep $state $beliefs $targets $executedSoFar)
    (inferenceControlStep $state $beliefs $targets $executedSoFar (INFERENCE_INITIAL_SHIFT))
)

(= (inferenceSummary (scoredInference $score (inferenceCandidate $rule $term $tv $stamp $premises) $features $appraised $deltaG))
    (fired $rule $term $tv (roundNum $score 3))
)

;; Trace entry: (inferenceStep $step $allocation $fired $deferred $pruned $state)
(= (inferenceControlLoop $state $beliefs $targets $step $maxSteps $executedSoFar $shift $trace)
    (if (> $step $maxSteps)
        (inferenceRun $state $beliefs $trace)
        (let* (
            ((inferenceStepResult $next $nextBeliefs $executed $deferred $pruned $allocation $nextShift)
             (inferenceControlStep $state $beliefs $targets $executedSoFar $shift))
            ($nextTrace (append $trace ((inferenceStep $step $allocation (inferenceMap inferenceSummary $executed)
                                                       (size-atom $deferred) (size-atom $pruned) $next))))
        )
            (if (== $executed ())
                (inferenceRun $state $beliefs $nextTrace)
                (inferenceControlLoop $next $nextBeliefs $targets (+ $step 1) $maxSteps
                                      (+ $executedSoFar (size-atom $executed)) $nextShift $nextTrace)))
    )
)

;; Example: (runInferenceControl $state (((Inheritance a b) (stv 0.9 0.9)) ...) ((Inheritance a c)) 3)
(= (runInferenceControl $state $facts $targets $maxSteps)
    (runInferenceControlOn $state (plnMakeBeliefs $facts 1) $targets $maxSteps)
)

(= (runInferenceControlOn $state $beliefs $targets $maxSteps)
    (inferenceControlLoop $state $beliefs $targets 1 $maxSteps 0 (INFERENCE_INITIAL_SHIFT) ())
)
