;; MetaMo-driven PLN inference control.
;; Appraise each candidate (r, H), score it with MAGUS, run the top-k,
;; and blend the state with alpha = alpha0 (1 - gInd) + beta0 gTrans.
;; Entry point: (runInferenceControl $state $facts $targets $maxSteps)

;; Data
;; (inferenceCandidate $rule $conclusion $tv $stamp $premises)
;; (inferenceAllocation $breadth $confidenceCutoff $maxDepth)
;; (scoredInference $score $candidate $appraisedState $action)
;; (inferenceRun $finalState $beliefs $trace)

(= (candidateBelief (inferenceCandidate $rule $term $tv $stamp $premises)) (belief $term $tv $stamp))

(= (allocationBreadth (inferenceAllocation $k $cutoff $depth)) $k)
(= (allocationCutoff (inferenceAllocation $k $cutoff $depth)) $cutoff)

(= (scoredScore (scoredInference $score $candidate $appraised $action)) $score)
(= (scoredCandidate (scoredInference $score $candidate $appraised $action)) $candidate)

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

;; Element-wise mean of equal-length vectors.
(= (inferenceMeanVectors $vectors)
    (scaleArray (inferenceSumVectors $vectors) (/ 1.0 (size-atom $vectors)))
)

(= (inferenceSumVectors $vectors)
    (let ($head $tail) (decons $vectors)
        (if (== $tail ()) $head (vectorAdd $head (inferenceSumVectors $tail))))
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

;; Best relevance over all targets.
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

;; Step 0: candidate generation

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

;; (candidateFeatures novelty relevance risk effort ruleNovelty known gain)
(= (inferenceFeatures $candidate $beliefs $targets)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        (($ruleNovelty $ruleRisk $ruleEffort) (inferenceRuleProfile $rule))
        ($known (plnKnownConfidence $term $beliefs))
        ($novelty (npClip
            (+ (* (INFERENCE_NOVELTY_UNKNOWN_WEIGHT) (- 1.0 $known))
               (* (INFERENCE_NOVELTY_RULE_WEIGHT) $ruleNovelty))
            0.0 1.0))
        ($risk (npClip
            (+ (+ (* (INFERENCE_RISK_RULE_WEIGHT) $ruleRisk)
                  (* (INFERENCE_RISK_UNCERTAINTY_WEIGHT) (- 1.0 $c)))
               (* (INFERENCE_RISK_DOMAIN_WEIGHT) (* $s (inferenceTagRisk (inferenceTermSymbols $term)))))
            0.0 1.0))
        ($effort (npClip
            (+ (* (INFERENCE_EFFORT_RULE_WEIGHT) $ruleEffort)
               (* (- 1.0 (INFERENCE_EFFORT_RULE_WEIGHT))
                  (/ (size-atom $stamp) (INFERENCE_EFFORT_DEPTH_REF))))
            0.0 1.0))
    )
        (candidateFeatures $novelty (inferenceRelevance $term $targets) $risk $effort
                           $ruleNovelty $known (positivePart (- $c $known)))
    )
)

;; Candidate as an OpenPSI stimulus (novelty conduciveness risk effort).
(= (inferenceStimulus (inferenceCandidate $rule $term (stv $s $c) $stamp $premises)
                      (candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain))
    (stimulus ($novelty (* $relevance (+ 0.5 (* 0.5 $c))) $risk $effort))
)

;; ((G, M), r, H) -> (G, M')
(= (inferenceAppraise $state $candidate $features)
    (appraise (inferenceAppraisalModule) $state (inferenceStimulus $candidate $features))
)

;; Step 2: decision (D)

;; rel_i(r, H) in [-1, 1], plus domain goal tags.
(= (inferenceGoalRelevance $goal $term $strength
                           (candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain))
    (npClip
        (+ (case $goal (
               (gHelp $relevance)
               (gCurio $novelty)
               (gNovel (* $ruleNovelty (- 1.0 $known)))
               (gSelf $gain)
               (gEthic (- 1.0 (* 2.0 $risk)))
               ($_ 0.0)
           ))
           (* $strength (inferenceTagGoal (inferenceTermSymbols $term) $goal)))
        -1.0 1.0)
)

;; Proposed deltaG: served goals grow, risk raises gInd, novelty feeds gTrans.
(= (inferenceGoalDelta $goal $correlation $confidence
                       (candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain))
    (case $goal (
        (gInd (* (INFERENCE_IND_RATE) (* $confidence (- $risk 0.3))))
        (gTrans (* (INFERENCE_TRANS_RATE) (- $novelty 0.5)))
        ($_ (* (INFERENCE_GOAL_RATE) (* $correlation $confidence)))
    ))
)

;; Candidate as a MAGUS action: (action id correlations risk deltaG).
(= (inferenceAction $candidate $features)
    (let* (
        ((inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $candidate)
        ((candidateFeatures $novelty $relevance $risk $effort $ruleNovelty $known $gain) $features)
        ($goals (inferenceGoalNames))
        ($pairs (collapse (let $goal (superpose $goals)
                              ($goal (inferenceGoalRelevance $goal $term $s $features)))))
    )
        (action (inference $rule $term)
                (collapse (let ($goal $corr) (superpose $pairs) $corr))
                $risk
                (collapse (let ($goal $corr) (superpose $pairs) (inferenceGoalDelta $goal $corr $c $features))))
    )
)

;; max(budget spent, safety boundary pressure).
(= (inferencePressure $state $executedSoFar)
    (max (npClip (/ (* 1.0 $executedSoFar) (INFERENCE_BUDGET)) 0.0 1.0)
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
    )
        (scoredInference (- (scoreCandidate (inferenceDecisionModule) $appraised $action) $throttle)
                         $candidate $appraised $action)
    )
)

;; Step 3: dynamic allocation and pruning

;; Breadth: arousal, gCurio/gNovel, gTrans. Cutoff: threshold, gEthic, gInd. Depth: resolution, gHelp.
(= (computeInferenceAllocation $state)
    (let* (
        ($widen (npClip
            (* (* (getModulator $state arousal)
                  (+ (* 0.5 (getGoal $state gCurio)) (* 0.5 (getGoal $state gNovel))))
               (+ 0.5 (getGoal $state gTrans)))
            0.0 1.0))
        ($cutoff (+ (INFERENCE_CUTOFF_MIN)
                    (* (INFERENCE_CUTOFF_SPAN)
                       (* (getModulator $state threshold)
                          (* (getGoal $state gEthic) (+ 0.5 (getGoal $state gInd)))))))
        ($deepen (* (getModulator $state resolution) (getGoal $state gHelp)))
    )
        (inferenceAllocation
            (+ (INFERENCE_K_MIN) (floor-math (+ (* (- (INFERENCE_K_MAX) (INFERENCE_K_MIN)) $widen) 0.5)))
            (min (INFERENCE_CUTOFF_MAX) $cutoff)
            (+ (INFERENCE_DEPTH_MIN) (floor-math (+ (* (INFERENCE_DEPTH_SPAN) $deepen) 0.5))))
    )
)

;; lowConfidence, tooDeep, lowScore or ok.
(= (inferencePruneReason (scoredInference $score (inferenceCandidate $rule $term (stv $s $c) $stamp $premises) $appraised $action)
                         (inferenceAllocation $k $cutoff $depth))
    (if (< $c $cutoff)
        lowConfidence
        (if (> (size-atom $stamp) $depth)
            tooDeep
            (if (< $score (INFERENCE_SCORE_FLOOR)) lowScore ok)))
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

;; x*: damped mean deltaG, mean appraised modulators, then safety projection.
(= (inferenceTargetState $state $executed)
    (let* (
        ($deltas (collapse (let (scoredInference $score $candidate $appraised $action) (superpose $executed)
                               (actionDeltaG $action))))
        ($mods (collapse (let (scoredInference $score $candidate $appraised $action) (superpose $executed)
                             (motivationModulators $appraised))))
        ($deltaG (applyHomeostaticDamping $state (inferenceMeanVectors $deltas)))
        ($goals (clipVector (vectorAdd (motivationGoals $state) $deltaG) 0.0 1.0))
        ($cautious (raiseBoundaryCaution (motivation $goals (inferenceMeanVectors $mods))))
    )
        (if (isInSafeRegion $cautious) $cautious (projectToSafeRegion $cautious))
    )
)

;; x_{t+1} = (1 - alpha) x_t + alpha x*
(= (inferenceBlend $state $target)
    (stateTowardTarget $state $target (inferenceBlendFactor $state))
)

;; Control step and loop

;; -> (inferenceStepResult $next $beliefs $executed $deferred $pruned $allocation)
(= (inferenceControlStep $state $beliefs $targets $executedSoFar)
    (let* (
        ($allocation (computeInferenceAllocation $state))
        ($throttle (inferenceThrottle $state (inferencePressure $state $executedSoFar)))
        ($candidates (inferenceCandidates $beliefs))
        ($scored (collapse (let $candidate (superpose $candidates)
                               (scoreInference $state $candidate $beliefs $targets $throttle))))
        ($reasons (collapse (let $item (superpose $scored)
                                ((inferencePruneReason $item $allocation) $item))))
        ($pruned (collapse (let ($reason $item) (superpose $reasons)
                               (if (== $reason ok) (empty) (pruned $reason $item)))))
        ($ranked (inferenceSortByScore (collapse (let ($reason $item) (superpose $reasons)
                                                     (if (== $reason ok) $item (empty))))))
        ($executed (inferenceTake $ranked (allocationBreadth $allocation)))
    )
        (inferenceStepResult
            (if (== $executed ()) $state (inferenceBlend $state (inferenceTargetState $state $executed)))
            (append $beliefs (inferenceMap candidateBelief (inferenceMap scoredCandidate $executed)))
            $executed
            (inferenceDrop $ranked (allocationBreadth $allocation))
            $pruned
            $allocation)
    )
)

(= (inferenceSummary (scoredInference $score (inferenceCandidate $rule $term $tv $stamp $premises) $appraised $action))
    (fired $rule $term $tv (roundNum $score 3))
)

;; Trace entry: (inferenceStep $step $allocation $fired $deferred $pruned $state)
(= (inferenceControlLoop $state $beliefs $targets $step $maxSteps $executedSoFar $trace)
    (if (> $step $maxSteps)
        (inferenceRun $state $beliefs $trace)
        (let* (
            ((inferenceStepResult $next $nextBeliefs $executed $deferred $pruned $allocation)
             (inferenceControlStep $state $beliefs $targets $executedSoFar))
            ($nextTrace (append $trace ((inferenceStep $step $allocation (inferenceMap inferenceSummary $executed)
                                                       (size-atom $deferred) (size-atom $pruned) $next))))
        )
            (if (== $executed ())
                (inferenceRun $state $beliefs $nextTrace)
                (inferenceControlLoop $next $nextBeliefs $targets (+ $step 1) $maxSteps
                                      (+ $executedSoFar (size-atom $executed)) $nextTrace)))
    )
)

;; Example: (runInferenceControl $state (((Inheritance a b) (stv 0.9 0.9)) ...) ((Inheritance a c)) 3)
(= (runInferenceControl $state $facts $targets $maxSteps)
    (runInferenceControlOn $state (plnMakeBeliefs $facts 1) $targets $maxSteps)
)

(= (runInferenceControlOn $state $beliefs $targets $maxSteps)
    (inferenceControlLoop $state $beliefs $targets 1 $maxSteps 0 ())
)
