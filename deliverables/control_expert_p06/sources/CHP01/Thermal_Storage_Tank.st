(* Thermal storage tank mode (rewritten per SOO). Valve actions are in section OUT_ARB.
   Start done: TST-CAP > 85% -> normal, else -> bypass
   Normal/charge -> discharge: chiller power loss or fault while the pump runs (alarm)
   Discharge -> bypass: TST-CAP < 20% or CHS-T02 > setpoint + 1.7 °C for 30 s
   Discharge -> normal: chiller running again
   Normal/bypass -> charge: chiller running, CHS=ON, header supply < setpoint + 1.1 °C for 15 min, TST-CAP < 95%
   Charge -> normal: TST-CAP > 95% and all 4 tank temps < setpoint + 0.8 °C
   Charge -> bypass: chiller stopped normally
   Bypass -> normal: chiller running and TST-CAP >= 95% *)
TST_INIT_TRIG (CLK := Chiller_Start_ENA[4], Q => TST_INIT);
(* user 2026-10-15: TES maintenance switched off -> decide the TES mode again *)
TST_MS_F_TRIG (CLK := TST_MS, Q => TST_MS_INIT);
IF TST_MS THEN
    TST_MODE := 0;
ELSE
    IF (TST_INIT OR TST_MS_INIT) AND (TST_MODE = 0) THEN
        IF TST_CAP > TST_CAP_STP THEN TST_MODE := 2; ELSE TST_MODE := 1; END_IF;
    END_IF;

    (* 2026-10-15: chiller lost (no power / fault) while the tank has no usable capacity (TST-CAP below the discharge
       minimum, typically during charging): discharging is pointless and the mode toggled 1 <-> 3. Go to bypass,
       latch TST_NOCAP = unit not available (UNIT_ENABLE FALSE) -> SMCL starts the next unit and stops this one
       after the handover (supply temperature reached). Cleared when the unit is stopped (ACH_EN removed). *)
    IF ((TST_MODE = 2) OR (TST_MODE = 4) OR (TST_MODE = 3)) AND CHP_RUN AND ((NOT ACH_PWR) OR ACH_Fault)
       AND (TST_CAP < TST_CAP_MINSTP) THEN
        TST_NOCAP := TRUE;
    END_IF;
    IF TST_NOCAP THEN
        TST_MODE := 1;
    ELSIF ((TST_MODE = 2) OR (TST_MODE = 4)) AND CHP_RUN AND ((NOT ACH_PWR) OR ACH_Fault) THEN
        TST_MODE := 3;
    END_IF;

    TST_DtB_Condition (Condition := (TST_MODE = 3) AND ((TST_CAP < TST_CAP_MINSTP) OR (CHS_T02 > CHS_TSP_OUT + TSTDT)),
                       SP_Condition_Delay := TST_TIME, SEC_P := SEC_P, Condition_OK => TST_DtB_OK);
    IF TST_DtB_OK THEN TST_MODE := 1; END_IF;

    IF (TST_MODE = 3) AND ACH_RUN AND ACH_PWR AND NOT ACH_Fault THEN TST_MODE := 2; END_IF;

    (* 2026-10-20 user (ACH-01 edit): no CHS in the condition *)
    TST_BtC_Condition (Condition := ((TST_MODE = 1) OR (TST_MODE = 2)) AND ACH_RUN
                                    AND (CHWS_T01_T02 < CHS_TSP_OUT + TDM_CHWS_DT) AND (TST_CAP < TST_CAP_MAXSTP),
                       SP_Condition_Delay := TDMCHWS_TIME1, SEC_P := SEC_P, Condition_OK => TST_BtC_OK);
    IF TST_BtC_OK THEN TST_MODE := 4; END_IF;

    TST_FULL := (TST_CAP > TST_CAP_MAXSTP) AND (TST_T01 < CHS_TSP_OUT + TST_DT) AND (TST_T02 < CHS_TSP_OUT + TST_DT)
                AND (TST_T03 < CHS_TSP_OUT + TST_DT) AND (TST_T04 < CHS_TSP_OUT + TST_DT);
    IF (TST_MODE = 4) AND TST_FULL THEN TST_MODE := 2; END_IF;
    IF (TST_MODE = 4) AND (NOT ACH_RUN) AND ACH_PWR AND NOT ACH_Fault THEN TST_MODE := 1; END_IF;
    IF (TST_MODE = 1) AND ACH_RUN AND (TST_CAP >= TST_CAP_MAXSTP) THEN TST_MODE := 2; END_IF;

    (* no-capacity latch: keep bypass whatever the transitions above did; cleared once the unit is stopped *)
    (* 2026-10-20 user (ACH-01 edit): also cleared once the chiller runs again *)
    IF NOT ACH_EN OR ACH_RUN THEN TST_NOCAP := FALSE; END_IF;
    IF TST_NOCAP THEN TST_MODE := 1; END_IF;
    (* Unit disabled and pump stopped: clear the mode *)
    IF (NOT ACH_EN) AND (NOT CHP_RUN) THEN TST_MODE := 0; END_IF;
END_IF;

DISCH_ALM := TST_MODE = 3;
TST_ENA[0] := TST_MODE = 1;
TST_ENA[1] := TST_MODE = 2;
TST_ENA[2] := TST_MODE = 3;
TST_ENA[3] := TST_MODE = 4;
