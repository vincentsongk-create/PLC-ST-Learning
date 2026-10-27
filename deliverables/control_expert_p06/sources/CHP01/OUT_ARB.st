(* Output arbitration (all auto commands in one place so sections do not overwrite each other)
   Valve priority: unit maintenance > tank maintenance > freeze protection > chemical treatment > start step 1 > tank mode > standby (CHV01/02/CHBPV 100%)
   Fix: bypass valve uses CHBPV_Auto_OP everywhere (FPM/chemical sections wrote CHBPV while the drive block read CHPBV); PID enable recalculated every scan *)
(* 2026-10-19 (user): CHV03-only lineup (bypass mode, or start step 1 with TES not full) - when the minimum flow PID
   opens CHBPV (> BYP_CHV01_ON), CHV01 goes to 100 %; back to closed when CHBPV has been < BYP_CHV01_OFFP
   for BYP_CHV01_TM or the lineup is left. Same branch conditions as the arbitration below. *)
BYP_LINEUP := FALSE;
IF NOT (CH_MS OR TST_MS OR FPM_VALVE_REQ OR Chemical_Mode_ENA[0]) THEN
    IF Chiller_Start_ENA[1] OR (ACH_EN AND (TST_MODE = 0) AND NOT TST_MS) THEN
        BYP_LINEUP := NOT START_TST_FULL;
    ELSIF TST_MODE = 1 THEN
        BYP_LINEUP := TRUE;
    END_IF;
END_IF;
IF BYP_LINEUP AND (CHPBV_MinFL_PID_OP > BYP_CHV01_ON) THEN
    BYP_CHV01 := TRUE;
END_IF;
BYP_CHV01_OFF (Condition := CHPBV_MinFL_PID_OP < BYP_CHV01_OFFP, SP_Condition_Delay := BYP_CHV01_TM, SEC_P := SEC_P, Condition_OK => BYP_CHV01_OFF_OK);
IF (NOT BYP_LINEUP) OR BYP_CHV01_OFF_OK THEN
    BYP_CHV01 := FALSE;
END_IF;
V1 := CHV01_Auto_OP; V2 := CHV02_Auto_OP; V3 := CHV03_Auto_OP; VB := CHBPV_Auto_OP;
CHPPV_MinFL_Enable := FALSE;
CHPPV_MinTST_FL_Enable := FALSE;
CHPPV_MinCHWDT_Enable := FALSE;

IF P06_Isolatable THEN
    V1 := 0.0; V2 := 0.0; V3 := 0.0; VB := 0.0;
ELSIF (P06_State >= 50) AND (P06_State <= 70) THEN
    (* Keep the last proven lineup through actual stop and pump post-run. *)
    V1 := CHV01_Auto_OP; V2 := CHV02_Auto_OP;
    V3 := CHV03_Auto_OP; VB := CHBPV_Auto_OP;
ELSIF TST_MS AND NOT ACH_RUN AND NOT CHP_RUN THEN
    V1 := CHV01_MS_OP; V2 := CHV02_MS_OP; V3 := CHV03_MS_OP; VB := CHBPV_MS_OP;
ELSIF FPM_VALVE_REQ THEN
    (* 2026-10-19 (user): CHV01 always 100 % - with CHV02 closed there is no flow path through CHBPV otherwise *)
    V1 := 100.0; V2 := CHV_FPM_SP; VB := CHBPV_FPM_SP; V3 := CHV_FPM_SP;
ELSIF Chemical_Mode_ENA[0] THEN
    V1 := 100.0; VB := CHV_CHE; V2 := 0.0; V3 := 0.0;
ELSIF Chiller_Start_ENA[1] OR (ACH_EN AND (TST_MODE = 0) AND NOT TST_MS) THEN
    CHPPV_MinFL_Enable := TRUE;
    VB := CHPBV_MinFL_PID_OP;
    IF START_TST_FULL THEN
        V1 := 100.0; V2 := 100.0;
        IF (CHV01_FB > CHV_OSTP) AND (CHV02_FB > CHV_OSTP) THEN V3 := 0.0; END_IF;
    ELSE
        V3 := 100.0;
        IF CHV03_FB > CHV_OSTP THEN
            V2 := 0.0;
            IF BYP_CHV01 THEN V1 := 100.0; ELSE V1 := 0.0; END_IF;
        END_IF;
    END_IF;
ELSIF TST_MODE = 1 THEN             (* Bypass *)
    V3 := 100.0;
    (* 2026-10-19 (user): CHBPV opened by the minimum flow PID -> CHV01 100 % (flow path through CHBPV), CHV02 stays closed *)
    IF CHV03_FB > CHV_OSTP THEN
        V2 := 0.0;
        IF BYP_CHV01 THEN V1 := 100.0; ELSE V1 := 0.0; END_IF;
    END_IF;
    CHPPV_MinFL_Enable := TRUE;
    VB := CHPBV_MinFL_PID_OP;
ELSIF TST_MODE = 2 THEN             (* Normal cooling *)
    V1 := 100.0; V2 := 100.0;
    IF (CHV01_FB > CHV_OSTP) AND (CHV02_FB > CHV_OSTP) THEN V3 := 0.0; END_IF;
    CHPPV_MinFL_Enable := TRUE;
    VB := CHPBV_MinFL_PID_OP;
ELSIF TST_MODE = 3 THEN             (* Discharge *)
    V1 := 100.0; V2 := 100.0;
    IF (CHV01_FB > CHV_OSTP) AND (CHV02_FB > CHV_OSTP) THEN V3 := 0.0; END_IF;
    VB := 0.0;
ELSIF TST_MODE = 4 THEN             (* Charge *)
    V1 := 100.0; V3 := 100.0;
    IF (CHV01_FB > CHV_OSTP) AND (CHV03_FB > CHV_OSTP) THEN V2 := 0.0; END_IF;
    CHPPV_MinTST_FL_Enable := TRUE;
    CHPPV_MinCHWDT_Enable := TRUE;
    VB := MIN(CHPPV_MinCHWDT_PID_OP, CHPPV_MinTST_FL_PID_OP);
ELSE                                (* standby: CHV01/CHV02/CHV03 100%, CHBPV 0% (2026-10-19 user) *)
    V1 := 100.0; V2 := 100.0; V3 := 100.0; VB := 0.0;
END_IF;
CHV01_Auto_OP := V1; CHV02_Auto_OP := V2; CHV03_Auto_OP := V3; CHBPV_Auto_OP := VB;
(* PID halt flags: see PID_PARA *)

(* Pumps and chillers *)
(* 2026-10-15 bench test (user): no MM / line-up interlock on the auto outputs here *)
(* 2026-10-20 user (ACH-01 edit): anti-freeze / chemical pump request held 40 s after it drops *)
PUMP_REQ := FPM_PUMP_REQ OR Chemical_Mode_ENA[4];
TOF_PUMP_OFF (IN := PUMP_REQ, PT := T#40s, Q => PUMP_REQ_OUT);
(* 2026-10-22 user (ACH-01 of 10-22): the water path interlock CHP_Shutdown of 10-21 is removed again *)
CHP_Auto_OP := (START_PUMP_REQ OR STOP_PUMP_HOLD OR PUMP_REQ_OUT)
               AND NOT CHP_FLT_DI AND CHP_REM AND NOT P06_Isolatable;
ACH_Auto_OP := START_ACH_REQ AND NOT CH_MS AND NOT TST_MS
    AND NOT P06_SeqFault AND NOT P06_ConfigFault;
IF FPM_PUMP_REQ OR Chemical_Mode_ENA[4] THEN
    CHPVSD_Auto_OP := CHP_MIN;
ELSE
    CHPVSD_Auto_OP := MAX(CHVSD_SEQ_OUT, CHP_MIN);
END_IF;

(* Chiller leaving water setpoint: written to chiller register 1 over Modbus RTU (Modbus_RTU_COMM step 7); ACH_TSP is for display only *)
ACH_TSP := CHS_TSP_OUT;
