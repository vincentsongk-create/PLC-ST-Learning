(* P06: feedback based, non-reversing sequence. Start/stop sections share P06_State.
   Existing bit arrays remain HMI/TES compatibility outputs, not state memory. *)
P06_ResetEdge := (P06_LocalReset OR SMCL_RESET) AND NOT P06_ResetOld;
P06_ResetOld := P06_LocalReset OR SMCL_RESET;
P06_TempValid := NOT (CHS_T01_UnderRange OR CHS_T01_OverRange)
    OR NOT (CHS_T02_UnderRange OR CHS_T02_OverRange);
P06_FlowValid := NOT (CHS_FL01_UnderRange OR CHS_FL01_OverRange);
P06_Path := ((CHV01_FB > CHV_OSTP) AND (CHV02_FB > CHV_OSTP))
    OR (CHV03_FB > CHV_OSTP);
P06_Water := CHP_RUN AND P06_FlowValid AND (CHS_FL01 > CH_INFL_MIN) AND P06_Path;
P06_RawFault := CHP_FLT_DI OR NOT CHP_REM OR ACH_F1 OR ACHF_F
    OR NOT ACH_AM OR ALM_CHP_MM OR ALM_ACH_MM OR ALM_CHBPV_MM
    OR ALM_CHV01_MM OR ALM_CHV02_MM OR ALM_CHV03_MM;
P06_ConfigFault := (CH_INFL_MIN <= 0.0) OR (CHV_OSTP <= 0.0)
    OR (CHV_OSTP >= 100.0) OR (STOP_PUMP_DELAY < 0)
    OR (STOP_PUMP_DELAY > 3600) OR (START_LOWFL_TM <= 0)
    OR (START_LOWFL_TM > 3600);

(* Timers execute once per scan, including fault/idle scans. Cold/warm resets
   only the non-retained sequence; min-off starts again conservatively. *)
IF ((P06_State = 30) OR (P06_State = 40)) AND NOT ACH_PWR THEN
    P06_PowerEvent := TRUE;
END_IF;
IF NOT ACH_EN OR (ACH_RUN AND ACH_PWR AND (P06_State = 40)) THEN
    P06_PowerEvent := FALSE;
END_IF;
P06_OffPreset := T#10m;
(* Enable only after the chiller vendor confirms this specific quick-restart
   contract. It never bypasses process interlocks, faults or post-run. *)
IF P06_FastRestartApproved AND P06_PowerEvent THEN P06_OffPreset := T#120s; END_IF;
P06_TOff(IN := NOT ACH_RUN AND NOT P06_Boot, PT := P06_OffPreset);
P06_TOn(IN := ACH_RUN AND NOT P06_Boot, PT := T#10m);
P06_TValve(IN := (P06_State = 10) AND NOT P06_Boot, PT := T#120s);
P06_TFlow(IN := (P06_State = 20) AND NOT P06_Boot,
    PT := DINT_TO_TIME(LIMIT(1, START_LOWFL_TM, 3600) * 1000));
P06_TStable(IN := P06_Water AND NOT P06_Boot, PT := T#10s);
P06_TChiller(IN := (P06_State = 30) AND NOT P06_Boot, PT := T#180s);
P06_TLostFlow(IN := ((P06_State = 30) OR (P06_State = 40))
    AND NOT P06_Water AND NOT P06_Boot, PT := T#2s);

IF P06_Boot THEN
    P06_State := 0;
    P06_ResetOld := UNIT_Reset OR SMCL_RESET;
    P06_ResetEdge := FALSE;
    IF ACH_RUN THEN
        IF P06_Water AND NOT P06_RawFault AND ACH_PWR AND NOT CH_MS THEN
            P06_State := 40;
        ELSE P06_State := 50;
        END_IF;
    ELSIF CHP_RUN THEN P06_State := 60;
    END_IF;
END_IF;
IF (P06_State <> 0) AND (P06_State <> 10) AND (P06_State <> 20)
    AND (P06_State <> 30) AND (P06_State <> 40) AND (P06_State <> 50)
    AND (P06_State <> 60) AND (P06_State <> 70) AND (P06_State <> 80)
    AND (P06_State <> 900) THEN
    P06_SeqFault := TRUE; P06_FaultCode := 99; P06_State := 50;
END_IF;
IF P06_ResetEdge AND NOT ACH_RUN AND NOT CHP_RUN AND NOT P06_RawFault
    AND ACH_PWR AND NOT P06_ConfigFault
    AND ((P06_State = 0) OR (P06_State = 900)) THEN
    P06_SeqFault := FALSE; P06_FaultCode := 0; P06_StopFault := FALSE;
    P06_State := 0;
END_IF;

(* A supply failure does not invent an equipment-fault latch. Stop commands;
   water/TES may continue on their own UPS supply while pumps remain healthy. *)
P06_Trip := P06_RawFault OR P06_ConfigFault OR P06_TLostFlow.Q;
IF ((P06_State = 10) OR (P06_State = 20) OR (P06_State = 30)
    OR (P06_State = 40)) AND P06_Trip THEN
    P06_SeqFault := TRUE;
    IF P06_ConfigFault THEN P06_FaultCode := 1;
    ELSIF P06_RawFault THEN P06_FaultCode := 2;
    ELSE P06_FaultCode := 3;
    END_IF;
    P06_State := 50;
END_IF;
IF ((P06_State = 10) OR (P06_State = 20) OR (P06_State = 30)
    OR (P06_State = 40)) AND NOT ACH_PWR THEN P06_State := 50; END_IF;
IF (P06_State = 40) AND NOT ACH_RUN AND NOT P06_Boot THEN
    P06_SeqFault := TRUE; P06_FaultCode := 4; P06_State := 50;
END_IF;
(* Maintenance requests an orderly stop. Only normal demand withdrawal waits
   MinOn; maintenance and process protection may stop the chiller immediately. *)
IF (CH_MS OR TST_MS) AND (P06_State > 0) AND (P06_State < 50) THEN P06_State := 50; END_IF;
IF NOT ACH_EN AND NOT P06_Boot THEN
    IF (P06_State = 10) OR (P06_State = 20) OR (P06_State = 30) THEN
        P06_State := 50;
    ELSIF (P06_State = 40) AND P06_TOn.Q THEN P06_State := 50;
    END_IF;
END_IF;

CASE P06_State OF
0:
    IF ACH_RUN THEN P06_State := 50;
    ELSIF ACH_EN AND NOT CH_MS AND NOT TST_MS AND NOT P06_SeqFault
        AND NOT P06_RawFault AND NOT P06_ConfigFault AND ACH_PWR
        AND NOT UNIT_NOA AND P06_TOff.Q AND P06_TempValid THEN
        START_TST_FULL := TST_CAP > TST_CAP_STP;
        P06_State := 10;
    END_IF;
10:
    IF (START_TST_FULL AND (CHV01_FB > CHV_OSTP) AND (CHV02_FB > CHV_OSTP))
        OR (NOT START_TST_FULL AND (CHV03_FB > CHV_OSTP)) THEN
        P06_State := 20;
    ELSIF P06_TValve.Q THEN
        P06_SeqFault := TRUE; P06_FaultCode := 10; P06_State := 50;
    END_IF;
20:
    IF P06_TStable.Q THEN P06_State := 30;
    ELSIF P06_TFlow.Q THEN
        P06_SeqFault := TRUE; P06_FaultCode := 20; P06_State := 50;
    END_IF;
30:
    IF ACH_RUN THEN P06_State := 40;
    ELSIF P06_TChiller.Q THEN
        P06_SeqFault := TRUE; P06_FaultCode := 30; P06_State := 50;
    END_IF;
900:
    IF ACH_RUN THEN P06_State := 50; END_IF;
END_CASE;

FOR I := 0 TO 5 DO Chiller_Start_ENA[I] := FALSE; END_FOR;
Chiller_Start_ENA[1] := P06_State = 10;
Chiller_Start_ENA[2] := P06_State = 20;
Chiller_Start_ENA[3] := P06_State = 30;
Chiller_Start_ENA[4] := P06_State = 40;
START_ACH_REQ := ((P06_State = 30) OR (P06_State = 40))
    AND ACH_PWR AND NOT P06_Trip AND NOT P06_SeqFault AND NOT CH_MS;
(* New starts require current water proof; running loss uses the 2 s debounce. *)
IF (P06_State = 30) AND NOT P06_Water THEN START_ACH_REQ := FALSE; END_IF;
START_PUMP_REQ := (P06_State >= 20) AND (P06_State <= 40);
ALM_START_LOWFL := P06_SeqFault AND (P06_FaultCode = 20);
