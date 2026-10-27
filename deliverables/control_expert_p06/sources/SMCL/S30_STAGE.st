(* P06 supervisory dispatch. Existing 5-unit command/status layout is retained.
   Extension words +24/+25 identify upgraded peers. Unknown peers never receive
   a valid command. The physical safety loop remains in each M340. *)
P06_ConfigFault := (N_CH_CFG < 1) OR (N_CH_CFG > 5) OR (ACH_MinQ < 0)
    OR (ACH_MinQ > N_CH_CFG) OR (STG_INTERVAL < 1) OR (STG_INTERVAL > 86400)
    OR (HANDOVER_TM < 1) OR (HANDOVER_TM > 3600)
    OR (RCV_TM < 1) OR (RCV_TM > 3600)
    OR (CH_NOM_KW <= 0.0) OR (CH_NOM_FL <= 0.0);
P06_AllKnown := TRUE;
FOR I := 1 TO 5 DO
    P06_Fresh[I] := (HB_CNT[I] < COMM_TMO) AND (COMM_TMO > 0)
        AND (P06_Version[I] = 2606) AND (I <= N_CH_CFG);
    P06_Ready[I] := (P06_Ext[I] AND 16#0002) <> 0;
    P06_CanStop[I] := (P06_Ext[I] AND 16#0004) <> 0;
    P06_TempOK[I] := (P06_Ext[I] AND 16#0008) <> 0;
    P06_Local[I] := (P06_Ext[I] AND 16#0040) <> 0;
    IF NOT P06_Fresh[I] OR P06_Local[I] THEN
        P06_Known[I] := FALSE;
        RCV_HB0[I] := HB_LAST[I];
    ELSIF NOT P06_Known[I] AND (HB_LAST[I] <> RCV_HB0[I]) THEN
        (* Per-unit takeover: never infer OFF from a timeout. *)
        P06_Known[I] := TRUE;
        CH_ENA[I] := ACH_ENA_FB[I];
        ROT_OUT[I] := FALSE; PWR_OUT[I] := FALSE;
        PWR_LOST[I] := FALSE; RESTART_FAIL[I] := FALSE;
        STG_CNT := 0;
        IF CH_ENA[I] THEN P06_Adopted := TRUE; END_IF;
    END_IF;
    IF (I <= N_CH_CFG) AND NOT P06_Known[I] THEN P06_AllKnown := FALSE; END_IF;
    AVLB_NOPWR[I] := P06_Known[I] AND P06_Fresh[I] AND UNIT_EN[I]
        AND NOT CH_MS[I] AND NOT P06_Local[I] AND NOT P06_Inhibit[I];
    AVLB[I] := AVLB_NOPWR[I] AND CH_PWR[I];
    IF ALM_RESET AND NOT ACH_S[I] AND NOT CHWP_S[I] THEN P06_Inhibit[I] := FALSE; END_IF;
END_FOR;

IF RCV_ACT THEN
    IF SEC_P AND (RCV_CNT < 30000) THEN RCV_CNT := RCV_CNT + 1; END_IF;
    IF P06_AllKnown OR (RCV_CNT >= RCV_TM) THEN
        RCV_N := 0;
        FOR I := 1 TO 5 DO
            IF P06_Known[I] AND CH_ENA[I] THEN RCV_N := RCV_N + 1; END_IF;
        END_FOR;
        IF RCV_N > 0 THEN System_ENA := TRUE; END_IF;
        STAGE_REQ := RCV_N;
        IF System_ENA AND (STAGE_REQ < ACH_MinQ) THEN STAGE_REQ := ACH_MinQ; END_IF;
        IF (N_CHG >= 2) AND (STAGE_REQ > ACH_MinQ) THEN STAGE_REQ := STAGE_REQ - 1; END_IF;
        STG_CNT := 0; RCV_ACT := FALSE;
    END_IF;
END_IF;
(* A late healthy running peer is adopted before dispatch. No immediate shed. *)
IF P06_Adopted THEN
    RCV_N := 0;
    FOR I := 1 TO 5 DO
        IF P06_Known[I] AND CH_ENA[I] AND AVLB[I] THEN RCV_N := RCV_N + 1; END_IF;
    END_FOR;
    IF RCV_N > 0 THEN System_ENA := TRUE; END_IF;
    IF RCV_N > STAGE_REQ THEN STAGE_REQ := RCV_N; END_IF;
    P06_Adopted := FALSE; STG_CNT := 0;
END_IF;
P06_UnknownAlarm := NOT P06_AllKnown;
P06_TSpace(IN := P06_SpaceActive AND NOT P06_SpaceReset AND NOT P06_Boot,
    PT := T#120s);
P06_SpaceReset := FALSE;
IF P06_TSpace.Q THEN P06_SpaceActive := FALSE; END_IF;
P06_TStart(IN := (P06_StartID <> 0) AND NOT P06_StartReset AND NOT P06_Boot, PT := T#10m);
P06_TStop(IN := (P06_StopID <> 0) AND NOT P06_StopReset AND NOT P06_Boot, PT := T#15m);
P06_StartReset := FALSE; P06_StopReset := FALSE;
IF NOT System_ENA AND (P06_StartID >= 1) AND (P06_StartID <= 5) THEN
    IF P06_Known[P06_StartID] THEN CH_ENA[P06_StartID] := FALSE; END_IF;
    P06_StopID := P06_StartID; P06_StopReset := TRUE; P06_StartID := 0;
END_IF;
IF (P06_StartID >= 1) AND (P06_StartID <= 5) THEN
    I := P06_StartID;
    IF NOT P06_Known[I] OR NOT AVLB[I] OR ((P06_Ext[I] AND 16#0001) <> 0)
        OR P06_TStart.Q THEN
        IF P06_Known[I] THEN CH_ENA[I] := FALSE; END_IF;
        P06_Inhibit[I] := TRUE; P06_StartAlarm := TRUE; P06_StartID := 0;
    ELSIF ACH_S[I] AND START_DONE[I] THEN
        P06_StartID := 0; STG_CNT := 0;
    END_IF;
END_IF;
IF (P06_StopID >= 1) AND (P06_StopID <= 5) THEN
    I := P06_StopID;
    IF P06_Fresh[I] AND STOP_DONE[I] AND NOT ACH_S[I] AND NOT CHWP_S[I] THEN
        P06_StopID := 0; STG_CNT := 0;
    ELSIF P06_TStop.Q THEN P06_StopAlarm := TRUE;
    END_IF;
END_IF;
IF ALM_RESET THEN P06_StartAlarm := FALSE; P06_StopAlarm := FALSE; END_IF;

STG_HOLD := RCV_ACT OR P06_ConfigFault OR (P06_StartID <> 0)
    OR (P06_StopID <> 0) OR (P06_RotOld <> 0);
(* All delay instances are called on every scan; demand changes alone use the
   original SOO thresholds. Fault replacement uses the retained target directly. *)
DLY_UP1(IN := System_ENA AND P06_BMS_LOAD_VALID AND NOT STG_HOLD
    AND (Server_LOAD > CH_CAP_RUN * UP_LOADSP1 / 100.0) AND NOT STG_JUST_CHG,
    PT_S := UPT_LOADSP1, Q => UP_C[1]);
DLY_UP2(IN := System_ENA AND P06_LoadValid AND NOT STG_HOLD
    AND (SYS_LOAD > CH_CAP_RUN * UP_LOADSP2 / 100.0) AND NOT STG_JUST_CHG,
    PT_S := UPT_LOADSP2, Q => UP_C[2]);
DLY_UP3(IN := System_ENA AND CHWS_T_OK AND NOT STG_HOLD
    AND (CHWS_T01_T02 > CHS_TSP_OUT + UP_DTSP1) AND NOT STG_JUST_CHG,
    PT_S := UPT_DTSP1, Q => UP_C[3]);
DLY_UP4(IN := System_ENA AND CHWS_T_OK AND NOT STG_HOLD
    AND (CHWS_T01_T02 > CHS_TSP_OUT + UP_DTSP2) AND NOT STG_JUST_CHG,
    PT_S := UPT_DTSP2, Q => UP_C[4]);
DLY_UP5(IN := System_ENA AND NOT STG_HOLD AND (N_PUMP > 0)
    AND (CHPVSD_SEQ_OUT >= UP_CPSP) AND NOT STG_JUST_CHG,
    PT_S := UPT_CPSP, Q => UP_C[5]);
DLY_UP6(IN := System_ENA AND P06_LoadValid AND NOT STG_HOLD AND (N_RUN > 0)
    AND (TOT_CHF > CHF_HL) AND NOT STG_JUST_CHG,
    PT_S := CHF_HL_TD, Q => UP_C[6]);
UP_C[7] := N_CHG >= 2;
CASE N_RUN OF
5: LOAD_STD := LOAD_STD_5;
4: LOAD_STD := LOAD_STD_4;
3: LOAD_STD := LOAD_STD_3;
2: LOAD_STD := LOAD_STD_2;
ELSE LOAD_STD := -1.0;
END_CASE;
DLY_DN1(IN := System_ENA AND P06_LoadValid AND NOT STG_HOLD AND (N_RUN >= 2)
    AND (SYS_LOAD <= LOAD_STD) AND NOT STG_JUST_CHG,
    PT_S := LOAD_STD_DL, Q => DN_C[1]);
DLY_DN2(IN := System_ENA AND CHWS_T_OK AND P06_LoadValid AND NOT STG_HOLD
    AND (CHWS_T01_T02 < CHS_TSP_OUT - DN_DTSP) AND NOT STG_JUST_CHG,
    PT_S := DNT_DTSP, Q => DN_C[2]);
STG_JUST_CHG := FALSE;
STAGE_UP_REQ := UP_C[1] OR UP_C[2] OR UP_C[3] OR UP_C[4] OR UP_C[5] OR UP_C[6];
STAGE_DN_REQ := (DN_C[1] OR DN_C[2]) AND NOT STAGE_UP_REQ;
IF SEC_P AND (STG_CNT < 100000) THEN STG_CNT := STG_CNT + 1; END_IF;
IF System_ENA AND NOT P06_ConfigFault THEN
    IF STAGE_REQ < ACH_MinQ THEN STAGE_REQ := ACH_MinQ; END_IF;
    IF STAGE_REQ > N_CH_CFG THEN STAGE_REQ := N_CH_CFG; END_IF;
    IF NOT STG_HOLD AND (STG_CNT >= STG_INTERVAL) THEN
        IF STAGE_UP_REQ AND (STAGE_REQ < N_CH_CFG) THEN
            STAGE_REQ := STAGE_REQ + 1; STG_CNT := 0; STG_JUST_CHG := TRUE;
        ELSIF STAGE_DN_REQ AND (STAGE_REQ > ACH_MinQ) THEN
            STAGE_REQ := STAGE_REQ - 1; STG_CNT := 0; STG_JUST_CHG := TRUE;
        END_IF;
    END_IF;
    STAGE_TGT := STAGE_REQ;
    IF UP_C[7] THEN STAGE_TGT := STAGE_REQ + 1; END_IF;
    IF STAGE_TGT > N_CH_CFG THEN STAGE_TGT := N_CH_CFG; END_IF;
ELSIF NOT System_ENA THEN
    STAGE_REQ := 0; STAGE_TGT := 0;
END_IF;

(* Retain original RTC rotation trigger; no direct output writes here. *)
RRTC_DT(OUT => Result_ET_Date);
ET_Date_Array := DT_TO_ARINT(Result_ET_Date);
ET_Day_BCD := ET_Date_Array[2] AND 16#00FF;
RTC_DAY := BCD_TO_INT(ET_Day_BCD);
RTC_HHMM := BCD_TO_INT(ET_Date_Array[1]);
ROT_TRIG(CLK := ((RTC_DAY = ROT_DAY) AND (RTC_HHMM = ROT_HHMM)) OR ROT_CMD OR MV_ROT_CMD);
ROT_CMD := FALSE;
IF ROT_TRIG.Q THEN P06_RotatePending := TRUE; END_IF;

N_EFF := 0; N_EFF_RUN := 0; N_EFF_DONE := 0; P06_Occupied := 0;
P06_HealthyRequested := 0; P06_RunningOut := 0;
FOR I := 1 TO 5 DO
    EFF_OK[I] := CH_ENA[I] AND AVLB[I] AND NOT ROT_OUT[I];
    IF EFF_OK[I] THEN
        N_EFF := N_EFF + 1;
        IF ACH_S[I] THEN N_EFF_RUN := N_EFF_RUN + 1; END_IF;
        IF ACH_S[I] AND START_DONE[I] AND P06_TempOK[I]
            AND (CH_STS_CHST[I] < CHS_TSP_OUT + HANDOVER_DT) THEN
            N_EFF_DONE := N_EFF_DONE + 1;
        END_IF;
    END_IF;
    IF CH_ENA[I] OR (COMM_OK[I] AND ACH_S[I]) THEN P06_Occupied := P06_Occupied + 1; END_IF;
END_FOR;
SEL_ADD := 0; SEL_DN := 0;
FOR I := 1 TO 5 DO
    IF (I <= N_CH_CFG) AND P06_Known[I] AND AVLB[I] AND P06_Ready[I]
        AND NOT CH_ENA[I] AND STOP_DONE[I] THEN
        IF SEL_ADD = 0 THEN SEL_ADD := I;
        ELSIF CH_RUNH[I] < CH_RUNH[SEL_ADD] THEN SEL_ADD := I;
        END_IF;
    END_IF;
    IF EFF_OK[I] AND P06_CanStop[I] AND ACH_S[I] THEN
        IF SEL_DN = 0 THEN SEL_DN := I;
        ELSIF CH_RUNH[I] > CH_RUNH[SEL_DN] THEN SEL_DN := I;
        END_IF;
    END_IF;
END_FOR;

(* Rotation overlap is tied to the actual replacement and valid temperature. *)
P06_ReplacementOK := FALSE;
P06_ReplacementBad := TRUE;
IF (P06_RotNew >= 1) AND (P06_RotNew <= 5) THEN
    I := P06_RotNew;
    P06_ReplacementBad := NOT P06_Known[I] OR NOT AVLB[I] OR P06_Inhibit[I];
    P06_ReplacementOK := EFF_OK[I] AND ACH_S[I] AND START_DONE[I] AND P06_TempOK[I]
        AND (CH_STS_CHST[I] < CHS_TSP_OUT + HANDOVER_DT);
END_IF;
P06_TOverlap(IN := (P06_RotOld <> 0) AND P06_ReplacementOK AND NOT P06_Boot,
    PT := DINT_TO_TIME(LIMIT(1, HANDOVER_TM, 3600) * 1000));
P06_TRotation(IN := (P06_RotOld <> 0) AND NOT P06_Boot, PT := T#20m);
IF (P06_RotOld >= 1) AND (P06_RotOld <= 5) THEN
    I := P06_RotOld;
    IF NOT AVLB[I] THEN
        (* Old unit failed: keep replacement, switch to ordinary fault handover. *)
        ROT_OUT[I] := FALSE; P06_RotOld := 0; P06_RotNew := 0;
    ELSIF NOT System_ENA OR P06_ConfigFault OR (STAGE_TGT <> P06_RotTarget)
        OR P06_TRotation.Q OR P06_ReplacementBad THEN
        (* Original stays enabled if replacement cannot prove capacity. *)
        IF (P06_RotNew >= 1) AND (P06_RotNew <= 5) THEN
            IF P06_Known[P06_RotNew] THEN CH_ENA[P06_RotNew] := FALSE; END_IF;
        END_IF;
        ROT_OUT[I] := FALSE; P06_RotOld := 0; P06_RotNew := 0;
        P06_RotateAlarm := TRUE;
    ELSIF P06_TOverlap.Q AND P06_CanStop[I] THEN
        CH_ENA[I] := FALSE; ROT_OUT[I] := FALSE;
        P06_StopID := I; P06_StopReset := TRUE;
        P06_RotOld := 0; P06_RotNew := 0;
    END_IF;
END_IF;

ALM_NO_STANDBY := FALSE;
IF NOT RCV_ACT AND NOT P06_ConfigFault AND (P06_StartID = 0)
    AND (P06_StopID = 0) AND (P06_RotOld = 0) THEN
    IF System_ENA AND (N_EFF < STAGE_TGT) THEN
        IF (SEL_ADD > 0) AND NOT P06_SpaceActive AND (P06_Occupied < N_CH_CFG) THEN
            CH_ENA[SEL_ADD] := TRUE; P06_StartID := SEL_ADD;
            P06_StartReset := TRUE;
            P06_SpaceActive := TRUE; P06_SpaceReset := TRUE;
        ELSIF SEL_ADD = 0 THEN ALM_NO_STANDBY := TRUE;
        END_IF;
    ELSIF (N_EFF > STAGE_TGT) AND (SEL_DN > 0)
        AND (P06_LoadValid OR NOT System_ENA) THEN
        CH_ENA[SEL_DN] := FALSE; P06_StopID := SEL_DN;
        P06_StopReset := TRUE;
    ELSIF System_ENA AND P06_RotatePending AND (STAGE_TGT > 0)
        AND (N_EFF_DONE >= STAGE_TGT) AND (SEL_DN > 0) AND (SEL_ADD > 0)
        AND NOT P06_SpaceActive AND (P06_Occupied < N_CH_CFG) THEN
        P06_RotOld := SEL_DN; P06_RotNew := SEL_ADD; P06_RotTarget := STAGE_TGT;
        ROT_DONE_MSG := SEL_ADD;
        ROT_OUT[SEL_DN] := TRUE; CH_ENA[SEL_ADD] := TRUE;
        P06_StartID := SEL_ADD; P06_SpaceActive := TRUE; P06_SpaceReset := TRUE;
        P06_StartReset := TRUE;
        P06_RotatePending := FALSE; P06_RotateAlarm := FALSE;
    END_IF;
END_IF;

(* Existing SCADA diagnostic slots retain useful meanings. They do not bypass
   the new state/quality based dispatch or alter the fast-restart policy. *)
NUM_ENABLE := 0; NUM_RESTART_FAIL := 0;
FOR I := 1 TO 5 DO
    RESTART_FAIL[I] := P06_Inhibit[I];
    PWR_LOST[I] := CH_ENA[I] AND P06_Fresh[I] AND NOT CH_PWR[I];
    IF PWR_LOST[I] THEN
        IF SEC_P AND (PWR_CNT[I] < 30000) THEN PWR_CNT[I] := PWR_CNT[I] + 1; END_IF;
    ELSE PWR_CNT[I] := 0;
    END_IF;
    IF UNIT_EN[I] AND COMM_OK[I] THEN NUM_ENABLE := NUM_ENABLE + 1; END_IF;
    IF RESTART_FAIL[I] THEN NUM_RESTART_FAIL := NUM_RESTART_FAIL + 1; END_IF;
END_FOR;

(* One failed/outgoing unit is retired only when replacement capacity is proven.
   Communication-unknown units retain their command echo; valid bit stays OFF. *)
OUT_PENDING := FALSE;
FOR I := 1 TO 5 DO
    IF CH_ENA[I] AND NOT EFF_OK[I] AND NOT ROT_OUT[I] THEN OUT_PENDING := TRUE; END_IF;
END_FOR;
HANDOVER_C := OUT_PENDING AND (N_EFF_DONE >= STAGE_TGT) AND (N_EFF_DONE > 0);
DLY_HANDOVER(IN := HANDOVER_C AND NOT RCV_ACT, PT_S := HANDOVER_TM, Q => HANDOVER_OK);
IF (HANDOVER_OK OR NOT System_ENA) AND (P06_StopID = 0) THEN
    FOR I := 1 TO 5 DO
        IF CH_ENA[I] AND NOT EFF_OK[I] AND NOT ROT_OUT[I] AND P06_Known[I]
            AND (P06_StopID = 0) THEN
            CH_ENA[I] := FALSE; P06_StopID := I;
            P06_StopReset := TRUE;
        END_IF;
    END_FOR;
END_IF;
CHS_ON := (STAGE_TGT > 0) AND (N_EFF_DONE >= STAGE_TGT);
LEAD_ID := 0;
FOR I := 1 TO 5 DO
    IF EFF_OK[I] AND ACH_S[I] THEN
        IF LEAD_ID = 0 THEN LEAD_ID := I;
        ELSIF CH_RUNH[I] < CH_RUNH[LEAD_ID] THEN LEAD_ID := I;
        END_IF;
    END_IF;
END_FOR;

(* Central chemical start grant. No grant with any unknown/unreachable peer;
   an already active local cycle is allowed to complete. *)
P06_ChemID := 0; P06_ChemBusy := FALSE;
FOR I := 1 TO 5 DO
    IF (I <= N_CH_CFG) AND CHEM_ACT[I] THEN P06_ChemBusy := TRUE; END_IF;
END_FOR;
IF P06_AllKnown AND NOT P06_ChemBusy AND NOT RCV_ACT THEN
    FOR I := 1 TO 5 DO
        IF (I <= N_CH_CFG) AND P06_Fresh[I] AND NOT CH_ENA[I] AND NOT ACH_S[I]
            AND NOT CHWP_S[I] AND ((P06_Ext[I] AND 16#0020) <> 0)
            AND (P06_ChemID = 0) THEN P06_ChemID := I;
        END_IF;
    END_FOR;
END_IF;
