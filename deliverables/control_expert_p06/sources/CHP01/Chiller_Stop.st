(* P06: no restart reversal while stopping; actual feedback controls post-run. *)
P06_TStop(IN := (P06_State = 50) AND NOT P06_Boot, PT := T#180s);
P06_TPost(IN := (P06_State = 60) AND NOT ACH_RUN AND NOT P06_Boot,
    PT := DINT_TO_TIME(LIMIT(0, STOP_PUMP_DELAY, 3600) * 1000));
P06_TPumpStop(IN := (P06_State = 70) AND NOT P06_Boot, PT := T#60s);
(* A chiller-only failure must not discard useful TES cooling while the SMCL
   is proving the replacement. Pump/process faults and maintenance still win. *)
P06_TESHold := ACH_EN AND NOT CH_MS AND NOT TST_MS AND NOT P06_ConfigFault
    AND NOT CHP_FLT_DI AND CHP_REM AND NOT ALM_CHP_MM
    AND P06_Water AND (TST_MODE = 3) AND (TST_CAP > TST_CAP_MINSTP);
IF ACH_RUN AND ((P06_State = 60) OR (P06_State = 70)
    OR (P06_State = 80) OR (P06_State = 900)) THEN
    P06_SeqFault := TRUE; P06_FaultCode := 51; P06_State := 50;
END_IF;
CASE P06_State OF
50:
    IF NOT ACH_RUN THEN
        IF CHP_RUN THEN P06_State := 60; ELSE P06_State := 70; END_IF;
    ELSIF P06_TStop.Q THEN
        P06_StopFault := TRUE; P06_SeqFault := TRUE; P06_FaultCode := 50;
    END_IF;
60:
    IF P06_TPost.Q AND NOT P06_TESHold THEN P06_State := 70; END_IF;
70:
    IF NOT CHP_RUN THEN P06_State := 80;
    ELSIF P06_TPumpStop.Q THEN
        P06_StopFault := TRUE; P06_SeqFault := TRUE; P06_FaultCode := 70;
    END_IF;
80:
    IF P06_SeqFault THEN P06_State := 900; ELSE P06_State := 0; END_IF;
END_CASE;
FOR I := 0 TO 5 DO Chiller_Stop_ENA[I] := FALSE; END_FOR;
Chiller_Stop_ENA[1] := P06_State = 50;
Chiller_Stop_ENA[2] := P06_State = 60;
Chiller_Stop_ENA[3] := P06_State = 70;
Chiller_Stop_ENA[5] := (P06_State = 0) OR (P06_State = 900);
STOP_PUMP_HOLD := (P06_State = 50) OR (P06_State = 60);
P06_Isolatable := CH_MS AND NOT ACH_RUN AND NOT CHP_RUN
    AND ((P06_State = 0) OR (P06_State = 900));
START_ACH_REQ := START_ACH_REQ AND ((P06_State = 30) OR (P06_State = 40));
START_PUMP_REQ := (P06_State >= 20) AND (P06_State <= 40);
