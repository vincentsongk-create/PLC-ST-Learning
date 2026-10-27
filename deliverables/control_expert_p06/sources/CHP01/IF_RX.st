(* 2026-10-15 bench test (user): line 2 data from READ_VAR (Main FBD, SMCL 10.54.18.134 %MW200) *)
RX2_HB := RX2_BLK[0];
RX2_BITS := RX2_BLK[1];
RX2_SPD := RX2_BLK[2];
RX2_TSP := RX2_BLK[3];
RX2_CHWST := RX2_BLK[4];
RX2_OAT := RX2_BLK[5];
RX2_PRIM := RX2_BLK[6];

(* Receive the SMCL commands. line 1 %MW600..619 (10.54.18.134), line 2 %MW620..639 (10.54.18.135), read by NOE IO Scanning.
   Heartbeat unchanged for COMM_TMO s = comm lost; with both lines lost keep the last enable, speed and setpoint (SOO: hold pump speed). *)
IF RX1_HB <> RX1_HB_LAST THEN
    RX1_HB_LAST := RX1_HB; RX1_CNT := 0;
ELSIF SEC_P AND (RX1_CNT < 30000) THEN
    RX1_CNT := RX1_CNT + 1;
END_IF;
IF RX2_HB <> RX2_HB_LAST THEN
    RX2_HB_LAST := RX2_HB; RX2_CNT := 0;
ELSIF SEC_P AND (RX2_CNT < 30000) THEN
    RX2_CNT := RX2_CNT + 1;
END_IF;
Network_Main := RX1_CNT < COMM_TMO;
Network_Stby := RX2_CNT < COMM_TMO;

SMCL_COMM_OK := TRUE;
IF Network_Main AND ((RX1_BITS AND 16#0020) <> 0) THEN
    RX_BITS := RX1_BITS; RX_SPD := RX1_SPD; RX_TSP := RX1_TSP; RX_CHWST := RX1_CHWST; RX_OAT := RX1_OAT;
ELSIF Network_Stby AND ((RX2_BITS AND 16#0020) <> 0) THEN
    RX_BITS := RX2_BITS; RX_SPD := RX2_SPD; RX_TSP := RX2_TSP; RX_CHWST := RX2_CHWST; RX_OAT := RX2_OAT;
ELSE
    SMCL_COMM_OK := FALSE;
END_IF;
(* 2026-10-19: b5 = SMCL command block valid. The SMCL clears it after a restart until it has the stage back
   (cold start after both CPUs lost power) -> handled like comm lost: keep the last enable, speed and setpoint *)
IF (RX_BITS AND 16#0020) = 0 THEN
    SMCL_COMM_OK := FALSE;
END_IF;
ALM_SMCL_COMM := NOT SMCL_COMM_OK AND NOT LOCAL_EN;

SMCL_RESET := FALSE;
IF LOCAL_EN THEN
    (* Local mode: use the LOCAL_ variables directly *)
    ACH_EN := LOCAL_ACH_EN;
    CHVSD_SEQ_OUT := LOCAL_SPD;
    CHS_TSP_OUT := LOCAL_TSP;
    CHS := TRUE;
    Other_Chemical_Mode_Runing := FALSE;
    SMCL_RESET := FALSE;
ELSIF SMCL_COMM_OK THEN
    ACH_EN := (RX_BITS AND 16#0001) <> 0;
    Other_Chemical_Mode_Runing := (RX_BITS AND 16#0002) <> 0;
    CHS := (RX_BITS AND 16#0004) <> 0;
    SMCL_RESET_TRIG (CLK := (RX_BITS AND 16#0008) <> 0);
    SMCL_RESET := SMCL_RESET_TRIG.Q;
    CH_LEAD := (RX_BITS AND 16#0010) <> 0;
    CHVSD_SEQ_OUT := LIMIT(0.0, INT_TO_REAL(RX_SPD) / 100.0, 100.0);
    IF RX_TSP > 0 THEN
        CHS_TSP_OUT := INT_TO_REAL(RX_TSP) / 100.0;
    END_IF;
    CHWS_T01_T02 := INT_TO_REAL(RX_CHWST) / 100.0;
    OA_T := INT_TO_REAL(RX_OAT) / 100.0;
END_IF;

(* 2026-10-20 user (ACH-01 edit): control supply temperature from the unit's own CHS-T01 / CHS-T02 when valid *)
CHWS_T_OK := (NOT (CHS_T01_UnderRange OR CHS_T01_OverRange)) OR (NOT (CHS_T02_UnderRange OR CHS_T02_OverRange));
IF (NOT (CHS_T01_UnderRange OR CHS_T01_OverRange)) AND (NOT (CHS_T02_UnderRange OR CHS_T02_OverRange)) THEN
    CHWS_T01_T02 := MAX(CHS_T01, CHS_T02);
ELSIF (NOT (CHS_T01_UnderRange OR CHS_T01_OverRange)) THEN
    CHWS_T01_T02 := CHS_T01;
ELSIF (NOT (CHS_T02_UnderRange OR CHS_T02_OverRange)) THEN
    CHWS_T01_T02 := CHS_T02;
END_IF;

P06_ChemGrant := SMCL_COMM_OK AND NOT LOCAL_EN AND ((RX_BITS AND 16#0040) <> 0);
