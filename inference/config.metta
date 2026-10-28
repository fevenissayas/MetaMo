;; Inference control constants.

;; (InferenceRuleProfile $rule $novelty $risk $effort)
(InferenceRuleProfile revision    0.10 0.05 0.10)
(InferenceRuleProfile modusPonens 0.30 0.15 0.20)
(InferenceRuleProfile deduction   0.40 0.20 0.30)
(InferenceRuleProfile induction   0.70 0.45 0.40)
(InferenceRuleProfile abduction   0.80 0.50 0.40)

;; Stimulus mixing weights.
(= (INFERENCE_NOVELTY_UNKNOWN_WEIGHT) 0.6)
(= (INFERENCE_NOVELTY_RULE_WEIGHT) 0.4)
(= (INFERENCE_RISK_RULE_WEIGHT) 0.35)
(= (INFERENCE_RISK_UNCERTAINTY_WEIGHT) 0.25)
(= (INFERENCE_RISK_DOMAIN_WEIGHT) 0.6)
(= (INFERENCE_EFFORT_RULE_WEIGHT) 0.5)
(= (INFERENCE_EFFORT_DEPTH_REF) 6.0)

;; Scale for partial (non-equal) relevance to a target.
(= (INFERENCE_PARTIAL_RELEVANCE) 0.8)

;; deltaG rates.
(= (INFERENCE_GOAL_RATE) 0.15)
(= (INFERENCE_IND_RATE) 0.5)
(= (INFERENCE_TRANS_RATE) 0.1)

;; Allocation: breadth, confidence cutoff, depth.
(= (INFERENCE_K_MIN) 1)
(= (INFERENCE_K_MAX) 6)
(= (INFERENCE_CUTOFF_MIN) 0.05)
(= (INFERENCE_CUTOFF_SPAN) 0.6)
(= (INFERENCE_CUTOFF_MAX) 0.9)
(= (INFERENCE_DEPTH_MIN) 2)
(= (INFERENCE_DEPTH_SPAN) 4)

;; Below this score candidates are pruned, not deferred.
(= (INFERENCE_SCORE_FLOOR) 0.0)

;; Inferences before resource pressure reaches 1.0.
(= (INFERENCE_BUDGET) 12)

;; alpha = ALPHA_0 (1 - gInd) + BETA_0 gTrans
(= (INFERENCE_ALPHA_0) 0.3)
(= (INFERENCE_BETA_0) 0.4)

;; Near the safe-region boundary each state shift must satisfy
;; shift <= CONTRACTION * previous shift + EPSILON.
(= (INFERENCE_CONTRACTION) 0.9)
(= (INFERENCE_CONTRACTION_EPSILON) 0.01)
;; Previous shift assumed before the first update of a run.
(= (INFERENCE_INITIAL_SHIFT) 0.25)

(= (inferenceAppraisalModule) (openPsiAppraisal))
