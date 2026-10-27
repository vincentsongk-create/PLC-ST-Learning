(* Common chilled water pump speed: reverse acting PI holds CHW-DP = CHW-DPSP (initial 135 kPa) *)
(* 2026-10-19 restart recovery: take the speed the M340 pumps are holding; the PI tracks it and continues from there *)
IF RCV_ACT THEN
    FOR I := 1 TO 5 DO
        IF (HB_LAST[I] <> RCV_HB0[I]) AND COMM_OK[I] AND CHWP_S[I] THEN
            CHPVSD_SEQ_OUT := SPD_ECHO[I];
        END_IF;
    END_FOR;
END_IF;
PI_CHP (ENABLE := (N_PUMP > 0) AND CHW_DP_OK AND NOT CHPVSD_MAN_EN AND NOT RCV_ACT,
        PV := CHW_DP, SP := CHW_DPSP, KP := PID_KP, TI := PID_TI,
        OUT_MIN := CHP_SPD_MIN, OUT_MAX := CHP_SPD_MAX, DIRECT := FALSE,
        TRK_VAL := CHPVSD_SEQ_OUT, SAMPLE := SEC_P);
IF CHPVSD_MAN_EN THEN
    CHPVSD_SEQ_OUT := LIMIT(0.0, CHPVSD_MAN_SP, 100.0);
ELSIF RCV_ACT THEN
    CHPVSD_SEQ_OUT := LIMIT(CHP_SPD_MIN, CHPVSD_SEQ_OUT, CHP_SPD_MAX);
ELSIF N_PUMP = 0 THEN
    CHPVSD_SEQ_OUT := CHP_SPD_MIN;   (* no pump running: start from minimum speed *)
ELSE
    CHPVSD_SEQ_OUT := PI_CHP.OUT;
END_IF;
