;; Self-upgrade scenario: tasks efficacy, safety,
;; ethics and user trust; evidence arrives in phases, then a verdict.

;; Domain annotations

(InferenceRiskTag unsafe 0.9)
(InferenceRiskTag selfModification 0.3)
(InferenceRiskTag safe -0.5)
(InferenceRiskTag ethical -0.3)

(InferenceGoalTag efficacy gSelf 0.8)
(InferenceGoalTag fasterReasoning gSelf 0.4)
(InferenceGoalTag safe gEthic 0.6)
(InferenceGoalTag ethical gEthic 0.8)
(InferenceGoalTag userTrust gSoc 0.8)
(InferenceGoalTag userConsent gSoc 0.4)

;; Inference tasks

(selfUpgradeTask efficacy (Implication upgrade efficacy))
(selfUpgradeTask safety (Implication upgrade safe))
(selfUpgradeTask ethics (Implication upgrade ethical))
(selfUpgradeTask userTrust (Implication upgrade userTrust))

(= (selfUpgradeTargets)
    ((Implication upgrade efficacy)
     (Implication upgrade safe)
     (Implication upgrade ethical)
     (Implication upgrade userTrust))
)

(= (selfUpgradeRequiredTasks) (efficacy safety ethics))

;; Evidence by phase

(= (selfUpgradeEvidence discovery)
    (((Implication upgrade fasterReasoning) (stv 0.85 0.6))
     ((Implication fasterReasoning efficacy) (stv 0.9 0.8))
     ((Implication upgrade selfModification) (stv 0.95 0.9))
     ((Implication selfModification unsafe) (stv 0.35 0.6)))
)

(= (selfUpgradeEvidence sandbox)
    (((Implication upgrade sandboxPass) (stv 0.9 0.85))
     ((Implication sandboxPass safe) (stv 0.92 0.85))
     ((Implication upgrade efficacy) (stv 0.8 0.7)))
)

(= (selfUpgradeEvidence consult)
    (((Implication upgrade userConsent) (stv 0.85 0.8))
     ((Implication userConsent ethical) (stv 0.9 0.85))
     ((Implication userConsent userTrust) (stv 0.85 0.8)))
)

;; Distinct stamp ids per phase.
(= (selfUpgradeEvidenceStart discovery) 1)
(= (selfUpgradeEvidenceStart sandbox) 10)
(= (selfUpgradeEvidenceStart consult) 20)

;; Verdict

(= (SELF_UPGRADE_PROOF_STRENGTH) 0.6)
(= (SELF_UPGRADE_UNSAFE_LIMIT) 0.5)
(= (SELF_UPGRADE_IND_LIMIT) 0.5)

;; Strong enough and above the current confidence cutoff.
(= (selfUpgradeEstablished $task $state $beliefs)
    (let* (
        ($term (match &self (selfUpgradeTask $task $t) $t))
        ($best (plnBestBelief $term $beliefs))
    )
        (if (== $best ())
            False
            (and (>= (beliefStrength $best) (SELF_UPGRADE_PROOF_STRENGTH))
                 (>= (beliefConfidence $best) (allocationCutoff (computeInferenceAllocation $state))))
        )
    )
)

(= (selfUpgradeMissing $tasks $state $beliefs)
    (if (== $tasks ())
        ()
        (let ($head $tail) (decons $tasks)
            (if (selfUpgradeEstablished $head $state $beliefs)
                (selfUpgradeMissing $tail $state $beliefs)
                (cons-atom $head (selfUpgradeMissing $tail $state $beliefs))
            )
        )
    )
)

(= (selfUpgradeUnsafeStrength $beliefs)
    (let $best (plnBestBelief (Implication upgrade unsafe) $beliefs)
        (if (== $best ()) 0.0 (beliefStrength $best))
    )
)

;; (adoptIncrementally $alpha) or (defer $reasons).
(= (selfUpgradeVerdict $state $beliefs)
    (let* (
        ($missing (selfUpgradeMissing (selfUpgradeRequiredTasks) $state $beliefs))
        ($unsafe (selfUpgradeUnsafeStrength $beliefs))
        ($gInd (getGoal $state gInd))
        ($reasons (if (>= $unsafe (SELF_UPGRADE_UNSAFE_LIMIT)) (cons-atom unsafeEvidence $missing) $missing))
        ($allReasons (if (> $gInd (SELF_UPGRADE_IND_LIMIT)) (inferenceAppend $reasons (individuationHigh)) $reasons))
    )
        (if (== $allReasons ())
            (adoptIncrementally (roundNum (inferenceBlendFactor $state) 3))
            (defer $allReasons)
        )
    )
)

;; Phases

;; Add a phase's evidence and run inference on it.
(= (selfUpgradePhase $state $beliefs $phase $steps)
    (runInferenceControlOn
        $state
        (inferenceAppend $beliefs
            (plnMakeBeliefs (selfUpgradeEvidence $phase) (selfUpgradeEvidenceStart $phase)))
        (selfUpgradeTargets)
        $steps)
)

;; (phaseRecord $phase $state $beliefs $fired $verdict)
(= (phaseRecordState (phaseRecord $phase $state $beliefs $fired $verdict)) $state)
(= (phaseRecordBeliefs (phaseRecord $phase $state $beliefs $fired $verdict)) $beliefs)
(= (phaseRecordVerdict (phaseRecord $phase $state $beliefs $fired $verdict)) $verdict)

(= (selfUpgradeFired $trace)
    (if (== $trace ())
        ()
        (let* (
            (($head $tail) (decons $trace))
            ((inferenceStep $step $allocation $fired $deferred $pruned $state) $head)
        )
            (inferenceAppend $fired (selfUpgradeFired $tail))
        )
    )
)

(= (selfUpgradeRecord $phase $run)
    (let (inferenceRun $state $beliefs $trace) $run
        (phaseRecord $phase $state $beliefs (selfUpgradeFired $trace)
                     (selfUpgradeVerdict $state $beliefs))
    )
)

(= (selfUpgradeDecisionRecord $phase $state $beliefs)
    (phaseRecord $phase $state $beliefs () (selfUpgradeVerdict $state $beliefs))
)

;; Initial, Discovery, Decision, Sandbox, Consult, Final.
(= (runSelfUpgradeScenario $initialState $steps)
    (let* (
        ($initial (selfUpgradeDecisionRecord initial $initialState ()))
        ($discovery (selfUpgradeRecord discovery
            (selfUpgradePhase $initialState () discovery $steps)))
        ($decision (selfUpgradeDecisionRecord decision
            (phaseRecordState $discovery) (phaseRecordBeliefs $discovery)))
        ($sandbox (selfUpgradeRecord sandbox
            (selfUpgradePhase (phaseRecordState $discovery) (phaseRecordBeliefs $discovery) sandbox $steps)))
        ($consult (selfUpgradeRecord consult
            (selfUpgradePhase (phaseRecordState $sandbox) (phaseRecordBeliefs $sandbox) consult $steps)))
        ($final (selfUpgradeDecisionRecord final
            (phaseRecordState $consult) (phaseRecordBeliefs $consult)))
    )
        ($initial $discovery $decision $sandbox $consult $final)
    )
)
