(* Freeze protection mode (rewritten per SOO)
   Enter (any, standby units only, FPM-ENA on): OA-T < -5 °C; lowest water temp < -2.2 °C; EVAP-PUMP=ON
   Exit (all): OA-T > -5 + 1.1; lowest water temp > -2.2 + 1.1; EVAP-PUMP=OFF; or the unit is asked to run
   Action: CHV02 -> 17%, CHV01, CHBPV -> 100%; then pump at minimum speed for 5 min; after the pump stops valves return to standby 100%
   Repeat every FPM_REPEAT_TM while the condition lasts (not in SOO, added) *)
FPM_STANDBY := ((P06_State = 0) OR (P06_State = 900)) AND (NOT ACH_EN) AND (NOT ACH_RUN) AND (NOT CH_MS) AND (NOT TST_MS) AND CMD_FPM_ENA;
CH_Min_T := MIN(LCHLT, ECHLT, CHS_T01, CHS_T02, CHR_T01, CHIN_T01);
FPM_ENA[2] := OA_T < FPM_OA_IN_TSP;
(* 2026-10-19 (user): hysteresis FPM_IN_DTSP on the water temperature condition *)
IF CH_Min_T < FPM_IN_TSP THEN
  FPM_ENA[3] := TRUE;
END_IF;
IF CH_Min_T > FPM_IN_TSP + FPM_IN_DTSP THEN
  FPM_ENA[3] := FALSE;
END_IF;
FPM_ENA[4] := EVAP_PUMP;
FPM_CLR := (OA_T > FPM_OA_IN_TSP + FPM_OA_IN_TSP_plus) AND (CH_Min_T > FPM_IN_TSP + FPM_IN_TSP_plus) AND NOT EVAP_PUMP;
(* 2026-10-15: same as the chemical mode - pump cannot run or a valve does not follow -> leave the anti-freeze mode,
   no new start until the cause is gone (alarm reset) *)
IF FPM_ENA[0] AND (CHWP_Fault OR ALM_CHP_MM OR ALM_CHV01_MM OR ALM_CHV02_MM OR ALM_CHBPV_MM) THEN
    FPM_FAIL := TRUE;
END_IF;
IF ACH_EN OR NOT (CHWP_Fault OR ALM_CHP_MM OR ALM_CHV01_MM OR ALM_CHV02_MM OR ALM_CHBPV_MM) THEN
    IF NOT FPM_ENA[0] THEN FPM_FAIL := FALSE; END_IF;
END_IF;
IF FPM_STANDBY AND (FPM_ENA[2] OR FPM_ENA[3] OR FPM_ENA[4]) AND NOT FPM_FAIL THEN FPM_ENA[0] := TRUE; END_IF;
IF (NOT FPM_STANDBY) OR FPM_CLR OR FPM_FAIL THEN FPM_ENA[0] := FALSE; END_IF;
FPM_ENA[1] := FPM_STANDBY;

FPM_ENA_TRIG (CLK := FPM_ENA[0], Q => FPM_ENA[5]);
FPM_RPT (Condition := FPM_ENA[0] AND NOT FPM_ENA[6] AND NOT FPM_ENA[7], SP_Condition_Delay := FPM_REPEAT_TM,
         SEC_P := SEC_P, Condition_OK => FPM_RPT_OK);
IF FPM_ENA[5] OR FPM_RPT_OK THEN
    FPM_ENA[6] := TRUE;          (* valves moving to position *)
END_IF;
IF FPM_ENA[6] AND (CHV01_FB > CHV_OSTP) AND (CHV02_FB < CHV_FPM_SP + 5.0) AND (CHBPV_FB > CHBPV_FPM_SP - 5.0) THEN
    FPM_ENA[6] := FALSE;
    FPM_ENA[7] := TRUE;          (* pump running *)
END_IF;
FPM_PULSE (Condition := FPM_ENA[7], SP_Condition_Delay := FPM_CH_PULSE, SEC_P := SEC_P, Condition_OK => FPM_PULSE_OK);
IF FPM_PULSE_OK THEN FPM_ENA[7] := FALSE; END_IF;
IF NOT FPM_ENA[0] THEN
    FPM_ENA[5] := FALSE; FPM_ENA[6] := FALSE; FPM_ENA[7] := FALSE;
END_IF;
FPM_VALVE_REQ := FPM_ENA[6] OR FPM_ENA[7];
FPM_PUMP_REQ := FPM_ENA[7];

FPM_LOWFL_C (Condition := FPM_ENA[7] AND CHP_RUN AND (CHS_FL01 < CH_INFL_MIN - 10.0), SP_Condition_Delay := 180,
             SEC_P := SEC_P, Condition_OK => ALM_FPM_LOWFL);
