(* Unit fault (UNIT-FAULT)
   Fix: mismatch now compares with the actual command *_C (* _OP was never assigned); mismatch alarms latch, reset by HMI/SMCL;
         ACH-MM per SOO: commanded on and supply > setpoint + 2.8 °C and no run feedback for 5 min; ACH_Fault uses the delayed alarm *)
CHBPV_DV := ABS(CHBPV_C - CHBPV_FB);
CHBPV_MM_Condition (Condition := CHBPV_DV > SP_CHBPV_MM_DV, SP_Condition_Delay := SP_CHBPV_MM_Delay, SEC_P := SEC_P, Condition_OK => CHBPV_MM_DLY);
IF CHBPV_MM_DLY THEN ALM_CHBPV_MM := TRUE; END_IF;
CHV01_DV := ABS(CHV01_C - CHV01_FB);
CHV01_MM_Condition (Condition := CHV01_DV > SP_CHV01_MM_DV, SP_Condition_Delay := SP_CHV01_MM_Delay, SEC_P := SEC_P, Condition_OK => CHV01_MM_DLY);
IF CHV01_MM_DLY THEN ALM_CHV01_MM := TRUE; END_IF;
CHV02_DV := ABS(CHV02_C - CHV02_FB);
CHV02_MM_Condition (Condition := CHV02_DV > SP_CHV02_MM_DV, SP_Condition_Delay := SP_CHV02_MM_Delay, SEC_P := SEC_P, Condition_OK => CHV02_MM_DLY);
IF CHV02_MM_DLY THEN ALM_CHV02_MM := TRUE; END_IF;
CHV03_DV := ABS(CHV03_C - CHV03_FB);
CHV03_MM_Condition (Condition := CHV03_DV > SP_CHV03_MM_DV, SP_Condition_Delay := SP_CHV03_MM_Delay, SEC_P := SEC_P, Condition_OK => CHV03_MM_DLY);
IF CHV03_MM_DLY THEN ALM_CHV03_MM := TRUE; END_IF;

(* Pump failed to run: no run 30 s after command -> unit stops *)
CHP_MM := CHP_STC AND NOT CHP_RUN;
CHP_MM_Condition (Condition := CHP_MM, SP_Condition_Delay := SP_CHP_MM_Delay, SEC_P := SEC_P, Condition_OK => CHP_MM_DLY);
IF CHP_MM_DLY THEN ALM_CHP_MM := TRUE; END_IF;
LINEUP_TRIP := ALM_CHP_MM;
(* Make before break: under SMCL control a unit fault does not stop the line-up by itself (only the chiller, for protection); SMCL removes ACH_EN after the replacement start is done and supply temperature is reached;
   in local mode or with SMCL comm lost, a pump run failure still stops the whole line-up *)
LINEUP_STOP := LINEUP_TRIP AND (LOCAL_EN OR NOT SMCL_COMM_OK);

ACH_MM := ACH_STC AND (NOT ACH_RUN) AND ((CHS_T01 > CHS_TSP_OUT + CHS_TSP_OUT_plus) OR (CHS_T02 > CHS_TSP_OUT + CHS_TSP_OUT_plus));
ACH_MM_Condition (Condition := ACH_MM, SP_Condition_Delay := SP_ACH_MM_Delay, SEC_P := SEC_P, Condition_OK => ACH_MM_DLY);
IF ACH_MM_DLY THEN ALM_ACH_MM := TRUE; END_IF;

IF UNIT_Reset OR SMCL_RESET THEN
    ALM_CHBPV_MM := FALSE; ALM_CHV01_MM := FALSE; ALM_CHV02_MM := FALSE; ALM_CHV03_MM := FALSE;
    ALM_CHP_MM := FALSE; ALM_ACH_MM := FALSE;
    UNIT_Reset := FALSE;
END_IF;

CHWP_Fault := ALM_CHP_MM OR CHP_FLT_DI OR NOT CHP_REM;
(* Chiller power loss is also a chiller fault (old ACH_F2 position; there is no Fault 02 point) *)
ACH_Fault := ALM_ACH_MM OR ACH_F1 OR NOT ACH_PWR OR ACHF_F OR NOT ACH_AM;
CH_FAULT := ACH_Fault;
(* *_Auto = TRUE means the device is in MANUAL *)
UNIT_NOA := CHP_Auto OR ACH_Auto OR CHPVSD_AM OR CHV01_Auto OR CHV02_Auto OR CHV03_Auto OR CHBPV_Auto;
(* Available: auto, no fault, no mismatch, not in maintenance; power loss is not checked here (SMCL must tell power loss apart for quick restart) *)
UNIT_ENABLE := NOT (UNIT_NOA OR ACH_Fault OR CHWP_Fault OR ALM_CHBPV_MM OR ALM_CHV01_MM
                    OR ALM_CHV02_MM OR ALM_CHV03_MM OR CH_MS OR TST_MS OR TST_NOCAP OR P06_SeqFault OR P06_ConfigFault OR LOCAL_EN);
