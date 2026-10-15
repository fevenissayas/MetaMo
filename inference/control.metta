;; MetaMo-driven PLN inference control.
;; Appraise each candidate (r, H), score it with MAGUS, run the top-k,
;; and blend the state with alpha = alpha0 (1 - gInd) + beta0 gTrans.
;; Entry point: (runInferenceControl $state $facts $targets $maxSteps)

;; Data constructors

;; (inferenceCandidate $rule $conclusion $tv $stamp $premises)
(= (candidateRule (inferenceCandidate $rule $term $tv $stamp $premises)) $rule)
(= (candidateTerm (inferenceCandidate $rule $term $tv $stamp $premises)) $term)
(= (candidateTV (inferenceCandidate $rule $term $tv $stamp $premises)) $tv)
(= (candidateStamp (inferenceCandidate $rule $term $tv $stamp $premises)) $stamp)
(= (candidateBelief (inferenceCandidate $rule $term $tv $stamp $premises))
    (belief $term $tv $stamp)
)

;; (inferenceAllocation $breadth $confidenceCutoff $maxDepth)
(= (allocationBreadth (inferenceAllocation $k $cutoff $depth)) $k)
(= (allocationCutoff (inferenceAllocation $k $cutoff $depth)) $cutoff)
(= (allocationDepth (inferenceAllocation $k $cutoff $depth)) $depth)

;; (scoredInference $score $candidate $appraisedState $action)
(= (scoredScore (scoredInference $score $candidate $appraised $action)) $score)
(= (scoredCandidate (scoredInference $score $candidate $appraised $action)) $candidate)
(= (scoredAppraised (scoredInference $score $candidate $appraised $action)) $appraised)
(= (scoredAction (scoredInference $score $candidate $appraised $action)) $action)

;; (inferenceRun $finalState $beliefs $trace)
(= (inferenceRunState (inferenceRun $state $beliefs $trace)) $state)
(= (inferenceRunBeliefs (inferenceRun $state $beliefs $trace)) $beliefs)
(= (inferenceRunTrace (inferenceRun $state $beliefs $trace)) $trace)

;; Best belief about $term, or ().
(= (inferenceRunAnswer (inferenceRun $state $beliefs $trace) $term)
    (plnBestBelief $term $beliefs)
)

;; List helpers

(= (inferenceAppend $list1 $list2)
    (if (== $list1 ())
        $list2
        (let ($head $tail) (decons $list1)
            (cons-atom $head (inferenceAppend $tail $list2))
        )
    )
)

(= (inferenceTake $list $n)
    (if (or (== $list ()) (<= $n 0))
        ()
        (let ($head $tail) (decons $list)
            (cons-atom $head (inferenceTake $tail (- $n 1)))
        )
    )
)

(= (inferenceDrop $list $n)
    (if (or (== $list ()) (<= $n 0))
        $list
        (inferenceDrop (cdr-atom $list) (- $n 1))
    )
)

;; Element-wise mean of equal-length vectors.
(= (inferenceMeanVectors $vectors)
    (scaleArray (inferenceSumVectors $vectors) (/ 1.0 (size-atom $vectors)))
)

(= (inferenceSumVectors $vectors)
    (let ($head $tail) (decons $vectors)
        (if (== $tail ())
            $head
            (vectorAdd $head (inferenceSumVectors $tail))
        )
    )
)

;; Term structure

;; Concept symbols in a term, skipping link heads.
(= (inferenceTermSymbols $term)
    (case (get-metatype $term) (
        (Symbol ($term))
        (Expression (inferenceTermSymbolsList (cdr-atom $term)))
        ($_ ())
    ))
)

(= (inferenceTermSymbolsList $terms)
    (if (== $terms ())
        ()
        (let ($head $tail) (decons $terms)
            (union-atom (inferenceTermSymbols $head) (inferenceTermSymbolsList $tail))
        )
    )
)

;; 1.0 if equal, else scaled share of the target's concepts present.
(= (inferenceTermRelevance $term $target)
    (if (== $term $target)
        1.0
        (let $targetSymbols (inferenceTermSymbols $target)
            (if (== $targetSymbols ())
                0.0
                (let $shared (intersection-atom (inferenceTermSymbols $term) $targetSymbols)
                    (* (INFERENCE_PARTIAL_RELEVANCE)
                       (/ (* 1.0 (size-atom $shared)) (size-atom $targetSymbols)))
                )
            )
        )
    )
)

;; Best relevance over all targets.
(= (inferenceRelevance $term $targets)
    (if (== $targets ())
        0.0
        (let ($head $tail) (decons $targets)
            (max (inferenceTermRelevance $term $head) (inferenceRelevance $term $tail))
        )
    )
)

;; Domain annotations

;; Rule profile (novelty risk effort), neutral when missing.
(= (inferenceRuleProfile $rule)
    (let $found (collapse (match &self (InferenceRuleProfile $rule $n $r $e) ($n $r $e)))
        (if (== $found ()) (0.5 0.5 0.5) (car-atom $found))
    )
)

;; Summed InferenceRiskTag weights; negative means reassuring.
(= (inferenceTagRisk $symbols)
    (if (== $symbols ())
        0.0
        (let ($head $tail) (decons $symbols)
            (+ (sum (collapse (match &self (InferenceRiskTag $head $w) $w)))
               (inferenceTagRisk $tail))
        )
    )
)

;; Domain risk scaled by conclusion strength.
(= (inferenceDomainRisk $term $strength)
    (* $strength (inferenceTagRisk (inferenceTermSymbols $term)))
)

;; Summed InferenceGoalTag weights for one goal.
(= (inferenceTagGoal $symbols $goal)
    (if (== $symbols ())
        0.0
        (let ($head $tail) (decons $symbols)
            (+ (sum (collapse (match &self (InferenceGoalTag $head $goal $w) $w)))
               (inferenceTagGoal $tail $goal))
        )
    )
)

;; Goal names in GoalIndex order.
(= (inferenceGoalNames)
    (inferenceGoalNamesFrom 0 (NUM_GOALS))
)

(= (inferenceGoalNamesFrom $idx $count)
    (if (>= $idx $count)
        ()
        (cons-atom (match &self (GoalIndex $name $idx) $name)
                   (inferenceGoalNamesFrom (+ $idx 1) $count))
    )
)

;; Step 0: candidate generation

;; Rule applications over belief pairs with disjoint stamps, minus known conclusions.
(= (inferenceCandidates $beliefs)
    (inferenceDedupe
        (collapse
            (let* (
                ((belief $t1 $tv1 $s1) (superpose $beliefs))
                ((belief $t2 $tv2 $s2) (superpose $beliefs))
            )
                (if (plnStampDisjoint $s1 $s2)
                    (let ($rule ($term $tv)) (plnApplyRule ($t1 $tv1) ($t2 $tv2))
                        (inferenceCandidate $rule $term $tv (plnStampMerge $s1 $s2) ($t1 $t2))
                    )
                    (empty)
                )
            )
        )
        (inferenceBeliefKeys $beliefs)
    )
)

(= (inferenceBeliefKeys $beliefs)
    (if (== $beliefs ())
        ()
        (let ((belief $term $tv $stamp) $tail) (decons $beliefs)
            (cons-atom ($term $stamp) (inferenceBeliefKeys $tail))
        )
    )
)

(= (inferenceDedupe $candidates $seen)
    (if (== $candidates ())
        ()
        (let* (
            (($head $tail) (decons $candidates))
            ($key ((candidateTerm $head) (candidateStamp $head)))
        )
            (if (is-member $key $seen)
                (inferenceDedupe $tail $seen)
                (cons-atom $head (inferenceDedupe $tail (cons-atom $key $seen)))
            )
        )
    )
)

;; Step 1: appraisal (Psi)

;; (candidateFeatures novelty relevance risk effort ruleNovelty known gain)
(= (inferenceFeatures $candidate $beliefs $targets)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        (($ruleNovelty $ruleRisk $ruleEffort) (inferenceRuleProfile $rule))
        ($known (plnKnownConfidence $term $beliefs))
        ($novelty (plnClamp
            (+ (* (INFERENCE_NOVELTY_UNKNOWN_WEIGHT) (- 1.0 $known))
               (* (INFERENCE_NOVELTY_RULE_WEIGHT) $ruleNovelty))
            0.0 1.0))
        ($relevance (inferenceRelevance $term $targets))
        ($risk (plnClamp
            (+ (+ (* (INFERENCE_RISK_RULE_WEIGHT) $ruleRisk)
                  (* (INFERENCE_RISK_UNCERTAINTY_WEIGHT) (- 1.0 $c)))
               (* (INFERENCE_RISK_DOMAIN_WEIGHT) (inferenceDomainRisk $term $s)))
            0.0 1.0))
        ($effort (plnClamp
            (+ (* (INFERENCE_EFFORT_RULE_WEIGHT) $ruleEffort)
               (* (- 1.0 (INFERENCE_EFFORT_RULE_WEIGHT))
                  (/ (size-atom $stamp) (INFERENCE_EFFORT_DEPTH_REF))))
            0.0 1.0))
        ($gain (positivePart (- $c $known)))
    )
        (candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain)
    )
)

;; Candidate as an OpenPSI stimulus (novelty conduciveness risk effort).
(= (inferenceStimulus $candidate $features)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        ((candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain) $features)
    )
        (stimulus ($novelty (* $relevance (+ 0.5 (* 0.5 $c))) $risk $effort))
    )
)

;; ((G, M), r, H) -> (G, M')
(= (inferenceAppraise $state $candidate $features)
    (appraise (inferenceAppraisalModule) $state (inferenceStimulus $candidate $features))
)

;; Step 2: decision (D)

;; rel_i(r, H) in [-1, 1].
(= (inferenceBaseRelevance $goal (candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain))
    (case $goal (
        (gHelp $relevance)
        (gCurio $novelty)
        (gNovel (* $ruleNovelty (- 1.0 $known)))
        (gSelf $gain)
        (gEthic (- 1.0 (* 2.0 $risk)))
        ($_ 0.0)
    ))
)

(= (inferenceGoalRelevance $goal $term $strength $features)
    (plnClamp
        (+ (inferenceBaseRelevance $goal $features)
           (* $strength (inferenceTagGoal (inferenceTermSymbols $term) $goal)))
        -1.0 1.0)
)

(= (inferenceRelevanceVector $goals $term $strength $features)
    (if (== $goals ())
        ()
        (let ($head $tail) (decons $goals)
            (cons-atom (inferenceGoalRelevance $head $term $strength $features)
                       (inferenceRelevanceVector $tail $term $strength $features))
        )
    )
)

;; Proposed deltaG: served goals grow, risk raises gInd, novelty feeds gTrans.
(= (inferenceDeltaVector $goals $correlations $confidence $features)
    (if (== $goals ())
        ()
        (let* (
            (($goal $goalsTail) (decons $goals))
            (($corr $corrTail) (decons $correlations))
            ((candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain) $features)
            ($delta (case $goal (
                (gInd (* (INFERENCE_IND_RATE) (* $confidence (- $risk 0.3))))
                (gTrans (* (INFERENCE_TRANS_RATE) (- $novelty 0.5)))
                ($_ (* (INFERENCE_GOAL_RATE) (* $corr $confidence)))
            )))
        )
            (cons-atom $delta (inferenceDeltaVector $goalsTail $corrTail $confidence $features))
        )
    )
)

;; Candidate as a MAGUS action.
(= (inferenceAction $candidate $features)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        ((candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain) $features)
        ($goals (inferenceGoalNames))
        ($correlations (inferenceRelevanceVector $goals $term $s $features))
    )
        (action (inference $rule $term) $correlations $risk
                (inferenceDeltaVector $goals $correlations $c $features))
    )
)

;; max(budget spent, safety boundary pressure).
(= (inferencePressure $state $executedSoFar)
    (max (plnClamp (/ (* 1.0 $executedSoFar) (INFERENCE_BUDGET)) 0.0 1.0)
         (boundaryPressure $state))
)

;; gInd raises the penalty near limits, gTrans softens it.
(= (inferenceThrottle $state $pressure)
    (* $pressure
       (positivePart
           (- (* (LAMBDA_IND) (getGoal $state gInd))
              (* (INFERENCE_TRANS_SOFTENING) (* (LAMBDA_TRANS) (getGoal $state gTrans))))))
)

;; Appraise and score one candidate.
(= (scoreInference $state $candidate $beliefs $targets $throttle)
    (let* (
        ($features (inferenceFeatures $candidate $beliefs $targets))
        ($appraised (inferenceAppraise $state $candidate $features))
        ($action (inferenceAction $candidate $features))
        ($score (- (scoreCandidate (inferenceDecisionModule) $appraised $action) $throttle))
    )
        (scoredInference $score $candidate $appraised $action)
    )
)

(= (scoreInferences $state $candidates $beliefs $targets $throttle)
    (if (== $candidates ())
        ()
        (let ($head $tail) (decons $candidates)
            (cons-atom (scoreInference $state $head $beliefs $targets $throttle)
                       (scoreInferences $state $tail $beliefs $targets $throttle))
        )
    )
)

;; Step 3: dynamic allocation and pruning

;; Breadth: arousal, gCurio/gNovel, gTrans. Cutoff: threshold, gEthic, gInd. Depth: resolution, gHelp.
(= (computeInferenceAllocation $state)
    (let* (
        ($gInd (getGoal $state gInd))
        ($gTrans (getGoal $state gTrans))
        ($gHelp (getGoal $state gHelp))
        ($gCurio (getGoal $state gCurio))
        ($gNovel (getGoal $state gNovel))
        ($gEthic (getGoal $state gEthic))
        ($arousal (getModulator $state arousal))
        ($threshold (getModulator $state threshold))
        ($resolution (getModulator $state resolution))
        ($widen (plnClamp
            (* (* $arousal (+ (* 0.5 $gCurio) (* 0.5 $gNovel))) (+ 0.5 $gTrans))
            0.0 1.0))
        ($breadth (+ (INFERENCE_K_MIN)
                     (floor-math (+ (* (- (INFERENCE_K_MAX) (INFERENCE_K_MIN)) $widen) 0.5))))
        ($cutoff (min (INFERENCE_CUTOFF_MAX)
                      (+ (INFERENCE_CUTOFF_MIN)
                         (* (INFERENCE_CUTOFF_SPAN) (* $threshold (* $gEthic (+ 0.5 $gInd)))))))
        ($depth (+ (INFERENCE_DEPTH_MIN)
                   (floor-math (+ (* (INFERENCE_DEPTH_SPAN) (* $resolution $gHelp)) 0.5))))
    )
        (inferenceAllocation $breadth $cutoff $depth)
    )
)

;; lowConfidence, tooDeep, lowScore or ok.
(= (inferencePruneReason $scored $allocation)
    (let* (
        ($candidate (scoredCandidate $scored))
        ((stv $s $c) (candidateTV $candidate))
    )
        (if (< $c (allocationCutoff $allocation))
            lowConfidence
            (if (> (size-atom (candidateStamp $candidate)) (allocationDepth $allocation))
                tooDeep
                (if (< (scoredScore $scored) (INFERENCE_SCORE_FLOOR))
                    lowScore
                    ok
                )
            )
        )
    )
)

;; Returns (eligible pruned); pruned items are (pruned $reason $scored).
(= (inferencePartition $scoredList $allocation)
    (if (== $scoredList ())
        (() ())
        (let* (
            (($head $tail) (decons $scoredList))
            (($eligible $pruned) (inferencePartition $tail $allocation))
            ($reason (inferencePruneReason $head $allocation))
        )
            (if (== $reason ok)
                ((cons-atom $head $eligible) $pruned)
                ($eligible (cons-atom (pruned $reason $head) $pruned))
            )
        )
    )
)

;; Descending by score.
(= (inferenceSortByScore $scoredList)
    (if (== $scoredList ())
        ()
        (let ($head $tail) (decons $scoredList)
            (inferenceInsertByScore $head (inferenceSortByScore $tail))
        )
    )
)

(= (inferenceInsertByScore $item $sorted)
    (if (== $sorted ())
        ($item)
        (let ($head $tail) (decons $sorted)
            (if (>= (scoredScore $item) (scoredScore $head))
                (cons-atom $item $sorted)
                (cons-atom $head (inferenceInsertByScore $item $tail))
            )
        )
    )
)

;; Step 4: incremental self-model coherence

;; alpha = alpha0 (1 - gInd) + beta0 gTrans
(= (inferenceBlendFactor $state)
    (plnClamp
        (+ (* (INFERENCE_ALPHA_0) (- 1.0 (getGoal $state gInd)))
           (* (INFERENCE_BETA_0) (getGoal $state gTrans)))
        0.0 1.0)
)

;; x*: damped mean deltaG, mean appraised modulators, then safety projection.
(= (inferenceTargetState $state $executed)
    (let* (
        ($deltas (inferenceExecutedDeltas $executed))
        ($mods (inferenceExecutedModulators $executed))
        ($deltaG (applyHomeostaticDamping $state (inferenceMeanVectors $deltas)))
        ($goals (clipVector (vectorAdd (motivationGoals $state) $deltaG) 0.0 1.0))
        ($cautious (raiseBoundaryCaution (motivation $goals (inferenceMeanVectors $mods))))
    )
        (if (isInSafeRegion $cautious) $cautious (projectToSafeRegion $cautious))
    )
)

(= (inferenceExecutedDeltas $executed)
    (if (== $executed ())
        ()
        (let ($head $tail) (decons $executed)
            (cons-atom (actionDeltaG (scoredAction $head)) (inferenceExecutedDeltas $tail))
        )
    )
)

(= (inferenceExecutedModulators $executed)
    (if (== $executed ())
        ()
        (let ($head $tail) (decons $executed)
            (cons-atom (motivationModulators (scoredAppraised $head))
                       (inferenceExecutedModulators $tail))
        )
    )
)

;; x_{t+1} = (1 - alpha) x_t + alpha x*
(= (inferenceBlend $state $target)
    (stateTowardTarget $state $target (inferenceBlendFactor $state))
)

;; Control step and loop

(= (inferenceExecutedBeliefs $executed)
    (if (== $executed ())
        ()
        (let ($head $tail) (decons $executed)
            (cons-atom (candidateBelief (scoredCandidate $head)) (inferenceExecutedBeliefs $tail))
        )
    )
)

;; -> (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation)
(= (inferenceControlStep $state $beliefs $targets $executedSoFar)
    (let* (
        ($allocation (computeInferenceAllocation $state))
        ($throttle (inferenceThrottle $state (inferencePressure $state $executedSoFar)))
        ($scored (scoreInferences $state (inferenceCandidates $beliefs) $beliefs $targets $throttle))
        (($eligible $pruned) (inferencePartition $scored $allocation))
        ($ranked (inferenceSortByScore $eligible))
        ($executed (inferenceTake $ranked (allocationBreadth $allocation)))
        ($deferred (inferenceDrop $ranked (allocationBreadth $allocation)))
        ($nextState (if (== $executed ())
                        $state
                        (inferenceBlend $state (inferenceTargetState $state $executed))))
    )
        (inferenceStepResult
            $nextState
            (inferenceAppend $beliefs (inferenceExecutedBeliefs $executed))
            $executed
            $deferred
            $pruned
            $allocation)
    )
)

(= (inferenceSummary $scored)
    (let (inferenceCandidate $rule $term $tv $stamp $premises) (scoredCandidate $scored)
        (fired $rule $term $tv (roundNum (scoredScore $scored) 3))
    )
)

(= (inferenceSummaries $scoredList)
    (if (== $scoredList ())
        ()
        (let ($head $tail) (decons $scoredList)
            (cons-atom (inferenceSummary $head) (inferenceSummaries $tail))
        )
    )
)

;; Trace entry: (inferenceStep $step $allocation $fired $deferred $pruned $state)
(= (inferenceControlLoop $state $beliefs $targets $step $maxSteps $executedSoFar $trace)
    (if (> $step $maxSteps)
        (inferenceRun $state $beliefs $trace)
        (let (inferenceStepResult $next $nextBeliefs $executed $deferred $pruned $allocation)
             (inferenceControlStep $state $beliefs $targets $executedSoFar)
            (let $entry (inferenceStep $step $allocation (inferenceSummaries $executed)
                                       (size-atom $deferred) (size-atom $pruned) $next)
                (if (== $executed ())
                    (inferenceRun $state $beliefs (inferenceAppend $trace ($entry)))
                    (inferenceControlLoop $next $nextBeliefs $targets (+ $step 1) $maxSteps
                                          (+ $executedSoFar (size-atom $executed))
                                          (inferenceAppend $trace ($entry)))
                )
            )
        )
    )
)

;; Example: (runInferenceControl $state (((Inheritance a b) (stv 0.9 0.9)) ...) ((Inheritance a c)) 3)
(= (runInferenceControl $state $facts $targets $maxSteps)
    (runInferenceControlOn $state (plnMakeBeliefs $facts 1) $targets $maxSteps)
)

(= (runInferenceControlOn $state $beliefs $targets $maxSteps)
    (inferenceControlLoop $state $beliefs $targets 1 $maxSteps 0 ())
)
