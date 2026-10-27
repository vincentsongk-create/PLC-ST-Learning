(* Modbus RTU master (CPU serial port, single bus, BMS-S01-03-01)
   Address 5 VSD IVS102: read 100..110, 300 (table 03)
   Address 6 pump power meter iEM3000: read 3000..3077, Float32 high word first (table 04)
   Address 7 chiller YVAM1500: read 1..29, 61..72, 65001; write 1 = supply setpoint x10 (table 05; the only way to set the chiller, AO no longer used)
   Address 8 storage tank, address 9 tank heat tracing: register tables pending, not polled yet
   One request at a time; process the result before sending the next. RTU_ERR_MAX failures in a row = comm fault.
   Note: set the CPU serial port to Modbus master in the hardware configuration; baud rate/parity per device. *)
RTU_ADR_VFD := ADDM('0.0.0.5');
RTU_ADR_PPM := ADDM('0.0.0.6');
RTU_ADR_ACH := ADDM('0.0.0.7');
RTU_BUSY := (RTU_GEST[0] AND 16#0001) <> 0;

IF SIM_EN OR NOT RTU_EN THEN
    RTU_STEP := 1; RTU_SENT := FALSE;
    ERR_VFD := 0; ERR_PPM := 0; ERR_ACH := 0;
ELSIF NOT RTU_BUSY THEN
    IF RTU_SENT THEN
        (* ---------- process the result of the previous request ---------- *)
        RTU_SENT := FALSE;
        RTU_OK := RTU_GEST[1] = 0;
        CASE RTU_STEP OF
        1:  (* VSD 100..110 *)
            IF RTU_OK THEN
                FOR I := 0 TO 10 DO VFD_RAW[I] := RTU_BUF[I]; END_FOR;
                VFD_SPD_RPM := RTU_BUF[0];
                VFD_SPD_RAW := RTU_BUF[1];
            END_IF;
        2:  (* VSD 300 *)
            IF RTU_OK THEN VFD_CTRL_MODE := RTU_BUF[0]; END_IF;
        3:  (* meter 3000..3077: array index = register - 3000 *)
            IF RTU_OK THEN
                (* Registers 3010 current avg, 3026 line voltage avg, 3060 active, 3068 reactive, 3076 apparent *)
                PPM_IDX[0] := 10; PPM_IDX[1] := 26; PPM_IDX[2] := 60; PPM_IDX[3] := 68; PPM_IDX[4] := 76;
                FOR I := 0 TO 4 DO
                    (* Float32 high word first, decoded per IEEE754 (M340 has no located %MF variables) *)
                    FLT_HI := INT_TO_DINT(RTU_BUF[PPM_IDX[I]]);
                    IF FLT_HI < 0 THEN FLT_HI := FLT_HI + 65536; END_IF;
                    FLT_LO := INT_TO_DINT(RTU_BUF[PPM_IDX[I] + 1]);
                    IF FLT_LO < 0 THEN FLT_LO := FLT_LO + 65536; END_IF;
                    FLT_E := DINT_TO_INT((FLT_HI / 128) MOD 256);
                    FLT_M := (FLT_HI MOD 128) * 65536 + FLT_LO;
                    IF (FLT_E = 0) OR (FLT_E = 255) THEN      (* 0, denormal, NaN/inf treated as 0 *)
                        PPM_VAL[I] := 0.0;
                    ELSE
                        PPM_VAL[I] := (1.0 + DINT_TO_REAL(FLT_M) / 8388608.0) * EXP(INT_TO_REAL(FLT_E - 127) * 0.69314718);
                        IF FLT_HI >= 32768 THEN PPM_VAL[I] := -PPM_VAL[I]; END_IF;
                    END_IF;
                END_FOR;
                PPM_I_AVG := PPM_VAL[0]; PPM_U_LL := PPM_VAL[1]; PPM_KW := PPM_VAL[2];
                PPM_KVAR := PPM_VAL[3]; PPM_KVA := PPM_VAL[4];
            END_IF;
        4:  (* chiller 1..29: index = register - 1 *)
            IF RTU_OK THEN
                ACH_SP_RB := INT_TO_REAL(RTU_BUF[0]) / 10.0;
                LCHLT := INT_TO_REAL(RTU_BUF[4]) / 10.0;
                ECHLT := INT_TO_REAL(RTU_BUF[5]) / 10.0;
                ACH_OAT := INT_TO_REAL(RTU_BUF[15]) / 10.0;
                ACH_ACT_SP := INT_TO_REAL(RTU_BUF[19]) / 10.0;
                ACH_OPH := INT_TO_DINT(RTU_BUF[25]);
                IF ACH_OPH < 0 THEN ACH_OPH := ACH_OPH + 65536; END_IF;
                ACH_FLA := INT_TO_REAL(RTU_BUF[28]) / 10.0;
                IF ACH_UNITS = 0 THEN          (* imperial °F -> °C *)
                    ACH_SP_RB := (ACH_SP_RB - 32.0) / 1.8;
                    LCHLT := (LCHLT - 32.0) / 1.8;
                    ECHLT := (ECHLT - 32.0) / 1.8;
                    ACH_OAT := (ACH_OAT - 32.0) / 1.8;
                    ACH_ACT_SP := (ACH_ACT_SP - 32.0) / 1.8;
                END_IF;
            END_IF;
        5:  (* chiller 61..72: index = register - 61 *)
            IF RTU_OK THEN
                ACH_REM_RUN_RB := RTU_BUF[0] <> 0;
                ACH_MOTOR_RUN := RTU_BUF[4] <> 0;
                (* register 66 BV6 "Chilled Liquid Pump [0=Off, 1=On]" CH LIQ PUMP STAT (05 YVAM BAS table) *)
                ACH_LIQ_PUMP := RTU_BUF[5] <> 0;
                ACH_PERMIT := RTU_BUF[7] <> 0;
                ACH_FLOWSW := RTU_BUF[8] <> 0;
                ACH_EVAP_FRZ := RTU_BUF[11] <> 0;      (* 3.2.26 evaporator freeze *)
            END_IF;
        6:  (* chiller 65001 units *)
            IF RTU_OK THEN ACH_UNITS := RTU_BUF[0]; END_IF;
        END_CASE;

        (* Comm counters *)
        IF (RTU_STEP = 1) OR (RTU_STEP = 2) THEN
            IF RTU_OK THEN ERR_VFD := 0; ELSIF ERR_VFD < 100 THEN ERR_VFD := ERR_VFD + 1; END_IF;
        ELSIF RTU_STEP = 3 THEN
            IF RTU_OK THEN ERR_PPM := 0; ELSIF ERR_PPM < 100 THEN ERR_PPM := ERR_PPM + 1; END_IF;
        ELSE
            IF RTU_OK THEN ERR_ACH := 0; ELSIF ERR_ACH < 100 THEN ERR_ACH := ERR_ACH + 1; END_IF;
        END_IF;

        RTU_STEP := RTU_STEP + 1;
        IF RTU_STEP > 7 THEN RTU_STEP := 1; END_IF;
    ELSE
        (* ---------- send the next request ---------- *)
        IF (RTU_STEP < 1) OR (RTU_STEP > 7) THEN RTU_STEP := 1; END_IF;
        RTU_GEST[2] := RTU_TMO;
        CASE RTU_STEP OF
        1: READ_VAR(ADR := RTU_ADR_VFD, OBJ := '%MW', NUM := INT_TO_DINT(100 + RTU_OFS), NB := 11, GEST := RTU_GEST, RECP => RTU_BUF);
        2: READ_VAR(ADR := RTU_ADR_VFD, OBJ := '%MW', NUM := INT_TO_DINT(300 + RTU_OFS), NB := 1, GEST := RTU_GEST, RECP => RTU_BUF);
        3: READ_VAR(ADR := RTU_ADR_PPM, OBJ := '%MW', NUM := INT_TO_DINT(3000 + RTU_OFS), NB := 78, GEST := RTU_GEST, RECP => RTU_BUF);
        4: READ_VAR(ADR := RTU_ADR_ACH, OBJ := '%MW', NUM := INT_TO_DINT(1 + RTU_OFS), NB := 29, GEST := RTU_GEST, RECP => RTU_BUF);
        5: READ_VAR(ADR := RTU_ADR_ACH, OBJ := '%MW', NUM := INT_TO_DINT(61 + RTU_OFS), NB := 12, GEST := RTU_GEST, RECP => RTU_BUF);
        6: READ_VAR(ADR := RTU_ADR_ACH, OBJ := '%MW', NUM := 65001 + INT_TO_DINT(RTU_OFS), NB := 1, GEST := RTU_GEST, RECP => RTU_BUF);
        7: IF ACH_UNITS = 0 THEN
               RTU_WBUF[0] := REAL_TO_INT((CHS_TSP_OUT * 1.8 + 32.0) * 10.0);
           ELSE
               RTU_WBUF[0] := REAL_TO_INT(CHS_TSP_OUT * 10.0);
           END_IF;
           WRITE_VAR(ADR := RTU_ADR_ACH, OBJ := '%MW', NUM := INT_TO_DINT(1 + RTU_OFS), NB := 1, EMIS := RTU_WBUF, GEST := RTU_GEST);
        END_CASE;
        RTU_SENT := TRUE;
    END_IF;
END_IF;

COMM_VFD_FAIL := ERR_VFD >= RTU_ERR_MAX;
COMM_PPM_FAIL := ERR_PPM >= RTU_ERR_MAX;
COMM_ACH_FAIL := ERR_ACH >= RTU_ERR_MAX;

(* EVAP_PUMP (SOO FPM: pump request from the chiller) = chiller point CH LIQ PUMP STAT; OFF while the chiller link is down *)
IF RTU_EN AND NOT SIM_EN THEN
    EVAP_PUMP := ACH_LIQ_PUMP AND NOT COMM_ACH_FAIL;
ELSE
    EVAP_PUMP := FALSE;
END_IF;

(* Chiller powered: not in the chiller register table, taken from chiller controller comm OK (when PWR_FROM_COMM=TRUE) *)
IF PWR_FROM_COMM AND RTU_EN AND NOT SIM_EN THEN
    ACH_PWR_RTU := NOT COMM_ACH_FAIL;
END_IF;
(* ACH_AM_RTU (chiller remote): not in the chiller register table, kept as a software point until the vendor provides a register *)

(* When SMCL comm is lost, freeze protection uses the chiller own outdoor temperature *)
IF (NOT SMCL_COMM_OK) AND (NOT LOCAL_EN) AND (NOT COMM_ACH_FAIL) AND RTU_EN AND NOT SIM_EN THEN
    OA_T := ACH_OAT;
END_IF;
