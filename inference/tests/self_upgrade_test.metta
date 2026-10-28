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
!(import! &self ../self_upgrade)

(= (initialState)
    (motivation (0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5) (0.5 0.5 0.5 0.5 0.5 0.5))
)

;; Run the scenario once and cache the phase records.
!(let $records (runSelfUpgradeScenario (initialState) 2)
    (add-atom &self (cachedScenario $records)))

(= (scenario) (match &self (cachedScenario $records) $records))

(= (phase $name)
    (let $records (scenario)
        (let (phaseRecord $phase $state $beliefs $fired $verdict) (superpose $records)
            (if (== $phase $name) (phaseRecord $phase $state $beliefs $fired $verdict) (empty))))
)

(= (goalAt $name $goal) (getGoal (phaseRecordState (phase $name)) $goal))

;; The play-by-play has six steps: initial, discovery, decision, sandbox, consult, final.
!(test (size-atom (scenario)) 6)

;; Nothing is proven before any evidence arrives.
!(test (phaseRecordVerdict (phase initial)) (defer (efficacy safety ethics)))

;; After discovery only efficacy has support; the upgrade is deferred.
!(test
    (let (defer $reasons) (phaseRecordVerdict (phase decision))
        (and (is-member safety $reasons) (is-member ethics $reasons)))
    True
)

!(test (selfUpgradeEstablished efficacy (phaseRecordState (phase decision)) (phaseRecordBeliefs (phase decision))) True)

;; The sandbox phase proves safety.
!(test (selfUpgradeEstablished safety (phaseRecordState (phase sandbox)) (phaseRecordBeliefs (phase sandbox))) True)

;; Once ethics passes after consultation the upgrade is adopted incrementally.
!(test
    (let ($tag $alpha) (phaseRecordVerdict (phase final)) $tag)
    adoptIncrementally
)

;; Outcome: gInd decreases while gEthic and gSelf grow.
!(test (< (goalAt final gInd) (goalAt initial gInd)) True)
!(test (> (goalAt final gEthic) (goalAt initial gEthic)) True)
!(test (> (goalAt final gSelf) (goalAt initial gSelf)) True)

;; Every phase keeps the motivational state in the safe region.
!(test (isInSafeRegion (phaseRecordState (phase final))) True)

;; Strong unsafe evidence blocks adoption.
!(test
    (selfUpgradeVerdict
        (phaseRecordState (phase final))
        (cons-atom (belief (Implication upgrade unsafe) (stv 0.9 0.9) (99))
                   (phaseRecordBeliefs (phase final))))
    (defer (unsafeEvidence))
)
