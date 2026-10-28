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
(= (modulatorAt $name $mod) (getModulator (phaseRecordState (phase $name)) $mod))

;; The play-by-play has six steps: initial, discovery, decision, sandbox, consult, final.
!(test (size-atom (scenario)) 6)

;; Nothing is proven before any evidence arrives.
!(test (phaseRecordVerdict (phase initial)) (defer (efficacy safety ethics individuationNotFalling)))

;; After discovery only efficacy has support; the upgrade is deferred.
!(test
    (let (defer $reasons) (phaseRecordVerdict (phase decision))
        (and (is-member safety $reasons) (is-member ethics $reasons)))
    True
)

!(test (selfUpgradeEstablished efficacy (phaseRecordState (phase decision)) (phaseRecordBeliefs (phase decision))) True)

;; The possible unsafe side effect raises gInd and threshold during discovery.
!(test (> (goalAt discovery gInd) (goalAt initial gInd)) True)
!(test (> (modulatorAt discovery threshold) (modulatorAt initial threshold)) True)

;; The sandbox phase proves safety, and threshold drops.
!(test (selfUpgradeEstablished safety (phaseRecordState (phase sandbox)) (phaseRecordBeliefs (phase sandbox))) True)
!(test (< (modulatorAt sandbox threshold) (modulatorAt discovery threshold)) True)

;; The consult phase proves ethics, and threshold drops again.
!(test (< (modulatorAt consult threshold) (modulatorAt sandbox threshold)) True)

;; Modulators stay inside [0, 1].
!(test
    (let $mods (motivationModulators (phaseRecordState (phase final)))
        (and (>= (min-atom $mods) 0.0) (<= (max-atom $mods) 1.0)))
    True
)

;; Once safety, efficacy and ethics are proven gInd has fallen and the upgrade
;; is adopted incrementally, paced by alpha.
!(test (< (goalAt final gInd) (goalAt discovery gInd)) True)
!(test
    (phaseRecordVerdict (phase final))
    (adoptIncrementally (roundNum (inferenceBlendFactor (phaseRecordState (phase final))) 3))
)

;; Outcome: gEthic and gSelf grow.
!(test (> (goalAt final gEthic) (goalAt initial gEthic)) True)
!(test (> (goalAt final gSelf) (goalAt initial gSelf)) True)

;; Every phase keeps the motivational state in the safe region.
!(test (isInSafeRegion (phaseRecordState (phase final))) True)

;; Strong unsafe evidence blocks adoption.
!(test
    (let (defer $reasons)
         (selfUpgradeVerdict
            (phaseRecordState (phase sandbox))
            (phaseRecordState (phase final))
            (cons-atom (belief (Implication upgrade unsafe) (stv 0.9 0.9) (99))
                       (phaseRecordBeliefs (phase final))))
        (is-member unsafeEvidence $reasons))
    True
)

;; Without a fall in gInd the upgrade waits.
!(test
    (selfUpgradeVerdict (phaseRecordState (phase final)) (phaseRecordState (phase final))
                        (phaseRecordBeliefs (phase final)))
    (defer (individuationNotFalling))
)
