(* ================= Header supply temperature: max of the healthy values, hold when none is healthy ================= *)
CHWS_T_OK := OK_CHWS_T01 OR OK_CHWS_T02;
IF OK_CHWS_T01 AND OK_CHWS_T02 THEN
    CHWS_T01_T02 := MAX(V_CHWS_T01, V_CHWS_T02);
ELSIF OK_CHWS_T01 THEN
    CHWS_T01_T02 := V_CHWS_T01;
ELSIF OK_CHWS_T02 THEN
    CHWS_T01_T02 := V_CHWS_T02;
END_IF;

(* ================= Flow: return/supply meters of each loop are redundant =================
   FL_SEL 0=auto (return first, supply on fault) 1=return first 2=supply first; both failed: hold last value *)
(* P06 independent redundant selection per loop. *)
FLOW_A_OK := OK_CHWR_FL01 OR OK_CHWS_FL01;
FLOW_B_OK := OK_CHWR_FL02 OR OK_CHWS_FL02;
ALM_FLOW_A_FAIL := NOT FLOW_A_OK; ALM_FLOW_B_FAIL := NOT FLOW_B_OK;
IF (FL_SEL_A = 2) AND OK_CHWS_FL01 THEN FLOW_A := V_CHWS_FL01;
ELSIF OK_CHWR_FL01 THEN FLOW_A := V_CHWR_FL01;
ELSIF OK_CHWS_FL01 THEN FLOW_A := V_CHWS_FL01;
END_IF;
IF (FL_SEL_B = 2) AND OK_CHWS_FL02 THEN FLOW_B := V_CHWS_FL02;
ELSIF OK_CHWR_FL02 THEN FLOW_B := V_CHWR_FL02;
ELSIF OK_CHWS_FL02 THEN FLOW_B := V_CHWS_FL02;
END_IF;
FLOW_STATE := 0;
IF NOT FLOW_A_OK OR NOT FLOW_B_OK THEN FLOW_STATE := 9; END_IF;
P06_LoadValid := FLOW_A_OK AND FLOW_B_OK AND OK_CHWR_T01 AND OK_CHWS_T01
    AND OK_CHWR_T02 AND OK_CHWS_T02;

(* Redundant flow meter deviation *)
FL_DISP_A := 0.0;
IF OK_CHWR_FL01 AND OK_CHWS_FL01 AND (MAX(V_CHWR_FL01, V_CHWS_FL01) > 1.0) THEN
    FL_DISP_A := ABS(V_CHWR_FL01 - V_CHWS_FL01) / MAX(V_CHWR_FL01, V_CHWS_FL01) * 100.0;
END_IF;
FL_DISP_B := 0.0;
IF OK_CHWR_FL02 AND OK_CHWS_FL02 AND (MAX(V_CHWR_FL02, V_CHWS_FL02) > 1.0) THEN
    FL_DISP_B := ABS(V_CHWR_FL02 - V_CHWS_FL02) / MAX(V_CHWR_FL02, V_CHWS_FL02) * 100.0;
END_IF;
DLY_FLD1A (IN := FL_DISP_A > FL_DISP1_PCT, PT_S := 10, Q => ALM_FL_DISP1_A);
DLY_FLD1B (IN := FL_DISP_B > FL_DISP1_PCT, PT_S := 10, Q => ALM_FL_DISP1_B);
DLY_FLD2A (IN := FL_DISP_A > FL_DISP2_PCT, PT_S := FL_DISP2_TM, Q => ALM_FL_DISP2_A);
DLY_FLD2B (IN := FL_DISP_B > FL_DISP2_PCT, PT_S := FL_DISP2_TM, Q => ALM_FL_DISP2_B);

(* ================= Cooling load kW (V_ already holds the last value when a temperature is not healthy) ================= *)
CLG_LOAD_A := FLOW_A * (V_CHWR_T01 - V_CHWS_T01) * 1.163;
CLG_LOAD_B := FLOW_B * (V_CHWR_T02 - V_CHWS_T02) * 1.163;
SYS_LOAD := CLG_LOAD_A + CLG_LOAD_B;
LOAD_DISP := 0.0;
IF MAX(CLG_LOAD_A, CLG_LOAD_B) > 1.0 THEN
    LOAD_DISP := ABS(CLG_LOAD_A - CLG_LOAD_B) / MAX(CLG_LOAD_A, CLG_LOAD_B) * 100.0;
END_IF;

(* ================= Total flow and limit ================= *)
TOT_CHF := FLOW_A + FLOW_B;
CHF_HL := INT_TO_REAL(N_RUN) * CH_NOM_FL * CHF_HL_PCT / 100.0;

(* ================= BMS interface ================= *)
Server_LOAD := INT_TO_REAL(BMS_SRV_LOAD_KW);
SYSTEM_FL := INT_TO_REAL(BMS_SYSTEM_FL_X10) / 10.0;
(* 2026-10-20 user: outdoor temperature from weather station 1 instead of the BMS *)
OA_T := WS1_OAT;
(* OA_T := INT_TO_REAL(BMS_OA_T_X100) / 100.0; *)

CH_CAP_RUN := INT_TO_REAL(N_RUN) * CH_NOM_KW;
IF CH_CAP_RUN > 0.0 THEN
    LOAD_PCT_SYS := SYS_LOAD / CH_CAP_RUN * 100.0;
    LOAD_PCT_IT := Server_LOAD / CH_CAP_RUN * 100.0;
ELSE
    LOAD_PCT_SYS := 999.0;
    LOAD_PCT_IT := 999.0;
END_IF;

(* Every POLL_TM s compare the terminal total flow with the header total flow *)
IF SEC_P THEN POLL_CNT := POLL_CNT + 1; END_IF;
IF POLL_CNT >= POLL_TM THEN
    POLL_CNT := 0;
    SYSFL_DISP := 0.0;
    IF TOT_CHF > 1.0 THEN
        SYSFL_DISP := ABS(SYSTEM_FL - TOT_CHF) / TOT_CHF * 100.0;
    END_IF;
    ALM_SYSFL := SYSFL_DISP > SYSFL_DISP_PCT;
END_IF;

(* ================= Effective differential pressure ================= *)
DP1_OK := OK_CHWS_P01 AND OK_CHWR_P01;
DP2_OK := OK_CHWS_P02 AND OK_CHWR_P02;
CHW_DP1 := (V_CHWS_P01 - V_CHWR_P01) * 100.0;   (* bar -> kPa *)
CHW_DP2 := (V_CHWS_P02 - V_CHWR_P02) * 100.0;
CHW_DP_OK := DP1_OK OR DP2_OK;
IF (DP_SEL = 1) AND DP1_OK THEN
    CHW_DP := CHW_DP1;
ELSIF (DP_SEL = 2) AND DP2_OK THEN
    CHW_DP := CHW_DP2;
ELSIF DP1_OK AND DP2_OK THEN
    CHW_DP := (CHW_DP1 + CHW_DP2) / 2.0;
ELSIF DP1_OK THEN
    CHW_DP := CHW_DP1;
ELSIF DP2_OK THEN
    CHW_DP := CHW_DP2;
END_IF;   (* none available: hold the last value *)
ALM_DP_FAIL := NOT CHW_DP_OK;
